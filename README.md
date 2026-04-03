# erlbasic

A BASIC interpreter, implemented in Erlang, exposed over TCP/IP. Each TCP client gets its own isolated interpreter state.

## Features

- Multiple concurrent TCP and/or WebSocket clients
- One interpreter instance per connection
- Stored program lines using numeric BASIC line numbers
- Immediate commands: `PRINT`, `LET`, `INPUT`, `LIST`, `RUN`, `CONT`, `NEW`, `DIR`, `SAVE`, `LOAD`, `SCRATCH`, `RENUM`, `QUIT`
- Program statements: `LET`, `REM`, `PRINT`, `PRINT USING`, `INPUT`, `LOCATE`, `COLOR`, `DATA`, `READ`, `DIM`, `IF/THEN/ELSE`, `FOR/NEXT`, `GOTO`, `GOSUB/RETURN`, `GET`, `GETKEY`, `SLEEP`, `END`
- Graphics mode (WebSocket only): `HGR`, `TEXT`, `PSET`, `LINE`, `LINETO`, `RECT`, `CIRCLE` with 640×480 resolution and 16 colors
- Expression engine with numeric operators, exponentiation, BASIC-style math functions (`SIN`, `COS`, `TAN`, `ACOS`, `SQRT`, `INT`, `FLOOR`, `CEIL`, `TIMER`, `VAL`, etc.), and string helpers (`LEFT$`, `RIGHT$`, `MID$`, `LEN`, `ASC`, `CHR$`, `STR$`, `STRING$`, `DATE$`, `TIME$`, `TERM$`)

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

### HTTPS Support

ErlBASIC supports HTTPS for secure connections. For development with self-signed certificates:

```powershell
# Generate self-signed certificates
pwsh generate_certs.ps1

# Enable HTTPS in sys.config
cp sys.config.https sys.config

# Build and run
pwsh run.ps1
```

Then access via:
```
https://localhost:8443/
```

For production deployment with Let's Encrypt and automatic certificate renewal, see [CERTBOT_DEPLOYMENT.md](CERTBOT_DEPLOYMENT.md).

For testing on localhost and local network, see [HTTPS_TESTING.md](HTTPS_TESTING.md).

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

- Expressions support integer/float literals, quoted strings, scalar/array variable lookup (including 1D/2D/3D arrays), arithmetic operators, common BASIC math functions, and string functions (`LEFT$`, `RIGHT$`, `MID$`, `LEN`, `ASC`, `CHR$`, `STR$`, `STRING$`, `DATE$`, `TIME$`, `TERM$`).
- `TIMER` returns seconds since midnight as a float (GW-BASIC compatible).
- `REM` starts a comment statement. Any `:` after `REM` is treated as comment text, not a statement separator.
- Undefined variables evaluate to `0`.
- Sending an empty stored line like `20` deletes that line from the program.
- Ctrl-C during `RUN` triggers `BREAK`; `CONT` resumes from the break point when continuation context exists.
- Runtime errors include `?TYPE MISMATCH ERROR`, `?CAN'T CONTINUE ERROR`, and `?RETURN WITHOUT GOSUB ERROR`.
- `LOCATE row, col` moves the cursor for WebSocket/xterm clients. Telnet/TCP sessions report `?TTY DOESN'T SUPPORT CURSOR MOVEMENT`.
- `COLOR fg[, bg]` sets text color (0–15 foreground, 0–7 background). No-op on telnet/TCP.
- `GET A$` reads one character non-blocking (empty string if buffer empty); `GETKEY A$` blocks until a keystroke arrives. Both switch the WebSocket browser into char mode for immediate keystroke delivery.
- `SLEEP n` pauses execution for `n` seconds (float). Yields the Erlang scheduler; other connections are unaffected.
- `SAVE <name>`, `LOAD <name>`, `SCRATCH <name>`, and `DIR` manage stored programs in a per-user directory under `~/BASIC/<user-id>` (falls back to `default`).

## Syntax Reference

See [Basic_Syntax.md](Basic_Syntax.md) for the complete currently supported syntax.

## Examples

- [examples/tictactoe.bas](examples/tictactoe.bas) - Tic-Tac-Toe with human/computer play.
- [examples/flag.bas](examples/flag.bas) - colorized American flag using loops, `COLOR`, and `STRING$`.
- [examples/enterprise.bas](examples/enterprise.bas) - Starship Enterprise side-view with animated twinkling starfield, using `LOCATE`, `COLOR`, `SLEEP`, and `TIMER`.
- [examples/graphics.bas](examples/graphics.bas) - Graphics demo using `HGR`, `PSET`, `LINE`, `LINETO`, `RECT`, `CIRCLE`, and `TEXT` to draw shapes and pixels on a 640×480 canvas (WebSocket only).
- [examples/life.bas](examples/life.bas) - Graphics-mode Conway's Life with optimized neighbor summation.
- [examples/textlife.bas](examples/textlife.bas) - Text-mode Conway's Life using `#` for occupied cells.
- [examples/textlife_fast.bas](examples/textlife_fast.bas) - Faster text-mode Life renderer with reduced cursor movement and lightweight per-cell drawing.

## EUnit Tests

EUnit tests live under `eunit_tests/`.

Run EUnit from the repo root with:

```powershell
escript $env:USERPROFILE\rebar3 eunit
```

If `rebar3` is already on your PATH, this also works:

```powershell
rebar3 eunit
```

## Smoke Tests

Sample BASIC programs for smoke testing live in [smoke_tests/run_smoke_tests.ps1](smoke_tests/run_smoke_tests.ps1) and [smoke_tests](smoke_tests).

Run them with:

```powershell
.\run_tests.ps1
```

## Performance Tests (Life)

To benchmark Life programs in a repeatable runner:

```powershell
.\run_perf_tests.ps1
```

The perf runner executes in WebSocket mode with reduced generation counts for CI-friendly runtime and verifies:

- `examples/life.bas` stays under its budget
- `examples/textlife.bas` stays under its budget
- `examples/textlife_fast.bas` stays under its budget
- `examples/textlife_fast.bas` is faster than `examples/textlife.bas` (hard fail otherwise)

Optional budget overrides:

- `ERLBASIC_PERF_MAX_LIFE_MS`
- `ERLBASIC_PERF_MAX_TEXTLIFE_MS`
- `ERLBASIC_PERF_MAX_TEXTLIFE_FAST_MS`

