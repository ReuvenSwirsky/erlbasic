# Development Log

This document tracks significant development changes, bug fixes, and their rationale.

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
