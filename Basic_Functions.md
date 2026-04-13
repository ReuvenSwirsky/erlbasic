# BASIC Built-in Functions Reference

This document describes all built-in functions available in erlbasic.
Functions return a value and can appear anywhere an expression is accepted.

For BASIC statements (PRINT, IF, FOR, etc.) see [Basic_Syntax.md](Basic_Syntax.md).

---

## Numeric Conversion Quick Reference

Numeric model note:
- erlbasic treats unsuffixed numeric values as default decimal numbers.
- `#` suffixed variables are explicit floating-point variables.

| Function | Input | Output | Behavior |
|---|---|---|---|
| Default unsuffixed numeric (`A`) | Numeric literal/expression | Decimal numeric value | Default language numeric model |
| `A#` variable | Numeric literal/expression | Float | Explicit floating-point variable |
| `CDBL(x)` | Numeric | Float | Converts integer to float; float unchanged |
| `CSNG(x)` | Numeric | Float | Same runtime result type as `CDBL` in erlbasic |
| `CINT(x)` | Numeric | Integer | Rounds to nearest integer |
| `INT(x)` | Numeric | Integer | Rounds toward negative infinity |
| `FLOOR(x)` | Numeric | Integer | Rounds toward negative infinity |
| `CEIL(x)` | Numeric | Integer | Rounds toward positive infinity |
| `FIX(x)` | Numeric | Integer | Truncates toward zero |
| `TYPEOF(x)` | Any scalar expression | String | Returns `"INTEGER"`, `"FLOAT"`, or `"STRING"` |
| `STR$(x)` | Numeric | String | Number to string; may emit scientific notation for extreme magnitudes |
| `VAL(s$)` | String | Number | Parses numeric prefix; supports decimal and scientific notation (`E`/`D`) |

Quick examples:

```text
PRINT CINT(2.5), FLOOR(2.5), CEIL(2.5), FIX(2.5)     '  3  2  3  2
PRINT CINT(-2.5), FLOOR(-2.5), CEIL(-2.5), FIX(-2.5) ' -3 -3 -2 -2
PRINT TYPEOF(A), TYPEOF(A#), TYPEOF(A$)               ' INTEGER FLOAT STRING
PRINT STR$(1.25E3)                                     ' 1250.0
PRINT VAL("3D-2")                                      ' 0.03
```

---

## Math Functions

### ABS

Returns the absolute value of a number.

Syntax:
- `ABS(<expr>)`

Examples:
```text
PRINT ABS(-5)      '  5
PRINT ABS(3.7)     '  3.7
```

---

### ACOS

Returns the arc cosine of *x* in radians.

Syntax:
- `ACOS(<expr>)`

Notes:
- *x* must be in the range −1 to 1; otherwise an Illegal function call error is raised.

Example:
```text
PRINT ACOS(1)      '  0.0
```

---

### ASIN

Returns the arc sine of *x* in radians.

Syntax:
- `ASIN(<expr>)`

Notes:
- *x* must be in the range −1 to 1; otherwise an Illegal function call error is raised.

Example:
```text
PRINT ASIN(0)      '  0.0
```

---

### ATAN / ATN

Returns the arc tangent of *x* in radians. Both names are equivalent.

Syntax:
- `ATAN(<expr>)`
- `ATN(<expr>)`

Example:
```text
PRINT ATN(1) * 4   '  pi
```

---

### ATAN2

Returns the arc tangent of *y/x* in radians, using the signs of both arguments to determine the correct quadrant.

Syntax:
- `ATAN2(<y>, <x>)`

Example:
```text
PRINT ATAN2(1, 1)  '  0.785398...  (pi/4)
```

---

### CEIL

Returns the smallest integer that is greater than or equal to *x*.

Syntax:
- `CEIL(<expr>)`

Examples:
```text
PRINT CEIL(2.1)    '  3
PRINT CEIL(-2.1)   '  -2
PRINT CEIL(2.0)    '  2
```

Notes:
- Argument must be numeric; a string argument raises an Illegal function call error.
- `CEIL` is distinct from `CINT`: `CEIL` always rounds toward +infinity, while `CINT` rounds to nearest integer.

---

### CDBL

Converts a numeric value to floating-point (double-precision runtime float).

Syntax:
- `CDBL(<expr>)`

Examples:
```text
PRINT CDBL(5)      '  5.0
PRINT CDBL(2.25)   '  2.25
```

Notes:
- Argument must be numeric; a non-numeric argument raises an Illegal function call error.

---

### CINT

Converts a numeric value to integer by rounding to nearest integer.

Syntax:
- `CINT(<expr>)`

Examples:
```text
PRINT CINT(2.1)    '  2
PRINT CINT(2.9)    '  3
PRINT CINT(-2.5)   '  -3
```

Notes:
- `CINT` is not the same as `FLOOR`/`INT`/`FIX`.
- Argument must be numeric; a non-numeric argument raises an Illegal function call error.

---

### CSNG

Converts a numeric value to floating-point.

Syntax:
- `CSNG(<expr>)`

Examples:
```text
PRINT CSNG(9)      '  9.0
PRINT CSNG(3.5)    '  3.5
```

Notes:
- In erlbasic runtime semantics, `CSNG` and `CDBL` both return the interpreter float type.
- Argument must be numeric; a non-numeric argument raises an Illegal function call error.

---

### COS

Returns the cosine of *x* (angle in radians).

Syntax:
- `COS(<expr>)`

Example:
```text
PRINT COS(0)       '  1
```

---

### DEG

Converts *x* from radians to degrees.

Syntax:
- `DEG(<expr>)`

Example:
```text
PRINT DEG(3.14159) '  ~180
```

---

### EXP

Returns *e* raised to the power *x*.

Syntax:
- `EXP(<expr>)`

Example:
```text
PRINT EXP(1)       '  2.71828...
```

---

### FIX

Truncates *x* toward zero (removes the fractional part without rounding).

Syntax:
- `FIX(<expr>)`

Examples:
```text
PRINT FIX(3.9)     '  3
PRINT FIX(-3.9)    '  -3
```

Notes:
- Differs from `INT` for negative numbers: `INT(-3.9)` returns −4, `FIX(-3.9)` returns −3.

---

### FLOOR

Returns the largest integer less than or equal to *x*.

Syntax:
- `FLOOR(<expr>)`

Examples:
```text
PRINT FLOOR(3.9)   '  3
PRINT FLOOR(-2.1)  '  -3
```

Notes:
- `FLOOR` is distinct from `CINT`: `FLOOR` always rounds toward -infinity, while `CINT` rounds to nearest integer.

---

### INT

Returns the integer part of *x*, rounding toward negative infinity (GW-BASIC compatible).

Syntax:
- `INT(<expr>)`

Examples:
```text
PRINT INT(3.9)     '  3
PRINT INT(-3.1)    '  -4
```

Notes:
- For positive numbers `INT` and `FLOOR` are equivalent. For negative numbers, `INT` rounds toward −∞ while `FIX` truncates toward zero.

---

### LN / LOG

Returns the natural logarithm (base *e*) of *x*. Both names are equivalent.

Syntax:
- `LN(<expr>)`
- `LOG(<expr>)`

Notes:
- *x* must be positive; otherwise an Illegal function call error is raised.

Example:
```text
PRINT LOG(1)       '  0.0
PRINT LN(2.71828)  '  ~1.0
```

---

### PI

Returns the value of π (approximately 3.14159265358979).

Syntax:
- `PI()`
- `PI`

Example:
```text
PRINT PI           '  3.14159265358979
```

---

### POW

Returns *x* raised to the power *y*. Equivalent to the `^` operator.

Syntax:
- `POW(<x>, <y>)`

Example:
```text
PRINT POW(2, 10)   '  1024
```

---

### RAD

Converts *x* from degrees to radians.

Syntax:
- `RAD(<expr>)`

Example:
```text
PRINT RAD(180)     '  3.14159...
```

---

### RND

Returns a pseudo-random floating-point number in the range [0, 1).

Syntax:
- `RND`
- `RND()`
- `RND(<x>)`

Argument behavior (GW-BASIC compatible):
- `RND` or `RND(positive)` — returns a new random number.
- `RND(0)` — returns the last value generated by `RND`.
- `RND(negative)` — seeds the generator from *x* and returns a new number. The same negative value always produces the same sequence.

Example:
```text
10 FOR I = 1 TO 5
20   PRINT INT(RND * 100)
30 NEXT I
```

---

### SGN

Returns the sign of *x*: −1 if *x* < 0, 0 if *x* = 0, or 1 if *x* > 0.

Syntax:
- `SGN(<expr>)`

Example:
```text
PRINT SGN(-7)      '  -1
PRINT SGN(0)       '  0
PRINT SGN(3.5)     '  1
```

---

### SIN

Returns the sine of *x* (angle in radians).

Syntax:
- `SIN(<expr>)`

Example:
```text
PRINT SIN(0)       '  0.0
```

---

### SQR / SQRT

Returns the square root of *x*. Both names are equivalent.

Syntax:
- `SQR(<expr>)`
- `SQRT(<expr>)`

Notes:
- *x* must be non-negative; otherwise an Illegal function call error is raised.

Example:
```text
PRINT SQR(9)       '  3.0
PRINT SQRT(2)      '  1.41421...
```

---

### TAN

Returns the tangent of *x* (angle in radians).

Syntax:
- `TAN(<expr>)`

Example:
```text
PRINT TAN(0)       '  0.0
```

---

### TYPEOF

Returns a string describing the runtime scalar type of an expression.

Syntax:
- `TYPEOF(<expr>)`

Return values:
- `"INTEGER"`
- `"FLOAT"`
- `"STRING"`

Examples:
```text
PRINT TYPEOF(123)      '  INTEGER
PRINT TYPEOF(1.5E2)    '  FLOAT
PRINT TYPEOF("HELLO")  '  STRING
PRINT TYPEOF(A#)       '  FLOAT
```

---

### VAL

Converts a string to a number. Leading whitespace is ignored; any non-numeric trailing characters are ignored.

Syntax:
- `VAL(<string-expr>)`

Returns 0 if the string contains no recognizable number.

Scientific notation is supported (`E`/`e` and `D`/`d` exponents).

Examples:
```text
PRINT VAL("123")       '  123
PRINT VAL("  -4.5xyz") '  -4.5
PRINT VAL("1.25E3")    '  1250.0
PRINT VAL("3D-2")      '  0.03
PRINT VAL("ABC")       '  0
```

---

## String Functions

### ASC

Returns the ASCII code of the first character of a string.

Syntax:
- `ASC(<string-expr>)`

Notes:
- An empty string argument raises an Illegal function call error.

Example:
```text
PRINT ASC("A")     '  65
```

---

### CHR$

Returns the single-character string whose ASCII code is *n*.

Syntax:
- `CHR$(<expr>)`

Notes:
- *n* must be in the range 0–255; otherwise an Illegal function call error is raised.

Example:
```text
PRINT CHR$(66)     '  B
```

---

### INSTR

Returns the position of the first occurrence of *pattern$* in *text$*, or 0 if not found. Position is 1-based.

Syntax:
- `INSTR(<text$>, <pattern$>)`
- `INSTR(<start>, <text$>, <pattern$>)`

Notes:
- *start* must be ≥ 1; omitting it defaults to 1.
- An empty *pattern$* returns *start* (or 1 if *start* is omitted), as long as *start* ≤ `LEN(text$) + 1`.

Examples:
```text
PRINT INSTR("ABCDE","BC")      '  2
PRINT INSTR(3,"ABCDE","DE")    '  4
PRINT INSTR("ABCDE","ZZ")      '  0
```

---

### LEFT$

Returns the leftmost *n* characters of a string.

Syntax:
- `LEFT$(<string-expr>, <n>)`

Notes:
- If *n* ≤ 0 an empty string is returned.
- If *n* ≥ `LEN(string)` the entire string is returned.

Example:
```text
PRINT LEFT$("HELLO", 2)    '  HE
```

---

### LEN

Returns the number of characters in a string. When passed a numeric value it is converted to its string representation first.

Syntax:
- `LEN(<string-expr>)`
- `LEN(<expr>)`

Example:
```text
PRINT LEN("HELLO")     '  5
PRINT LEN(12345)       '  5
```

---

### MID$

Returns a substring of *text$* beginning at *start* (1-based).

Syntax:
- `MID$(<string-expr>, <start>)`
- `MID$(<string-expr>, <start>, <count>)`

Notes:
- *start* must be ≥ 1; otherwise an Illegal function call error is raised.
- If *start* > `LEN(text$)` an empty string is returned.
- If *count* is 0 an empty string is returned.
- If *count* is omitted, all characters from *start* to the end are returned.

Examples:
```text
PRINT MID$("HELLO", 2, 2)  '  EL
PRINT MID$("HELLO", 4)     '  LO
PRINT MID$("ABCDE", 6, 2)  '  (empty)
```

---

### RIGHT$

Returns the rightmost *n* characters of a string.

Syntax:
- `RIGHT$(<string-expr>, <n>)`

Notes:
- If *n* ≤ 0 an empty string is returned.
- If *n* ≥ `LEN(string)` the entire string is returned.

Example:
```text
PRINT RIGHT$("HELLO", 3)   '  LLO
```

---

### SPACE$

Returns a string of *n* space characters.

Syntax:
- `SPACE$(<n>)`

Notes:
- *n* must be ≥ 0; a negative value raises an Illegal function call error.

Example:
```text
PRINT "A";SPACE$(3);"B"    '  A   B
```

---

### STR$

Converts a number to its string representation.

Syntax:
- `STR$(<numeric-expr>)`

Notes:
- Passing a non-numeric argument raises a Type mismatch error.
- Very large/small magnitudes may be formatted in scientific notation.

Examples:
```text
PRINT STR$(123)    '  123
PRINT STR$(-45)    '  -45
PRINT STR$(3.5)    '  3.5
```

---

### STRING$

Returns a string of *n* copies of a character (specified either by ASCII code or by the first character of a string).

Syntax:
- `STRING$(<n>, <code>)`
- `STRING$(<n>, <char$>)`

Notes:
- *n* must be ≥ 0.
- *code* must be in the range 0–255.
- An empty *char$* raises an Illegal function call error.

Examples:
```text
PRINT STRING$(5, 42)       '  *****
PRINT STRING$(4, "*")      '  ****
```

---

## I/O and System Functions

### DATE$

Returns the current local date as a string in `MM-DD-YYYY` format.

Syntax:
- `DATE$()`
- `DATE$`

Example:
```text
PRINT DATE$        '  04-09-2026
```

---

### EOF

Returns −1 (true) if the file on *channel* is at end-of-file; otherwise returns 0.

Syntax:
- `EOF(<channel>)`

Example:
```text
10 OPEN "DATA.TXT" FOR INPUT AS #1
20 WHILE NOT EOF(1)
30   INPUT #1, A$
40   PRINT A$
50 WEND
60 CLOSE #1
```

---

### FREE

Returns the number of bytes of memory still available to the current user's program. The limit is set by the account configuration; if no limit is configured a large sentinel value is returned.

Syntax:
- `FREE()`
- `FREE`

Example:
```text
PRINT FREE
```

---

### MEM_USED

Returns the interpreter's current estimate of how many bytes of memory the current BASIC session is using.

Syntax:
- `MEM_USED()`

Notes:
- This is the same approximation used by `FREE()` and the session memory watchdog.
- It measures the serialized size of the current program, variables, DATA items, loop stack, call stack, and user functions.
- It is an approximation of interpreter state size, not a full Erlang VM process-memory reading.

Example:
```text
PRINT "USED: "; MEM_USED()
PRINT "FREE: "; FREE
```

---

### LOF

Returns the length (in bytes) of the open file on *channel*.

Syntax:
- `LOF(<channel>)`

Example:
```text
OPEN "FILE.TXT" FOR INPUT AS #1
PRINT LOF(1)
CLOSE #1
```

---

### POS

Returns the current column position of the output cursor (1-based). The optional argument is accepted for GW-BASIC compatibility but is ignored.

Syntax:
- `POS()`
- `POS`
- `POS(<dummy>)`

Example:
```text
PRINT "HELLO";
PRINT POS(0)       '  6
```

---

### PLAY

Returns the number of notes currently remaining in the background `PLAY` queue.

Syntax:
- `PLAY(<dummy>)`

Notes:
- The argument is accepted for compatibility but ignored.
- Typical usage is `PLAY(0)`.
- Foreground phrases (`MF`) do not leave queued background notes.

Example:
```text
ON PLAY(4) GOSUB 1000
PRINT "Queue: "; PLAY(0)
```

---

### SEEK

Returns the current byte position in the open file on *channel* (1-based).

Syntax:
- `SEEK(<channel>)`

Example:
```text
PRINT SEEK(1)
```

---

### TERM$

Returns a string identifying the terminal type of the current connection: `"XTERM"` for WebSocket sessions and `"TELNET"` for TCP sessions.

Syntax:
- `TERM$()`
- `TERM$`

Example:
```text
IF TERM$ = "XTERM" THEN GOTO 100
```

---

### TIME$

Returns the current local time as a string in `HH:MM:SS` format (24-hour clock).

Syntax:
- `TIME$()`
- `TIME$`

Example:
```text
PRINT TIME$        '  14:30:05
```

---

### TIMER

Returns the number of seconds elapsed since midnight as a floating-point number.

Syntax:
- `TIMER()`
- `TIMER`

Range: 0.0 to 86399.999...

Example:
```text
LET T = TIMER
' ... do work ...
PRINT TIMER - T; "seconds elapsed"
```

See also: `ON TIMER(...) GOSUB` in Basic_Syntax.md for timer-driven event callbacks.

---

## Operators

All operators work in expressions in any context (assignment, `IF`, `PRINT`, etc.).
Operator precedence (highest to lowest):

| Precedence | Operators |
|------------|-----------|
| 1 (highest) | Unary `-` (negation), unary `+` |
| 2 | `^` (exponentiation) |
| 3 | `*`, `/`, `\`, `MOD` |
| 4 | `+`, `-` |
| 5 | `=`, `<>`, `<`, `>`, `<=`, `>=` |
| 6 | `NOT` |
| 7 | `AND` |
| 8 | `XOR` |
| 9 (lowest) | `OR` |

---

### Arithmetic Operators

| Operator | Meaning | Example |
|----------|---------|---------|
| `+` | Addition (numbers) or concatenation (strings) | `3 + 4` → `7`; `"A" + "B"` → `"AB"` |
| `-` | Subtraction | `10 - 3` → `7` |
| `*` | Multiplication | `4 * 5` → `20` |
| `/` | Floating-point division | `7 / 2` → `3.5` |
| `\` | Integer division (truncates toward zero) | `7 \ 2` → `3`; `-7 \ 2` → `-3` |
| `^` | Exponentiation | `2 ^ 8` → `256` |
| `MOD` | Integer modulo (remainder) | `10 MOD 3` → `1` |

Notes:
- Dividing by zero raises a Division by zero error.
- `\` truncates both operands to integer before dividing.

Example:
```text
PRINT 2 ^ 10       '  1024
PRINT 7 / 2        '  3.5
PRINT 7 \ 2        '  3
PRINT 10 MOD 3     '  1
```

---

### Comparison Operators

Comparisons return −1 for true and 0 for false (GW-BASIC compatible).

| Operator | Meaning |
|----------|---------|
| `=` | Equal |
| `<>` | Not equal |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less than or equal |
| `>=` | Greater than or equal |

Works on both numbers and strings. String comparison is case-sensitive and lexicographic.

Example:
```text
IF X > 5 THEN PRINT "BIG"
IF A$ <> B$ THEN PRINT "DIFFERENT"
PRINT (3 = 3)      '  -1
PRINT (3 = 4)      '  0
```

---

### Logical / Bitwise Operators

When both operands are integers, `AND`, `OR`, `XOR`, and `NOT` perform bitwise operations (GW-BASIC compatible). When either operand is a float or string, they perform boolean operations returning −1 (true) or 0 (false).

#### AND

Returns the bitwise AND of two integers, or −1 if both operands are true (non-zero/non-empty).

Syntax:
- `<expr> AND <expr>`

Example:
```text
PRINT 12 AND 10    '  8   (1100 AND 1010 = 1000)
IF X > 5 AND Y < 10 THEN PRINT "BOTH"
```

---

#### NOT

Returns the bitwise NOT of an integer, or 0/−1 for boolean negation.

Syntax:
- `NOT <expr>`

Example:
```text
PRINT NOT 0        '  -1
PRINT NOT 255      '  -256
IF NOT (X = 0) THEN PRINT "X IS NON-ZERO"
```

---

#### OR

Returns the bitwise OR of two integers, or −1 if either operand is true.

Syntax:
- `<expr> OR <expr>`

Example:
```text
PRINT 12 OR 3      '  15  (1100 OR 0011 = 1111)
IF X = 7 OR Y = 3 THEN PRINT "AT LEAST ONE"
```

---

#### XOR

Returns the bitwise XOR of two integers, or −1 if exactly one operand is true.

Syntax:
- `<expr> XOR <expr>`

Example:
```text
PRINT 12 XOR 10    '  6   (1100 XOR 1010 = 0110)
IF A XOR B THEN PRINT "EXACTLY ONE IS TRUE"
```
