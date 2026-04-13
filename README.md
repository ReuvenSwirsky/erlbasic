# erlbasic

A BASIC interpreter, implemented in Erlang, exposed over TCP/IP and WebSocket. Each connection gets its own isolated interpreter instance. Users can publish personal BASIC homepages served over HTTP.

## Features

- Multiple concurrent TCP and/or WebSocket clients; one interpreter per connection
- Browser WebSocket sessions use permessage-deflate compression with `server_no_context_takeover` for stable interactive `INPUT`/`GETKEY` traffic
- Stored program lines using numeric BASIC line numbers
- Immediate commands: `PRINT`, `LET`, `INPUT`, `LIST`, `RUN`, `CONT`, `NEW`, `DIR`, `SAVE`, `LOAD`, `SCRATCH`, `RENUM`, `QUIT`
- Program statements: `LET`, `REM`, `PRINT`, `PRINT USING`, `INPUT`, `INPUT LINE`, `LOCATE`, `COLOR`, `DATA`, `READ`, `DIM`, `DEF FN`, `IF/THEN/ELSE`, `FOR/NEXT`, `GOTO`, `GOSUB/RETURN`, `ON...GOTO`, `ON...GOSUB`, `ON PLAY(...) GOSUB`, `ON SPRITE GOSUB`, `ON TIMER(...) GOSUB`, `ON ERROR GOTO`, `RESUME`, `STOP`, `GET`, `GETKEY`, `SLEEP`, `TRON`, `TROFF`, `END`
- Graphics mode (WebSocket only): `HGR`, `HGR2`, `TEXT`, `PSET`, `LINE`, `LINETO`, `RECT`, `CIRCLE`, `BUFFER`, `FLUSH`, `PGET`, `GETCHAR`, `SOUND`, `SPRITE` (`LOAD`, `SHOW`, `HIDE`, `SCALE`, `CLEAR`, position)
- Full expression engine: numeric operators, exponentiation, decimal/scientific (`E`/`D`) and `0x...` hexadecimal integer literals, math functions (`SIN`, `COS`, `TAN`, `ACOS`, `SQRT`, `INT`, `FLOOR`, `CEIL`, `CINT`, `CDBL`, `CSNG`, `TYPEOF`, `TIMER`, `FREE`, `MEM_USED()`, `VAL`, `POS`, …), string functions (`LEFT$`, `RIGHT$`, `MID$`, `INSTR`, `LEN`, `ASC`, `CHR$`, `STR$`, `SPACE$`, `STRING$`, `DATE$`, `TIME$`, `TERM$`)
- Error handling: `ON ERROR GOTO`, `RESUME`, `RESUME NEXT`, `RESUME line`, `ERR`, `ERL`
- File I/O: `OPEN`, `CLOSE`, `PRINT #`, `INPUT #`, `LINE INPUT #`, `WRITE #`, `FIELD`, `PUT #`, `GET #`, `EOF()`, `LOF()`, `LOC()` — sandboxed to user directory
- **User homepages**: each user can place `HOME.BAS` in their program directory; the interpreter runs it server-side and renders the output as a styled HTML page at `/:username`; text output is captured as coloured terminal panels; `HGR`/`HGR2` graphics output is captured as inline SVG panels; `HOME PUBLISH` flushes the current screen as a panel and resets for the next one — multiple panels per page are supported
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

If a file named `HOME.BAS` (or `home.bas`) exists in the user's program directory, the interpreter runs it server-side and renders the output as a styled HTML page. The program uses ordinary `PRINT`, `COLOR`, `LOCATE`, and graphics statements to build panels, then calls `HOME PUBLISH` to flush the current screen as a rendered panel. Multiple `HOME PUBLISH` calls produce multiple stacked panels. If `HOME.BAS` is absent, a styled default page is shown instead.

See [HOMEPAGE_GUIDE.md](HOMEPAGE_GUIDE.md) for authoring instructions and examples.


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
- Default numeric values in erlbasic follow a decimal-style numeric model.
- `#` suffix declares an explicit floating-point variable (double-precision runtime float).
- `REM` starts a comment; `:` after `REM` is comment text, not a separator.
- Undefined variables evaluate to `0`.
- Sending an empty stored line (e.g. `20`) deletes that line from the program.
- Ctrl-C during `RUN` triggers `BREAK`; `CONT` resumes from the break point.
- `STOP` during `RUN` triggers `BREAK IN <line>`; `CONT` resumes after the `STOP` statement.
- `TRON`/`TROFF` toggle runtime line tracing (`[line]` markers during `RUN`).
- `LOCATE row, col` moves the cursor (WebSocket/xterm only; errors on telnet/TCP).
- `COLOR fg[, bg]` sets text colour (0–15 fg, 0–7 bg). No-op on telnet/TCP.
- `GET A$` reads one character non-blocking; `GETKEY A$` blocks until a keystroke.
- Browser WebSocket compression is enabled, but negotiated with `server_no_context_takeover` so successive prompt/output frames remain decodable during interactive sessions.
- `SLEEP n` pauses for up to 30 seconds (maximum capped); other sessions are unaffected.
- `SPRITE LOAD` reads bitmap bytes from 1D BYTE arrays (`&` suffix); `255` is treated as transparent.
- Integer expressions also accept `0x...` / `0X...` hexadecimal literals, which are useful for packed sprite row masks and other bit-oriented code.
- `ON SPRITE GOSUB` is collision-edge triggered and exposes colliding sprite IDs via `SPRCOL1%` and `SPRCOL2%`.
- `ON TIMER(n) GOSUB` fires a subroutine approximately every `n` seconds during `RUN`, independently of player input; re-entrancy guarded.
- `SAVE`/`LOAD`/`SCRATCH`/`DIR` manage programs in the user's sandboxed directory.
- `DIR` output is grouped by source (`Your files` and `Shared examples`) to distinguish personal files from bundled examples.
- `IF ... THEN <line>` and `IF ... THEN <line> ELSE <line>` are accepted as shorthand for implied `GOTO` targets.
- File I/O is sandboxed to the user directory; max 15 channels open simultaneously.
- Absolute paths and `..` path traversal are rejected.

## Architecture Notes

- Time-sharing and distributed-node roadmap: [TIMESHARING_DISTRIBUTION_ARCHITECTURE.md](TIMESHARING_DISTRIBUTION_ARCHITECTURE.md)

## Syntax Reference

See [Basic_Syntax.md](Basic_Syntax.md) for full syntax documentation.

## Roadmap

See [ISSUE_LIST.md](ISSUE_LIST.md) for the prioritized backlog and next-phase issue list.

## Examples

- [examples/tictactoe.bas](examples/tictactoe.bas) — Tic-Tac-Toe with human/computer play
- [examples/flag.bas](examples/flag.bas) — Colourised American flag using `COLOR` and `STRING$`
- [examples/enterprise.bas](examples/enterprise.bas) — Animated starship using `LOCATE`, `COLOR`, `SLEEP`, `TIMER`
- [examples/graphics.bas](examples/graphics.bas) — Graphics demo: `HGR`, `PSET`, `LINE`, `RECT`, `CIRCLE` (WebSocket only)
- [examples/example_home.bas](examples/example_home.bas) — Three-panel sample `HOME.BAS`: colour-effect intro text, `HGR` graphics panel (colour bars + concentric circles), closing note — demonstrates `HOME PUBLISH` for homepage authoring
- [examples/sprites.bas](examples/sprites.bas) — 32x32 sprite demo built from 32-bit hexadecimal row masks expanded into BYTE sprite buffers, with collision callback (WebSocket only)
- [examples/sprites_hgr2.bas](examples/sprites_hgr2.bas) — Interactive `HGR2` demo with 64x64 sprites generated from 64-bit hexadecimal row masks and `GETKEY` movement (`WASD`)
- [examples/hgr2demo.bas](examples/hgr2demo.bas) — Split-screen demo: `HGR2` 800×480 graphics above 4 text rows (WebSocket only)
- [examples/bufffer.bas](examples/bufffer.bas) — Buffered-output demo: `BUFFER`, `FLUSH`, `PGET`, `GETCHAR` (WebSocket only)
- [examples/lunarlander.bas](examples/lunarlander.bas) — Interactive side-view Lunar Lander in `HGR2` with thrust controls and pad landing physics
- [examples/life.bas](examples/life.bas) — Graphics-mode Conway's Life
- [examples/asciilife.bas](examples/asciilife.bas) — Text-mode Conway's Life using `#` for occupied cells
- [examples/file_io.bas](examples/file_io.bas) — Sequential and random file I/O demo
- [examples/playmusic.bas](examples/playmusic.bas) — MML background music demo using `PLAY` background mode and `ON PLAY(...) GOSUB` refill callback
- [examples/scale.bas](examples/scale.bas) — C major scale played with `SOUND` (two octaves up and down)
- [examples/stripesfx.bas](examples/stripesfx.bas) — Stars & Stripes ASCII fireworks display with `SOUND`, `LOCATE`, `COLOR`
- [examples/animtest.bas](examples/animtest.bas) — Simple HGR animation test using `BUFFER`/`FLUSH` double-buffering
- [examples/space_sprites.bas](examples/space_sprites.bas) — Space Invaders-style game in HGR2 mode: sprite fleet, player launcher, collision detection via `ON SPRITE GOSUB`, autonomous fleet movement via `ON TIMER(0.08) GOSUB`

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

The EUnit suite includes a compressed WebSocket integration test that performs a real login plus `INPUT` roundtrip against a temporary Cowboy listener.

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
