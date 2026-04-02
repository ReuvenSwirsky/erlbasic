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
- `LIST <line>` - prints a single line.
- `LIST <start>-<end>` - prints lines in the given range.
- `LIST -<end>` - prints from the beginning to the specified line.
- `LIST <start>-` - prints from the specified line to the end.
- `DELETE <line>` - deletes a single line.
- `DELETE <start>-<end>` - deletes lines in the given range.
- `DELETE -<end>` - deletes from the beginning to the specified line.
- `DELETE <start>-` - deletes from the specified line to the end.
- `RUN` - executes the stored program.
- `CONT` - continues execution after a `BREAK` caused by Ctrl-C during `RUN`.
- `NEW` - clears the stored program.
- `DIR` - lists saved program files for the current user.
- `SAVE <name>` - saves the current stored program to a file.
- `LOAD <name>` - loads a saved program file into memory.
- `SCRATCH <name>` - deletes a saved program file from the user's directory.
- `RENUM [start[,increment]]` - renumbers stored program lines in order (defaults: `10,10`) and updates direct `GOTO`/`GOSUB` line-number references.
- `QUIT` - disconnects from the TCP session.

Examples:
```text
LIST          - lists entire program
LIST 100      - lists line 100 only
LIST 10-50    - lists lines 10 through 50
LIST -30      - lists from beginning through line 30
LIST 40-      - lists from line 40 to the end

DELETE 100    - deletes line 100
DELETE 10-50  - deletes lines 10 through 50
DELETE -30    - deletes from beginning through line 30
DELETE 40-    - deletes from line 40 to the end
```

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
- Variable names: `[A-Za-z][A-Za-z0-9_]*` with optional trailing `$` for string-style names, `%` for integer-style names, or `&` for byte-style names
- Byte variables (`&` suffix) store integers clamped to 0-255 range
- Variable lookup is case-insensitive (`X`, and `x` refer to the same variable).

Examples:

```text
LET A$ = "HELLO"
PRINT A$
LET I% = 42
PRINT I%
LET B& = 200
PRINT B&
LET B& = 300
PRINT B&
REM Prints 255 (clamped to byte range)
```

### REM

Adds a comment. The interpreter ignores the rest of the statement.

```text
REM THIS IS A COMMENT
REM DRAW FLAG: RED/WHITE STRIPES
```

Notes:
- `REM` is valid in immediate mode and stored program lines.
- Any `:` after `REM` is treated as comment text, not a statement separator.

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
- Variables ending in `&` behave like byte variables (values clamped to 0-255).
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

### COLOR

Sets the text foreground and optionally background color.

```text
COLOR 14
COLOR 14, 1
COLOR 7, 0
```

Notes:
- Foreground values 0–15 follow the standard GW-BASIC palette (0=black, 1=blue, 2=green, 3=cyan, 4=red, 5=magenta, 6=brown, 7=white, 8–15=bright variants).
- Background values 0–7 (same palette, no bright variants).
- On WebSocket/xterm sessions the appropriate ANSI SGR escape is emitted.
- On telnet/TCP sessions `COLOR` is silently ignored.

### HGR

Enters high-resolution graphics mode (640×480 with 16 colors).

```text
HGR
```

Notes:
- On WebSocket sessions, hides the terminal and displays a graphics canvas.
- On telnet/TCP sessions, `HGR` is silently ignored.
- The graphics canvas is cleared to black when entering graphics mode.

### TEXT

Returns to text mode from graphics mode.

```text
TEXT
```

Notes:
- On WebSocket sessions, hides the graphics canvas and restores the terminal.
- On telnet/TCP sessions, `TEXT` is silently ignored.

### PSET

Sets a pixel at coordinates (x, y) to the specified color.

```text
PSET (100, 200), 14
PSET (X, Y), C
```

Notes:
- Coordinates are 0-based: x ∈ [0, 639], y ∈ [0, 479].
- Color values 0–15 use the EGA/VGA palette.
- Only works in graphics mode (after `HGR`).
- On telnet/TCP sessions, `PSET` is silently ignored.

### LINE

Draws a line from (x1, y1) to (x2, y2) in the specified color.

```text
LINE (10, 10)-(100, 100), 15
LINE (X1, Y1)-(X2, Y2), C
```

Notes:
- Coordinates are 0-based.
- Color values 0–15 use the EGA/VGA palette.
- Only works in graphics mode (after `HGR`).
- Sets the graphics pen position to the endpoint (x2, y2) for use with `LINETO`.

### LINETO

Draws a line from the previous graphics endpoint to (x, y) in the specified color.

```text
LINETO (50, 100), 12
LINETO (X, Y), C
```

Notes:
- Requires a previous `LINE` or `LINETO` command to establish the starting point.
- Raises `?NO PREVIOUS LINE` error if no previous line has been drawn since `HGR`.
- Coordinates are 0-based.
- Color values 0–15 use the EGA/VGA palette.
- Only works in graphics mode (after `HGR`).
- Sets the graphics pen position to the endpoint (x, y) for subsequent `LINETO` commands.

### RECT

Draws a filled rectangle from (x1, y1) to (x2, y2) in the specified color.

```text
RECT (10, 10)-(100, 100), 15
RECT (X1, Y1)-(X2, Y2), C
```

Notes:
- Coordinates are 0-based and inclusive.
- Color values 0–15 use the EGA/VGA palette.
- Only works in graphics mode (after `HGR`).
- On telnet/TCP sessions, `RECT` is silently ignored.
- Much faster than drawing multiple lines for filled areas.

### CIRCLE

Draws a circle centered at (x, y) with the specified radius and color.

```text
CIRCLE (320, 240), 50, 12
CIRCLE (X, Y), R, C
```

Notes:
- Coordinates are 0-based.
- Radius is in pixels.
- Color values 0–15 use the EGA/VGA palette.
- Only works in graphics mode (after `HGR`).
- On telnet/TCP sessions, `CIRCLE` is silently ignored.

### SAVE

Saves the current stored program to disk.

```text
SAVE DEMO
SAVE myprog.bas
```

Notes:
- The file is saved to `~/BASIC/<user-id>/`.
- Filenames are normalized for safety.
- Filenames (excluding extension) must not exceed 16 characters.
- Filenames longer than 16 characters raise `?FILE NAME TOO LONG`.
- File write failures raise `?FILE ERROR`.

### LOAD

Loads a saved program from disk, replacing the current stored program.

```text
LOAD DEMO
LOAD myprog.bas
```

Notes:
- Files are loaded from `~/BASIC/<user-id>/`.
- Missing files raise `?PROGRAM NOT FOUND`.
- Other read failures raise `?FILE ERROR`.

### SCRATCH

Deletes a saved program file from the user's directory.

```text
SCRATCH DEMO
SCRATCH myprog.bas
```

Notes:
- Files are deleted from `~/BASIC/<user-id>/`.
- Example files (in the shared `examples/` directory) cannot be deleted with `SCRATCH`.
- Missing files raise `?PROGRAM NOT FOUND`.
- Other file errors raise `?FILE ERROR`.

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

### GET

Reads one character from the keyboard buffer into a string variable (non-blocking).

```text
GET A$
```

Notes:
- If the keyboard buffer is empty, the variable is set to `""` and execution continues immediately.
- The connection layer yields for up to 10 ms before resuming, so a polling loop runs cooperatively at ~100 Hz without spinning the CPU.
- On WebSocket sessions, the browser switches to char mode so individual keystrokes arrive immediately without waiting for Enter.

Typical usage:

```text
10 GET A$
20 IF A$ = "" THEN 10
30 PRINT "KEY: "; A$
```

### GETKEY

Blocks until one character is available in the keyboard buffer, then assigns it to a string variable.

```text
GETKEY A$
```

Notes:
- Execution suspends until a keystroke arrives; no CPU is consumed while waiting.
- On WebSocket sessions, the browser switches to char mode for the duration of the wait.
- Any extra characters received with the keystroke are stored in an internal buffer and consumed by subsequent `GET` or `GETKEY` calls.

### SLEEP

Pauses execution for the specified number of seconds (DEC BASIC).

```text
SLEEP 1
SLEEP 0.5
```

Notes:
- The argument is a numeric expression (integer or float).
- Fractional seconds are supported (e.g., `SLEEP 0.25` pauses for 250 ms).
- Negative values are treated as zero (no pause).
- The Erlang scheduler is yielded during the sleep; other connections continue unaffected.
- Passing a string raises `?TYPE MISMATCH ERROR`.

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
- Using an index outside the declared bounds raises `?SUBSCRIPT OUT OF RANGE`.

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

### ON...GOSUB / ON...GOTO

Computed jump statements that select a target from a list based on an index expression.

```text
ON <expr> GOSUB line1, line2, line3, ...
ON <expr> GOTO line1, line2, line3, ...
```

The expression is evaluated and used as a 1-based index into the list of target line numbers:
- If the value is 1, jump to the first target
- If the value is 2, jump to the second target
- And so on...

If the index is less than 1 or greater than the number of targets, the statement is ignored and execution continues with the next statement.

Examples:

```text
10 LET X = 2
20 ON X GOSUB 100, 200, 300
30 PRINT "BACK"
40 END
100 PRINT "SUB1" : RETURN
200 PRINT "SUB2" : RETURN
300 PRINT "SUB3" : RETURN
REM Output: SUB2, BACK
```

```text
10 LET CHOICE = 3
20 ON CHOICE GOTO 100, 200, 300
30 PRINT "SKIP"
100 PRINT "FIRST" : END
200 PRINT "SECOND" : END
300 PRINT "THIRD" : END
REM Output: THIRD
```

Notes:
- `ON...GOSUB` pushes a return address onto the call stack, just like `GOSUB`
- `ON...GOTO` performs an unconditional jump, just like `GOTO`
- Out-of-range indices (≤ 0 or > number of targets) continue to the next statement
- The index expression is evaluated as an integer (fractional parts are truncated)

### NEXT [var]

Advances the active FOR loop.

```text
NEXT
NEXT I
```

### ON ERROR GOTO / RESUME

Error handling statements that allow programs to trap runtime errors and recover gracefully.

#### Setting an Error Handler

```text
ON ERROR GOTO line
```

Sets an error handler at the specified line number. When a runtime error occurs, execution jumps to the handler instead of stopping the program.

```text
ON ERROR GOTO 0
```

Disables error handling and restores default behavior (stop on error).

#### RESUME Statements

Used within an error handler to continue execution after handling an error.

```text
RESUME
RESUME 0
```

Retries the statement that caused the error. Useful when the error handler fixes the problem.

```text
RESUME NEXT
```

Continues execution with the statement immediately after the one that caused the error. Most common form.

```text
RESUME line
```

Continues execution at a specific line number.

#### Error Variables

Two special variables are automatically set when an error occurs:

- `ERR` - Error code number (integer)
- `ERL` - Line number where the error occurred (integer)

Error codes follow GW-BASIC conventions:
- 1 = NEXT WITHOUT FOR
- 2 = SYNTAX ERROR
- 3 = RETURN WITHOUT GOSUB
- 4 = OUT OF DATA
- 5 = ILLEGAL FUNCTION CALL
- 11 = DIVISION BY ZERO
- 13 = TYPE MISMATCH
- 17 = CAN'T CONTINUE
- 20 = RESUME WITHOUT ERROR

Example:

```text
10 ON ERROR GOTO 1000
20 PRINT "Starting"
30 X = 1 / 0
40 PRINT "After error"
50 END
1000 REM Error handler
1010 PRINT "Error"; ERR; "at line"; ERL
1020 RESUME NEXT
```

Output:
```text
Starting
Error11at line30
After error
Program ended
```

Notes:
- Using `RESUME` outside an error handler raises `?RESUME WITHOUT ERROR`
- Error handlers remain active until disabled with `ON ERROR GOTO 0`
- Errors within error handlers are not caught and will stop the program

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
- Logical/Bitwise operators (work on integers as bitwise, on boolean values as logical):
	- `AND` - Bitwise/logical AND
	- `OR` - Bitwise/logical OR
	- `XOR` - Bitwise/logical XOR
	- `NOT` - Bitwise/logical NOT
- Built-in numeric functions (case-insensitive):
	- Single-argument: `ABS`, `ACOS`, `ASIN`, `ATAN`, `ATN`, `CEIL`, `COS`, `DEG`, `EXP`, `FIX`, `FLOOR`, `INT`, `LN`, `LOG`, `RAD`, `SGN`, `SIN`, `SQR`, `SQRT`, `TAN`, `VAL`
	- Two-argument: `ATAN2`, `POW`
	- Zero-argument: `PI`, `RND`, `TIMER`
- Built-in string functions (case-insensitive):
	- `LEFT$(text, n)`
	- `RIGHT$(text, n)`
	- `MID$(text, start[, n])` (1-based start index)
	- `LEN(text)`
	- `ASC(text)`
	- `CHR$(code)`
	- `STR$(number)`
	- `STRING$(n, code_or_text)`
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
PRINT STRING$(5, 42)
PRINT DATE$()
PRINT TIME$()
PRINT TERM$()
```

Undefined variables evaluate to `0`.

GW-BASIC / DEC BASIC alignment notes:
- `TIMER` returns the number of seconds elapsed since midnight as a floating-point number, matching GW-BASIC behaviour.
- `^` binds tighter than unary `-`, so `-2^2` evaluates as `-(2^2)` and yields `-4`.
- `/` performs floating-point division.
- `\\` performs integer division.
- `MOD` returns remainder.
- `RND` behavior follows DEC BASIC / GW-BASIC syntax:
	- `RND` or `RND(x)` with `x > 0`: returns next pseudo-random value in range [0, 1).
	- `RND(0)`: returns the previous random value (allows repeating the last result).
	- `RND(x)` with `x < 0`: reseeds the random number generator deterministically from `x` and returns the first value from that seed. Same negative value produces same sequence.
- Random number examples:
	```text
	10 PRINT RND          ' Random value
	20 PRINT RND(1)       ' Another random value
	30 PRINT RND(0)       ' Repeat last value
	40 PRINT RND(-42)     ' Seed and get value
	50 PRINT RND(-42)     ' Same seed = same value
	60 PRINT INT(RND*100) ' Random 0-99
	```
- Runtime math errors use GW-BASIC-style messages and stop `RUN`:
	- `?DIVISION BY ZERO ERROR`
	- `?ILLEGAL FUNCTION CALL`
	- `?OUT OF DATA ERROR`
	- `?SUBSCRIPT OUT OF RANGE`
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
IF X > 5 AND Y < 10 THEN PRINT "IN RANGE"
IF A = 1 OR B = 1 THEN PRINT "ONE IS SET"
IF NOT (X = 0) THEN PRINT "NOT ZERO"
```

Logical operators (`AND`, `OR`, `XOR`, `NOT`) can be used in conditions and work as expected:
- `AND` - Both conditions must be true
- `OR` - At least one condition must be true  
- `XOR` - Exactly one condition must be true (exclusive or)
- `NOT` - Negates the condition

Bitwise operations on integers:

```text
LET A = 12 AND 10    REM Bitwise AND: 12 (1100) AND 10 (1010) = 8 (1000)
LET B = 12 OR 3      REM Bitwise OR: 12 (1100) OR 3 (0011) = 15 (1111)
LET C = 12 XOR 10    REM Bitwise XOR: 12 (1100) XOR 10 (1010) = 6 (0110)
LET D = NOT 0        REM Bitwise NOT: NOT 0 = -1 (two's complement)
```

If no comparison operator is present, truthiness is used:
- Integer: true if not `0`
- String: true if not empty/whitespace


