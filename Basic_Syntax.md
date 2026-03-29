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
- `CONT` - continues execution after a `BREAK` caused by Ctrl-C during `RUN`.
- `NEW` - clears the stored program.
- `DIR` - lists saved program files for the current user.
- `SAVE <name>` - saves the current stored program to a file.
- `LOAD <name>` - loads a saved program file into memory.
- `RENUM [start[,increment]]` - renumbers stored program lines in order (defaults: `10,10`) and updates direct `GOTO`/`GOSUB` line-number references.
- `QUIT` - disconnects from the TCP session.

Notes:
- `CONT` without a prior break context raises `?CAN'T CONTINUE ERROR`.
- Saved programs are stored under the user's home directory in `BASIC/<user-id>`.
- If no user id is set for the session, `default` is used.

## Statements

Statements can be used in immediate mode (no line number) and in stored programs, unless noted.

### LET

Assigns an expression to a variable.

```text
LET X = 42
LET NAME = "ALICE"
```

Array assignment is also supported:

```text
LET A(0) = 10
LET GRID(1,2) = 42
LET CUBE(1,1,1) = 99
```

Variable rules:
- Variable names: `[A-Za-z][A-Za-z0-9_]*` with optional trailing `$` for string-style names or `%` for integer-style names
- Variable lookup is case-insensitive (`X`, and `x` refer to the same variable).

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
? X
```

`?` is accepted as a shorthand synonym for `PRINT`.

`PRINT` also supports separator control between items:

```text
PRINT "A", "B"
PRINT "A"; "B"
PRINT "A";
PRINT "B"
```

Notes:
- `,` advances to the next print zone (14 columns).
- `;` concatenates adjacent output with no extra spacing.
- A trailing `;` suppresses newline so the next `PRINT` continues on the same line.

### PRINT USING

Formats values with a format expression.

```text
PRINT USING "###.##"; 12.3
PRINT USING "&"; "HELLO"; "!"
```

Supported format forms:
- Numeric mask: `#` with optional decimal point (for example `###`, `###.##`).
- String slot: `&` (replaces the first `&` with the value text).

Notes:
- The format expression must evaluate to a string.
- Non-numeric values used with numeric masks raise `?TYPE MISMATCH ERROR`.
- Separators `,` and `;` after formatted items follow the same spacing/newline rules as `PRINT`.

### INPUT

Reads a value from the user and stores it in a variable.

```text
INPUT N
INPUT A$
INPUT A(3)
```

Notes:
- Numeric variables parse the entered text as an integer expression.
- Variables ending in `$` store the entered text as a string.
- Variables ending in `%` behave like integer-style numeric variables.
- During `RUN`, program execution pauses until a value is entered.

### LOCATE

Moves the cursor to a row and column.

```text
LOCATE 5, 10
```

Notes:
- Row and column expressions are evaluated and normalized to integers.
- Minimum position is row `1`, column `1`.
- Cursor movement is supported for WebSocket/xterm sessions.
- On telnet/TCP sessions, `LOCATE` raises `?TTY DOESN'T SUPPORT CURSOR MOVEMENT`.

### SAVE

Saves the current stored program to disk.

```text
SAVE DEMO
SAVE myprog.bas
```

Notes:
- The file is saved to `~/BASIC/<user-id>/`.
- Filenames are normalized for safety.
- File write failures raise `?FILE ERROR`.

### LOAD

Loads a saved program from disk, replacing the current stored program.

```text
LOAD DEMO
LOAD myprog.bas
```

Notes:
- Files are loaded from `~/BASIC/<user-id>/`.
- Missing or unreadable files raise `?FILE ERROR`.

### DIR

Lists saved program files for the current user.

```text
DIR
```

Notes:
- Lists files from `~/BASIC/<user-id>/`.
- If no files exist, no filenames are printed.

### DATA

Declares literal values that can be consumed sequentially by `READ`.

```text
DATA 10, 20, "HELLO"
```

Notes:
- `DATA` is used by `READ` during program execution.
- Items are consumed in program order.

### READ

Reads one or more values from `DATA` into variables.

```text
READ A, B, NAME$
READ A(0), GRID(1,2)
READ CUBE(0,0,0)
```

Notes:
- String variables (ending in `$`) receive text values.
- Numeric variables receive numeric values.
- Reading past available `DATA` raises `?OUT OF DATA ERROR`.

### END

Stops execution of a running stored program.

```text
END
```

### DIM

Declares 1D, 2D, or 3D arrays and their upper bounds.

```text
DIM A(10)
DIM M(5,5), N$(3)
DIM CUBE(2,2,2)
```

Notes:
- Indices are zero-based (`0..upper_bound`).
- One-, two-, and three-dimensional arrays are supported.
- Using an index outside the declared bounds raises `?ILLEGAL FUNCTION CALL`.

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

Notes:
- Executing `RETURN` without an active `GOSUB` stack raises `?RETURN WITHOUT GOSUB ERROR`.

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
- Array reference: `A(I)`, `M(I,J)`, `CUBE(I,J,K)`
- Arithmetic with numbers and variables: `+`, `-`, `*`, `/`, `^`, parentheses, unary `+`/`-`
- GW-BASIC-compatible numeric operators:
	- Integer division: `\\`
	- Modulus: `MOD`
- Built-in numeric functions (case-insensitive):
	- Single-argument: `ABS`, `ACOS`, `ASIN`, `ATAN`, `ATN`, `CEIL`, `COS`, `DEG`, `EXP`, `FIX`, `FLOOR`, `INT`, `LN`, `LOG`, `RAD`, `SGN`, `SIN`, `SQR`, `SQRT`, `TAN`, `VAL`
	- Two-argument: `ATAN2`, `POW`
	- Zero-argument: `PI`, `RND`
- Built-in string functions (case-insensitive):
	- `LEFT$(text, n)`
	- `RIGHT$(text, n)`
	- `MID$(text, start[, n])` (1-based start index)
	- `LEN(text)`
	- `ASC(text)`
	- `CHR$(code)`
	- `STR$(number)`
	- `DATE$()` (local date in `MM-DD-YYYY`)
	- `TIME$()` (local time in `HH:MM:SS`)
	- `TERM$()` (`"XTERM"` for WebSocket terminal sessions, `"TELNET"` for TCP/telnet sessions)
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
PRINT TERM$()
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
	- `?OUT OF DATA ERROR`
	- `?TYPE MISMATCH ERROR`
	- `?CAN'T CONTINUE ERROR`
	- `?RETURN WITHOUT GOSUB ERROR`

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


