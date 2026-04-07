# erlbasic

A BASIC interpreter, implemented in Erlang, exposed over TCP/IP and WebSocket. Each connection gets its own isolated interpreter instance. Users can publish personal BASIC homepages served over HTTP.

## Features

- Multiple concurrent TCP and/or WebSocket clients; one interpreter per connection
- Stored program lines using numeric BASIC line numbers
- Immediate commands: `PRINT`, `LET`, `INPUT`, `LIST`, `RUN`, `CONT`, `NEW`, `DIR`, `SAVE`, `LOAD`, `SCRATCH`, `RENUM`, `QUIT`
- Program statements: `LET`, `REM`, `PRINT`, `PRINT USING`, `INPUT`, `INPUT LINE`, `LOCATE`, `COLOR`, `DATA`, `READ`, `DIM`, `DEF FN`, `IF/THEN/ELSE`, `FOR/NEXT`, `GOTO`, `GOSUB/RETURN`, `ON...GOTO`, `ON...GOSUB`, `ON ERROR GOTO`, `RESUME`, `GET`, `GETKEY`, `SLEEP`, `TRON`, `TROFF`, `END`
- Graphics mode (WebSocket only): `HGR`, `TEXT`, `PSET`, `LINE`, `LINETO`, `RECT`, `CIRCLE` — 800×600 canvas, 16 colours
- Full expression engine: numeric operators, exponentiation, math functions (`SIN`, `COS`, `TAN`, `ACOS`, `SQRT`, `INT`, `FLOOR`, `CEIL`, `TIMER`, `VAL`, `POS`, …), string functions (`LEFT$`, `RIGHT$`, `MID$`, `INSTR`, `LEN`, `ASC`, `CHR$`, `STR$`, `SPACE$`, `STRING$`, `DATE$`, `TIME$`, `TERM$`)
- Error handling: `ON ERROR GOTO`, `RESUME`, `RESUME NEXT`, `RESUME line`, `ERR`, `ERL`
- File I/O: `OPEN`, `CLOSE`, `PRINT #`, `INPUT #`, `LINE INPUT #`, `WRITE #`, `FIELD`, `PUT #`, `GET #`, `EOF()`, `LOF()`, `LOC()` — sandboxed to user directory
- **User homepages**: each user can place `HOME.BAS` in their program directory; the interpreter runs it server-side and serves the output as an HTML page at `/:username`
- RSTS/E-style PPN login (`[Project,Programmer]`) with PBKDF2-SHA256 password hashing
- Per-user disk quotas, per-session memory quotas (watchdog process), per-PPN session limits
- HTTPS support (self-signed or Let's Encrypt)

## Module Map

| Module | Role |
|---|---|
| `erlbasic_app` | OTP application entry point; initialises limits, accounts, homepage cache |
| `erlbasic_sup` | Supervisor; starts memory watchdog, TCP listener, Cowboy HTTP/HTTPS server |
| `erlbasic_listener` | `gen_server` accepting TCP connections on port 5555 |
| `erlbasic_conn` | TCP and WebSocket connection handlers; RSTS/E login loop |
| `erlbasic_ws_handler` | Cowboy WebSocket handler; bridges browser ↔ `erlbasic_conn` |
| `erlbasic_http_handler` | Serves `priv/www/index.html` for unmatched HTTP routes |
| `erlbasic_homepage_handler` | Serves user homepages at `/:username`; runs `HOME.BAS`, caches output |
| `erlbasic_admin_handler` | Web admin UI (account management, quota inspection) |
| `erlbasic_interp` | REPL layer: parses typed lines, routes to runtime or command handler |
| `erlbasic_runtime` | Program execution loop; FOR/NEXT, GOSUB/RETURN, error handling |
| `erlbasic_parser` | Statement and expression text → parse-tree tuples |
| `erlbasic_commands` | LIST, SAVE, LOAD, SCRATCH, DIR, RENUM, DELETE, program serialisation |
| `erlbasic_eval` | Expression evaluation, value formatting, error codes |
| `erlbasic_eval_expr` | Recursive-descent expression parser |
| `erlbasic_eval_lexer` | Tokeniser for the expression parser |
| `erlbasic_eval_builtins` | Built-in functions (math, string, I/O helpers) |
| `erlbasic_eval_arrays` | Array allocation, bounds checking, element access |
| `erlbasic_fileio` | OPEN/CLOSE/READ/WRITE channel dispatch; eval helpers for channel expressions |
| `erlbasic_filestore` | Abstraction layer over the backing disk store for channel files |
| `erlbasic_graphics` | Graphics and display statement dispatch (`HGR`, `PSET`, `LINE`, `LOCATE`, `COLOR`, …) |
| `erlbasic_print_using` | `PRINT USING` format-string engine |
| `erlbasic_storage` | Per-user program storage (SAVE/LOAD/DIR) backed by `~/ErlUsers/` |
| `erlbasic_accounts` | DETS-backed PBKDF2 account store |
| `erlbasic_limits` | Per-project / per-user disk and memory quota policy |
| `erlbasic_mem_watchdog` | `gen_server` that polls session heap sizes and enforces memory quotas |
| `erlbasic_keywords` | Centralised keyword registry (parser, lexer, LIST formatter all read from here) |
| `erlbasic_state.hrl` | Shared `#state{}` record definition |

## Build

```powershell
.\build.ps1
```

## Run

```powershell
.\run.ps1
```

The BASIC terminal server listens on port **5555** (TCP). The web interface listens on port **8081** (HTTP).

## Connect

```powershell
telnet localhost 5555
```

or navigate to:

```
http://localhost:8081/
```

### HTTPS Support

For development with self-signed certificates:

```powershell
pwsh generate_certs.ps1
cp sys.config.https sys.config
pwsh run.ps1
```

Access via `https://localhost:8443/`. For production Let's Encrypt deployment see [CERTBOT_DEPLOYMENT.md](CERTBOT_DEPLOYMENT.md). For localhost/LAN testing see [HTTPS_TESTING.md](HTTPS_TESTING.md).

## User Homepages

Every user account gets a public homepage at `/:username` (e.g. `http://localhost:8081/alice`).

If a file named `HOME.BAS` (or `home.bas`) exists in the user's program directory, the interpreter runs it and serves the terminal output wrapped in an HTML page. If the file is absent, a styled default page is shown instead.

**Caching policy** — output is cached by file SHA-256 hash:
- Programs using `INPUT`, `INKEY$`, `GETKEY`, `RND`, or `RANDOMIZE` are **never cached** (volatile).
- Programs using `TIME$` or `TIMER` are cached for **30 seconds**.
- Programs using `DATE$` are cached for **1 hour**.
- Static programs are cached **until the file changes**.

## Example session

```text
10 LET X = 42
20 PRINT X
30 PRINT "HELLO"
40 END
RUN
```

## Notes

- Variable names are case-insensitive and cannot use reserved language keywords.
- `REM` starts a comment; `:` after `REM` is comment text, not a separator.
- Undefined variables evaluate to `0`.
- Sending an empty stored line (e.g. `20`) deletes that line from the program.
- Ctrl-C during `RUN` triggers `BREAK`; `CONT` resumes from the break point.
- `TRON`/`TROFF` toggle runtime line tracing (`[line]` markers during `RUN`).
- `LOCATE row, col` moves the cursor (WebSocket/xterm only; errors on telnet/TCP).
- `COLOR fg[, bg]` sets text colour (0–15 fg, 0–7 bg). No-op on telnet/TCP.
- `GET A$` reads one character non-blocking; `GETKEY A$` blocks until a keystroke.
- `SLEEP n` pauses for up to 30 seconds (maximum capped); other sessions are unaffected.
- `SAVE`/`LOAD`/`SCRATCH`/`DIR` manage programs in the user's sandboxed directory.
- File I/O is sandboxed to the user directory; max 15 channels open simultaneously.
- Absolute paths and `..` path traversal are rejected.

## Syntax Reference

See [Basic_Syntax.md](Basic_Syntax.md) for full syntax documentation.

## Examples

- [examples/tictactoe.bas](examples/tictactoe.bas) — Tic-Tac-Toe with human/computer play
- [examples/flag.bas](examples/flag.bas) — Colourised American flag using `COLOR` and `STRING$`
- [examples/enterprise.bas](examples/enterprise.bas) — Animated starship using `LOCATE`, `COLOR`, `SLEEP`, `TIMER`
- [examples/graphics.bas](examples/graphics.bas) — Graphics demo: `HGR`, `PSET`, `LINE`, `RECT`, `CIRCLE` (WebSocket only)
- [examples/hgr2demo.bas](examples/hgr2demo.bas) — Split-screen demo: `HGR2` 800×480 graphics above 4 text rows (WebSocket only)
- [examples/dblbuff_demo.bas](examples/dblbuff_demo.bas) — Double-buffer demo: `DBLBUFF`, `FLUSH`, `PGET`, `GETCHAR` (WebSocket only)
- [examples/life.bas](examples/life.bas) — Graphics-mode Conway's Life
- [examples/asciilife.bas](examples/asciilife.bas) — Text-mode Conway's Life using `#` for occupied cells
- [examples/file_io.bas](examples/file_io.bas) — Sequential and random file I/O demo

## Testing

### Run everything at once

```powershell
.\run_all.ps1
```

This runs, in order:
1. **Build** — `rebar3 compile`
2. **EUnit tests** — unit tests in `eunit_tests/`
3. **Smoke tests** — end-to-end BASIC programs in `smoke_tests/`
4. **Perf gate** — `life.bas` and `asciilife.bas` within budget thresholds
5. **Textlife benchmark** — 100-generation asciilife, 5 runs, with history

### Individual test scripts

```powershell
.\run_tests.ps1               # EUnit + smoke tests only
.\run_perf_tests.ps1          # Pass/fail perf gate only
.\run_textlife_benchmark.ps1  # Detailed benchmark only
```

### Performance history

Each run of the perf gate and textlife benchmark appends a dated record:

- `perf_tests/perf_runner_history.txt` — `{UnixSecs, GitSha, LifeMs, AsciiLifeMs}.`
- `perf_tests/textlife_history.txt` — `{UnixSecs, GitSha, MinMs, AvgMs, MaxMs}.`

On each run a delta line is printed comparing against the previous entry:

```
Vs previous (4840ea7): life.bas +12 ms  asciilife.bas -5 ms
```

Environment variable overrides:

| Variable | Default | Effect |
|---|---|---|
| `ERLBASIC_PERF_MAX_LIFE_MS` | 15000 | Budget for `life.bas` perf gate |
| `ERLBASIC_PERF_MAX_ASCIILIFE_MS` | 30000 | Budget for `asciilife.bas` perf gate |
| `ERLBASIC_TEXTLIFE_BENCH_RUNS` | 5 | Number of benchmark runs |
