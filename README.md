# erlbasic

A minimal Erlang BASIC interpreter exposed over TCP/IP. Each TCP client gets its own isolated interpreter state.

## Features

- Multiple concurrent TCP clients
- One interpreter instance per connection
- Stored program lines using numeric BASIC line numbers
- Immediate commands: `PRINT`, `LET`, `INPUT`, `LIST`, `RUN`, `NEW`, `RENUM`, `QUIT`
- Program statements: `LET`, `PRINT`, `INPUT`, `IF/THEN/ELSE`, `FOR/NEXT`, `GOTO`, `GOSUB/RETURN`, `END`
- Expression engine with numeric operators, exponentiation, and BASIC-style math functions (`SIN`, `COS`, `TAN`, `ACOS`, `SQRT`, etc.)

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

- Expressions support integer/float literals, quoted strings, variable lookup, arithmetic operators, and common BASIC math functions.
- Undefined variables evaluate to `0`.
- Sending an empty stored line like `20` deletes that line from the program.

## Known Limitations

- `FOR/NEXT` is designed for `RUN`; using it in immediate mode returns `?SYNTAX ERROR`.

## Syntax Reference

See [Basic_Syntax.md](Basic_Syntax.md) for the complete currently supported syntax.

## Smoke Tests

Sample BASIC programs for smoke testing live in [tests/smoke/run_smoke_tests.ps1](tests/smoke/run_smoke_tests.ps1) and [tests/smoke](tests/smoke).

Run them with:

```powershell
.\tests\smoke\run_smoke_tests.ps1
```