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
- `RENUM [start[,increment]]` - renumbers stored program lines in order (defaults: `10,10`) and updates direct `GOTO`/`GOSUB` line-number references.
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
- Variable names: `[A-Za-z][A-Za-z0-9_]*` with optional trailing `$` for string-style names or `%` for integer-style names
- Variable lookup is case-insensitive (`x`, `X`, and `x` all refer to the same variable).

Examples:

```text
LET A$ = "HELLO"
PRINT A$
LET I% = 42
PRINT I%
```

### DEF FN

Defines a user function (GW-BASIC style) for use in expressions.

```text
DEF FNQ(X)=X*X+1
PRINT FNQ(3)
```

Notes:
- Function names use `FN` prefix (for example, `FNQ`, `FNSCORE`).
- Parameter is optional in this interpreter (`DEF FNPI=3.14159` style), but standard usage is one parameter.
- Function names and parameter names are case-insensitive.

### PRINT

Prints an expression value.

```text
PRINT X
PRINT "HELLO"
PRINT 123
```

### INPUT

Reads a value from the user and stores it in a variable.

```text
INPUT N
INPUT A$
```

Notes:
- Numeric variables parse the entered text as an integer expression.
- Variables ending in `$` store the entered text as a string.
- Variables ending in `%` behave like integer-style numeric variables.
- During `RUN`, program execution pauses until a value is entered.

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

### GOTO

Jumps to a target line number during `RUN`.

```text
GOTO 200
```

### GOSUB / RETURN

Calls a subroutine line and returns to the line after `GOSUB`.

```text
10 GOSUB 100
20 PRINT "BACK"
30 END
100 PRINT "SUB"
110 RETURN
```

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
- Floating-point literal: `3.14`, `.5`
- Quoted string literal: `"HELLO"`
- Variable reference: `X`
- Arithmetic with numbers and variables: `+`, `-`, `*`, `/`, `^`, parentheses, unary `+`/`-`
- GW-BASIC-compatible numeric operators:
	- Integer division: `\\`
	- Modulus: `MOD`
- Built-in numeric functions (case-insensitive):
	- Single-argument: `ABS`, `ACOS`, `ASIN`, `ATAN`, `ATN`, `COS`, `DEG`, `EXP`, `FIX`, `INT`, `LN`, `LOG`, `RAD`, `SGN`, `SIN`, `SQR`, `SQRT`, `TAN`
	- Two-argument: `ATAN2`, `POW`
	- Zero-argument: `PI`, `RND`
- Built-in string functions (case-insensitive):
	- `LEFT$(text, n)`
	- `RIGHT$(text, n)`
	- `MID$(text, start[, n])` (1-based start index)
	- `LEN(text)`
	- `DATE$()` (local date in `MM-DD-YYYY`)
	- `TIME$()` (local time in `HH:MM:SS`)
- User-defined function calls with `DEF FN...` syntax: `FNQ(3)`

Examples:

```text
LET X = 2 + 3 * 4
PRINT (X - 2) / 3
PRINT SIN(PI() / 2)
PRINT SQRT(16)
PRINT LEFT$("HELLO", 2)
PRINT MID$("HELLO", 2, 3)
PRINT DATE$()
PRINT TIME$()
```

Undefined variables evaluate to `0`.

GW-BASIC alignment notes:
- `^` binds tighter than unary `-`, so `-2^2` evaluates as `-(2^2)` and yields `-4`.
- `/` performs floating-point division.
- `\\` performs integer division.
- `MOD` returns remainder.
- `RND` behavior follows GW-BASIC style:
	- `RND` or `RND(x)` with `x > 0`: next pseudo-random value.
	- `RND(0)`: repeat the previous random value.
	- `RND(x)` with `x < 0`: reseed deterministically from `x` and return the first value from that seed.
- Runtime math errors use GW-BASIC-style messages and stop `RUN`:
	- `?DIVISION BY ZERO ERROR`
	- `?ILLEGAL FUNCTION CALL`

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


