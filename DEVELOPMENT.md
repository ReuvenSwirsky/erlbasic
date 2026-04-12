# Development Log

This document tracks significant development changes, bug fixes, and their rationale.

---

## April 11, 2026 - YECC Migration Finalization (Validation + Facade Cleanup)

### Enhancement
Completed final YECC migration cleanup by removing dead grammar fallback helpers, simplifying the parser facade to a single active path, and validating the full test/build pipeline.

### Implementation

**`src/erlbasic_parser_yecc.yrl`**
- Removed unreachable fallback productions:
  - `stmt -> kw_print text`
  - `stmt -> kw_close text`
  - `stmt -> kw_dim text`
  - `stmt -> kw_def text`
- Removed corresponding dead action helpers:
  - `parse_print_stmt/1`
  - `parse_close_stmt/1`
  - `parse_dim_stmt/1`
  - `parse_def_stmt/1`

**`src/erlbasic_parser.erl`**
- Removed obsolete parser mode shim now that YECC is the only parser path:
  - `set_parser_mode/1`
  - `clear_parser_mode/0`
  - `parse_statement_legacy/1`
  - `parser_mode/0`
- Simplified `parse_statement/1` to directly call `parse_statement_yecc/1`.

**`eunit_tests/erlbasic_eunit_tests.erl`**
- Replaced mode-switch test with direct entrypoint parity coverage:
  - `parse_statement_entrypoint_parity_test/0`

### Validation
- `./build.ps1`: PASS, zero warnings
- `./run_tests.ps1`: PASS (EUnit + smoke tests)

### Rationale
Keeping mode selection after YECC parity was complete added maintenance overhead and created the impression of two supported parser implementations. Removing the dead facade path makes behavior explicit, reduces surface area, and prevents future confusion.

### Lessons Learned
- Once migration parity is proven, remove compatibility shims promptly to avoid dead-API drift.
- Grammar fallback rules should be kept only when lexer output can actually produce those token shapes.

---

## April 10, 2026 - ON TIMER(n) GOSUB Language Feature and Space Invaders Example

### Enhancement
Added `ON TIMER(n) GOSUB` — a periodic timer callback that fires a subroutine approximately every `n` seconds during program execution, independent of player input or any blocking statement. Also added `examples/space_sprites.bas`, a Space Invaders-style demo game using the new feature.

### Implementation

**`src/erlbasic_state.hrl`**
- Added three new fields to `#state{}`:
  - `on_timer_gosub = undefined` — stores `{NExpr, TargetExpr}` when armed
  - `on_timer_return_depth = -1` — re-entrancy guard (depth of callstack when fired)
  - `on_timer_last_ms = undefined` — monotonic timestamp of last fire (milliseconds)

**`src/erlbasic_parser.erl`**
- Added `ON TIMER(n) GOSUB` regex clause in `parse_jump_statement/1`, checked before the generic `ON...GOSUB` rule.
- Added `{on_timer_gosub, NExpr, TargetExpr}` validate clause in `validate_statement/1`.

**`src/erlbasic_interp.erl`**
- Added immediate-mode handler for `{on_timer_gosub, NExpr, TargetExpr}` — arms the handler in the interpreter state.

**`src/erlbasic_runtime.erl`**
- Added `{on_timer_gosub, NExpr, TargetExpr}` execution clause in `execute_program_line_statement/7`.
- Added `on_timer_trigger/3` — checks elapsed time via `erlang:monotonic_time(millisecond)` and fires a `gosub` when the interval is reached. Re-entrancy guarded via `on_timer_return_depth`.
- Chained `on_timer_trigger` after `on_play_trigger` in `event_gosub_trigger/3`. Changed `on_play_trigger` return from bare `no_trigger` to `{no_trigger, State}` to support chaining.
- Updated `update_event_return_depths/2` to handle `on_timer_return_depth`.
- Cleared all three timer state fields on `END` and Ctrl-C break.

**`examples/space_sprites.bas`**
- Space Invaders-style game in HGR2 mode.
- 3 rows × 6 columns of invaders (sprites 10–27) with 3 damage states.
- Player launcher (sprite 1, 4× scale), player missile (sprite 2), enemy bullet (sprite 3).
- `ON SPRITE GOSUB 3000` for collision detection.
- `ON TIMER(0.08) GOSUB 2600` for autonomous fleet sweep, descent on wall bounce, and random enemy fire — all running independently of player input.
- Non-blocking `GET K$` in main loop for player movement (A/D) and fire (SPACE).
- HUD text in LOCATE rows 22–25 (score, lives, level).

### Tests
- `on_timer_gosub_parses_test` — parser returns correct `{on_timer_gosub, _, _}` tuple.
- `on_timer_gosub_sets_state_test` — statement arms `on_timer_gosub` in state.
- `on_timer_gosub_cleared_by_end_test` — `END` clears `on_timer_gosub` and resets depth.
- `on_timer_gosub_fires_during_run_test` — runs program with 20 ms interval + 50 ms SLEEP; asserts callback fired.
- `smoke_tests/on_timer_gosub.bas` + `.out` — smoke test: sets 50 ms timer, sleeps 200 ms, asserts `TIMER FIRED`.

### Validation
- `rebar3 compile`: PASS
- `rebar3 eunit --module=erlbasic_eunit_tests`: All 144 tests passed
- `escript smoke_runner.escript .` (from `smoke_tests/`): All 66 tests passed

### Rationale
Game loops and animations need independent time-driven events that do not stall waiting for input. `ON TIMER(n) GOSUB` follows the same event-handler pattern as `ON SPRITE GOSUB` and `ON PLAY(n) GOSUB`: the handler is checked after each executed statement and fires into a standard GOSUB/RETURN frame. Using `erlang:monotonic_time/1` avoids wall-clock wraparound issues and produces accurate intervals regardless of system load. The re-entrancy guard prevents runaway recursive fires if the handler takes longer than the interval.

---

## April 9, 2026 - Hex Integer Literals and Larger Sprite Examples

### Enhancement
Extended the expression lexer to support hexadecimal integer literals and refreshed the sprite examples to show larger 32x32 and 64x64 sprite workflows built from packed row masks.

### Implementation
- `src/erlbasic_eval_lexer.erl`:
  - Added `0x...` / `0X...` tokenization for hexadecimal integer literals.
  - Supports larger unsigned constants used for packed 32-bit and 64-bit sprite row masks.
- `examples/sprites.bas`:
  - Reworked to generate 32x32 sprites from 32-bit hex row masks stored in `%` arrays.
  - Expands those masks into 1D BYTE arrays before `SPRITE LOAD`.
- `examples/sprites_hgr2.bas`:
  - Reworked to generate 64x64 sprites from 64-bit hex row masks stored in `%` arrays.
  - Keeps the interactive `GETKEY` control/collision flow while demonstrating much larger sprites.
- `Basic_Syntax.md`:
  - Added literal notes documenting hexadecimal integer syntax.
  - Updated the sprite example snippet to reflect the larger packed-mask workflow.
- `README.md`:
  - Updated feature notes and example descriptions for hex literals and the larger sprite demos.

### Tests
- Added `hex_literal_eval_test/0` to verify direct hex literal parsing and arithmetic.
- Added `hex_literal_64bit_promotion_test/0` to verify large unsigned values can be assigned to `%` variables and printed correctly.
- Added `sprites_examples_load_test/0` to verify both updated sprite examples load successfully via `LOAD`.

### Validation
- `rebar3 compile`: PASS
- `rebar3 eunit --module=erlbasic_eunit_tests`: PASS

### Rationale
The original sprite demos showed the feature but forced verbose per-pixel setup. Hex row masks make larger sprites practical to author in BASIC while still preserving the BYTE-array `SPRITE LOAD` model. Adding lexer support keeps the language side aligned with how those examples are now written.

---

## April 9, 2026 - LOAD Robustness for Malformed Shared Examples (SPRITES crash fix)

### Bug
Loading a malformed shared example (for example `LOAD sprites` before the loop-variable fix) could crash in WebSocket command handling with:
- `case_clause {syntax_errors, Program, ErrorLines}`

Root cause:
- `parse_bin_as_program/1` may return `{syntax_errors, Program, ErrorLines}`.
- `handle_load_command/2` already handled that tuple.
- `load_program_file/1` (shared examples path) did not handle it, so the tuple escaped into a `case` that only matched `{ok,...}` and legacy `syntax_error` variants.

### Fix
- Added explicit `{syntax_errors, _Program, _ErrorLines}` handling in `src/erlbasic_commands.erl` within `load_program_file/1`.
- Kept current loader semantics: continue loading valid lines, skip invalid lines, and report each bad line number as `?SYNTAX ERROR IN <line>`.

### Additional correction
- Updated `examples/sprites.bas` to avoid reserved-word variable naming (`STEP%` -> `N%`), which had been triggering line syntax errors.

### Regression tests
- Added `load_malformed_shared_example_reports_error_without_crash_test/0` in `eunit_tests/erlbasic_eunit_tests.erl`.
  - Creates a temporary malformed shared example under `examples/`.
  - Verifies `LOAD` returns syntax-line diagnostics without crashing.
  - Verifies bad lines are omitted while valid lines remain listable.

### Validation
- `rebar3 eunit --module=erlbasic_eunit_tests`: PASS
- `smoke_tests/smoke_runner.escript`: PASS

---

## April 8, 2026 - IF/THEN Line-Number Shorthand, Safer Syntax Failure Handling, and HGR2 Lunar Lander Example

### Enhancements
- Added parser support for `IF ... THEN <line>` and `IF ... THEN <line> ELSE <line>` shorthand, interpreted as implied `GOTO` targets.
- Hardened connection handling so malformed interpreter return shapes with `syntax_errors` are surfaced as `?SYNTAX ERROR` instead of bubbling up as connection-level system errors.
- Added a new WebSocket/HGR2 gameplay example: `examples/lunarlander.bas`.

### Implementation
- `src/erlbasic_parser.erl`:
  - `parse_if_statement/1` now normalizes bare numeric THEN/ELSE branches to `GOTO <line>`.
  - Added `normalize_if_branch_statement/1` helper.
- `src/erlbasic_conn.erl`:
  - `tcp_handle_basic/4` and `ws_handle_basic/4` now guard unexpected interpreter return shapes.
  - Cases carrying `syntax_errors` are mapped to a user-facing `?SYNTAX ERROR` response rather than generic crash output.
- `examples/lunarlander.bas`:
  - New side-view LEM in `HGR2` with terrain, landing pad, fuel/speed HUD rows, and crash/landing outcomes.
  - Added responsive key handling using buffered `GET` scans and `ON ... GOSUB` dispatch.

### Documentation
- Updated `Basic_Syntax.md`:
  - Added IF shorthand documentation (`THEN 200` implied `GOTO`).
  - Clarified DIR grouped output by file source.
  - Updated storage path wording to the sandbox under `~/ErlUsers/`.
- Updated `README.md`:
  - Added Lunar Lander to examples.
  - Corrected buffered demo example path.
  - Added notes for DIR grouping and IF shorthand behavior.

### Testing
- Added EUnit coverage for IF shorthand parsing and runtime behavior.
- Full test run passed (EUnit + smoke tests).

---

## April 6, 2026 - Security Hardening for Public Deployment

### Enhancement
Applied a set of security hardening measures necessary before exposing the interpreter publicly on-line.

### Implementation

#### 1. Supervisor-driven memory watchdog (`src/erlbasic_mem_watchdog.erl` — new module)
Replaced the in-loop memory quota checks (called `erlang:external_size` on all interpreter state every 25 steps — expensive) with a dedicated `gen_server` watchdog started as a supervisor child ahead of the TCP/WS listeners:
- `process_info(Pid, memory)` reads the VM's already-maintained heap counter — negligible CPU cost.
- Polls every 500 ms; sends `memory_limit_exceeded` to any session process that exceeds its quota.
- Tracks sessions with `erlang:monitor` so dead connections auto-clean without explicit deregistration.
- Sessions register/deregister on login and logout through `erlbasic_mem_watchdog:try_register_session/4`.
- Removed `should_check_memory_quota`, `memory_quota_ok`, `post_step_memory_quota_ok`, and `approximate_memory_bytes` from `src/erlbasic_runtime.erl`.
- `FRE()` still works — it calls `approximate_current_memory_bytes()` in `src/erlbasic_eval_builtins.erl` only when explicitly invoked by the user, not on every step.

#### 2. Path traversal prevention (`src/erlbasic_fileio.erl`)
`normalize_path/1` previously passed absolute paths through unchanged, allowing `OPEN "/etc/passwd" FOR INPUT AS #1` to read arbitrary server files.
- Absolute paths now return `error` immediately.
- Any relative path containing a `..` component (checked via `filename:split`) also returns `error`.
- Both cases resolve to `?TYPE MISMATCH ERROR` in the interpreter.

#### 3. SLEEP cap at 30 seconds (`src/erlbasic_interp.erl`, `src/erlbasic_runtime.erl`)
`SLEEP 9999999` would hold a session process for days, pinning its resources. The computed sleep duration is now capped:
```erlang
min(30000, max(0, trunc(Value * 1000)))
```
`SLEEP` values greater than 30 silently sleep for exactly 30 seconds.

#### 4. Login brute-force delay (`src/erlbasic_conn.erl`)
After each failed authentication attempt (wrong PPN or password), a 2-second `timer:sleep/2000` is inserted before the next prompt is shown. Combined with the existing 4-attempt hard limit, this limits automated credential stuffing to ~0.5 attempts/second and disconnects the client after ~8 seconds of bad attempts.

#### 5. Per-PPN concurrent session cap (`src/erlbasic_mem_watchdog.erl`, `src/erlbasic_conn.erl`)
The memory watchdog's session registry now tracks a `ppn_counts` map. Login uses `try_register_session/4` (a synchronous `gen_server:call`) which atomically checks the count before accepting the session:
- Rejects login with `?TOO MANY SESSIONS` if the per-PPN session count is at or above the configured limit.
- Default: 3 concurrent sessions per PPN.
- Configurable via `{max_sessions_per_ppn, N}` in `sys.config`.
- System/admin accounts in project 0 or 1 are exempt (unlimited sessions).

#### 6. Open file channel cap (`src/erlbasic_fileio.erl`)
`OPEN` in a tight loop can exhaust OS file descriptors for the server process. `open_file/6` now checks:
```erlang
maps:size(OpenFiles) >= 15
```
and returns `?ILLEGAL FUNCTION CALL` if 15 channels are already open. The limit cannot be raised within a session; `CLOSE` must be used to free channels.

### Files Changed
- `src/erlbasic_mem_watchdog.erl`: New `gen_server` module; session registry; per-PPN count enforcement
- `src/erlbasic_sup.erl`: Added watchdog as first supervisor child (before listeners)
- `src/erlbasic_conn.erl`: `try_register_session`, brute-force delay, session limit rejection, `max_sessions_for/2` helper, watchdog unregistration on logout/HELLO/QUIT
- `src/erlbasic_runtime.erl`: Removed hot-loop quota checks; added `memory_limit_exceeded` message handling in `run_program_lines_continue`
- `src/erlbasic_fileio.erl`: Absolute path block; `..` traversal block; 15-channel cap
- `src/erlbasic_interp.erl`: SLEEP value capped to 30 seconds

### Configuration
New optional `sys.config` key:
```erlang
{erlbasic, [
    {max_sessions_per_ppn, 3}   %% default: 3; 0 = unlimited
]}
```

### Testing
- `escript $env:USERPROFILE/rebar3 compile`: PASS (no warnings)
- `./run_tests.ps1`: PASS (all EUnit + smoke tests)

### Rationale
Before public deployment, a single malicious or runaway user could previously:
- Read arbitrary server files via absolute `OPEN` paths
- Block a session indefinitely with `SLEEP 9999999`
- Enumerate credentials at high speed with no delay
- Exhaust server resources with unlimited parallel logins
- Exhaust OS file descriptors with unlimited `OPEN` calls
- Trigger expensive `external_size` serialisation on every interpreter step

The watchdog approach for memory measurement is also faster — the VM maintains the process heap counter continuously; reading it is O(1) rather than O(size of all interpreter state).

---

## April 3, 2026 - Keyword Architecture Refactor and Consistency Enforcement

### Refactoring
Completed a keyword-handling refactor to eliminate duplicated keyword lists across parser, expression lexer, LIST formatting, and builtin function checks.

### Implementation
- Added centralized keyword registry in `src/erlbasic_keywords.erl` with explicit category APIs:
  - `expr_keywords/0`
  - `list_keywords/0`
  - `builtin_function_keywords/0`
  - `reserved_only_keywords/0`
  - predicate helpers (`is_expr_keyword/1`, `is_list_keyword/1`, `is_builtin_function_keyword/1`, `is_reserved_variable_name/1`)
- Rewired consumers to use centralized policy:
  - `src/erlbasic_eval_lexer.erl` now uses `is_expr_keyword/1`
  - `src/erlbasic_commands.erl` LIST normalization now uses `is_list_keyword/1`
  - `src/erlbasic_parser.erl` variable-name reservation checks now use `is_reserved_variable_name/1`
  - `src/erlbasic_eval_builtins.erl` builtin membership now delegates to `is_builtin_function_keyword/1`
- Finalized keyword policy:
  - Variable names reserve all language keywords (not just a small parser subset)
  - `TIMER` and `STRING$` are explicit expression builtins
- Added automated consistency coverage in `eunit_tests/erlbasic_eunit_tests.erl`:
  - category intent tests
  - union/coverage tests to prevent keyword drift

### Bug Fixes During Refactor
- Normalized parser error shape handling for reserved-word parse failures in validation paths.
- Restored/implemented byte variable helpers in `src/erlbasic_eval_arrays.erl`:
  - `is_byte_var/1`
  - `normalize_byte_value/1`
- Ensured array bounds violations continue returning `?SUBSCRIPT OUT OF RANGE`.
- Updated perf runner tuning for `examples/life.bas` to avoid reserved keyword array name collisions under strict policy.

### Files Changed
- `src/erlbasic_keywords.erl`
- `src/erlbasic_eval_lexer.erl`
- `src/erlbasic_commands.erl`
- `src/erlbasic_parser.erl`
- `src/erlbasic_eval_builtins.erl`
- `src/erlbasic_eval_arrays.erl`
- `eunit_tests/erlbasic_eunit_tests.erl`
- `perf_tests/perf_runner.escript`

### Testing
- `escript $env:USERPROFILE/rebar3 compile`: PASS
- `./run_tests.ps1`: PASS (all EUnit + smoke tests)
- `./run_perf_tests.ps1`: PASS

### Rationale
Before this refactor, keyword knowledge was duplicated in multiple modules, which made behavior inconsistent and fragile when adding language features. Centralizing keyword policy keeps parser, lexer, builtin dispatch, and LIST formatting aligned while still preserving modular boundaries via focused category APIs.

---

## April 2, 2026 - Performance Work: Life/AsciiLife Speedups and Perf Gating

### Enhancement
Improved execution speed for Life-style workloads and added a repeatable performance test runner for the currently shipped graphics and text Life examples.

### Implementation
- **Runtime hot-path optimization** (`src/erlbasic_runtime.erl`):
  - Removed duplicate statement parsing during `RUN` execution.
  - Statements are now parsed once per execution step and reused.
- **Example program optimization**:
  - `examples/life.bas`:
    - Replaced nested neighbor loops + `GOSUB` with direct 8-neighbor summation.
    - Expanded arrays with borders (`DIM GRID(65, 49)`, `DIM NEXT(65, 49)`) to remove bounds checks in inner loops.
  - `examples/asciilife.bas`:
    - Same direct neighbor summation approach.
    - Expanded arrays with borders (`DIM GRID(61, 21)`, `DIM NEXTGRID(61, 21)`).
    - Removed deliberate delays for faster simulation updates.
    - Changed occupied-cell display character from extended ASCII block to `#` for cleaner cross-terminal rendering.
- **Perf runner and gate**:
  - Added `perf_tests/perf_runner.escript` and `run_perf_tests.ps1`.
  - Runner benchmarks `life.bas` and `asciilife.bas` using reduced generation counts for CI-friendliness.

### Documentation
- Updated `README.md` with:
  - Life example entries
  - Perf runner usage
  - Budget env vars including `ERLBASIC_PERF_MAX_ASCIILIFE_MS`

### Testing
- `./run_tests.ps1`: PASS (all EUnit + smoke tests)
- `./run_perf_tests.ps1`: PASS

### Rationale
Life programs stress the interpreter through dense nested loops and high-frequency rendering. Removing parse duplication and reducing per-cell overhead in example code improves responsiveness while preserving behavior. The perf runner keeps the current shipped Life examples within practical runtime budgets.

---

## April 1, 2026 - Add ON ERROR GOTO and RESUME Error Handling

**Commits:** 47cea45

### Enhancement
Added comprehensive error handling support with ON ERROR GOTO and RESUME statements, allowing programs to trap and recover from runtime errors gracefully.

### Implementation
- **State Extensions**: Added error handler tracking fields to `erlbasic_state.hrl`:
  - `error_handler` - Line number of active error handler (or undefined)
  - `error_resume_pc` - PC where error occurred (for RESUME)
  - `error_code` - ERR variable value (GW-BASIC compatible error code)
  - `error_line` - ERL variable value (line number where error occurred)
- **Parser Support**: Extended `erlbasic_parser.erl` to recognize:
  - `ON ERROR GOTO line` / `ON ERROR GOTO 0` (enable/disable handler)
  - `RESUME` (retry statement)
  - `RESUME NEXT` (continue after error)
  - `RESUME line` (jump to specific line)
- **Runtime Error Handling**: Refactored `erlbasic_runtime.erl` error handling:
  - Created `handle_runtime_error/6` function that checks for active error handler
  - When handler is set, jumps to handler line with ERR and ERL variables set
  - When no handler, stops with error message (original behavior)
- **Error Codes**: Added `error_code/1` function to `erlbasic_eval.erl` mapping error reasons to GW-BASIC error codes:
  - 1 = NEXT WITHOUT FOR, 2 = SYNTAX ERROR, 3 = RETURN WITHOUT GOSUB
  - 4 = OUT OF DATA, 5 = ILLEGAL FUNCTION CALL, 11 = DIVISION BY ZERO
  - 13 = TYPE MISMATCH, 17 = CAN'T CONTINUE, 20 = RESUME WITHOUT ERROR
- **RESUME Execution**: Implemented three RESUME variants:
  - `RESUME` - Retry the statement that caused the error
  - `RESUME NEXT` - Continue with statement after the error
  - `RESUME line` - Jump to specific line number
- **Documentation**: Updated `Basic_Syntax.md` with comprehensive error handling examples and error code table

**Syntax:**
```basic
ON ERROR GOTO line   ' Set error handler
ON ERROR GOTO 0      ' Disable error handler
RESUME               ' Retry error statement
RESUME NEXT          ' Skip to next statement
RESUME line          ' Jump to line
ERR                  ' Error code variable
ERL                  ' Error line variable
```

**Example:**
```basic
10 ON ERROR GOTO 1000
20 X = 1 / 0          ' Causes error
30 PRINT "AFTER"
40 END
1000 PRINT "Error"; ERR; "at line"; ERL
1010 RESUME NEXT      ' Continue at line 30
```

**Files Changed:**
- `src/erlbasic_state.hrl`: Added error tracking fields
- `src/erlbasic_parser.erl`: Added ON ERROR GOTO and RESUME parsing
- `src/erlbasic_runtime.erl`: Refactored error handling, added RESUME execution
- `src/erlbasic_eval.erl`: Added error_code/1 mapping function
- `eunit_tests/erlbasic_eunit_tests.erl`: Added 6 error handling tests (66 total)
- `smoke_tests/error_handler.bas`: New smoke test (55 total)
- `Basic_Syntax.md`: Comprehensive error handling documentation

**Testing:**
- 6 new EUnit tests covering all RESUME variants, ERR/ERL variables, and edge cases
- 1 new smoke test verifying end-to-end error handling behavior
- All 66 EUnit tests pass, all 55 smoke tests pass

---

## April 1, 2026 - Add ON...GOSUB and ON...GOTO Computed Jump Statements

**Commits:** 11b1012

### Enhancement
Added support for computed GOSUB and GOTO statements that select a target from a list based on an integer index expression.

### Implementation
- **Parser Support**: Extended `erlbasic_parser.erl` to recognize `ON <expr> GOSUB/GOTO` syntax with comma-separated target lists
- **Runtime Execution**: Added `execute_on_gosub/7` and `execute_on_goto/7` functions to `erlbasic_runtime.erl` that evaluate the index and jump to the nth target (1-based indexing)
- **Out-of-Range Handling**: When the index is ≤ 0 or > number of targets, execution continues with the next statement (no error)
- **Documentation**: Updated `Basic_Syntax.md` with comprehensive examples and notes on behavior

**Syntax:**
```basic
ON <expr> GOSUB line1, line2, line3, ...
ON <expr> GOTO line1, line2, line3, ...
```

**Example:**
```basic
10 LET X = 2
20 ON X GOSUB 100, 200, 300  ' Calls line 200
30 PRINT "BACK"
```

**Files Changed:**
- `src/erlbasic_parser.erl`: Added `parse_jump_statement/1`, `parse_comma_separated_list/1`, `validate_line_targets/1`
- `src/erlbasic_runtime.erl`: Added `execute_on_gosub/7` and `execute_on_goto/7`
- `eunit_tests/erlbasic_eunit_tests.erl`: Added 4 new tests (60 total, up from 56)
- `smoke_tests/on_gosub.bas` and `on_gosub.out`: New smoke test (54 total, up from 53)
- `Basic_Syntax.md`: Added documentation for ON...GOSUB / ON...GOTO

**Test Coverage:**
- Valid index selection (1, 2, 3)
- Out-of-range indices (0, 4+ when only 2-3 targets)
- Return stack management for ON...GOSUB
- All 60 EUnit tests pass
- All 54 smoke tests pass

---

## April 1, 2026 - Add HTTPS Support with Certbot Auto-Renewal

**Commits:** 68c194c, (pending)

### Enhancement
Added comprehensive HTTPS/TLS support to the Cowboy web server with both development (self-signed certificates) and production (Let's Encrypt/Certbot) configurations.

### Implementation
- **HTTPS Listener**: Added `start_https_listener/1` to `erlbasic_sup.erl` that starts a TLS-enabled Cowboy listener using `cowboy:start_tls/3`
- **Optional HTTPS**: HTTPS is opt-in via configuration (`enable_https` flag), keeping HTTP-only development simple
- **Certificate Validation**: Checks for certificate file existence before starting HTTPS listener, providing helpful error messages
- **Configuration System**: Created `sys.config` with examples for development, production, and reverse proxy scenarios
- **Development Tools**: Created `generate_certs.ps1` PowerShell script to generate self-signed certificates with Subject Alternative Names (SANs) for localhost and local network IPs
- **Production Deployment**: Created comprehensive `CERTBOT_DEPLOYMENT.md` guide covering:
  - Initial Let's Encrypt certificate generation with certbot
  - Automatic renewal using systemd timers or cron jobs
  - Certificate copy and permission management
  - Zero-downtime renewal with post-renewal hooks
  - Reverse proxy configuration (nginx) for standard ports
- **Testing Guide**: Created `HTTPS_TESTING.md` with instructions for testing on localhost and local network devices

**Files Changed:**
- `src/erlbasic_sup.erl`: Added `start_https_listener/1` with TLS configuration
- `run.ps1`: Updated to load `sys.config` for runtime configuration
- `sys.config`: New configuration file with HTTP/HTTPS parameters
- `sys.config.https`: Example HTTPS-enabled configuration
- `generate_certs.ps1`: Self-signed certificate generation script with SAN support
- `CERTBOT_DEPLOYMENT.md`: Production deployment guide with auto-renewal
- `HTTPS_TESTING.md`: Local and network testing guide
- `HTTPS_QUICKSTART.md`: Quick reference guide
- `eunit_tests/erlbasic_eunit_tests.erl`: Added 4 HTTPS configuration tests
- `.gitignore`: Updated to exclude certificate secrets

### Configuration Options
```erlang
{erlbasic, [
    {http_port, 8081},           % HTTP listener port
    {enable_https, false},       % Enable/disable HTTPS
    {https_port, 8443},          % HTTPS listener port
    {certfile, "priv/ssl/cert.pem"},
    {keyfile, "priv/ssl/key.pem"},
    {cacertfile, "..."}          % Optional CA certificate
]}
```

### Testing
- Added 4 automated EUnit tests for HTTPS configuration:
  - `https_disabled_by_default_test` - Verifies HTTPS is disabled by default
  - `https_cert_file_validation_test` - Tests certificate file existence checking
  - `https_config_reading_test` - Validates configuration reading/writing
  - `https_ca_cert_optional_test` - Tests optional CA certificate handling
- All 56 EUnit tests pass
- All 53 smoke tests pass
- Manual test: Generated self-signed certificates and verified HTTPS on localhost:8443
- Manual test: Verified certificate includes SANs for localhost and local IP addresses
- Manual test: Confirmed WebSocket connections work over both HTTP and HTTPS (ws:// and wss://)
- Verified graceful failure when certificates are missing (doesn't crash, shows helpful message)

### Rationale
TLS/HTTPS support is essential for production deployment and testing secure connections during development. The implementation provides:

1. **Development Flexibility**: Self-signed certificates with `generate_certs.ps1` allow HTTPS testing on localhost and local network without external dependencies
2. **Production Ready**: Full Let's Encrypt/Certbot integration with automatic renewal prevents certificate expiration
3. **Zero Configuration for Simple Use**: HTTP-only mode remains the default for quick development
4. **Security Best Practices**: Certificate file validation, proper permissions, and secure defaults
5. **WebSocket Compatibility**: WSS (WebSocket Secure) works automatically with HTTPS enabled
6. **Network Testing**: Generated certificates include IP addresses via SANs, enabling testing from mobile devices and other computers on the local network

The automatic renewal system using systemd timers ensures certificates stay valid in production without manual intervention. The guide includes both standalone and reverse proxy configurations to accommodate different deployment scenarios.

---

## March 31, 2026 - Implement SCRATCH Command and Update DIR Output Format

**Commit:** 89223e1

### Enhancement
Added `SCRATCH` command to delete saved programs and improved `DIR` output with RSTS/E style columnar format. Also added 16-character filename limit for SAVE operations.

### Implementation
- `SCRATCH "filename"` — deletes the specified saved program file from the user's priv/accounts directory. Files in the examples/ directory cannot be deleted (protection against accidental deletion of system examples).
- `DIR` command now outputs in RSTS/E style columnar format showing:
  - User's saved programs from priv/accounts/username/ directory
  - Example programs from examples/ directory (marked read-only)
  - File sizes and creation dates
- `SAVE` command now enforces 16-character maximum filename length (matches DEC BASIC / RSTS/E convention)

**Files Changed:**
- `src/erlbasic_commands.erl`: Added `exec_scratch/3`; updated `exec_dir/2` with columnar format; added filename length validation to `exec_save/3`
- `src/erlbasic_storage.erl`: Added `delete_program/2` function with examples/ directory protection
- `src/erlbasic_interp.erl`: Added `"SCRATCH"` to keyword list
- `smoke_tests/filename_length.bas`, `smoke_tests/filename_length.direct`, `smoke_tests/filename_length.out`: Test for filename length limit
- `smoke_tests/scratch_test.bas`, `smoke_tests/scratch_test.direct`, `smoke_tests/scratch_test.out`: Test for SCRATCH command
- `Basic_Syntax.md`: Added SCRATCH documentation and DIR output example
- `README.md`: Updated DIR command description

### Testing
- All smoke tests pass (including new filename_length and scratch_test)
- Manual test: SCRATCH successfully deletes user files but rejects attempts to delete example files

### Rationale
DEC BASIC's SCRATCH command allowed users to delete unwanted saved programs, essential for managing disk space and organizing saved work. The columnar DIR format matches RSTS/E conventions and provides better readability than the previous simple list. The 16-character filename limit matches historical DEC BASIC conventions and prevents excessively long filenames that could cause display issues.
---

## March 31, 2026 - Refactor: Split Interpreter into Commands/State Modules

**Commit:** 17f4e30

### Refactoring
Major code reorganization to improve maintainability by separating concerns and eliminating code duplication.

### Implementation
Created three new/updated modules to extract functionality from the monolithic interpreter:

- `src/erlbasic_state.hrl` — shared `#state{}` record definition (previously copy-pasted between interp and runtime modules)
- `src/erlbasic_commands.erl` — REPL commands extracted from `erlbasic_interp.erl`:
  - File I/O: `SAVE`, `LOAD`, `DIR`, `RENUM`
  - Program text: `LIST`, `DELETE`, `format_program`, `renumber_program`
  - Serialization: `parse_bin_as_program`, `serialize_program`
  - Keyword highlighting: `normalize_keywords_for_list`
- `src/erlbasic_runtime.erl` — exported shared render/eval helpers used by interp:
  - `render_print_items`, `render_print_using_items`, `cls_output`, `eval_color`
  - `apply_dim_decls`, `collect_program_data`, `apply_read_vars`, `eval_locate`
  - `update_pending_input_rest`, `format_input_prompt`
- `src/erlbasic_interp.erl` — reduced from 1158 lines to 491 lines (-667 lines), now focused on REPL dispatch and INPUT continuation

**Files Changed:**
- `src/erlbasic_commands.erl`: New file (449 lines)
- `src/erlbasic_state.hrl`: New file (13 lines)
- `src/erlbasic_interp.erl`: Reduced from 1158 to 491 lines
- `src/erlbasic_runtime.erl`: Added exports for shared functions

### Testing
- All existing tests pass unchanged (no behavior changes)
- All smoke tests pass

### Rationale
The original `erlbasic_interp.erl` had grown to over 1100 lines with mixed concerns (REPL commands, program editing, file I/O, rendering). The `#state{}` record was duplicated between modules. This refactoring:
1. Eliminates code duplication by defining shared state in a header file
2. Groups related functionality (file commands, rendering helpers) into focused modules
3. Makes the codebase more maintainable and easier to navigate
4. Reduces coupling by explicitly exporting shared functions
5. Sets the foundation for future enhancements without growing monolithic modules

---

## March 31, 2026 - Add Enterprise Example

**Commits:** d19952c, c689d9b, e4357ba

### Enhancement
Added a full-featured text adventure game example demonstrating advanced BASIC programming techniques.

### Implementation
Created `examples/enterprise.bas` — a Star Trek themed text adventure game featuring:
- Multiple locations (Bridge, Engineering, Sickbay, Transporter Room, Cargo Bay)
- Inventory system and object interactions
- Energy management mechanics
- Victory/loss conditions
- Demonstrates GOSUBs, arrays, nested IF/THEN, INPUT handling, and program structure

**Files Changed:**
- `examples/enterprise.bas`: New 77-line adventure game
- `priv/www/index.html`: Added Enterprise to example list in web UI
- `README.md`: Updated example description (referenced as "startrek" in UI)

### Testing
- Manual playthrough confirms all game paths work correctly
- All commands (LOOK, TAKE, DROP, USE, GO, INVENTORY) function as designed
- Victory and loss conditions trigger appropriately

### Rationale
The existing examples (flag.bas, tictactoe.bas) demonstrated basic functionality, but a more complex example was needed to showcase:
1. Program structure and organization for larger projects
2. State management across multiple locations
3. Interactive fiction techniques in BASIC
4. Practical use of arrays, GOSUBs, and string handling
The Enterprise example serves as both a playable game and a learning resource for intermediate BASIC programming.

---

## March 31, 2026 - Add TIMER Function and SLEEP Statement

**Commit:** 812cac6

### Enhancement
Added `TIMER` (GW-BASIC) and `SLEEP` (DEC BASIC) to the interpreter.

### Implementation
- `TIMER` — zero-argument numeric function returning seconds elapsed since midnight as a float, matching GW-BASIC behaviour. Implemented via `calendar:local_time/0`.
- `SLEEP n` — statement pausing execution for `n` seconds (integer or float). Calls `timer:sleep/1` which yields the Erlang scheduler so other connections continue unaffected. Negative values are clamped to zero. Passing a string raises `?TYPE MISMATCH ERROR`.

**Files Changed:**
- `src/erlbasic_eval_builtins.erl`: Added `"TIMER"` to `is_builtin_function/1`; added `apply_math_function("TIMER", [])` clause
- `src/erlbasic_parser.erl`: Added `parse_sleep_statement/1`; added `{sleep, Expr}` to `validate_statement/1`
- `src/erlbasic_interp.erl`: Added `"SLEEP"` and `"TIMER"` to keyword list; added `{sleep, Expr}` case to `execute_statement_single/2`
- `src/erlbasic_runtime.erl`: Added `{sleep, Expr}` case to `execute_basic_statement/7`
- `smoke_tests/timer.bas`, `smoke_tests/timer.out`: Smoke test for TIMER
- `smoke_tests/sleep.bas`, `smoke_tests/sleep.out`: Smoke test for SLEEP

### Testing
- All EUnit tests pass
- All 51 smoke tests pass (sleep and timer added)

### Rationale
`TIMER` is essential for timing loops and simple benchmarks, while `SLEEP` is needed for programs that want to pace output or wait between actions (e.g., game loops, animations). Both are standard in GW-BASIC and DEC BASIC. Using `timer:sleep/1` (rather than a busy-wait `receive after` in the runtime) correctly yields the Erlang scheduler without burning CPU.

---

## March 31, 2026 - Add GET and GETKEY Single-Key Input

**Commit:** 46aff02

### Enhancement
Added `GET` (non-blocking single-key read) and `GETKEY` (blocking single-key read) statements matching Commodore BASIC 7.0 / GW-BASIC behaviour for interactive programs.

### Implementation
- `GET A$` — reads one character from the keyboard buffer. If the buffer is empty, the variable is set to `""` and execution continues. Internally the interpreter suspends with `pending_input = {get_nb,...}` and the connection layer waits up to 10 ms before resuming, so a polling loop runs cooperatively at ~100 Hz without spinning the CPU.
- `GETKEY A$` — blocks indefinitely until a keystroke arrives, then assigns the first character to the target variable. Any extra characters are stored in an internal buffer and consumed by subsequent `GET`/`GETKEY` calls.
- WebSocket clients receive `CHAR_MODE_ON` / `CHAR_MODE_OFF` control frames (byte `\x02` prefix) that switch the browser into char mode so individual keystrokes are sent immediately without waiting for Enter.

**Files Changed:**
- `src/erlbasic_parser.erl`: Added `parse_get_statement/1`, `parse_getkey_statement/1`; added `{get,...}` and `{getkey,...}` to `validate_statement/1`
- `src/erlbasic_interp.erl`: Added keyword entries and execution cases for GET/GETKEY; added `char_buffer` field handling
- `src/erlbasic_runtime.erl`: Added `{get,...}` and `{getkey,...}` cases; added `char_buffer` to state record
- `src/erlbasic_conn.erl`: Added `after 10` timeout for GET in both TCP and WebSocket loops; added CHAR_MODE_ON/OFF frame emission
- `priv/www/index.html`: Added `charMode` flag; CHAR_MODE_ON/OFF handling; immediate keystroke send in char mode
- `eunit_tests/erlbasic_eunit_tests.erl`: Added GET/GETKEY tests; updated smoke expected output

### Testing
- All EUnit tests pass
- All 50 smoke tests pass
- Manual WebSocket test: `GET` polling loop runs without browser tab spinning; `GETKEY` blocks cleanly

### Rationale
Without GET/GETKEY, interactive programs (games, menus) must use `INPUT` which requires pressing Enter. Commodity BASICs all provided single-key input for this purpose. Using a 10 ms `after` timeout (rather than `after 0`) in the conn layer prevents the CPU from spinning flat-out in polling loops while keeping latency imperceptible.

---

## March 30, 2026 - Fix Login Hang After Failed Attempts

**Commit:** 93c5f3f

### Bug Fix
Fixed a hang condition when users repeatedly hit enter without logging in. After failed login attempts, the connection previously would hang instead of closing cleanly.

### Problem
The login worker process exits after failed attempts, but the receive loop (TCP) and WebSocket handler didn't properly close the connection. This created a hang when users kept hitting enter without authenticating.

### Solution
For TCP connections: Added `gen_tcp:close(Socket)` when the attempt limit is reached, immediately closing the socket.

For WebSocket connections: Worker sends a `close` message to the WebSocket handler, which returns `{stop, State}` to cleanly terminate the connection.

Set the attempt limit to 4 for both connection types, giving users adequate opportunity to log in while preventing indefinite hangs.

**Files Changed:**
- `src/erlbasic_conn.erl`: Updated `tcp_login_loop/2` and `ws_login_loop/2` to close connections after 4 failed attempts
- `src/erlbasic_ws_handler.erl`: Added handler for `close` message to stop WebSocket connection

### Testing
Manual test:
1. Connect via WebSocket (web terminal) or telnet to port 8080
2. Hit enter 4 times without logging in
3. Connection closes cleanly after 4th attempt with proper disconnect message

### Rationale
The original code assumed that timeout periods or link exits would handle cleanup, but this didn't work for continuous input or WebSocket connections. The fix ensures graceful connection termination regardless of connection type or input timing, preventing resource leaks and improving user experience.

---

## March 30, 2026 - RND() Function Testing and Documentation

**Commit:** 469a06c

### Enhancement
Added comprehensive testing and improved documentation for the RND() function, which was already implemented following DEC BASIC / GW-BASIC syntax.

### Implementation
The RND() function was already correctly implemented with DEC BASIC semantics:
- `RND` or `RND(x)` with x > 0 - returns next random value in range [0, 1)
- `RND(0)` - returns the last random value generated
- `RND(x)` with x < 0 - seeds the random generator deterministically from x

**Files Changed:**
- `eunit_tests/erlbasic_eunit_tests.erl`: Added `rnd_function_test/0` to verify RND behavior
- `smoke_tests/rnd_test.bas` and `smoke_tests/rnd_test.out`: Added smoke test for RND
- `Basic_Syntax.md`: Enhanced documentation with detailed RND examples and clarified DEC BASIC syntax

### Testing
- Added unit test verifying all RND variations (no argument, positive, zero, negative)
- Added smoke test verifying deterministic seeding and last-value retrieval
- All 49 smoke tests pass

### Rationale
While the RND() function was already fully implemented, it lacked comprehensive tests and clear documentation. The DEC BASIC RND syntax allows for reproducible random sequences (via seeding with negative values) which is essential for testing, debugging, and creating games with consistent behavior. The enhanced documentation with examples makes this functionality discoverable to users.

---

## March 30, 2026 - DELETE Command Implementation

**Commit:** ee38a2f

### Enhancement
Added DELETE command to delete single lines or ranges of lines following DEC BASIC syntax.

### Implementation
- `DELETE <line>` - deletes a single line (e.g., `DELETE 20`)
- `DELETE <start>-<end>` - deletes lines in range (e.g., `DELETE 10-50`)
- `DELETE -<end>` - deletes from beginning to line (e.g., `DELETE -30`)
- `DELETE <start>-` - deletes from line to end (e.g., `DELETE 40-`)

**Files Changed:**
- `src/erlbasic_interp.erl`: Added `parse_delete_command/1` and `delete_lines_by_range/2`, updated `exec_immediate/2`
- `Basic_Syntax.md`: Updated documentation with DELETE examples
- `eunit_tests/erlbasic_eunit_tests.erl`: Added `delete_command_test/0` to verify all variations

### Testing
- All 48 smoke tests pass
- Unit test verifies all DELETE variations work correctly

### Rationale
DEC BASIC's DELETE command allowed efficient removal of line ranges without manually deleting each line individually. This is essential for program editing and maintenance, especially when restructuring code or removing large blocks. The syntax mirrors the LIST command for consistency.

---

## March 30, 2026 - LIST Command Range Parameters

**Commit:** bdfb11b

### Enhancement
Added support for LIST command range parameters following GW-BASIC syntax.

### Implementation
- `LIST` - lists entire program (existing behavior)
- `LIST <line>` - lists a single line (e.g., `LIST 20`)
- `LIST <start>-<end>` - lists lines in range (e.g., `LIST 10-50`)
- `LIST -<end>` - lists from beginning to line (e.g., `LIST -30`)
- `LIST <start>-` - lists from line to end (e.g., `LIST 40-`)

**Files Changed:**
- `src/erlbasic_interp.erl`: Added `parse_list_command/1` and `filter_program_by_range/3`, refactored `exec_immediate/2`
- `Basic_Syntax.md`: Updated documentation with LIST examples
- `eunit_tests/erlbasic_eunit_tests.erl`: Added `list_command_test/0` to verify all variations

### Testing
- All 48 smoke tests pass
- Unit test verifies all LIST variations work correctly

### Rationale
GW-BASIC LIST command supported range parameters, allowing users to view specific sections of their program without scrolling through the entire listing. This is particularly useful for large programs and enables efficient program navigation and debugging.

---

## March 30, 2026 - INPUT Prompt Variable Names Fix

**Commit:** c9b10b3

### Problem
The compiler was issuing warnings about unused `target_to_text/1` functions in both `erlbasic_runtime.erl` and `erlbasic_interp.erl`. Initial investigation suggested these were dead code, but further testing revealed they were needed but never called.

### Root Cause
INPUT statements were displaying generic prompts (`"? "`) instead of including the variable name being requested (e.g., `"EXTRA%? "`). The `target_to_text/1` functions existed to format variable names but were never actually invoked by the INPUT handling code.

### Solution
Rather than removing the "unused" functions, we:
1. Added `format_input_prompt/1` helper functions that use `target_to_text/1`
2. Modified both regular and INPUT LINE statement handlers to call `format_input_prompt/1`
3. Updated the functions to handle both single targets and lists of targets

**Files Changed:**
- `src/erlbasic_runtime.erl`: Added helpers and updated 2 INPUT handlers
- `src/erlbasic_interp.erl`: Added helpers and updated 2 INPUT handlers  
- `smoke_tests/error_type_mismatch_plus.out`: Updated to reflect current string concatenation behavior

### Testing
- All 6 EUnit tests pass
- All 48 smoke tests pass
- No compiler warnings

### Rationale
This fix aligns with BASIC language conventions where INPUT prompts should display the variable name(s) being requested, improving user experience by making it clear what input is expected. The compiler warning was actually highlighting a genuine missing feature rather than dead code.

---

---

## April 7, 2026 - Module Refactor: File I/O and Graphics Split into Domain Modules

### Refactoring

Extracted two large domains out of the monolithic `execute_statement_single/2` function in `erlbasic_interp.erl` into dedicated modules with a consistent `execute_stmt/2` dispatch API.

### Motivation

`execute_statement_single/2` had grown to ~400 lines — a single `case` expression containing the full inline implementation of every BASIC statement type.  File I/O alone accounted for ~130 lines (9 statement kinds) and graphics/display for ~90 lines (11 statement kinds).  Two patterns motivated the split:

1. **Cohesion**: file channel logic (`OPEN`, `CLOSE`, `PRINT #`, `WRITE #`, `INPUT #`, `LINE INPUT #`, `FIELD`, `PUT #`, `GET #`) belongs in the module that already owns channel management — `erlbasic_fileio`.
2. **Dependency clarification**: three expression-evaluation helpers (`eval_file_open_args`, `eval_file_close_channels`, `eval_channel_record`) were exported from `erlbasic_runtime` even though they exist solely to pre-evaluate arguments for `erlbasic_fileio` calls.  Moving them to `erlbasic_fileio` removes the awkward cross-module coupling.

### Implementation

#### New: `erlbasic_fileio:execute_stmt/2`

Added a new exported function `execute_stmt(ParsedStmt, State) -> {NewState, Output}` to `erlbasic_fileio` handling all 9 file I/O statement kinds.  Also added `eval_file_open_args/5`, `eval_file_close_channels/4`, and `eval_channel_record/4` (moved from `erlbasic_runtime`).

#### New module: `erlbasic_graphics`

Created `src/erlbasic_graphics.erl` with `execute_stmt/2` handling 11 graphics and display statements: `CLS`, `HGR`, `TEXT`, `PSET`, `LINE`, `LINETO`, `RECT`, `CIRCLE`, `LOCATE`, `COLOR`, `SOUND`.  This module delegates the actual evaluation arithmetic to helpers already in `erlbasic_runtime` (`eval_pset`, `eval_line`, `eval_lineto`, `eval_rect`, `eval_circle`, `eval_locate`, `eval_color`, `eval_sound`, `cls_output`, `hgr_output`, `text_output`).

#### `erlbasic_interp` — statement dispatch slimmed down

All 20 replaced clauses become one-liner delegations:
```erlang
{file_open, _, _, _, _} = Stmt -> erlbasic_fileio:execute_stmt(Stmt, State);
{cls} = Stmt               -> erlbasic_graphics:execute_stmt(Stmt, State);
```

`execute_statement_single` is now ~170 lines (core interpreter logic: `LET`, `PRINT`, `INPUT`, `IF/THEN/ELSE`, `GET`, `GETKEY`, `SLEEP`, `DEF FN`, `DIM`, `DATA/READ`, flow control stubs, and TRON/TROFF).

#### `erlbasic_runtime` — helpers removed

`eval_file_open_args/5`, `eval_file_close_channels/4`, and `eval_channel_record/4` removed from exports and function bodies.  Call sites within `execute_basic_statement` updated to `erlbasic_fileio:eval_file_open_args(...)` etc.

### Line count before → after

| File | Before | After |
|---|---|---|
| `erlbasic_interp.erl` | 734 | 557 (−177) |
| `erlbasic_runtime.erl` | 1474 | 1425 (−49) |
| `erlbasic_fileio.erl` | 592 | 740 (+148) |
| `erlbasic_graphics.erl` | — | 108 (new) |

### Files Changed

- `src/erlbasic_fileio.erl`: Added `execute_stmt/2`, `eval_file_open_args/5`, `eval_file_close_channels/4`, `eval_channel_record/4`
- `src/erlbasic_graphics.erl`: New module — `execute_stmt/2` for graphics and display
- `src/erlbasic_interp.erl`: 20 case clauses replaced with one-liner delegates
- `src/erlbasic_runtime.erl`: Removed 3 exported helpers (now in `erlbasic_fileio`), updated 4 call sites

### Testing

- `.\run_all.ps1`: PASS — build, all 94 EUnit tests, all 64 smoke tests, perf gate

---

## April 7, 2026 - Performance History Tracking; `run_all.ps1` Master Test Script

### Enhancement

Added persistent per-run result history to both performance scripts so regressions can be spotted at a glance, and created a single `run_all.ps1` script that runs every test and benchmark in sequence.

### Implementation

#### Performance history files

Each run appends one Erlang-term line to a text file:

- `perf_tests/perf_runner_history.txt` — `{UnixTimeSecs, GitSha, LifeMs, AsciiLifeMs}.`
- `perf_tests/textlife_history.txt` — `{UnixTimeSecs, GitSha, MinMs, AvgMs, MaxMs}.`

The files are committed to the repo so history is preserved across clones and CI runs.

On each run, the scripts call `file:consult/1` to load history, compare the new result against the last entry, and print a delta line:

```
Vs previous (4840ea7): life.bas +12 ms  asciilife.bas -5 ms
Vs previous (4840ea7): min +5 ms  avg +3.2 ms (+1.6%)  max -10 ms
```

New helper functions added to each escript: `load_history/1`, `save_history/N`, `show_history_comparison/N`, `sign/1`.

The Git short SHA is read at runtime via `os:cmd("git -C <repo> rev-parse --short HEAD")`.

#### `run_all.ps1`

New top-level script running the full pipeline:
1. Build (`.\build.ps1`)
2. EUnit tests
3. Smoke tests
4. Perf gate (`perf_runner.escript`)
5. Textlife benchmark (`textlife_100gen_benchmark.escript`)

Each phase is clearly labelled with coloured headers. Any failure exits immediately.

#### Benchmark output formatting

Improved the textlife benchmark output alignment: `Min/Average/Max` now on separate aligned lines, average shown with one decimal place.

### Files Changed

- `perf_tests/perf_runner.escript`: `show_history_comparison/3`, `save_history/4`, `load_history/1`, `sign/1`; updated `main/1` to call them
- `perf_tests/textlife_100gen_benchmark.escript`: same additions; improved output formatting
- `perf_tests/perf_runner_history.txt`: new — first entry recorded after adding history
- `perf_tests/textlife_history.txt`: new — first entry recorded after adding history
- `run_all.ps1`: new master test runner

### Testing

- `.\run_all.ps1`: PASS — all 94 EUnit tests, all 64 smoke tests, perf gate, benchmark

---

## April 7, 2026 - User Homepages: Run HOME.BAS and Cache Output

### Enhancement

Users can place a BASIC program named `HOME.BAS` in their program directory. When someone visits `/:username`, the server runs the program and serves the terminal output as an HTML page, replacing the placeholder "no home.bas found" default.

### Implementation (commits c11f888, 4840ea7)

#### `erlbasic_homepage_handler` — core logic

Two-phase implementation:

**Phase 1** (c11f888): Added basic handler routing, account lookup, static HTML default page for missing `HOME.BAS`, and the Cowboy route `/:username`.

**Phase 2** (4840ea7): Extended the handler to actually execute `HOME.BAS` and serve the output:

- `read_home_bas/1` — reads `HOME.BAS` or `home.bas` (case fallback) from the user's program directory.
- `run_home_bas/1` — parses the program with `erlbasic_commands:parse_bin_as_program/1`, creates a fresh `#state{}`, and runs it in a spawned process with a 5-second timeout.  Output is collected by the parent via `receive`.  Control frames (bytes starting with `<<2, _/binary>>`) are filtered out; carriage returns and the trailing "Program ended" suffix are stripped.
- `execute_home_bas/3` — checks the ETS cache before running; calls `detect_dynamic/1` to pick a TTL; stores the result.

#### Caching (`init_cache/0`, `cache_lookup/2`, `cache_store/4`)

Output is cached in an ETS table named `erlbasic_home_cache`, keyed by `{Project, Programmer}`, with the file's SHA-256 hash stored alongside so a changed file immediately invalidates the entry.

`detect_dynamic/1` scans the uppercased program source for keywords:

| Keyword detected | TTL |
|---|---|
| `INPUT`, `INKEY$`, `GETKEY`, `RND`, `RANDOMIZE` | `never` (not cached) |
| `TIME$`, `TIMER` | 30 seconds |
| `DATE$` | 3600 seconds |
| (none of the above) | `infinity` (until file changes) |

`erlbasic_app:start/2` calls `erlbasic_homepage_handler:init_cache/0` before starting the supervisor so the table exists before any HTTP request arrives.

#### Default page

When `HOME.BAS` is absent, `default_homepage/4` returns a styled HTML page explaining how to create one, showing the username, display name, and PPN.

#### Route registration (`erlbasic_sup`)

```erlang
{"/:username",  erlbasic_homepage_handler, []},
{"/:username/", erlbasic_homepage_handler, []},
```

Both the bare and trailing-slash forms are handled.  The fallback `{'_', erlbasic_http_handler, []}` serves `index.html` for all other paths.

### Files Changed

- `src/erlbasic_homepage_handler.erl`: New module (254 lines) — full homepage serving, caching, HTML generation
- `src/erlbasic_sup.erl`: Added `/:username` and `/:username/` routes; calls `init_cache/0`
- `src/erlbasic_app.erl`: Added `erlbasic_homepage_handler:init_cache()` call in `start/2`
- `src/erlbasic_commands.erl`: Added `parse_bin_as_program/1` (used by homepage runner)

### Security Notes

- The program runs in a spawned Erlang process under the normal interpreter; all existing sandboxing (file path validation, memory watchdog, SLEEP cap) applies.
- The 5-second execution timeout prevents any homepage from holding up an HTTP worker indefinitely.
- HTML output is passed through `escape_html/1` before insertion into the page template.
- The spawned program process does not inherit the HTTP connection's PPN, so it sees `undefined` storage context and cannot access other users' files.

### Testing

- `.\run_all.ps1`: PASS — all 94 EUnit tests, all 64 smoke tests, perf gate
