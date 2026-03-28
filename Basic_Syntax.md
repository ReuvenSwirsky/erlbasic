# BASIC Syntax Reference

This document describes the currently supported syntax for erlbasic.

## Program Structure

A stored program line starts with a numeric line number:

```text
10 PRINT "HELLO"
20 END
```

Rules:
- Line numbers are integers.
- Entering a line number with no code deletes that line:

```text
20
```

## REPL Commands

These commands can be entered without a line number:

- `LIST` - prints all stored program lines in numeric order.
- `RUN` - executes the stored program.
- `NEW` - clears the stored program.
- `QUIT` - disconnects from the TCP session.

## Statements

Statements can be used in immediate mode (no line number) and in stored programs, unless noted.

### LET

Assigns an expression to a variable.

```text
LET X = 42
LET NAME = "ALICE"
```

Variable rules:
- Variable names: `[A-Za-z][A-Za-z0-9_]*`
- Variable lookup is case-insensitive (`x`, `X`, and `x` all refer to the same variable).

### PRINT

Prints an expression value.

```text
PRINT X
PRINT "HELLO"
PRINT 123
```

### END

Stops execution of a running stored program.

```text
END
```

### IF ... THEN ... [ELSE ...]

Conditional statement.

```text
IF X = 10 THEN PRINT "TEN"
IF X > 0 THEN PRINT "POS" ELSE PRINT "NONPOS"
```

THEN/ELSE bodies can contain one statement or multiple statements separated by `:`.

```text
IF X = 1 THEN LET Y = 7 : PRINT Y ELSE PRINT 0
```

### FOR ... TO ... [STEP ...]

Loop statement (intended for program execution with `RUN`).

```text
FOR I = 1 TO 10
PRINT I
NEXT
```

With explicit step:

```text
FOR I = 10 TO 1 STEP -1
PRINT I
NEXT I
```

Notes:
- If `STEP` is omitted, step defaults to `1`.
- A step of `0` is normalized to `1`.

### NEXT [var]

Advances the active FOR loop.

```text
NEXT
NEXT I
```

## Multiple Statements on One Line

Top-level statement chaining is supported using `:` for non-IF lines:

```text
LET A = 5 : PRINT A
```

Inside IF branches, chaining is also supported:

```text
IF A = 5 THEN PRINT "YES" : LET B = 9 ELSE PRINT "NO"
```

A colon inside a quoted string does not split statements:

```text
PRINT "A:B"
```

## Expressions

Supported expression forms:
- Integer literal: `123`
- Quoted string literal: `"HELLO"`
- Variable reference: `X`

Undefined variables evaluate to `0`.

Arithmetic expressions are not implemented yet (for example `X + 1`).

## Conditions

Supported comparison operators in IF conditions:
- `=`
- `<>`
- `<`
- `>`
- `<=`
- `>=`

Examples:

```text
IF X <> 0 THEN PRINT "NONZERO"
IF NAME = "ALICE" THEN PRINT "HI"
```

If no comparison operator is present, truthiness is used:
- Integer: true if not `0`
- String: true if not empty/whitespace

## Current Limitations

- No GOTO/GOSUB/RETURN.
- No arithmetic parser (only literal/variable expression forms).
- FOR/NEXT is designed for `RUN` execution; using these in immediate mode returns `?SYNTAX ERROR`.
