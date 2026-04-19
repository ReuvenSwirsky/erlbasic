# ErlBASIC Issue List

This document turns the current roadmap into a concrete, prioritized backlog for the next phase of the project.

Priority bands:
- `P0` - do next; reduces immediate delivery or production risk
- `P1` - high-value follow-up after `P0`
- `P2` - important, but can wait until the platform is more stable

## P0

### 1. Add CI pipeline for compile, tests, and smoke validation

**Why**

The repo has solid local scripts, but no hosted automation. Every change still depends on manual execution of [build.ps1](build.ps1), [run_tests.ps1](run_tests.ps1), and [run_all.ps1](run_all.ps1).

**Scope**

- Add a CI workflow that runs compile, EUnit, and smoke tests on every push and PR.
- Run at least one lightweight performance lane or perf sanity check.
- Fail fast on compile or test regressions.
- Publish logs/artifacts that make failures diagnosable.

**Acceptance Criteria**

- A contributor can open a PR and see automated pass/fail status.
- CI runs compile plus the existing automated test suites.
- The workflow is documented in the repo.

### 2. Add structured runtime logging

**Why**

The interpreter has serious runtime features and recent security hardening, but production debugging still relies too much on ad hoc console output and local reproduction.

**Scope**

- Log authentication failures, session registration/rejection, quota enforcement, watchdog kills, homepage render failures, and important admin actions.
- Use consistent event names and payload fields.
- Avoid logging secrets or raw passwords.

**Acceptance Criteria**

- Key operational events are emitted in a consistent format.
- Logs contain enough context to correlate a failure to account/session/resource limits.
- No secrets are written to logs.

### 3. Add concurrency and abuse-oriented integration tests

**Why**

Recent work added session limits, memory watchdog enforcement, path restrictions, and failed-login delay, but the current tests are mostly single-session correctness tests.

**Scope**

- Add tests for concurrent logins under the same PPN.
- Add tests for memory quota exceedance and session cap enforcement.
- Add tests for repeated failed authentication and file channel exhaustion.
- Add at least one multi-session WebSocket stress scenario.

**Acceptance Criteria**

- Security and quota controls are exercised under concurrent load.
- Failures are deterministic enough for CI.
- New tests cover the recent hardening paths in the runtime and connection layer.

### 4. Add health and metrics endpoints

**Why**

Operators need a fast way to answer simple questions: is the system healthy, how many sessions are active, are homepages timing out, are limits being hit.

**Scope**

- Add a machine-readable health endpoint.
- Add a metrics or status summary endpoint for active sessions, cache stats, and limit events.
- Keep privileged detail behind admin auth where appropriate.

**Acceptance Criteria**

- Basic liveness/readiness can be checked without attaching to the Erlang shell.
- Operators can inspect current system state from HTTP.
- Sensitive information is not exposed anonymously.

### 5. Document supported environments and canonical workflows

**Why**

The repo currently assumes a lot of local knowledge around Windows, PowerShell, rebar invocation, and OTP behavior.

**Scope**

- Document supported OTP versions.
- Document supported OS targets and known caveats.
- Define the canonical build, run, and test workflows.
- Capture current Windows-specific workarounds from repo memory in a permanent doc.

**Acceptance Criteria**

- A new contributor can build and test the project without reverse-engineering scripts.
- Known platform caveats are documented in the repo.

## P1

### 6. Expand the admin UI into an operator dashboard

**Why**

The admin handler and HTML assets exist, but the current surface is closer to a management stub than a day-to-day operations tool.

**Scope**

- Show active sessions, quota usage, memory limits, recent failures, and homepage/cache state.
- Expose account lifecycle actions from the UI.
- Make it clear which actions are read-only and which are destructive.

**Acceptance Criteria**

- Operators can inspect the current state of the system without shell access.
- The dashboard is useful for support workflows, not just configuration.

### 7. Make build and test automation cross-platform

**Why**

The project is practical on the current Windows setup, but deployment and CI will likely need Linux support.

**Scope**

- Remove avoidable Windows-only assumptions from the automation.
- Add a Linux-friendly path for build and test execution.
- Keep PowerShell workflows working where already established.

**Acceptance Criteria**

- Build and tests run reliably on both Windows and Linux.
- CI validates both environments or clearly documents the supported subset.

### 8. Add parser fuzzing and malformed-input stress coverage

**Why**

The parser/evaluator boundary is a natural fault line for correctness and resilience issues, especially with a large BASIC surface area.

**Scope**

- Generate malformed and edge-case input for statement parsing.
- Cover long lines, nested expressions, quote edge cases, bad separators, and chained statements.
- Ensure bad input fails cleanly without crashing session processes.

**Acceptance Criteria**

- Malformed input produces stable, expected failure behavior.
- No parser crash or runaway behavior occurs for tested fuzz cases.

### 9. Broaden performance benchmarks beyond Life workloads

**Why**

Performance work so far is meaningful but concentrated on Life-style examples and graphics send paths.

**Scope**

- Add benchmarks for string-heavy programs.
- Add benchmarks for file I/O and large stored programs.
- Add homepage render benchmarking.
- Track results in the same style as the existing perf history files.

**Acceptance Criteria**

- Performance coverage reflects more than one program archetype.
- Regressions in non-Life workloads can be detected automatically.

### 10. Publish a BASIC compatibility matrix

**Why**

The project has grown into a hybrid dialect with GW-BASIC, DEC BASIC, and project-specific behavior. That should be made explicit.

**Scope**

- Document supported features, partially supported features, and intentional omissions.
- Call out behavioral differences where they matter.
- Link the matrix from [README.md](README.md) and [Basic_Syntax.md](Basic_Syntax.md).

**Acceptance Criteria**

- Users can tell what dialect behavior to expect.
- Contributors can evaluate feature requests against a documented compatibility target.

## P2

### 11. Harden the homepage execution pipeline

**Why**

`HOME.BAS` execution is a compelling feature, but it now sits on the boundary between interpreter behavior, web serving, and caching.

**Scope**

- Add explicit execution budgets and better timeout reporting.
- Improve visibility into cache hit/miss behavior.
- Tighten behavior for expensive or hostile homepage programs.

**Acceptance Criteria**

- Homepage execution failures are visible and diagnosable.
- Expensive homepages cannot silently degrade the whole service.

### 12. Add account recovery and session revocation flows

**Why**

The account backend is solid, but support workflows still look manual.

**Scope**

- Add password reset or admin-driven credential recovery.
- Add account disable/reenable support.
- Add session revocation or forced logout capability.

**Acceptance Criteria**

- Operators can recover compromised or locked-out accounts without low-level intervention.
- Existing sessions can be revoked when needed.

### 13. Document deployment architecture limits

**Why**

The current design is effectively single-node and local-disk oriented. That is fine, but it should be explicit.

**Scope**

- Document single-node assumptions around DETS, local file storage, session state, and quotas.
- Describe what would need to change for clustered deployment.

**Acceptance Criteria**

- Readers understand the current scaling boundary.
- Future infra work has a documented starting point.

### 14. Improve onboarding and product UX documentation

**Why**

The project has a strong feature set and good examples, but the onboarding path is still thin for new users and operators.

**Scope**

- Add a first-run guide.
- Add browser and telnet quickstarts.
- Add a homepage tutorial.
- Add an admin usage guide.

**Acceptance Criteria**

- A first-time user can get from clone to running session quickly.
- A first-time operator can create accounts and manage the system from documentation.

## Suggested Delivery Order

If these are implemented as milestones, the recommended sequence is:

1. `P0` items 1 through 5
2. `P1` items 6 through 10
3. `P2` items 11 through 14

Within `P0`, the first three issues are the highest leverage:

1. CI pipeline
2. Structured runtime logging
3. Concurrency and abuse-oriented integration tests