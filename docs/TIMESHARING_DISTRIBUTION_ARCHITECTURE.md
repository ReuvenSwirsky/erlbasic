# Time-Sharing and Distribution Architecture

This document describes:

1. How erlbasic currently time-shares CPU/memory/network work across many users.
2. Where a single user can still hog resources.
3. What to change to support reliable operation with dozens/hundreds of sessions.
4. What is required to evolve into a multi-node Erlang deployment.

## Scope and Current Execution Model

The runtime is mostly process-per-session:

- TCP: supervised listener accepts a socket and starts an `erlbasic_tcp_conn` worker under `erlbasic_conn_sup`; that worker owns the raw socket receive loop and delegates shell/session state to `erlbasic_session`.
- WebSocket: Cowboy process starts an `erlbasic_ws_conn` worker per upgraded socket, also backed by `erlbasic_session`.
- Each session executes BASIC in its own BEAM process.

Relevant modules:

- `src/erlbasic_listener.erl`: TCP accept loop.
- `src/erlbasic_web_listener.erl`: explicit supervised HTTP/HTTPS listener workers.
- `src/erlbasic_conn.erl`: compatibility facade for the split connection modules.
- `src/erlbasic_tcp_conn.erl`: TCP transport adapter.
- `src/erlbasic_ws_conn.erl`: WebSocket transport adapter.
- `src/erlbasic_session.erl`: transport-neutral shell/session state machine.
- `src/erlbasic_shell.erl`: login shell and interpreter selection.
- `src/erlbasic_ws_handler.erl`: Cowboy WebSocket bridge process.
- `src/erlbasic_runtime.erl`: RUN loop and output flush behavior.
- `src/erlbasic_mem_watchdog.erl`: per-session memory polling/quota enforcement.
- `src/erlbasic_sup.erl`: top-level supervision tree.

## Current Time-Sharing Behavior

### Strengths

1. Isolation by process
- Each user session is independent. A crashing session usually does not crash siblings.

2. BEAM scheduler fairness
- Long-running BASIC loops are preempted by BEAM reductions, so one process cannot monopolize an OS thread forever.

3. Session quota enforcement
- `erlbasic_mem_watchdog` polls process memory and signals over-limit sessions (`memory_limit_exceeded`).
- Per-account session count limit exists (`max_sessions_per_ppn`).

4. Cooperative GET polling
- GET/GETKEY nonblocking paths use short waits and return to receive loops frequently.

### What This Means in Practice

For CPU fairness alone, the architecture is good. The biggest remaining risks are not scheduler starvation; they are unbounded queues, unbounded payload sizes, and unbounded connection lifetimes.

## Resource-Hog Risk Review

Severity uses: High / Medium / Low.

### High: WebSocket session can idle forever

- `src/erlbasic_ws_handler.erl` sets `idle_timeout => infinity`.
- A client can keep many dormant sockets open indefinitely.

Impact:
- Consumes connection/process memory and per-connection overhead permanently.
- Enables low-cost connection hoarding.

Recommended action:
- Add configurable WebSocket idle timeout (for example 5-15 minutes) with periodic ping/pong expectations.

### High: No explicit inbound frame-size guard for WebSocket input

- `src/erlbasic_ws_handler.erl` accepts `{text, Data}` and forwards it after `binary_to_list(Data)`.
- No app-level size check is applied before list conversion.

Impact:
- Very large text frames can trigger large binary/list allocations and GC pressure.
- Repeated frames can become memory/CPU amplification.

Recommended action:
- Add max command/frame size guard in handler before conversion.
- Also set Cowboy WebSocket `max_frame_size` explicitly via config.

### High: Potential unbounded mailbox growth between runtime and ws handler

- Runtime flush sends output via `Pid ! {output, Text}`.
- Under fast-producing programs and slow network clients, ws handler mailbox can grow.

Impact:
- Per-session memory blowup; under enough sessions this can pressure node memory.

Recommended action:
- Add mailbox-aware flow control for output (high-water/low-water).
- Option A: drop/coalesce non-critical frames (best-effort visual updates).
- Option B: pause producer when ws mailbox exceeds threshold.

### Medium: TCP listener/session supervision is explicit, but the protocol implementation is still custom

- The listener and session roots are now supervised explicitly.
- TCP session logic is now single-process, but it still uses a hand-rolled socket/protocol loop rather than a Ranch protocol module.

Impact:
- Works, but the runtime still owns custom TCP protocol/session lifecycle code rather than delegating that layer to Ranch.

Recommended action:
- Keep the current explicit supervision model unless you later want to standardize the raw TCP side onto Ranch as well.

### Medium: DETS-backed account/limits state is node-local

- `src/erlbasic_accounts.erl` and `src/erlbasic_limits.erl` use DETS local files.

Impact:
- In multi-node mode, credentials/limits diverge unless externally synchronized.

Recommended action:
- Move durable state to shared backend (Mnesia disc_copies, SQL, or external store).

### Low: Memory watchdog polling cadence and work are global but small

- Polling every 500ms over registered sessions is acceptable at modest scale.

Impact:
- At very high session counts this adds predictable overhead.

Recommended action:
- Keep, but make interval configurable and collect metrics.

## Hardening Plan for Better Time-Sharing

Prioritized steps.

### Phase 1: Fast safety wins

1. Add configurable connection lifetime guards
- `ws_idle_timeout_ms`
- Optional `tcp_login_idle_timeout_ms` and `tcp_session_idle_timeout_ms`

2. Add input size limits
- `max_input_line_bytes` (TCP)
- `max_ws_frame_bytes` (WebSocket)

3. Add output backpressure controls
- `max_ws_mailbox_messages`
- `max_ws_mailbox_bytes` (approximate)
- Behavior when exceeded: throttle or disconnect with explicit error.

4. Add global connection caps
- Cowboy/Ranch `max_connections` per listener.
- Separate caps for WS and TCP listeners if needed.

### Phase 2: Observability and operations

1. Expand `/a/system/stats`
- Per-listener connection counts.
- Distribution of session mailbox lengths.
- Top-N session memory and reduction counters.

2. Add telemetry
- Session start/stop reasons.
- Disconnect reason counters (idle, over-quota, oversized frame, etc.).

3. Add load tests
- Synthetic 100/500/1000 concurrent session test scripts for idle and active chatty clients.

### Phase 3: Robust output pipeline

1. Introduce explicit producer-consumer flow contract between runtime and websocket process.
2. Prefer bounded queue semantics over unbounded actor mailbox growth for large-frame workloads.

## Multi-Node Distribution: What Must Change

To run across multiple Erlang nodes (not just one node with many schedulers), these are the key requirements.

### 1. Shared source of truth for identity and quotas

Current:
- Accounts and limits in local DETS files.

Needed:
- Replace with replicated/shared store:
  - Option A: Mnesia (with proper table types and quorum strategy).
  - Option B: external DB (PostgreSQL, etc.) via service module.

### 2. Global session-count enforcement across nodes

Current:
- Session counting is local inside one `erlbasic_mem_watchdog` process.

Needed:
- Cluster-wide active-session registry keyed by PPN.
- Registration/unregistration must be atomic cluster-wide.

Possible approaches:
- Mnesia transaction on session-count table.
- Global coordinator process (or hashed partition by PPN).

### 3. Shared file storage semantics

Current:
- User files under local filesystem path (`~/ErlUsers`).

Needed:
- Shared storage visible to all nodes:
  - Network filesystem (simple, lower complexity).
  - Object storage abstraction (more scalable).

### 4. Stateless front-door routing and session affinity

Current:
- Session state is in-memory process state.

Needed:
- Load balancer that supports sticky sessions for WebSocket and long-lived TCP.
- Sticky key can be cookie, source hash, or token-based route hint.

Why:
- A live interpreter process is node-local. Mid-session hopping is expensive unless you build process migration/state serialization.

### 5. Distribution-safe process addressing

Current:
- Many interactions use local PIDs and process dictionary assumptions.

Needed:
- Encapsulate session addressing behind an API boundary so internals can later map to `{Node, SessionId}`.
- Keep wire protocols and APIs free of direct PID exposure.

### 6. Cluster observability and failure handling

Needed:
- Node health checks and admission control.
- Per-node connection and memory budgets.
- Draining mode (stop accepting new sessions before deploy/restart).
- Reconciliation jobs for stale session registry entries after node loss.

## Suggested Target Architecture (Incremental)

1. Keep per-session interpreter process model.
2. Add strict per-connection I/O bounds and idle timeouts.
3. Add backpressure-aware WS output queue.
4. Externalize identity/quota/storage state.
5. Add cluster-wide session registry.
6. Put LB in front with sticky routing.

This preserves most of the existing interpreter code while making scale-out realistic.

## Definition of Done for "Distributed Ready"

The system can be considered distribution-ready when all are true:

1. Any node can authenticate any user against shared auth state.
2. Session limits are enforced globally, not per node.
3. User files are readable/writable from any node with consistent semantics.
4. Front-door routing keeps each live session pinned to one node.
5. Node loss does not permanently leak session counts or lock accounts out.
6. Load tests demonstrate stable behavior at target concurrency with bounded memory growth.

## Immediate Next Steps (Recommended)

1. Add config keys and enforcement for:
- WS idle timeout
- WS max frame size
- Max input line size
- Listener max connections

2. Add mailbox metrics and protection in WebSocket path.

3. Create a storage/auth abstraction layer module now, even if first implementation still calls DETS/local FS. This will reduce migration cost later.

4. Add a cluster session-registry interface with local implementation first, then swap to Mnesia/external backend.
