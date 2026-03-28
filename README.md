# erlbasic

A minimal Erlang BASIC interpreter exposed over TCP/IP. Each TCP client gets its own isolated interpreter state.

## Features

- Multiple concurrent TCP clients
- One interpreter instance per connection
- Stored program lines using numeric BASIC line numbers
- Immediate commands: `PRINT`, `LET`, `LIST`, `RUN`, `NEW`, `QUIT`
- Program statements: `LET`, `PRINT`, `END`

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

## Notes

- Expressions currently support integer literals, quoted strings, and variable lookup.
- Undefined variables evaluate to `0`.
- Sending an empty stored line like `20` deletes that line from the program.

## Syntax Reference

See [Basic_Syntax.md](Basic_Syntax.md) for the complete currently supported syntax.