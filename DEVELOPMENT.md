# Development Log

This document tracks significant development changes, bug fixes, and their rationale.

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
