#!/usr/bin/env escript
%%! -pa ../../ebin

main([BaseDir]) ->
    BasFiles = lists:sort(filelib:wildcard(filename:join(BaseDir, "*.bas"))),
    lists:foreach(fun run_case_file/1, BasFiles),
    ok;
main(_) ->
    io:format("usage: smoke_runner.escript <dir>~n"),
    halt(1).

run_case_file(BasFile) ->
    Base = filename:rootname(BasFile),
    Name = filename:basename(Base),
    OutFile = Base ++ ".out",
    InputFile = Base ++ ".input",
    DirectModeFile = Base ++ ".direct",
    {ok, BasBin} = file:read_file(BasFile),
    ProgramLines = [string:trim(Line) || Line <- string:split(binary_to_list(BasBin), "\n", all), string:trim(Line) =/= ""],
    InputLines = read_optional_lines(InputFile),
    Mode = run_mode(DirectModeFile),
    {_FinalState, Output} =
        case Mode of
            direct ->
                run_case_direct(ProgramLines, InputLines);
            run ->
                run_case_run(ProgramLines, InputLines)
        end,
    {ok, ExpectedBin} = file:read_file(OutFile),
    Expected = normalize(binary_to_list(ExpectedBin)),
    Actual = normalize(lists:flatten(Output)),
    case Actual =:= Expected of
        true ->
            io:format("PASS ~s~n", [Name]);
        false ->
            io:format("FAIL ~s~nEXPECTED:\n~s\nACTUAL:\n~s\n", [Name, Expected, Actual]),
            halt(1)
    end.

read_optional_lines(Path) ->
    case file:read_file(Path) of
        {ok, Bin} ->
            [string:trim(Line) || Line <- string:split(binary_to_list(Bin), "\n", all), string:trim(Line) =/= ""];
        {error, enoent} ->
            []
    end.

run_mode(DirectModeFile) ->
    case file:read_file_info(DirectModeFile) of
        {ok, _} -> direct;
        {error, enoent} -> run
    end.

run_case_run(ProgramLines, Inputs) ->
    State0 = erlbasic_interp:new_state(),
    State1 = lists:foldl(
        fun(Line, AccState) ->
            {NextState, _} = erlbasic_interp:handle_input(Line, AccState),
            NextState
        end,
        State0,
        ProgramLines),
    {RunState, Output0} = erlbasic_interp:handle_input("RUN", State1),
    resume_inputs(RunState, Inputs, Output0).

run_case_direct(ProgramLines, Inputs) ->
    State0 = erlbasic_interp:new_state(),
    {State1, Output0} = lists:foldl(
        fun(Line, {AccState, OutAcc}) ->
            {NextState, NextOutput} = erlbasic_interp:handle_input(Line, AccState),
            {NextState, OutAcc ++ NextOutput}
        end,
        {State0, []},
        ProgramLines),
    resume_inputs(State1, Inputs, Output0).

resume_inputs(State, [], OutputAcc) ->
    {State, OutputAcc};
resume_inputs(State, [Input | Rest], OutputAcc) ->
    case erlbasic_interp:next_prompt(State) of
        "" ->
            {NextState, NextOutput} = erlbasic_interp:handle_input(Input, State),
            resume_inputs(NextState, Rest, OutputAcc ++ NextOutput);
        _ ->
            {State, OutputAcc}
    end.

normalize(Text) ->
    string:trim(string:replace(Text, "\r\n", "\n", all)).