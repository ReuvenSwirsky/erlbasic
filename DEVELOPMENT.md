# Development Log

This document tracks significant development changes, bug fixes, and their rationale.

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
