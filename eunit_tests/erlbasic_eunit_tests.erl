-module(erlbasic_eunit_tests).

-include_lib("eunit/include/eunit.hrl").

validate_program_line_ok_test() ->
    ?assertEqual(ok, erlbasic_parser:validate_program_line("PRINT \"HELLO\"")),
    ?assertEqual(ok, erlbasic_parser:validate_program_line("LET X = 1 : PRINT X")).

validate_program_line_error_test() ->
    ?assertEqual(error, erlbasic_parser:validate_program_line("PRINT \"HELLO")).

builtin_chr_test() ->
    ?assertEqual({ok, "A"}, erlbasic_eval_builtins:apply_math_function("CHR$", [65])).

builtin_len_test() ->
    ?assertEqual({ok, 5}, erlbasic_eval_builtins:apply_math_function("LEN", ["HELLO"])).

immediate_print_test() ->
    State0 = erlbasic_interp:new_state(),
    {_State1, Output} = erlbasic_interp:handle_input("PRINT 1+1", State0),
    ?assertEqual("2\r\n", lists:flatten(Output)),
    PrevConnType = erlang:get(erlbasic_conn_type),
    erlang:put(erlbasic_conn_type, websocket),
    try
        State2 = erlbasic_interp:new_state(),
        {_State3, ClsOutput} = erlbasic_interp:handle_input("CLS", State2),
        ?assertEqual("\e[0m\e[2J\e[H", lists:flatten(ClsOutput))
    after
        case PrevConnType of
            undefined -> erlang:erase(erlbasic_conn_type);
            _ -> erlang:put(erlbasic_conn_type, PrevConnType)
        end
    end.

run_program_output_test() ->
    State0 = erlbasic_interp:new_state(),
    {State1, _} = erlbasic_interp:handle_input("10 LET X = 41", State0),
    {State2, _} = erlbasic_interp:handle_input("20 PRINT X + 1", State1),
    {State3, _} = erlbasic_interp:handle_input("30 END", State2),
    {_State4, Output} = erlbasic_interp:handle_input("RUN", State3),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "42", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "Program ended", [{capture, none}])).
