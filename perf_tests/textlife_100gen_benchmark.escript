#!/usr/bin/env escript
%%! -pa ../_build/default/lib/erlbasic/ebin

main([RepoRoot]) ->
    code:add_pathz(filename:join([RepoRoot, "_build", "default", "lib", "erlbasic", "ebin"])),
    code:add_pathz(filename:join([RepoRoot, "_build", "default", "lib", "cowboy", "ebin"])),
    Runs = env_int("ERLBASIC_TEXTLIFE_BENCH_RUNS", 5),
    io:format("Benchmarking examples/asciilife.bas for 100 generations (~B runs)~n", [Runs]),
    case run_benchmark(RepoRoot, Runs) of
        {ok, Times} ->
            MinMs = lists:min(Times),
            MaxMs = lists:max(Times),
            AvgMs = lists:sum(Times) / length(Times),
            io:format("Runs: ~p~n", [Times]),
            io:format("Average: ~.2f ms~n", [AvgMs]),
            io:format("Min: ~B ms~n", [MinMs]),
            io:format("Max: ~B ms~n", [MaxMs]),
            ok;
        {error, runtime_error, RunNumber, ElapsedMs, OutText} ->
            io:format("Run ~B failed after ~B ms~n~s~n", [RunNumber, ElapsedMs, OutText]),
            halt(1)
    end;
main(_) ->
    io:format("usage: textlife_100gen_benchmark.escript <repo-root>~n"),
    halt(1).

run_benchmark(RepoRoot, Runs) ->
    Path = filename:join([RepoRoot, "examples", "asciilife.bas"]),
    {ok, BasBin} = file:read_file(Path),
    ProgramLines0 = [
        string:trim(Line)
        || Line <- string:split(binary_to_list(BasBin), "\n", all),
           string:trim(Line) =/= ""
    ],
    ProgramLines = tune_program(ProgramLines0),
    run_benchmark(ProgramLines, Runs, 1, []).

run_benchmark(_ProgramLines, Runs, RunNumber, Times) when RunNumber > Runs ->
    {ok, lists:reverse(Times)};
run_benchmark(ProgramLines, Runs, RunNumber, Times) ->
    io:format("RUN ~B ... ", [RunNumber]),
    case run_once(ProgramLines) of
        {ok, ElapsedMs} ->
            io:format("~B ms~n", [ElapsedMs]),
            run_benchmark(ProgramLines, Runs, RunNumber + 1, [ElapsedMs | Times]);
        {error, runtime_error, ElapsedMs, OutText} ->
            {error, runtime_error, RunNumber, ElapsedMs, OutText}
    end.

run_once(ProgramLines) ->
    PrevConnType = erlang:get(erlbasic_conn_type),
    PrevOutputPid = erlang:get(output_pid),
    PrevOutputSocket = erlang:get(output_socket),
    SinkPid = spawn(fun sink_loop/0),

    erlang:put(erlbasic_conn_type, websocket),
    erlang:put(output_pid, SinkPid),
    erlang:erase(output_socket),

    try
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
            nomatch -> {ok, ElapsedMs}
        end
    after
        SinkPid ! stop,
        restore_env(erlbasic_conn_type, PrevConnType),
        restore_env(output_pid, PrevOutputPid),
        restore_env(output_socket, PrevOutputSocket)
    end.

tune_program(Lines) ->
    [
        case string:trim(Line) of
            "250 FOR GEN% = 1 TO 500" -> "250 FOR GEN% = 1 TO 100";
            Other -> Other
        end
        || Line <- Lines
    ].

env_int(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        Str ->
            case string:to_integer(Str) of
                {Int, ""} when Int > 0 -> Int;
                _ -> Default
            end
    end.

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