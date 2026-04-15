#!/usr/bin/env escript
%%! -pa ../_build/default/lib/erlbasic/ebin

main([BaseDir]) ->
    add_default_build_paths(),
    BasFiles = lists:sort(filelib:wildcard(filename:join(BaseDir, "*.bas"))),
    lists:foreach(fun run_case_file/1, BasFiles),
    run_optional_s3_smoke(),
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

add_default_build_paths() ->
    code:add_paths(filelib:wildcard("../_build/default/lib/*/ebin")).

run_optional_s3_smoke() ->
    case os:getenv("AWS_SMOKE_TESTS") of
        "1" ->
            io:format("RUN S3_SMOKE~n"),
            run_s3_smoke();
        _ ->
            ok
    end.

run_s3_smoke() ->
    ConfigPath = choose_s3_config_path(),
    OldBackend = application:get_env(erlbasic, storage_backend),
    OldConfigFile = application:get_env(erlbasic, storage_s3_config_file),
    OldS3Module = application:get_env(erlbasic, storage_s3_module),
    OldPpn = erlang:get(erlbasic_ppn),
    SmokeBase = "S3SMOKE_" ++ integer_to_list(erlang:unique_integer([positive])),
    ChannelFile = SmokeBase ++ ".DAT",
    ProgramFile = SmokeBase ++ ".BAS",
    try
        ok = application:set_env(erlbasic, storage_s3_config_file, ConfigPath),
        ok = erlbasic_s3_config:load(),
        ok = application:set_env(erlbasic, storage_backend, s3),
        application:unset_env(erlbasic, storage_s3_module),
        erlang:put(erlbasic_ppn, {88, 9}),

        %% Storage API roundtrip on real S3/MinIO/LocalStack.
        ok = erlbasic_storage:write_program(ProgramFile, <<"10 PRINT \"SMOKE\"\n">>),
        {ok, Bin} = erlbasic_storage:read_program(ProgramFile),
        true = binary:matches(Bin, <<"SMOKE">>) =/= [],

        %% OPEN/PRINT#/INPUT# roundtrip through S3 temp-file channel path.
        S0 = erlbasic_interp:new_state(),
        {S1, Out1} = erlbasic_interp:handle_input("OPEN \"" ++ ChannelFile ++ "\" FOR OUTPUT AS #1", S0),
        ok = assert_ok_output(Out1),
        {S2, Out2} = erlbasic_interp:handle_input("PRINT #1, \"HELLO S3 SMOKE\"", S1),
        ok = assert_ok_output(Out2),
        {S3, Out3} = erlbasic_interp:handle_input("CLOSE #1", S2),
        ok = assert_ok_output(Out3),

        {S4, Out4} = erlbasic_interp:handle_input("OPEN \"" ++ ChannelFile ++ "\" FOR INPUT AS #1", S3),
        ok = assert_ok_output(Out4),
        {S5, Out5} = erlbasic_interp:handle_input("INPUT #1, A$", S4),
        ok = assert_ok_output(Out5),
        {S6, Out6} = erlbasic_interp:handle_input("CLOSE #1", S5),
        ok = assert_ok_output(Out6),
        {_S7, PrintOut} = erlbasic_interp:handle_input("PRINT A$", S6),
        ok = assert_output_contains(PrintOut, "HELLO S3 SMOKE"),

        io:format("PASS S3_SMOKE~n")
    after
        _ = safe_delete_program(ChannelFile),
        _ = safe_delete_program(ProgramFile),
        restore_app_env(storage_backend, OldBackend),
        restore_app_env(storage_s3_config_file, OldConfigFile),
        restore_app_env(storage_s3_module, OldS3Module),
        restore_ppn(OldPpn)
    end.

choose_s3_config_path() ->
    EnvPath = os:getenv("ERLBASIC_S3_CONFIG_FILE"),
    case valid_config_path(EnvPath) of
        {ok, Path} ->
            Path;
        error ->
            case valid_config_path(".s3.config") of
                {ok, DotPath} ->
                    DotPath;
                error ->
                    case valid_config_path("s3.config") of
                        {ok, LocalPath} ->
                            LocalPath;
                        error ->
                            io:format("FAIL S3_SMOKE~n"),
                            io:format("Set AWS_SMOKE_TESTS=1 only when .s3.config or s3.config is available.\n"),
                            halt(1)
                    end
            end
    end.

valid_config_path(false) ->
    error;
valid_config_path(Path) when is_list(Path) ->
    case file:read_file_info(Path) of
        {ok, _} -> {ok, Path};
        _ -> error
    end;
valid_config_path(_Other) ->
    error.

assert_ok_output(Output) ->
    case lists:flatten(Output) of
        "OK\r\n" -> ok;
        Other ->
            io:format("FAIL S3_SMOKE unexpected output: ~s~n", [Other]),
            halt(1)
    end.

assert_output_contains(Output, Needle) ->
    Text = lists:flatten(Output),
    case re:run(Text, Needle, [{capture, none}]) of
        match -> ok;
        nomatch ->
            io:format("FAIL S3_SMOKE missing text: ~s~nOUTPUT:~n~s~n", [Needle, Text]),
            halt(1)
    end.

safe_delete_program(Name) ->
    case erlbasic_storage:delete_program(Name) of
        ok -> ok;
        {error, _} -> ok
    end.

restore_ppn(undefined) ->
    erlang:erase(erlbasic_ppn),
    ok;
restore_ppn(Ppn) ->
    erlang:put(erlbasic_ppn, Ppn),
    ok.

restore_app_env(Key, undefined) ->
    application:unset_env(erlbasic, Key),
    ok;
restore_app_env(Key, {ok, Value}) ->
    application:set_env(erlbasic, Key, Value),
    ok.