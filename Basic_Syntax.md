# BASIC Syntax Reference

This document lists the BASIC and REPL commands currently implemented in erlbasic.

## Program Line Structure

A stored program line starts with a numeric line number:

```text
10 PRINT "HELLO"
20 END
```

Rules:
- Line numbers are integers.
- Entering only a line number deletes that line from the stored program.
- Multiple statements can be placed on one line using `:`.
- `REM` comments consume the rest of the statement text.

## Literal Notes

- Default numeric values in erlbasic are decimal-style numbers; this language model emphasizes decimal quantities rather than fixed-width machine integers.
- Unsuffixed numeric variables are treated as default numeric values, and a decimal point form is always valid (`1.0`, `0.25`, `10.`).
- Integer literals may be written in decimal or hexadecimal.
- Hexadecimal literals use the form `0x...` or `0X...` and can be used anywhere an integer expression is accepted.
- Hex literals are useful for packed bit masks, including sprite row definitions stored in `%` integer variables.
- Floating-point literals may be written in decimal (`1.5`, `.25`, `10.`) or scientific notation (`1E3`, `1.5e-3`, `3D2`).
- Scientific notation accepts `E`/`e` and `D`/`d` exponents.

## REPL Commands (Immediate Mode)

These commands are entered without a line number.

### CHAIN

Loads and runs another program immediately.

Syntax:
- `CHAIN <name>`

Example:
```text
CHAIN demo
```

### CONT

Continues execution after a Ctrl-C break.

Syntax:
- `CONT`

Notes:
- Requires a valid break context (from Ctrl-C or `STOP` in a running program).

### DELETE

Deletes lines from the current stored program.

Syntax:
- `DELETE <line>`
- `DELETE <start>-<end>`
- `DELETE -<end>`
- `DELETE <start>-`

Examples:
```text
DELETE 100
DELETE 100-200
DELETE -50
DELETE 500-
```

### DIR

Lists available user programs and shared examples.

Syntax:
- `DIR`

### LIST

Lists stored program lines.

Syntax:
- `LIST`
- `LIST <line>`
- `LIST <start>-<end>`
- `LIST -<end>`
- `LIST <start>-`

Examples:
```text
LIST
LIST 100
LIST 100-200
LIST -50
LIST 500-
```

### LOAD

Loads a program file into memory (replacing current program).

Syntax:
- `LOAD <name>`

### NEW

Clears the current stored program.

Syntax:
- `NEW`

### QUIT

Disconnects the current session.

Syntax:
- `QUIT`

### RENUM

Renumbers stored lines and rewrites direct `GOTO`/`GOSUB` line references.

Syntax:
- `RENUM`
- `RENUM <start>`
- `RENUM <start>,<increment>`

Defaults:
- `start = 10`
- `increment = 10`

Examples:
```text
RENUM
RENUM 100
RENUM 100,5
```

### RUN

Runs current program, or loads-and-runs a file.

Syntax:
- `RUN`
- `RUN <name>`

### SAVE

Saves the current stored program.

Syntax:
- `SAVE <name>`

### SCRATCH

Deletes a saved program file.

Syntax:
- `SCRATCH <name>`

## BASIC Statements

Statements below are listed in alphabetical order by command name. Unless noted otherwise, they work both in immediate mode and in stored program lines.

Scope notes:
- Line-flow statements (`GOTO`, `GOSUB`, `RETURN`, `ON ... GOTO`, `ON ... GOSUB`, `ON PLAY(...) GOSUB`, `ON SPRITE GOSUB`, `ON TIMER(...) GOSUB`, `ON ERROR GOTO`, `RESUME`, `STOP`) are intended for stored program execution.
- `INPUT`, `GET`, `GETKEY`, `SLEEP`, `PGET`, and `GETCHAR` may pause execution waiting for input or browser replies.

### BUFFER

Controls double-buffered output mode (WebSocket sessions).

Syntax:
- `BUFFER ON`
- `BUFFER OFF`

### CHAIN

In program execution, loads another program and continues execution from that new program.

Syntax:
- `CHAIN <string-expression>`

Examples:
```text
CHAIN "nextprog"
CHAIN FILE$
```

### CIRCLE

Draws a circle in graphics mode.

Syntax:
- `CIRCLE (<x>,<y>),<radius>,<color>`

Example:
```text
CIRCLE (320,240),50,12
```

### CLS

Clears the text display.

Syntax:
- `CLS`

### CLOSE

Closes file channels.

Syntax:
- `CLOSE`
- `CLOSE #<channel>`
- `CLOSE #<channel>,#<channel>,...`

Examples:
```text
CLOSE
CLOSE #1
CLOSE #1,#2,#3
```

### COLOR

Sets text foreground/background color.

Syntax:
- `COLOR <fg>`
- `COLOR <fg>,<bg>`

### DATA

Defines literal data items for `READ`.

Syntax:
- `DATA`
- `DATA <item>,<item>,...`

Examples:
```text
DATA 10,20,30
DATA "ALPHA","BETA",99
```

### DEF FN

Defines a user function.

Syntax:
- `DEF FN<name>=<expr>`
- `DEF FN<name>(<arg>)=<expr>`

Examples:
```text
DEF FNQ(X)=X*X+1
DEF FNPI=3.14159
```

Notes:
- User function names must start with `FN` followed by at least one letter or digit (e.g. `FNX`, `FNPI`, `FNQ%`).
- Calling a function that has not been defined with `DEF FN` raises `?UNDEFINED FUNCTION ERROR`.
- Variable names starting with `FN` are reserved for user functions and cannot be used as array names.

### DIM

Declares one or more arrays.

Syntax:
- `DIM A(<d1>)`
- `DIM A(<d1>,<d2>)`
- `DIM A(<d1>,<d2>,<d3>)`
- `DIM A(...),B(...),...`

Examples:
```text
DIM A(10)
DIM GRID(10,10)
DIM CUBE(4,4,4),NAMES$(50)
```

Notes:
- Arrays support 1, 2, or 3 dimensions. Indices are 0-based; the dimension size is the maximum valid index.
- Referencing an array that has not been declared with `DIM` raises `?UNDIMMED ARRAY ERROR`.
- Array names starting with `FN` are not allowed (those names are reserved for user-defined functions).

### END

Stops program execution.

Syntax:
- `END`

### FIELD

Defines fixed-length string fields for a random-access channel.

Syntax:
- `FIELD #<channel>, <len-expr> AS <string-var>, <len-expr> AS <string-var>, ...`

Example:
```text
FIELD #1, 20 AS NAME$, 4 AS AGE$
```

### FLUSH

Forces buffered output to flush.

Syntax:
- `FLUSH`

### FOR

Starts a counted loop.

Syntax:
- `FOR <var>=<start> TO <end>`
- `FOR <var>=<start> TO <end> STEP <step>`

Example:
```text
FOR I=1 TO 10 STEP 2
```

### GET

Two implemented forms:

Syntax:
- `GET <target>`
- `GET #<channel>, <record-expr>`

Notes:
- `GET <target>` reads one character (non-blocking keyboard input behavior).
- `GET #...` reads a random-access record from an open file channel.

### GETCHAR

Reads character at a text cell position into a target variable (WebSocket text area behavior).

Syntax:
- `GETCHAR <row>,<col>,<target>`

### GETKEY

Reads one key (blocking behavior) into a target variable.

Syntax:
- `GETKEY <target>`

### GOSUB

Calls a subroutine at target line.

Syntax:
- `GOSUB <line-expr>`

### GOTO

Jumps to target line.

Syntax:
- `GOTO <line-expr>`

### HGR

Enters graphics mode.

Syntax:
- `HGR`

### HGR2

Enters split graphics/text mode.

Syntax:
- `HGR2`

### IF ... THEN ... ELSE

Conditional statement.

Syntax:
- `IF <condition> THEN <statement>`
- `IF <condition> THEN <statement> ELSE <statement>`
- `IF <condition> THEN <line-number>`
- `IF <condition> THEN <line-number> ELSE <line-number>`

Examples:
```text
IF X>0 THEN PRINT "POS"
IF X=0 THEN 500 ELSE 900
```

### INPUT

Reads one or more comma-separated values from user input.

Syntax:
- `INPUT <target>`
- `INPUT <target>,<target>,...`

Targets may be scalar variables or array elements.

### INPUT #

Reads one or more values from a file channel.

Syntax:
- `INPUT #<channel>, <target>`
- `INPUT #<channel>, <target>,<target>,...`

### INPUT LINE

Reads an entire input line (unparsed) into a target.

Syntax:
- `INPUT LINE <target>`

### LET

Assignment statement.

Syntax:
- `LET <target>=<expr>`
- `<target>=<expr>` (implicit `LET` form)

Targets may be scalar variables or array elements.

Notes:
- String targets (`$` suffix) require string values.
- Numeric targets (no `$`) require numeric values.
- Assigning incompatible types raises `?TYPE MISMATCH ERROR`.

Examples:
```text
LET X=42
TOTAL=TOTAL+1
LET A(3,2)=99
LET A$=20      ' TYPE MISMATCH
LET A="FOO"   ' TYPE MISMATCH
```

### LINE

Draws a line segment in graphics mode.

Syntax:
- `LINE (<x1>,<y1>)-(<x2>,<y2>),<color>`

### LINE INPUT #

Reads a full raw line from a file channel into a target.

Syntax:
- `LINE INPUT #<channel>, <target>`

### LINETO

Draws from previous graphics pen position to new point.

Syntax:
- `LINETO (<x>,<y>),<color>`

### LOCATE

Moves cursor to row/column.

Syntax:
- `LOCATE <row>,<col>`

### NEXT

Advances a `FOR` loop.

Syntax:
- `NEXT`
- `NEXT <var>`

### ON ... GOSUB

Computed subroutine dispatch.

Syntax:
- `ON <expr> GOSUB <line>,<line>,...`

### ON ... GOTO

Computed jump dispatch.

Syntax:
- `ON <expr> GOTO <line>,<line>,...`

### ON ERROR GOTO

Enables runtime error trap target.

Syntax:
- `ON ERROR GOTO <line-expr>`

### ON PLAY ... GOSUB

Background-music refill trigger.

Syntax:
- `ON PLAY(<notes-expr>) GOSUB <line-expr>`

Notes:
- Works with `PLAY` background mode (`MB`) and checks after each executed statement.
- When remaining queued notes drop below `<notes-expr>`, the subroutine is invoked.
- Re-entry is guarded: the handler will not trigger again while its prior invocation is still active.

### ON SPRITE GOSUB

Registers a collision event handler for sprite overlaps.

Syntax:
- `ON SPRITE GOSUB <line-expr>`

Notes:
- Triggering is edge-based: the handler fires when a collision pair first appears (not every statement while still overlapping).
- During the handler, collision IDs are available in `SPRCOL1%` and `SPRCOL2%`.
- Re-entry is guarded while a prior sprite handler invocation is active.

Example:
```text
ON SPRITE GOSUB 900
```

### ON TIMER ... GOSUB

Registers a periodic timer callback that fires approximately every `<seconds-expr>` seconds.

Syntax:
- `ON TIMER(<seconds-expr>) GOSUB <line-expr>`

Notes:
- The handler is checked and fired after each executed statement during `RUN`.
- `<seconds-expr>` is evaluated when the handler first fires and must be a positive number.
- Re-entry is guarded: the handler will not trigger again while its prior invocation is still active.
- The timer is cleared (along with all other event handlers) when `END` is executed or the program is broken with Ctrl-C.
- Setting a new `ON TIMER(...)` resets the interval and arms the timer from that point.

Example:
```text
ON TIMER(0.5) GOSUB 200   ' call subroutine at line 200 twice per second
```

### OPEN

Opens a file channel.

Syntax:
- `OPEN <path-expr> FOR INPUT AS #<channel>`
- `OPEN <path-expr> FOR OUTPUT AS #<channel>`
- `OPEN <path-expr> FOR APPEND AS #<channel>`
- `OPEN <path-expr> FOR RANDOM AS #<channel>`
- `OPEN <path-expr> FOR <mode> AS #<channel> LEN=<record-len-expr>`

Modes:
- `INPUT`
- `OUTPUT`
- `APPEND`
- `RANDOM`

### PGET

Reads pixel palette index into target.

Syntax:
- `PGET (<x>,<y>),<target>`

### PLAY

Queues and plays Music Macro Language (MML) notes.

Syntax:
- `PLAY <string-expr>`

Implemented MML controls:
- `O<n>` set octave (0-6)
- `<` and `>` shift octave down/up
- `L<n>[.]` default note length (1-64), optional dotted length
- `T<n>` tempo (32-255 BPM)
- `A`-`G` notes with optional accidental (`#`, `+`, `-`), optional length, optional dot
- `N<n>[.]` note by number (`0` = rest, `1-84` = note)
- `P<n>[.]` or `R<n>[.]` rest
- `MN`, `ML`, `MS` articulation (normal, legato, staccato)
- `MB`, `MF` playback mode (background, foreground)

Notes:
- `PLAY` is available in WebSocket sessions.
- In foreground mode (`MF`), execution waits for phrase duration.
- In background mode (`MB`), execution continues while notes remain queued.

Examples:
```text
PLAY "MF T160 L8 O4 C E G O5 C"
PLAY "MB T140 ML O4 L4 C E G O5 C"
```

### PRINT

Prints items.

Syntax:
- `PRINT`
- `PRINT <item-list>`
- `? <item-list>` (alias)

Item separator options:
- `,` zone separator
- `;` concatenation/no spacing
- trailing `;` suppresses newline

Examples:
```text
PRINT "A", "B"
PRINT "A";"B";
? X
```

### PRINT #

Prints to file channel.

Syntax:
- `PRINT #<channel>`
- `PRINT #<channel>, <item-list>`

### PRINT USING

Formatted print.

Syntax:
- `PRINT USING <format-expr>; <item-list>`

Supported format placeholders:
- `#` numeric mask (with optional decimal point)
- `&` string insertion

### PSET

Sets a pixel in graphics mode.

Syntax:
- `PSET (<x>,<y>),<color>`

### PUT #

Writes random-access record to file channel.

Syntax:
- `PUT #<channel>, <record-expr>`

### READ

Reads values from `DATA` stream into targets.

Syntax:
- `READ <target>`
- `READ <target>,<target>,...`

### RECT

Draws filled rectangle in graphics mode.

Syntax:
- `RECT (<x1>,<y1>)-(<x2>,<y2>),<color>`

### REM

Comment statement.

Syntax:
- `REM`
- `REM <text>`

### RESUME

Error handler resume control.

Syntax:
- `RESUME`
- `RESUME 0`
- `RESUME NEXT`
- `RESUME <line-expr>`

### RETURN

Returns from `GOSUB`.

Syntax:
- `RETURN`

### SLEEP

Pause execution.

Syntax:
- `SLEEP`
- `SLEEP <seconds-expr>`

Notes:
- `SLEEP` with no argument waits for a keypress.
- `SLEEP <seconds-expr>` pauses for that duration (bounded internally).

### SPRITE

Loads, positions, and controls bitmap sprites in graphics mode.

Syntax:
- `SPRITE LOAD <id-expr>,<width-expr>,<height-expr>,<byte-array-1d-element>`
- `SPRITE <id-expr>,(<x-expr>,<y-expr>)`
- `SPRITE SHOW <id-expr>`
- `SPRITE HIDE <id-expr>`
- `SPRITE SCALE <id-expr>,<scale-expr>`
- `SPRITE CLEAR`

Bitmap source notes:
- `SPRITE LOAD` reads `width * height` bytes from a 1D BYTE array (`&` suffix), starting at the supplied index.
- Value `255` is treated as transparent; other values use the low 4 bits as palette color index.

Behavior notes:
- Sprite rendering requires WebSocket graphics mode (`HGR` or `HGR2`).
- IDs are not fixed to legacy limits; many sprites and larger dimensions are supported.

See also:
- [examples/sprites.bas](examples/sprites.bas)
- [examples/sprites_hgr2.bas](examples/sprites_hgr2.bas)

Example:
```text
DIM ROW%(31),SHIP&(1023)
ROW%(6)=0x000FF000
SPRITE LOAD 1,32,32,SHIP&(0)
SPRITE 1,(120,80)
SPRITE SHOW 1
```

### SOUND

Emits sound command.

Syntax:
- `SOUND <voice>,<pitch>,<distortion>,<volume>`

### STOP

Breaks program execution and leaves a continuation context for `CONT`.

Syntax:
- `STOP`

Notes:
- During `RUN`, `STOP` prints `BREAK IN <line>`.
- `CONT` resumes from the statement after `STOP`.

### TEXT

Returns to text mode.

Syntax:
- `TEXT`

### TRON

Turns trace output on.

Syntax:
- `TRON`

### TROFF

Turns trace output off.

Syntax:
- `TROFF`

### WRITE #

Writes comma-separated values to file channel in WRITE format.

Syntax:
- `WRITE #<channel>`
- `WRITE #<channel>, <expr>,<expr>,...`

## Notes

- Variable names are case-insensitive and may include optional suffixes `$`, `%`, `&`, or `#`.
- Unsuffixed numeric variables follow the default decimal numeric model.
- `#` suffix declares an explicit floating-point variable (double-precision runtime float).
- Use `TYPEOF(<expr>)` to inspect runtime scalar type; it returns `"INTEGER"`, `"FLOAT"`, or `"STRING"`.
- Reserved words cannot be used as variable names.
- Arrays support 1, 2, or 3 dimensions.
- `FOR` loop control variables are numeric variable forms.
- Many graphics-oriented statements require WebSocket mode and active graphics mode.
