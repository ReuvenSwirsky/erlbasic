#!/usr/bin/env escript
%%! -pa ../_build/default/lib/erlbasic/ebin

main([RepoRoot]) ->
    code:add_pathz(filename:join([RepoRoot, "_build", "default", "lib", "erlbasic", "ebin"])),
    code:add_pathz(filename:join([RepoRoot, "_build", "default", "lib", "cowboy", "ebin"])),
    {ok, LifeMs}      = run_case(RepoRoot, "examples/life.bas",      15000),
    {ok, AsciiLifeMs} = run_case(RepoRoot, "examples/asciilife.bas", 30000),
    HistoryFile = filename:join([RepoRoot, "perf_tests", "perf_runner_history.txt"]),
    show_history_comparison(HistoryFile, LifeMs, AsciiLifeMs),
    GitSha = string:trim(os:cmd("git -C " ++ RepoRoot ++ " rev-parse --short HEAD")),
    save_history(HistoryFile, GitSha, LifeMs, AsciiLifeMs),
    io:format("Performance tests passed.~n"),
    ok;
main(_) ->
    io:format("usage: perf_runner.escript <repo-root>~n"),
    halt(1).

run_case(RepoRoot, RelPath, DefaultMaxMs) ->
    Path = filename:join(RepoRoot, RelPath),
    Name = filename:basename(Path),
    MaxMs = case os:getenv(env_name_for_case(Name)) of
        false -> DefaultMaxMs;
        Str ->
            case string:to_integer(Str) of
                {Int, ""} when Int > 0 -> Int;
                _ -> DefaultMaxMs
            end
    end,
    io:format("PERF ~s (budget: ~B ms) ... ", [Name, MaxMs]),

    PrevConnType = erlang:get(erlbasic_conn_type),
    PrevOutputPid = erlang:get(output_pid),
    PrevOutputSocket = erlang:get(output_socket),
    SinkPid = spawn(fun sink_loop/0),

    erlang:put(erlbasic_conn_type, websocket),
    erlang:put(output_pid, SinkPid),
    erlang:erase(output_socket),

    RunResult =
        try
            {ok, BasBin} = file:read_file(Path),
            ProgramLines0 = [
                string:trim(Line)
                || Line <- string:split(binary_to_list(BasBin), "\n", all),
                   string:trim(Line) =/= ""
            ],
            ProgramLines = tune_program(Name, ProgramLines0),
            State0 = erlbasic_interp:new_state(),
            State1 = lists:foldl(fun(Line, SAcc) ->
                {SNext, _} = erlbasic_interp:handle_input(Line, SAcc),
                SNext
            end, State0, ProgramLines),

            T0 = erlang:monotonic_time(millisecond),
            {_FinalState, Output} = erlbasic_interp:handle_input("RUN", State1),
            T1 = erlang:monotonic_time(millisecond),
            ElapsedMs = T1 - T0,
            OutText = lists:flatten(Output),
            case re:run(OutText, "ERROR", [{capture, none}]) of
                match -> {error, runtime_error, ElapsedMs, OutText};
                nomatch ->
                    case ElapsedMs =< MaxMs of
                        true -> {ok, ElapsedMs};
                        false -> {error, timeout, ElapsedMs, MaxMs}
                    end
            end
        after
            SinkPid ! stop,
            restore_env(erlbasic_conn_type, PrevConnType),
            restore_env(output_pid, PrevOutputPid),
            restore_env(output_socket, PrevOutputSocket)
        end,

    case RunResult of
        {ok, ElapsedResultMs} ->
            io:format("PASS (~B ms)~n", [ElapsedResultMs]),
            {ok, ElapsedResultMs};
        {error, timeout, ElapsedResultMs, BudgetMs} ->
            io:format("FAIL (~B ms > ~B ms)~n", [ElapsedResultMs, BudgetMs]),
            halt(1);
        {error, runtime_error, ElapsedResultMs, OutTextResult} ->
            io:format("FAIL (runtime error after ~B ms)~n~s~n", [ElapsedResultMs, OutTextResult]),
            halt(1)
    end.

env_name_for_case("life.bas") ->
    "ERLBASIC_PERF_MAX_LIFE_MS";
env_name_for_case("asciilife.bas") ->
    "ERLBASIC_PERF_MAX_ASCIILIFE_MS";
env_name_for_case(_Other) ->
    "ERLBASIC_PERF_MAX_MS".

load_history(HistoryFile) ->
    case file:consult(HistoryFile) of
        {ok, Terms} -> Terms;
        _ -> []
    end.

save_history(HistoryFile, GitSha, LifeMs, AsciiLifeMs) ->
    {Date, Time} = calendar:local_time(),
    UnixSecs = calendar:datetime_to_gregorian_seconds({Date, Time})
              - calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
    Record = io_lib:format("{~B, ~p, ~B, ~B}.~n",
                           [UnixSecs, GitSha, LifeMs, AsciiLifeMs]),
    file:write_file(HistoryFile, Record, [append]).

show_history_comparison(HistoryFile, LifeMs, AsciiLifeMs) ->
    case load_history(HistoryFile) of
        [] ->
            io:format("History: no previous results recorded~n");
        History ->
            {_Ts, PrevSha, PrevLife, PrevAscii} = lists:last(History),
            DeltaLife  = LifeMs  - PrevLife,
            DeltaAscii = AsciiLifeMs - PrevAscii,
            io:format("Vs previous (~s): life.bas ~s~B ms  asciilife.bas ~s~B ms~n",
                      [PrevSha,
                       sign(DeltaLife),  abs(DeltaLife),
                       sign(DeltaAscii), abs(DeltaAscii)])
    end.

sign(N) when N >= 0 -> "+";
sign(_)             -> "-".

tune_program("life.bas", Lines) ->
    [
        case string:trim(Line) of
            "50 LET W = 80" -> "50 LET W = 16";
            "60 LET H = 60" -> "60 LET H = 12";
            "240 FOR GEN = 1 TO 200" -> "240 FOR GEN = 1 TO 3";
            Other -> Other
        end
        || Line <- Lines
    ];
tune_program("asciilife.bas", Lines) ->
    [
        case string:trim(Line) of
            "60 LET W% = 60" -> "60 LET W% = 20";
            "70 LET H% = 20" -> "70 LET H% = 8";
            "250 FOR GEN% = 1 TO 500" -> "250 FOR GEN% = 1 TO 3";
            Other -> Other
        end
        || Line <- Lines
    ];
tune_program(_Name, Lines) ->
    Lines.

sink_loop() ->
    receive
        stop -> ok;
        {output, _} -> sink_loop();
        _Other -> sink_loop()
    end.

restore_env(Key, undefined) ->
    erlang:erase(Key);
restore_env(Key, Value) ->
    erlang:put(Key, Value).
