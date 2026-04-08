#!/usr/bin/env escript
%%! -pa ../_build/default/lib/erlbasic/ebin

main([RepoRoot]) ->
    code:add_pathz(filename:join([RepoRoot, "_build", "default", "lib", "erlbasic", "ebin"])),
    code:add_pathz(filename:join([RepoRoot, "_build", "default", "lib", "cowboy", "ebin"])),

    Runs = env_int("ERLBASIC_WS_GFX_BENCH_RUNS", 3),
    Gens = env_int("ERLBASIC_WS_GFX_BENCH_GENS", 30),

    io:format("Benchmarking websocket graphics send path: examples/life.bas (~B runs, ~B generations)~n",
              [Runs, Gens]),

    case run_benchmark(RepoRoot, Runs, Gens) of
        {ok, Results} ->
            print_summary(Results),
            HistoryFile = filename:join([RepoRoot, "perf_tests", "ws_graphics_history.txt"]),
            show_history_comparison(HistoryFile, Results),
            GitSha = string:trim(os:cmd("git -C " ++ RepoRoot ++ " rev-parse --short HEAD")),
            save_history(HistoryFile, GitSha, Results),
            ok;
        {error, runtime_error, RunNumber, ElapsedMs, OutText} ->
            io:format("Run ~B failed after ~B ms~n~s~n", [RunNumber, ElapsedMs, OutText]),
            halt(1)
    end;
main(_) ->
    io:format("usage: ws_graphics_benchmark.escript <repo-root>~n"),
    halt(1).

run_benchmark(RepoRoot, Runs, Gens) ->
    Path = filename:join([RepoRoot, "examples", "life.bas"]),
    {ok, BasBin} = file:read_file(Path),
    ProgramLines0 = [
        string:trim(Line)
        || Line <- string:split(binary_to_list(BasBin), "\n", all),
           string:trim(Line) =/= ""
    ],
    ProgramLines = tune_program(ProgramLines0, Gens),
    run_benchmark(ProgramLines, Runs, 1, []).

run_benchmark(_ProgramLines, Runs, RunNumber, Results) when RunNumber > Runs ->
    {ok, lists:reverse(Results)};
run_benchmark(ProgramLines, Runs, RunNumber, Results) ->
    io:format("RUN ~B ... ", [RunNumber]),
    case run_once(ProgramLines) of
        {ok, ElapsedMs, Stats} ->
            io:format("~B ms, ~B bytes, ~B ws frames (~B gfx, ~B gfxb, ~B gfx cmds)~n",
                      [ElapsedMs,
                       maps:get(bytes, Stats),
                       maps:get(msgs, Stats),
                       maps:get(gfx_frames, Stats),
                       maps:get(gfxb_frames, Stats),
                       maps:get(gfx_cmds, Stats)]),
            run_benchmark(ProgramLines, Runs, RunNumber + 1, [{ElapsedMs, Stats} | Results]);
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

        SinkPid ! {snapshot, self()},
        Stats = receive
            {snapshot, S} -> S
        after 5000 ->
            #{msgs => -1, bytes => -1, gfx_frames => -1, gfxb_frames => -1, gfx_cmds => -1}
        end,

        OutText = lists:flatten(Output),
        case re:run(OutText, "ERROR", [{capture, none}]) of
            match -> {error, runtime_error, ElapsedMs, OutText};
            nomatch -> {ok, ElapsedMs, Stats}
        end
    after
        SinkPid ! stop,
        restore_env(erlbasic_conn_type, PrevConnType),
        restore_env(output_pid, PrevOutputPid),
        restore_env(output_socket, PrevOutputSocket)
    end.

tune_program(Lines, Gens) ->
    [
        case string:trim(Line) of
            "240 FOR GEN = 1 TO 200" ->
                io_lib:format("240 FOR GEN = 1 TO ~B", [Gens]);
            Other ->
                Other
        end
        || Line <- Lines
    ].

print_summary(Results) ->
    Elapsed = [Ms || {Ms, _} <- Results],
    Bytes = [maps:get(bytes, S) || {_, S} <- Results],
    Msgs = [maps:get(msgs, S) || {_, S} <- Results],
    GfxFrames = [maps:get(gfx_frames, S) || {_, S} <- Results],
    GfxbFrames = [maps:get(gfxb_frames, S) || {_, S} <- Results],
    GfxCmds = [maps:get(gfx_cmds, S) || {_, S} <- Results],

    io:format("Runs: ~B~n", [length(Results)]),
    io:format("Elapsed ms: min=~B avg=~.1f max=~B~n",
              [lists:min(Elapsed), avg(Elapsed), lists:max(Elapsed)]),
    io:format("WS bytes:   min=~B avg=~.1f max=~B~n",
              [lists:min(Bytes), avg(Bytes), lists:max(Bytes)]),
    io:format("WS frames:  min=~B avg=~.1f max=~B~n",
              [lists:min(Msgs), avg(Msgs), lists:max(Msgs)]),
    io:format("GFX frames avg=~.1f, GFXB frames avg=~.1f, GFX cmds avg=~.1f~n",
              [avg(GfxFrames), avg(GfxbFrames), avg(GfxCmds)]).

load_history(HistoryFile) ->
    case file:consult(HistoryFile) of
        {ok, Terms} -> Terms;
        _ -> []
    end.

save_history(HistoryFile, GitSha, Results) ->
    Elapsed = [Ms || {Ms, _} <- Results],
    Bytes = [maps:get(bytes, S) || {_, S} <- Results],
    Msgs = [maps:get(msgs, S) || {_, S} <- Results],
    GfxbFrames = [maps:get(gfxb_frames, S) || {_, S} <- Results],
    AvgElapsed = avg(Elapsed),
    AvgBytes = avg(Bytes),
    AvgMsgs = avg(Msgs),
    AvgGfxb = avg(GfxbFrames),
    {Date, Time} = calendar:local_time(),
    UnixSecs = calendar:datetime_to_gregorian_seconds({Date, Time})
              - calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
    Record = io_lib:format("{~B, ~p, ~.1f, ~.1f, ~.1f, ~.1f}.~n",
                           [UnixSecs, GitSha, AvgElapsed, AvgBytes, AvgMsgs, AvgGfxb]),
    file:write_file(HistoryFile, Record, [append]).

show_history_comparison(HistoryFile, Results) ->
    Elapsed = [Ms || {Ms, _} <- Results],
    Bytes = [maps:get(bytes, S) || {_, S} <- Results],
    Msgs = [maps:get(msgs, S) || {_, S} <- Results],
    GfxbFrames = [maps:get(gfxb_frames, S) || {_, S} <- Results],
    AvgElapsed = avg(Elapsed),
    AvgBytes = avg(Bytes),
    AvgMsgs = avg(Msgs),
    AvgGfxb = avg(GfxbFrames),
    case load_history(HistoryFile) of
        [] ->
            io:format("History: no previous websocket benchmark results recorded~n");
        History ->
            {_Ts, PrevSha, PrevElapsed, PrevBytes, PrevMsgs, PrevGfxb} = lists:last(History),
            DElapsed = AvgElapsed - PrevElapsed,
            DBytes = AvgBytes - PrevBytes,
            DMsgs = AvgMsgs - PrevMsgs,
            DGfxb = AvgGfxb - PrevGfxb,
            io:format("Vs previous (~s): elapsed ~s~.1f ms  bytes ~s~.1f  msgs ~s~.1f  gfxb ~s~.1f~n",
                      [PrevSha,
                       sign(DElapsed), abs(DElapsed),
                       sign(DBytes), abs(DBytes),
                       sign(DMsgs), abs(DMsgs),
                       sign(DGfxb), abs(DGfxb)])
    end.

sign(N) when N >= 0 -> "+";
sign(_)             -> "-".

avg(List) ->
    lists:sum(List) / max(1, length(List)).

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
    sink_loop(#{msgs => 0, bytes => 0, gfx_frames => 0, gfxb_frames => 0, gfx_cmds => 0}).

sink_loop(Stats) ->
    receive
        stop ->
            ok;
        {snapshot, From} ->
            From ! {snapshot, Stats},
            sink_loop(Stats);
        {output, Text} ->
            Bin = iolist_to_binary(Text),
            sink_loop(update_stats(Bin, Stats));
        _Other ->
            sink_loop(Stats)
    end.

update_stats(Bin, Stats0) ->
    Stats1 = Stats0#{
        msgs => maps:get(msgs, Stats0) + 1,
        bytes => maps:get(bytes, Stats0) + byte_size(Bin)
    },
    case Bin of
        <<2, "GFX:", _/binary>> ->
            Stats1#{
                gfx_frames => maps:get(gfx_frames, Stats1) + 1,
                gfx_cmds => maps:get(gfx_cmds, Stats1) + 1
            };
        <<2, "GFXB:", Batch/binary>> ->
            CmdCount = count_batch_cmds(Batch),
            Stats1#{
                gfxb_frames => maps:get(gfxb_frames, Stats1) + 1,
                gfx_cmds => maps:get(gfx_cmds, Stats1) + CmdCount
            };
        _ ->
            Stats1
    end.

count_batch_cmds(Batch) when byte_size(Batch) =:= 0 ->
    0;
count_batch_cmds(Batch) ->
    1 + count_newlines(Batch).

count_newlines(Bin) ->
    count_newlines(Bin, 0).

count_newlines(<<>>, Acc) ->
    Acc;
count_newlines(<<$\n, Rest/binary>>, Acc) ->
    count_newlines(Rest, Acc + 1);
count_newlines(<<_, Rest/binary>>, Acc) ->
    count_newlines(Rest, Acc).

restore_env(Key, undefined) ->
    erlang:erase(Key);
restore_env(Key, Value) ->
    erlang:put(Key, Value).
