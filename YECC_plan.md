# YECC Parser Migration Plan

## Overview
Systematically migrate from hand-rolled regex parsing inside yecc grammar to proper token-based grammar productions. Current state: No-arg statements (Phase 1 starter) complete. This plan breaks the work into incremental, testable milestones.

**Architecture**: Lexer → Yecc Grammar → Facade Validation  
**Test Validation**: Build + run_tests.ps1 must pass after each phase  
**Git Strategy**: Atomic commits per statement family

---

## ✅ Phase 1: Tokenize No-Arg Statements (COMPLETE)

No-arg keywords that take no parameters or trailing text.

- [x] Convert RETURN to bare token production
- [x] Convert END to bare token production
- [x] Convert STOP to bare token production
- [x] Convert CLS to bare token production
- [x] Convert HGR to bare token production
- [x] Convert HGR2 to bare token production
- [x] Convert TEXT to bare token production
- [x] Convert TRON to bare token production
- [x] Convert TROFF to bare token production
- [x] Convert FLUSH to bare token production
- [x] Update lexer: emit bare token when no trailing text for no-arg keywords
- [x] Remove parse_noarg_stmt/2 helper function
- [x] Remove parse_flush_stmt/1 wrapper function
- [x] Build and validate (no warnings)
- [x] Run full test suite (all 33 tests pass)
- [x] Git commit: "yecc phase1: tokenize no-arg statements and prune parser dead code"

**Checkpoint Status**: COMPLETE (Commit 8b4c3a1)  
**Code Reduction**: -616 lines (dead code removal) / +20 lines (lexer logic)

---

## 📋 Phase 1: Expansion - Medium-Shape Statements (SINGLE VALUE EXPRESSIONS)

Statements that take a single line number or simple expression; one discrete value.

### Group 1A: Line Reference Statements (GOTO, GOSUB, RESUME)

- [x] **GOTO Statement**
  - [x] Create tokenize_goto_statement/1 in lexer
  - [x] Extract line number from text after GOTO
  - [x] Update grammar: replace `kw_goto text` with `kw_goto line_number`
  - [x] Remove parse_goto_stmt/1 from grammar
  - [x] Build validation
  - [x] Test: goto smoke tests pass
  - [x] Git commit: "phase1: tokenize GOTO statement"

- [x] **GOSUB Statement**
  - [x] Create tokenize_gosub_statement/1 in lexer
  - [x] Extract line number from text after GOSUB
  - [x] Update grammar: replace `kw_gosub text` with `kw_gosub line_number`
  - [x] Remove parse_gosub_stmt/1 from grammar
  - [x] Build validation
  - [x] Test: gosub smoke tests pass
  - [x] Git commit: "phase1: tokenize GOSUB statement"

- [x] **RESUME Statement**
  - [x] Create tokenize_resume_statement/1 in lexer (already partially done - check if present)
  - [x] Handle three forms: bare RESUME, RESUME NEXT, RESUME line_number
  - [x] Update grammar to use structured tokens
  - [x] Remove parse_resume_stmt/1 from grammar (no such function existed)
  - [x] Build validation
  - [x] Test: resume smoke tests pass
  - [x] Git commit: "phase1: tokenize RESUME statement"

### Group 1B: Buffer/Sleep (ON/OFF or Optional numeric)

- [x] **BUFFER Statement**
  - [x] Create tokenize_buffer_statement/1 in lexer
  - [x] Parse ON / OFF flags
  - [x] Update grammar to structured tokens
  - [x] Remove parse_buffer_stmt/1 from grammar
  - [x] Build validation
  - [x] Test: buffer smoke tests pass
  - [x] Git commit: "phase1: tokenize BUFFER statement"

- [x] **SLEEP Statement**
  - [x] Create tokenize_sleep_statement/1 in lexer
  - [x] Handle: bare SLEEP or SLEEP numeric_value
  - [x] Update grammar to structured tokens
  - [x] Remove parse_sleep_stmt/1 from grammar
  - [x] Build validation
  - [x] Test: smoke tests pass
  - [x] Git commit: "phase1: tokenize SLEEP statement"

### Group 1C: Simple Assignment-like Statements

- [x] **LET Statement**
  - [x] Create tokenize_let_statement/1 in lexer
  - [x] Parse: var_name = expression
  - [x] Update grammar to structured tokens
  - [x] Keep fallback parse_let_stmt/1 path for malformed input compatibility
  - [x] Build validation
  - [x] Test: assignment smoke tests pass
  - [ ] Git commit: "phase1: tokenize LET statement"

- [x] **LOCATE Statement**
  - [x] Create tokenize_locate_statement/1 in lexer
  - [x] Parse: row, column (comma-separated coordinates)
  - [x] Update grammar to structured tokens
  - [x] Remove parse_locate_stmt/1 from grammar
  - [x] Build validation
  - [x] Test: locate smoke tests pass
  - [x] Git commit: "phase1: tokenize LOCATE statement"

- [x] **PSET Statement**
  - [x] Create tokenize_pset_statement/1 in lexer
  - [x] Parse: (x, y, color) with optional color
  - [x] Update grammar to structured tokens
  - [x] Remove parse_pset_stmt/1 from grammar
  - [x] Build validation
  - [x] Test: pset smoke tests pass
  - [x] Git commit: "phase1: tokenize PSET statement"

### Phase 1 Expansion Validation 

- [x] Run full test suite after all Group 1A statements
- [x] Run full test suite after all Group 1B statements
- [x] Run full test suite after all Group 1C statements

### Check these after each group
- [x] All 33+ tests pass (verified after Group 1C completion)
- [x] Verify zero compiler warnings (BUILD SUCCEEDED with no warnings)
- [x] Git checkpoint: "phase1-expansion: complete medium-shape tokenization"

**Group 1A Status**: ✅ COMPLETE
- Commits: 2b79161 (GOTO/GOSUB), 3fbfe0b (RESUME)
- All three line-reference statements now tokenized with structured `line_number` tokens
- Grammar updated to use direct token productions instead of text parsing
- No regressions: All 33+ tests pass, build clean

---

## 📋 Phase 2: Complex Statements - PRINT/WRITE Family

PRINT and WRITE statements with separator logic (comma/semicolon), multiple items, USING clause.

### Print Statement Variants

- [x] **PRINT Statement (no args)**
  - [x] Create tokenize_print_statement/1 in lexer
  - [x] Handle bare PRINT (newline equivalent)
  - [x] Update grammar
  - [x] Keep `parse_print_stmt/1` fallback for compatibility/error-path parity (final removal deferred to Phase 7 cleanup)
  - [x] Build and test
  - [x] Git commit: "phase2: tokenize PRINT bare case" (covered by dcf1627)

- [x] **PRINT with items and separators**
  - [x] Enhance tokenize_print_statement/1 to parse comma/semicolon separators
  - [x] Tokenize print item sequence
  - [x] Update grammar for print_items nonterminal
  - [x] Handle USING clause (tokenized via `print_using`)
  - [x] Build and test
  - [x] Git commit: "phase2: tokenize PRINT with items and separators" (dcf1627 + 95c5609)

- [x] **WRITE Statement (file-less variant)**
  - [x] Create tokenize_write_statement/1 in lexer
  - [x] Not applicable in current dialect: language/runtime spec supports `WRITE #` channel form
  - [x] Update grammar (channel forms tokenized)
  - [x] Build and test
  - [x] Git commit: "phase2: tokenize WRITE statement" (covered by dcf1627)

- [x] **PRINT# to file**
  - [x] Extend tokenize_print_statement/1 to handle PRINT#channel
  - [x] Parse channel number and items
  - [x] Update grammar for file variant
  - [x] Build and test
  - [x] Git commit: "phase2: tokenize PRINT# to file" (covered by dcf1627)

### Phase 2 Validation

- [x] Run full test suite after PRINT family complete
- [x] All tests pass, no warnings
- [x] Run full test suite after current Phase 2 slice
- [x] Current slice tests pass, no warnings
- [x] Git checkpoint: "phase2: print/write tokenization complete" (dcf1627, 95c5609)

---

## 📋 Phase 3: FILE I/O Statements (OPEN/CLOSE/FIELD/PUT/GET)

File operations with channel numbers, mode keywords, record sizes.

- [ ] **OPEN Statement**
  - [x] Create tokenize_open_statement/1 in lexer
  - [x] Parse: FOR mode, file name, channel, RECORD size
  - [x] Update grammar
  - [ ] Remove parse_open_stmt/1 legacy (fallback retained for compatibility)
  - [x] Build and test
  - [ ] Git commit: "phase3: tokenize OPEN statement"

- [ ] **CLOSE Statement**
  - [x] Create tokenize_close_statement/1 in lexer
  - [x] Parse: channel numbers (may be comma-separated)
  - [x] Update grammar
  - [x] Build and test
  - [ ] Git commit: "phase3: tokenize CLOSE statement"

- [ ] **FIELD Statement**
  - [x] Create tokenize_field_statement/1 in lexer
  - [x] Parse: channel, field_size, var_name sequences
  - [x] Update grammar
  - [x] Build and test
  - [ ] Git commit: "phase3: tokenize FIELD statement"

- [ ] **PUT/GET Statements**
  - [x] Create tokenize_put_get_statement/1 in lexer (implemented as tokenize_put_statement/1 + tokenize_get_statement/1)
  - [x] Parse: channel, record_number (optional)
  - [x] Update grammar
  - [x] Build and test
  - [ ] Git commit: "phase3: tokenize PUT/GET statements"

### Phase 3 Validation

- [x] Run full test suite after FILE I/O statements complete
- [x] All tests pass
- [ ] Git checkpoint: "phase3: file-io tokenization complete"

---

## 📋 Phase 4: ARRAY / DECLARATION Statements (DIM/DEF FN)

Array declarations with bounds, function definitions with parameters.

- [x] **DIM Statement**
  - [x] Create tokenize_dim_statement/1 in lexer
  - [x] Parse: variable names and array bounds (brackets with commas)
  - [x] Handle multi-dimensional arrays
  - [x] Update grammar to structured dim_declarations nonterminal
  - [x] Remove parse_dim_stmt/1 legacy logic
  - [x] Build and test
  - [x] Git commit: "phase4: tokenize DIM statement"

- [x] **DEF FN Statement**
  - [x] Create tokenize_def_fn_statement/1 in lexer
  - [x] Parse: function name, parameter list, expression body
  - [x] Update grammar
  - [x] Build and test
  - [x] Git commit: "phase4: tokenize DEF FN statement"

- [ ] **REDIM Statement** (if applicable)
  - [ ] Create tokenize_redim_statement/1 in lexer
  - [ ] Similar to DIM but for reallocation
  - [ ] Build and test
  - [ ] Git commit: "phase4: tokenize REDIM statement"

### Phase 4 Validation

- [x] Run full test suite after DIM/DEF statements complete
- [x] All tests pass
- [x] Git checkpoint: "phase4: array/declaration tokenization complete"

---

## 📋 Phase 5: LOOP CONTROL Statements (FOR/NEXT/DO/LOOP)

Loop structure statements with complex variable binding and expressions.

- [ ] **FOR Statement** (if not already tokenized)
  - [ ] Verify tokenize_for_statement/1 in lexer (check if partial or full)
  - [ ] Parse: loop variable, start, end, optional step
  - [ ] Update grammar if needed
  - [ ] Build and test
  - [ ] Git commit: "phase5: verify FOR statement tokenization"

- [ ] **NEXT Statement** (if not already tokenized)
  - [ ] Verify tokenize_next_statement/1 in lexer
  - [ ] Parse: variable names (may be comma-separated)
  - [ ] Update grammar if needed
  - [ ] Build and test
  - [ ] Git commit: "phase5: verify NEXT statement tokenization"

- [ ] **DO/LOOP Statements** (if present in dialect)
  - [ ] Create tokenize_do_loop_statement/1 in lexer
  - [ ] Parse loop control keywords
  - [ ] Build and test
  - [ ] Git commit: "phase5: tokenize DO/LOOP statements"

- [ ] **WHILE/WEND Statements** (if present)
  - [ ] Create tokenize_while_statement/1 in lexer
  - [ ] Build and test
  - [ ] Git commit: "phase5: tokenize WHILE/WEND statements"

### Phase 5 Validation

- [ ] Run full test suite after loop statements complete
- [ ] All tests pass
- [ ] Git checkpoint: "phase5: loop-control tokenization complete"

---

## 📋 Phase 6: CONDITIONAL Statements (IF/THEN/ELSE)

Complex conditional logic with multiple branches and optional actions.

- [ ] **IF/THEN Statement** (if not already tokenized)
  - [ ] Verify tokenize_if_statement/1 in lexer (check current state)
  - [ ] Parse: condition, THEN clause, optional ELSE
  - [ ] Handle single-line and block IF forms
  - [ ] Update grammar if needed
  - [ ] Build and test
  - [ ] Git commit: "phase6: verify IF/THEN/ELSE tokenization"

- [ ] **SELECT/CASE Statements** (if present)
  - [ ] Create tokenize_select_statement/1 in lexer
  - [ ] Parse: expression and case labels
  - [ ] Build and test
  - [ ] Git commit: "phase6: tokenize SELECT/CASE statements"

- [ ] **ON GOTO/GOSUB** (multi-branch dispatch)
  - [ ] Verify tokenize_on_statement/1 in lexer
  - [ ] Parse: expression and line numbers
  - [ ] Build and test
  - [ ] Git commit: "phase6: verify ON GOTO/GOSUB tokenization"

### Phase 6 Validation

- [ ] Run full test suite after conditional statements complete
- [ ] All tests pass
- [ ] Git checkpoint: "phase6: conditional-statement tokenization complete"

---

## 📋 Phase 7: CLEANUP & VALIDATION

Remove all remaining hand-rolled regex helpers and dead code.

- [ ] **Audit remaining parse_*_stmt functions in grammar**
  - [ ] List all remaining text-parsing action functions
  - [ ] Verify which are truly no longer used
  - [ ] Remove dead ones
  - [ ] Git commit: "phase7: remove dead parse_*_stmt helpers"

- [ ] **Audit remaining helper functions in facade (erlbasic_parser.erl)**
  - [ ] Check validate_statement_sequence/1 and derivatives
  - [ ] Determine if validation logic can move into lexer/grammar or remain in facade
  - [ ] Remove any redundant helpers
  - [ ] Git commit: "phase7: simplify parser facade"

- [ ] **Lexer refactoring**
  - [ ] Consolidate tokenize_* functions into unified dispatch if appropriate
  - [ ] Remove any now-dead split_leading_keyword/2 clauses
  - [ ] Optimize token classification
  - [ ] Git commit: "phase7: refactor lexer clarity"

- [ ] **Final validation**
  - [ ] Build with zero warnings
  - [ ] Run full test suite (all tests pass)
  - [ ] Review codebase metrics (lines of code, cyclomatic complexity)
  - [ ] Git commit: "phase7: parser cleanup and validation complete"

- [ ] **Documentation update**
  - [ ] Update parser architecture docs if present (e.g., DEVELOPMENT.md)
  - [ ] Document new grammar structure and token types
  - [ ] Record lessons learned
  - [ ] Git commit: "docs: update parser architecture documentation"

### Phase 7 Validation

- [ ] Zero compiler warnings
- [ ] All 33+ tests pass
- [ ] Git checkpoint: "phase7: YECC migration complete"

---

## 📋 Testing Strategy (Per Phase)

For each phase, follow this validation sequence:

1. **Compile Check**
   ```bash
   .\build.ps1
   ```
   - Ensure no errors or warnings
   - If warnings appear, check the "debugging.md" memory note about duplicated declarations

2. **Test Execution**
   ```bash
   .\run_tests.ps1
   ```
   - All 33+ tests must pass
   - No flaky failures

3. **Smoke Tests**
   - Run specific .bas files from smoke_tests/ for the statement family being converted
   - Verify parse trees match pre-conversion output format

4. **Git Commit**
   - Atomic commit per statement family
   - Use pattern: "phaseN: tokenize STATEMENT(S) description"
   - Include before/after metrics in commit body if significant code reduction

---

## Progress Tracking

Use checkboxes above to track completion. As of last checkpoint:

- ✅ Phase 1 (no-arg statements): COMPLETE
- ✅ Phase 1-Expansion (medium-shape): COMPLETE
  - ✅ Group 1A (GOTO, GOSUB, RESUME): COMPLETE (Commits 2b79161, 3fbfe0b)
  - ✅ Group 1B (BUFFER, SLEEP): COMPLETE
  - ✅ Group 1C (LET, LOCATE, PSET): COMPLETE
- ✅ Phase 2 (PRINT/WRITE): COMPLETE (core tokenization done; compatibility fallbacks retained by design)
- 🔄 Phase 3 (FILE I/O): PARTIAL (OPEN/CLOSE/FIELD/PUT/GET tokenized; legacy fallback cleanup and final checkpoint pending)
- ⏳ Phase 4 (DIM/DEF): QUEUED
- ⏳ Phase 5 (LOOP): QUEUED
- ⏳ Phase 6 (CONDITIONALS): QUEUED
- ⏳ Phase 7 (CLEANUP): FINAL

---

## Key Files to Reference

- **Lexer**: [src/erlbasic_parser_yecc_lexer.erl](src/erlbasic_parser_yecc_lexer.erl)
- **Grammar**: [src/erlbasic_parser_yecc.yrl](src/erlbasic_parser_yecc.yrl)
- **Facade**: [src/erlbasic_parser.erl](src/erlbasic_parser.erl)
- **Smoke Tests**: [smoke_tests/](smoke_tests/) (*.bas files)
- **Build Script**: [build.ps1](build.ps1)
- **Test Script**: [run_tests.ps1](run_tests.ps1)

---

## Notes

- **Lexer Design**: Already has pattern for specialized tokenizers (IF, FOR, ON, RESUME). Extend this pattern for each new statement family.
- **Grammar Pattern**: Replace `stmt -> kw_* text : parse_*_stmt(...)` with `stmt -> kw_* token1 token2 ... : {Result}` where tokens come from lexer.
- **Code Reduction**: Each phase should reduce dead code (remove old parse_*_stmt helpers) more than it adds (new lexer tokenizers). Target ~2:1 deletion ratio.
- **Test Coverage**: All existing tests should continue to pass. No behavioral changes; only internal architecture refactoring.
- **Risk Mitigation**: Do not attempt multiple statement families in a single commit. Keep Git history atomic and bisectable.
