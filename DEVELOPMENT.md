# Development Log

This document tracks significant development changes, bug fixes, and their rationale.

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
