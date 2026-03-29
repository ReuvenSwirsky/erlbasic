# erlbasic

A BASIC interpreter, implemented in Erlang, exposed over TCP/IP. Each TCP client gets its own isolated interpreter state.

## Features

- Multiple concurrent TCP and/or WebSocket clients
- One interpreter instance per connection
- Stored program lines using numeric BASIC line numbers
- Immediate commands: `PRINT`, `LET`, `INPUT`, `LIST`, `RUN`, `CONT`, `NEW`, `RENUM`, `QUIT`
- Program statements: `LET`, `PRINT`, `PRINT USING`, `INPUT`, `DATA`, `READ`, `DIM`, `IF/THEN/ELSE`, `FOR/NEXT`, `GOTO`, `GOSUB/RETURN`, `END`
- Expression engine with numeric operators, exponentiation, BASIC-style math functions (`SIN`, `COS`, `TAN`, `ACOS`, `SQRT`, `INT`, `FLOOR`, `CEIL`, `VAL`, etc.), and string helpers (`LEFT$`, `RIGHT$`, `MID$`, `LEN`, `ASC`, `CHR$`, `STR$`, `DATE$`, `TIME$`, `TERM$`)

## Build

```powershell
erlc -o ebin src/*.erl
```

On Windows PowerShell, if `erlc` fails due to launcher quoting issues, use:

```powershell
.\build.ps1
```

## Run

```powershell
erl -pa ebin
application:start(erlbasic).
```

Or use the one-command helper (build + run):

```powershell
.\run.ps1
```

The server listens on port `5555` by default.

## Connect

```powershell
telnet localhost 5555
```

or

```powershell
nc localhost 5555
```

or navigate to URL

```
http://localhost:8081/
```

## Example session

```text
10 LET X = 42
20 PRINT X
30 PRINT "HELLO"
40 END
RUN
```

## More Examples

Immediate mode:

```text
LET A$ = "HELLO"
PRINT A$
LET I% = 42
PRINT I%
INPUT NAME$
PRINT NAME$
IF A$ = "HELLO" THEN PRINT "OK" ELSE PRINT "NO"
LET X = 5 : PRINT X
```

Stored program with loop and conditional:

```text
10 FOR I = 1 TO 5
20 IF I < 3 THEN PRINT "LOW" ELSE PRINT "HIGH"
30 PRINT I
40 NEXT I
50 END
RUN
```

Stored program with INPUT and subroutine flow:

```text
10 INPUT N
20 GOSUB 100
30 PRINT N
40 END
100 LET N = N + 1
110 RETURN
RUN
```

## Notes

- Expressions support integer/float literals, quoted strings, scalar/array variable lookup (including 1D/2D/3D arrays), arithmetic operators, common BASIC math functions, and string functions (`LEFT$`, `RIGHT$`, `MID$`, `LEN`, `ASC`, `CHR$`, `STR$`, `DATE$`, `TIME$`, `TERM$`).
- Undefined variables evaluate to `0`.
- Sending an empty stored line like `20` deletes that line from the program.
- Ctrl-C during `RUN` triggers `BREAK`; `CONT` resumes from the break point when continuation context exists.
- Runtime errors include `?TYPE MISMATCH ERROR`, `?CAN'T CONTINUE ERROR`, and `?RETURN WITHOUT GOSUB ERROR`.

## Syntax Reference

See [Basic_Syntax.md](Basic_Syntax.md) for the complete currently supported syntax.

## Smoke Tests

Sample BASIC programs for smoke testing live in [tests/smoke/run_smoke_tests.ps1](tests/smoke/run_smoke_tests.ps1) and [tests/smoke](tests/smoke).

Run them with:

```powershell
.\tests\smoke\run_smoke_tests.ps1
```

