-module(erlbasic_eunit_tests).

-include_lib("eunit/include/eunit.hrl").
-include("erlbasic_state.hrl").

validate_program_line_ok_test() ->
    ?assertEqual(ok, erlbasic_parser:validate_program_line("PRINT \"HELLO\"")), 
    ?assertEqual(ok, erlbasic_parser:validate_program_line("LET X = 1 : PRINT X")).

validate_program_line_error_test() ->
    ?assertEqual(error, erlbasic_parser:validate_program_line("PRINT \"HELLO")).

reserved_word_variable_name_test() ->
    ?assertEqual({error, reserved_word}, erlbasic_parser:validate_program_line("LET IF = 1")),
    State0 = erlbasic_interp:new_state(),
    {_State1, Output} = erlbasic_interp:handle_input("LET FOR = 1", State0),
    ?assertEqual("?RESERVED WORD ERROR\r\n", lists:flatten(Output)).

rem_comment_with_equals_regression_test() ->
    ?assertEqual({remark}, erlbasic_parser:parse_statement("REM =======")),
    ?assertEqual(ok, erlbasic_parser:validate_program_line("REM =======")),
    State0 = erlbasic_interp:new_state(),
    {_State1, Output} = erlbasic_interp:handle_input("REM =======", State0),
    ?assertEqual([], Output).

keyword_category_intent_test() ->
    ?assert(erlbasic_keywords:is_expr_keyword("AND")),
    ?assert(erlbasic_keywords:is_expr_keyword("LEFT$")),
    ?assert(erlbasic_keywords:is_expr_keyword("TIMER")),
    ?assert(erlbasic_keywords:is_expr_keyword("MEM_USED")),
    ?assert(erlbasic_keywords:is_expr_keyword("STRING$")),
    ?assertNot(erlbasic_keywords:is_expr_keyword("PRINT")),
    ?assert(erlbasic_keywords:is_list_keyword("PRINT")),
    ?assert(erlbasic_keywords:is_list_keyword("INPUT")),
    ?assert(erlbasic_keywords:is_list_keyword("TRON")),
    ?assert(erlbasic_keywords:is_list_keyword("TROFF")),
    ?assertNot(erlbasic_keywords:is_list_keyword("LEFT$")),
    ?assert(erlbasic_keywords:is_builtin_function_keyword("TIMER")),
    ?assert(erlbasic_keywords:is_builtin_function_keyword("MEM_USED")),
    ?assert(erlbasic_keywords:is_builtin_function_keyword("STRING$")).

keyword_consistency_union_reserved_test() ->
    ExprWords = erlbasic_keywords:expr_keywords(),
    ListWords = erlbasic_keywords:list_keywords(),
    ReservedOnlyWords = erlbasic_keywords:reserved_only_keywords(),
    lists:foreach(fun(Word) ->
        ?assert(erlbasic_keywords:is_reserved_variable_name(Word))
    end, ExprWords ++ ListWords ++ ReservedOnlyWords).

all_keywords_reserved_variable_names_test() ->
    ReservedNames = [
        "AND", "MOD", "PRINT", "INPUT", "TIMER",
        "ON", "ERROR", "RESUME", "HGR", "PSET", "SOUND", "STRING$", "TRON", "TROFF"
    ],
    lists:foreach(fun(Name) ->
        ?assertEqual({error, reserved_word},
            erlbasic_parser:validate_program_line("LET " ++ Name ++ " = 1"))
    end, ReservedNames),
    ?assertEqual({error, reserved_word},
        erlbasic_parser:validate_program_line("LET PRINT$ = \"X\"")),
    ?assertEqual(ok, erlbasic_parser:validate_program_line("LET HELLO = 1")).

builtin_chr_test() ->
    ?assertEqual({ok, "A"}, erlbasic_eval_builtins:apply_math_function("CHR$", [65])).

builtin_len_test() ->
    ?assertEqual({ok, 5}, erlbasic_eval_builtins:apply_math_function("LEN", ["HELLO"])).

builtin_instr_space_pos_test() ->
    ?assertEqual({ok, 2}, erlbasic_eval_builtins:apply_math_function("INSTR", ["ABCDE", "BC"])),
    ?assertEqual({ok, 4}, erlbasic_eval_builtins:apply_math_function("INSTR", [3, "ABCDE", "DE"])),
    ?assertEqual({ok, 0}, erlbasic_eval_builtins:apply_math_function("INSTR", ["ABCDE", "ZZ"])),
    ?assertEqual({ok, "   "}, erlbasic_eval_builtins:apply_math_function("SPACE$", [3])),
    PrevCol = erlang:get(erlbasic_print_col),
    erlang:put(erlbasic_print_col, 5),
    try
        ?assertEqual({ok, 6}, erlbasic_eval_builtins:apply_math_function("POS", [0]))
    after
        case PrevCol of
            undefined -> erlang:erase(erlbasic_print_col);
            _ -> erlang:put(erlbasic_print_col, PrevCol)
        end
    end.

mem_used_builtin_test() ->
    PrevVars = erlang:get(erlbasic_mem_vars),
    PrevFuncs = erlang:get(erlbasic_mem_funcs),
    PrevProg = erlang:get(erlbasic_mem_prog),
    PrevData = erlang:get(erlbasic_mem_data_items),
    PrevLoop = erlang:get(erlbasic_mem_loopstack),
    PrevCall = erlang:get(erlbasic_mem_callstack),
    erlang:put(erlbasic_mem_vars, #{"A" => 1}),
    erlang:put(erlbasic_mem_funcs, #{}),
    erlang:put(erlbasic_mem_prog, [{10, "PRINT MEM_USED()"}]),
    erlang:put(erlbasic_mem_data_items, [1, 2, 3]),
    erlang:put(erlbasic_mem_loopstack, [10]),
    erlang:put(erlbasic_mem_callstack, [20, 30]),
    try
        Expected = erlang:external_size(#{"A" => 1})
            + erlang:external_size(#{})
            + erlang:external_size([{10, "PRINT MEM_USED()"}])
            + erlang:external_size([1, 2, 3])
            + erlang:external_size([10])
            + erlang:external_size([20, 30]),
        ?assertEqual({ok, Expected}, erlbasic_eval_builtins:apply_math_function("MEM_USED", []))
    after
        case PrevVars of undefined -> erlang:erase(erlbasic_mem_vars); _ -> erlang:put(erlbasic_mem_vars, PrevVars) end,
        case PrevFuncs of undefined -> erlang:erase(erlbasic_mem_funcs); _ -> erlang:put(erlbasic_mem_funcs, PrevFuncs) end,
        case PrevProg of undefined -> erlang:erase(erlbasic_mem_prog); _ -> erlang:put(erlbasic_mem_prog, PrevProg) end,
        case PrevData of undefined -> erlang:erase(erlbasic_mem_data_items); _ -> erlang:put(erlbasic_mem_data_items, PrevData) end,
        case PrevLoop of undefined -> erlang:erase(erlbasic_mem_loopstack); _ -> erlang:put(erlbasic_mem_loopstack, PrevLoop) end,
        case PrevCall of undefined -> erlang:erase(erlbasic_mem_callstack); _ -> erlang:put(erlbasic_mem_callstack, PrevCall) end
    end.

hex_literal_eval_test() ->
    ?assertEqual({ok, 16, #{}}, erlbasic_eval:eval_expr_result("0x10", #{})),
    ?assertEqual({ok, 31, #{}}, erlbasic_eval:eval_expr_result("0x10+0x0F", #{})).

hex_literal_64bit_promotion_test() ->
    ?assertEqual({ok, 16#8000000000000000, #{}},
        erlbasic_eval:eval_expr_result("0x8000000000000000", #{})),
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("BIG%=0xFFFFFFFFFFFFFFFF", S0),
    {_S2, Output} = erlbasic_interp:handle_input("PRINT BIG%", S1),
    ?assertEqual(match, re:run(lists:flatten(Output), "18446744073709551615", [{capture, none}])).

expr_lexer_operator_token_contract_test() ->
    ?assertEqual(
        {ok, [{num, 1}, plus, {num, 2}, minus, {num, 3}, mul, {num, 4}, divi, {num, 5}, intdiv, {num, 6}, pow, {num, 2}, comma, lparen, {num, 8}, rparen]},
        erlbasic_eval_lexer:tokenize_expr("1+2-3*4/5\\6^2,(8)")).

expr_lexer_identifier_keyword_contract_test() ->
    ?assertEqual(
        {ok, [{kw, "LEFT$"}, lparen, {var, "A$"}, comma, {num, 1}, rparen, plus, {kw, "MEM_USED"}, lparen, rparen, plus, {var, "X%"}, plus, {var, "Y&"}, plus, {var, "Z#"}]},
        erlbasic_eval_lexer:tokenize_expr("LEFT$(A$,1)+MEM_USED()+X%+Y&+Z#")).

expr_lexer_number_contract_test() ->
    ?assertEqual(
        {ok, [{num, 16}, plus, {num, 0.6}, plus, {num, 1.25}, plus, {num, 12}]},
        erlbasic_eval_lexer:tokenize_expr("0x10 + .6 + 1.25 + 12")).

expr_lexer_scientific_number_contract_test() ->
    ?assertEqual(
        {ok, [{num, 2.0e30}, plus, {num, 2.0e30}, plus, {num, 2.0e30}, plus, {num, 0.02}, plus, {num, 5.0}]},
        erlbasic_eval_lexer:tokenize_expr("2e30 + 2E+30 + 2e+30 + 2e-2 + .5e1")).

expr_lexer_string_contract_test() ->
    ?assertEqual(
        {ok, [{str, "HELLO"}, plus, {str, " WORLD"}]},
        erlbasic_eval_lexer:tokenize_expr("\"HELLO\"+\" WORLD\" ")).

expr_lexer_error_contract_test() ->
    ?assertEqual(error, erlbasic_eval_lexer:tokenize_expr("\"unterminated")),
    ?assertEqual(error, erlbasic_eval_lexer:tokenize_expr(".")),
    ?assertEqual(error, erlbasic_eval_lexer:tokenize_expr("0x")),
    ?assertEqual(error, erlbasic_eval_lexer:tokenize_expr("@")),
    ?assertEqual(error, erlbasic_eval_lexer:tokenize_expr("1 + @")).

expr_eval_precedence_regression_test() ->
    ?assertEqual({ok, 14, #{}}, erlbasic_eval:eval_expr_result("2+3*4", #{})),
    ?assertEqual({ok, 20, #{}}, erlbasic_eval:eval_expr_result("(2+3)*4", #{})),
    ?assertEqual({ok, 512, #{}}, erlbasic_eval:eval_expr_result("2^3^2", #{})),
    ?assertEqual({ok, 3, #{}}, erlbasic_eval:eval_expr_result("7\\2", #{})),
    ?assertEqual({ok, 3, #{}}, erlbasic_eval:eval_expr_result("7 MOD 4", #{})).

expr_eval_scientific_regression_test() ->
    ?assertEqual({ok, 2.0e30, #{}}, erlbasic_eval:eval_expr_result("2e+30", #{})),
    ?assertEqual(ok, erlbasic_parser:validate_program_line("LET A=2E+30")).

undefined_fn_immediate_error_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("PRINT FNMISSING(1)", S0),
    ?assertEqual(match, re:run(lists:flatten(Output), "UNDEFINED FUNCTION", [{capture, none}])).

undefined_fn_program_error_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 PRINT FNMISSING(1)", S0),
    {S2, _} = erlbasic_interp:handle_input("20 END", S1),
    {_S3, Output} = erlbasic_interp:handle_input("RUN", S2),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "UNDEFINED FUNCTION", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "IN 10", [{capture, none}])).

file_io_parser_and_builtins_test() ->
    ?assertEqual(
        {file_open, "\"tmp.dat\"", "RANDOM", "1", "32"},
        erlbasic_parser:parse_statement("OPEN \"tmp.dat\" FOR RANDOM AS #1 LEN = 32")),
    ?assertEqual(
        {file_print, "1", [{"A$", comma}, {"B$", semicolon}], false},
        erlbasic_parser:parse_statement("PRINT #1, A$, B$;")),
    ?assertEqual(
        {file_write, "1", ["A", "B$", "C"]},
        erlbasic_parser:parse_statement("WRITE #1, A, B$, C")),
    ?assertEqual(
        {file_input, "1", [{var_target, "A"}, {var_target, "B$"}]},
        erlbasic_parser:parse_statement("INPUT #1, A, B$")),
    ?assertEqual(
        {file_line_input, "1", {var_target, "L$"}},
        erlbasic_parser:parse_statement("LINE INPUT #1, L$")),
    ?assertEqual(
        {file_field, "1", [{"5", "N$"}, {"7", "V$"}]},
        erlbasic_parser:parse_statement("FIELD #1, 5 AS N$, 7 AS V$")),
    ?assertEqual(
        {file_put_record, "1", "2"},
        erlbasic_parser:parse_statement("PUT #1, 2")),
    ?assertEqual(
        {file_get_record, "1", "2"},
        erlbasic_parser:parse_statement("GET #1, 2")),
    ?assertEqual({error, illegal_function_call}, erlbasic_eval_builtins:apply_math_function("EOF", [1])),
    ?assertEqual({error, illegal_function_call}, erlbasic_eval_builtins:apply_math_function("LOF", [1])),
    ?assertEqual({error, illegal_function_call}, erlbasic_eval_builtins:apply_math_function("SEEK", [1])).

immediate_print_test() ->
    State0 = erlbasic_interp:new_state(),
    {_State1, Output} = erlbasic_interp:handle_input("PRINT 1+1", State0),      
    ?assertEqual("2\r\n", lists:flatten(Output)),
    StateA = erlbasic_interp:new_state(),
    {_StateB, DotOutput} = erlbasic_interp:handle_input("PRINT .6", StateA),    
    ?assertEqual("0.6\r\n", lists:flatten(DotOutput)),
    StateSci0 = erlbasic_interp:new_state(),
    {StateSci1, SciAssignOutput} = erlbasic_interp:handle_input("A=2E+30", StateSci0),
    ?assertEqual([], SciAssignOutput),
    {_StateSci2, SciPrintOutput} = erlbasic_interp:handle_input("PRINT A", StateSci1),
    ?assertEqual(match, re:run(lists:flatten(SciPrintOutput), "(2(\\.0+)?[eE]\\+?30)|(2000000000000000000000000000000)", [{capture, none}])),
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

sound_parse_and_validate_test() ->
    ?assertEqual({sound, "0", "120", "10", "8"},
        erlbasic_parser:parse_statement("SOUND 0,120,10,8")),
    ?assertEqual(ok, erlbasic_parser:validate_program_line("SOUND 0,120,10,8")).

sprite_parse_and_validate_test() ->
    ?assertEqual({on_sprite_gosub, "200"},
        erlbasic_parser:parse_statement("ON SPRITE GOSUB 200")),
    ?assertEqual({sprite_clear},
        erlbasic_parser:parse_statement("SPRITE CLEAR")),
    ?assertEqual({sprite_move, "1", "10", "20"},
        erlbasic_parser:parse_statement("SPRITE 1,(10,20)")),
    ?assertEqual({sprite_show, "1"},
        erlbasic_parser:parse_statement("SPRITE SHOW 1")),
    ?assertEqual({sprite_hide, "1"},
        erlbasic_parser:parse_statement("SPRITE HIDE 1")),
    ?assertEqual({sprite_scale, "1", "3"},
        erlbasic_parser:parse_statement("SPRITE SCALE 1,3")),
    ?assertEqual(ok,
        erlbasic_parser:validate_program_line("DIM S&(31):SPRITE LOAD 1,4,4,S&(0):ON SPRITE GOSUB 200")).

sprite_collision_on_gosub_test() ->
    PrevConnType = erlang:get(erlbasic_conn_type),
    erlang:put(erlbasic_conn_type, websocket),
    try
        S0 = erlbasic_interp:new_state(),
        {S1, _} = erlbasic_interp:handle_input("10 HGR", S0),
        {S2, _} = erlbasic_interp:handle_input("20 DIM S&(31)", S1),
        {S3, _} = erlbasic_interp:handle_input("30 FOR I=0 TO 15:S&(I)=12:NEXT I", S2),
        {S4, _} = erlbasic_interp:handle_input("40 FOR I=16 TO 31:S&(I)=10:NEXT I", S3),
        {S5, _} = erlbasic_interp:handle_input("50 SPRITE LOAD 1,4,4,S&(0)", S4),
        {S6, _} = erlbasic_interp:handle_input("60 SPRITE LOAD 2,4,4,S&(16)", S5),
        {S7, _} = erlbasic_interp:handle_input("70 SPRITE 1,(10,10)", S6),
        {S8, _} = erlbasic_interp:handle_input("80 SPRITE 2,(40,10)", S7),
        {S9, _} = erlbasic_interp:handle_input("90 ON SPRITE GOSUB 200", S8),
        {S10, _} = erlbasic_interp:handle_input("100 SPRITE 2,(12,10)", S9),
        {S11, _} = erlbasic_interp:handle_input("110 PRINT \"AFTER\"", S10),
        {S12, _} = erlbasic_interp:handle_input("120 END", S11),
        {S13, _} = erlbasic_interp:handle_input("200 PRINT \"HIT\";SPRCOL1%;\"-\";SPRCOL2%", S12),
        {S14, _} = erlbasic_interp:handle_input("210 RETURN", S13),
        {_S15, Output} = erlbasic_interp:handle_input("RUN", S14),
        Text = lists:flatten(Output),
        ?assertEqual(match, re:run(Text, "HIT1-2", [{capture, none}])),
        ?assertEqual(match, re:run(Text, "AFTER", [{capture, none}]))
    after
        case PrevConnType of
            undefined -> erlang:erase(erlbasic_conn_type);
            _ -> erlang:put(erlbasic_conn_type, PrevConnType)
        end
    end.

buffer_parse_and_validate_test() ->
    ?assertEqual({buffer_mode, on}, erlbasic_parser:parse_statement("BUFFER ON")),
    ?assertEqual({buffer_mode, off}, erlbasic_parser:parse_statement("BUFFER OFF")),
    ?assertEqual(ok, erlbasic_parser:validate_program_line("BUFFER ON")),
    ?assertEqual(ok, erlbasic_parser:validate_program_line("BUFFER OFF")).

sound_immediate_requires_websocket_test() ->
    PrevConnType = erlang:get(erlbasic_conn_type),
    erlang:put(erlbasic_conn_type, tcp),
    try
        State0 = erlbasic_interp:new_state(),
        {_State1, Output} = erlbasic_interp:handle_input("SOUND 0,120,10,8", State0),
        ?assertEqual("?SOUND NOT SUPPORTED ON TTY\r\n", lists:flatten(Output))
    after
        case PrevConnType of
            undefined -> erlang:erase(erlbasic_conn_type);
            _ -> erlang:put(erlbasic_conn_type, PrevConnType)
        end
    end.

sound_immediate_websocket_emits_control_frame_test() ->
    PrevConnType = erlang:get(erlbasic_conn_type),
    erlang:put(erlbasic_conn_type, websocket),
    try
        State0 = erlbasic_interp:new_state(),
        {_State1, Output} = erlbasic_interp:handle_input("SOUND 1,90,10,12", State0),
        ?assertEqual("\x02SND:1:90:10:12", lists:flatten(Output))
    after
        case PrevConnType of
            undefined -> erlang:erase(erlbasic_conn_type);
            _ -> erlang:put(erlbasic_conn_type, PrevConnType)
        end
    end.

sound_run_end_stops_audio_test() ->
    PrevConnType = erlang:get(erlbasic_conn_type),
    erlang:put(erlbasic_conn_type, websocket),
    try
        S0 = erlbasic_interp:new_state(),
        {S1, _} = erlbasic_interp:handle_input("10 SOUND 1,90,10,12", S0),
        {S2, _} = erlbasic_interp:handle_input("20 END", S1),
        {_S3, Output} = erlbasic_interp:handle_input("RUN", S2),
        Text = lists:flatten(Output),
        ?assertEqual(match, re:run(Text, "\x02SND:STOPALL", [{capture, none}])),
        ?assertEqual(match, re:run(Text, "Program ended", [{capture, none}]))
    after
        case PrevConnType of
            undefined -> erlang:erase(erlbasic_conn_type);
            _ -> erlang:put(erlbasic_conn_type, PrevConnType)
        end
    end.

sound_run_error_stops_audio_test() ->
    PrevConnType = erlang:get(erlbasic_conn_type),
    erlang:put(erlbasic_conn_type, websocket),
    try
        S0 = erlbasic_interp:new_state(),
        {S1, _} = erlbasic_interp:handle_input("10 SOUND 1,90,10,12", S0),
        {S2, _} = erlbasic_interp:handle_input("20 DIM A(1)", S1),
        {S3, _} = erlbasic_interp:handle_input("30 PRINT A(2)", S2),
        {_S4, Output} = erlbasic_interp:handle_input("RUN", S3),
        Text = lists:flatten(Output),
        ?assertEqual(match, re:run(Text, "\x02SND:STOPALL", [{capture, none}])),
        ?assertEqual(match, re:run(Text, "SUBSCRIPT OUT OF RANGE", [{capture, none}]))
    after
        case PrevConnType of
            undefined -> erlang:erase(erlbasic_conn_type);
            _ -> erlang:put(erlbasic_conn_type, PrevConnType)
        end
    end.

sound_run_requires_websocket_with_line_number_test() ->
    PrevConnType = erlang:get(erlbasic_conn_type),
    erlang:put(erlbasic_conn_type, tcp),
    try
        State0 = erlbasic_interp:new_state(),
        {State1, _} = erlbasic_interp:handle_input("10 SOUND 0,120,10,8", State0),
        {State2, _} = erlbasic_interp:handle_input("20 END", State1),
        {_State3, Output} = erlbasic_interp:handle_input("RUN", State2),
        ?assertEqual("?SOUND NOT SUPPORTED ON TTY IN 10\r\n", lists:flatten(Output))
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

assignment_type_mismatch_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Out1} = erlbasic_interp:handle_input("A$=20", S0),
    ?assertEqual("?TYPE MISMATCH ERROR\r\n", lists:flatten(Out1)),

    S2 = erlbasic_interp:new_state(),
    {_S3, Out2} = erlbasic_interp:handle_input("A=\"FOO\"", S2),
    ?assertEqual("?TYPE MISMATCH ERROR\r\n", lists:flatten(Out2)),

    S4 = erlbasic_interp:new_state(),
    {S5, _} = erlbasic_interp:handle_input("10 A$=20", S4),
    {S6, _} = erlbasic_interp:handle_input("20 END", S5),
    {_S7, Out3} = erlbasic_interp:handle_input("RUN", S6),
    ?assertEqual("?TYPE MISMATCH ERROR IN 10\r\n", lists:flatten(Out3)).

float_variable_suffix_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Out0} = erlbasic_interp:handle_input("PRINT A#", S0),
    ?assertEqual("0.0\r\n", lists:flatten(Out0)),

    {S2, _} = erlbasic_interp:handle_input("A#=1", S0),
    {_S3, Out1} = erlbasic_interp:handle_input("PRINT A#", S2),
    ?assertEqual("1.0\r\n", lists:flatten(Out1)),

    {S4, _} = erlbasic_interp:handle_input("A#=A#+0.5", S2),
    {_S5, Out2} = erlbasic_interp:handle_input("PRINT A#", S4),
    ?assertEqual("1.5\r\n", lists:flatten(Out2)),

    {_S6, Out3} = erlbasic_interp:handle_input("A#=\"X\"", S4),
    ?assertEqual("?TYPE MISMATCH ERROR\r\n", lists:flatten(Out3)).

stop_and_cont_resume_test() ->
    State0 = erlbasic_interp:new_state(),
    {State1, _} = erlbasic_interp:handle_input("10 LET X = 1", State0),
    {State2, _} = erlbasic_interp:handle_input("20 STOP", State1),
    {State3, _} = erlbasic_interp:handle_input("30 LET X = X + 1", State2),
    {State4, _} = erlbasic_interp:handle_input("40 PRINT X", State3),
    {State5, _} = erlbasic_interp:handle_input("50 END", State4),
    {State6, BreakOutput} = erlbasic_interp:handle_input("RUN", State5),
    ?assertEqual("BREAK IN 20\r\n", lists:flatten(BreakOutput)),
    {_State7, ContOutput} = erlbasic_interp:handle_input("CONT", State6),
    ?assertEqual("2\r\nProgram ended\r\n", lists:flatten(ContOutput)).

websocket_implicit_boundary_flush_test() ->
    PrevOutputPid = erlang:get(output_pid),
    PrevOutputSocket = erlang:get(output_socket),
    PrevConnType = erlang:get(erlbasic_conn_type),
    _ = collect_output_messages(),
    erlang:erase(output_socket),
    erlang:put(output_pid, self()),
    erlang:put(erlbasic_conn_type, websocket),
    try
        S0 = erlbasic_interp:new_state(),
        {S1, _} = erlbasic_interp:handle_input("10 FOR I = 1 TO 3", S0),
        {S2, _} = erlbasic_interp:handle_input("20 PRINT \"X\";", S1),
        {S3, _} = erlbasic_interp:handle_input("30 NEXT I", S2),
        {S4, _} = erlbasic_interp:handle_input("40 END", S3),
        {_S5, RunOutput} = erlbasic_interp:handle_input("RUN", S4),
        ?assertEqual("Program ended\r\n", lists:flatten(RunOutput)),
        Chunks = [binary_to_list(iolist_to_binary(B)) || B <- collect_output_messages()],
        XChunks = [Chunk || Chunk <- Chunks, Chunk =:= "X"],
        ?assertEqual(3, length(XChunks))
    after
        case PrevOutputPid of
            undefined -> erlang:erase(output_pid);
            _ -> erlang:put(output_pid, PrevOutputPid)
        end,
        case PrevOutputSocket of
            undefined -> erlang:erase(output_socket);
            _ -> erlang:put(output_socket, PrevOutputSocket)
        end,
        case PrevConnType of
            undefined -> erlang:erase(erlbasic_conn_type);
            _ -> erlang:put(erlbasic_conn_type, PrevConnType)
        end,
        _ = collect_output_messages(),
        ok
    end.

compressed_websocket_input_roundtrip_test() ->
    Dir = accounts_setup(),
    WatchdogState = ensure_mem_watchdog_started(),
    ListenerRef = erlbasic_ws_compression_test,
    try
        start_compressed_test_listener(ListenerRef),
        Port = ranch:get_port(ListenerRef),
        {Socket, Extensions, Buffer0} = ws_connect_with_compression(Port),
        try
            {ok, _Banner, Buffer1} = ws_collect_visible_text_until(
            Socket, Extensions, Buffer0, fun(Text) -> binary:matches(Text, <<"#">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"hello 1,1\n">>),
            {ok, _LoginPrompt, Buffer2} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer1,
                fun(Text) -> binary:matches(Text, <<"Password: ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"system\n">>),
            {ok, _ReadyPrompt, Buffer3} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer2,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"10 PRINT \"hello\"\n">>),
            {ok, _Prompt4, Buffer4} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer3,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"20 INPUT A\n">>),
            {ok, _Prompt5, Buffer5} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer4,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"30 PRINT A\n">>),
            {ok, _Prompt6, Buffer6} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer5,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"RUN\n">>),
            {ok, RunText, Buffer7} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer6,
                fun(Text) -> binary:matches(Text, <<"? ">>) =/= [] end),
            ?assertEqual(match, re:run(binary_to_list(RunText), "hello", [{capture, none}])),

            ok = ws_send_text(Socket, Extensions, <<"1\n">>),
            {ok, FinalText, _Buffer8} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer7,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),
            FinalTextList = binary_to_list(FinalText),
            ?assertEqual(match, re:run(FinalTextList, "1", [{capture, none}])),
            ?assertEqual(nomatch, re:run(FinalTextList, "SYSTEM ERROR|Connection closed", [{capture, none}]))
        after
            cleanup_ws_extensions(Extensions),
            gen_tcp:close(Socket)
        end
    after
        catch cowboy:stop_listener(ListenerRef),
        cleanup_mem_watchdog(WatchdogState),
        accounts_teardown(Dir)
    end.

compressed_websocket_quit_no_false_crash_test() ->
    Dir = accounts_setup(),
    WatchdogState = ensure_mem_watchdog_started(),
    ListenerRef = erlbasic_ws_quit_test,
    try
        start_compressed_test_listener(ListenerRef),
        Port = ranch:get_port(ListenerRef),
        {Socket, Extensions, Buffer0} = ws_connect_with_compression(Port),
        try
            {ok, _Banner, Buffer1} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer0,
                fun(Text) -> binary:matches(Text, <<"#">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"hello 1,1\n">>),
            {ok, _LoginPrompt, Buffer2} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer1,
                fun(Text) -> binary:matches(Text, <<"Password: ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"system\n">>),
            {ok, _ReadyPrompt, Buffer3} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer2,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"10 A% = 1\n">>),
            {ok, _Prompt4, Buffer4} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer3,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"20 FOR X = 1 TO 1000\n">>),
            {ok, _Prompt5, Buffer5} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer4,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"30 A% = A% + A%\n">>),
            {ok, _Prompt6, Buffer6} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer5,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"40 PRINT A%\n">>),
            {ok, _Prompt7, Buffer7} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer6,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"50 NEXT\n">>),
            {ok, _Prompt8, Buffer8} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer7,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"RUN\n">>),
            {ok, _RunText, Buffer9} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer8,
                fun(Text) -> byte_size(Text) > 0 end),

            ok = ws_send_text(Socket, Extensions, <<3>>),
            {ok, _BreakText, Buffer10} = ws_collect_visible_text_until(
                Socket, Extensions, Buffer9,
                fun(Text) -> binary:matches(Text, <<"> ">>) =/= [] end),

            ok = ws_send_text(Socket, Extensions, <<"quit\n">>),
            {QuitText, Closed, _Buffer11} = ws_collect_text_until_close(Socket, Extensions, Buffer10, 4096),
            QuitTextList = binary_to_list(QuitText),
            ?assertEqual(true, Closed),
            ?assertEqual(nomatch, re:run(QuitTextList, "Interpreter crashed - normal", [{capture, none}]))
        after
            cleanup_ws_extensions(Extensions),
            catch gen_tcp:close(Socket)
        end
    after
        catch cowboy:stop_listener(ListenerRef),
        cleanup_mem_watchdog(WatchdogState),
        accounts_teardown(Dir)
    end.

list_command_test() ->
    State0 = erlbasic_interp:new_state(),
    {State1, _} = erlbasic_interp:handle_input("10 PRINT \"A\"", State0),       
    {State2, _} = erlbasic_interp:handle_input("20 PRINT \"B\"", State1),       
    {State3, _} = erlbasic_interp:handle_input("30 PRINT \"C\"", State2),       
    {State4, _} = erlbasic_interp:handle_input("40 PRINT \"D\"", State3),       

    %% Test LIST (all lines)
    {State5, Output1} = erlbasic_interp:handle_input("LIST", State4),
    Text1 = lists:flatten(Output1),
    ?assertEqual(match, re:run(Text1, "10 PRINT", [{capture, none}])),
    ?assertEqual(match, re:run(Text1, "40 PRINT", [{capture, none}])),

    %% Test LIST 20 (single line)
    {State6, Output2} = erlbasic_interp:handle_input("LIST 20", State5),        
    Text2 = lists:flatten(Output2),
    ?assertEqual(match, re:run(Text2, "20 PRINT", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text2, "10 PRINT", [{capture, none}])),        

    %% Test LIST 20-30 (range)
    {State7, Output3} = erlbasic_interp:handle_input("LIST 20-30", State6),     
    Text3 = lists:flatten(Output3),
    ?assertEqual(match, re:run(Text3, "20 PRINT", [{capture, none}])),
    ?assertEqual(match, re:run(Text3, "30 PRINT", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text3, "40 PRINT", [{capture, none}])),        

    %% Test LIST -25 (from start to line)
    {State8, Output4} = erlbasic_interp:handle_input("LIST -25", State7),       
    Text4 = lists:flatten(Output4),
    ?assertEqual(match, re:run(Text4, "10 PRINT", [{capture, none}])),
    ?assertEqual(match, re:run(Text4, "20 PRINT", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text4, "30 PRINT", [{capture, none}])),        

    %% Test LIST 25- (from line to end)
    {_State9, Output5} = erlbasic_interp:handle_input("LIST 25-", State8),      
    Text5 = lists:flatten(Output5),
    ?assertEqual(nomatch, re:run(Text5, "10 PRINT", [{capture, none}])),        
    ?assertEqual(match, re:run(Text5, "30 PRINT", [{capture, none}])),
    ?assertEqual(match, re:run(Text5, "40 PRINT", [{capture, none}])).

delete_command_test() ->
    State0 = erlbasic_interp:new_state(),
    {State1, _} = erlbasic_interp:handle_input("10 PRINT \"A\"", State0),       
    {State2, _} = erlbasic_interp:handle_input("20 PRINT \"B\"", State1),       
    {State3, _} = erlbasic_interp:handle_input("30 PRINT \"C\"", State2),       
    {State4, _} = erlbasic_interp:handle_input("40 PRINT \"D\"", State3),       
    {State5, _} = erlbasic_interp:handle_input("50 PRINT \"E\"", State4),       

    %% Test DELETE 30 (single line)
    {State6, _} = erlbasic_interp:handle_input("DELETE 30", State5),
    {State7, Out1} = erlbasic_interp:handle_input("LIST", State6),
    Text1 = lists:flatten(Out1),
    ?assertEqual(match, re:run(Text1, "10 PRINT", [{capture, none}])),
    ?assertEqual(match, re:run(Text1, "20 PRINT", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text1, "30 PRINT", [{capture, none}])),        
    ?assertEqual(match, re:run(Text1, "40 PRINT", [{capture, none}])),

    %% Test DELETE 10-20 (range)
    {State8, _} = erlbasic_interp:handle_input("DELETE 10-20", State7),
    {State9, Out2} = erlbasic_interp:handle_input("LIST", State8),
    Text2 = lists:flatten(Out2),
    ?assertEqual(nomatch, re:run(Text2, "10 PRINT", [{capture, none}])),        
    ?assertEqual(nomatch, re:run(Text2, "20 PRINT", [{capture, none}])),        
    ?assertEqual(match, re:run(Text2, "40 PRINT", [{capture, none}])),
    ?assertEqual(match, re:run(Text2, "50 PRINT", [{capture, none}])),

    %% Add more lines for testing other variations
    {State10, _} = erlbasic_interp:handle_input("10 PRINT \"X\"", State9),      
    {State11, _} = erlbasic_interp:handle_input("20 PRINT \"Y\"", State10),     
    {State12, _} = erlbasic_interp:handle_input("30 PRINT \"Z\"", State11),     

    %% Test DELETE -25 (from start to line)
    {State13, _} = erlbasic_interp:handle_input("DELETE -25", State12),
    {State14, Out3} = erlbasic_interp:handle_input("LIST", State13),
    Text3 = lists:flatten(Out3),
    ?assertEqual(nomatch, re:run(Text3, "10 PRINT", [{capture, none}])),        
    ?assertEqual(nomatch, re:run(Text3, "20 PRINT", [{capture, none}])),        
    ?assertEqual(match, re:run(Text3, "30 PRINT", [{capture, none}])),

    %% Test DELETE 35- (from line to end)
    {State15, _} = erlbasic_interp:handle_input("DELETE 35-", State14),
    {_State16, Out4} = erlbasic_interp:handle_input("LIST", State15),
    Text4 = lists:flatten(Out4),
    ?assertEqual(match, re:run(Text4, "30 PRINT", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text4, "40 PRINT", [{capture, none}])),        
    ?assertEqual(nomatch, re:run(Text4, "50 PRINT", [{capture, none}])).        

rnd_function_test() ->
    %% Test RND() or RND(1) returns a value between 0 and 1
    {ok, Val1} = erlbasic_eval_builtins:apply_math_function("RND", []),
    ?assert(Val1 >= 0.0),
    ?assert(Val1 < 1.0),

    {ok, Val2} = erlbasic_eval_builtins:apply_math_function("RND", [1]),        
    ?assert(Val2 >= 0.0),
    ?assert(Val2 < 1.0),

    %% Test RND() generates different values
    ?assertNotEqual(Val1, Val2),

    %% Test RND(0) returns the last random value
    {ok, LastVal} = erlbasic_eval_builtins:apply_math_function("RND", [0]),     
    ?assertEqual(Val2, LastVal),

    %% Test RND(0) again should return the same value
    {ok, LastVal2} = erlbasic_eval_builtins:apply_math_function("RND", [0]),    
    ?assertEqual(LastVal, LastVal2),

    %% Test RND(-1) seeds the generator
    {ok, Seeded1} = erlbasic_eval_builtins:apply_math_function("RND", [-1]),    
    ?assert(Seeded1 >= 0.0),
    ?assert(Seeded1 < 1.0),

    %% Test same negative seed produces same sequence
    {ok, Seeded2} = erlbasic_eval_builtins:apply_math_function("RND", [-1]),    
    ?assertEqual(Seeded1, Seeded2),

    %% Test different seeds produce different values
    {ok, Seeded3} = erlbasic_eval_builtins:apply_math_function("RND", [-42]),   
    {ok, Seeded4} = erlbasic_eval_builtins:apply_math_function("RND", [-1]),    
    ?assertNotEqual(Seeded3, Seeded4),

    %% Test RND(positive) generates new value after seeding
    {ok, _} = erlbasic_eval_builtins:apply_math_function("RND", [-100]),        
    {ok, Next1} = erlbasic_eval_builtins:apply_math_function("RND", [5]),       
    {ok, Next2} = erlbasic_eval_builtins:apply_math_function("RND", [10]),      
    ?assertNotEqual(Next1, Next2),
    ?assert(Next1 >= 0.0),
    ?assert(Next1 < 1.0),
    ?assert(Next2 >= 0.0),
    ?assert(Next2 < 1.0).

%% ===========================================================================  
%% Accounts (DETS) tests ΓÇö all run under a single setup/teardown
%% ===========================================================================  

accounts_test() ->
    Dir = accounts_setup(),
    try
        acc_create_and_authenticate(Dir),
        acc_wrong_password(Dir),
        acc_nonexistent_account(Dir),
        acc_password_case_insensitive(Dir),
        acc_list_accounts(Dir),
        acc_find_by_username(Dir),
        acc_reject_reserved_username(Dir),
        acc_allow_nonreserved_multi_letter_username(Dir),
        acc_reject_single_letter_username(Dir),
        acc_reject_duplicate_username(Dir),
        acc_delete_account(Dir),
        acc_change_password(Dir),
        acc_change_password_not_found(Dir),
        acc_default_accounts_seeded(Dir)
    after
        accounts_teardown(Dir)
    end.

accounts_setup() ->
    ok = application:ensure_started(crypto),
    TempDir = temp_dir(),
    ok = filelib:ensure_dir(filename:join([TempDir, "x"])),
    %% Close any leftover table from a previous run before opening a new one.   
    catch dets:close(account),
    ok = application:set_env(erlbasic, accounts_dir, TempDir),
    %% Empty credentials file ΓåÆ triggers default account seeding.
    CredFile = filename:join(TempDir, ".credentials"),
    ok = file:write_file(CredFile, ""),
    ok = application:set_env(erlbasic, credentials_file, CredFile),
    ok = erlbasic_accounts:init(),
    TempDir.

accounts_teardown(TempDir) ->
    dets:close(account),
    application:unset_env(erlbasic, credentials_file),
    file:delete(filename:join(TempDir, "accounts.dets")),
    file:delete(filename:join(TempDir, ".credentials")),
    file:del_dir(TempDir).

temp_dir() ->
    Base = case os:getenv("TEMP") of
        false -> "/tmp";
        D     -> D
    end,
    Id = integer_to_list(erlang:unique_integer([positive])),
    filename:join([Base, "erlbasic_test_" ++ Id]).

acc_create_and_authenticate(_Dir) ->
    ok = erlbasic_accounts:create_account(10, 5, "PASSWORD", "Test User"),      
    ?assertEqual({ok, <<"Test User">>},
                 erlbasic_accounts:authenticate(10, 5, "PASSWORD")).

acc_wrong_password(_Dir) ->
    ok = erlbasic_accounts:create_account(10, 6, "CORRECT", "User"),
    ?assertEqual({error, bad_credentials},
                 erlbasic_accounts:authenticate(10, 6, "WRONG")).

acc_nonexistent_account(_Dir) ->
    ?assertEqual({error, bad_credentials},
                 erlbasic_accounts:authenticate(99, 99, "ANYTHING")).

%% RSTS/E passwords are uppercased before hashing, so "system" == "SYSTEM"      
acc_password_case_insensitive(_Dir) ->
    ok = erlbasic_accounts:create_account(10, 7, "SYSTEM", "CaseUser"),
    ?assertMatch({ok, _}, erlbasic_accounts:authenticate(10, 7, "system")),     
    ?assertMatch({ok, _}, erlbasic_accounts:authenticate(10, 7, "System")),     
    ?assertMatch({ok, _}, erlbasic_accounts:authenticate(10, 7, "SYSTEM")).     

acc_list_accounts(_Dir) ->
    ok = erlbasic_accounts:create_account(5, 1, "PW", "Alice"),
    ok = erlbasic_accounts:create_account(5, 2, "PW", "Bob"),
    {ok, List} = erlbasic_accounts:list_accounts(),
    PPNs = [PPN || {PPN, _, _} <- List],
    ?assert(lists:member({5, 1}, PPNs)),
    ?assert(lists:member({5, 2}, PPNs)).

acc_find_by_username(_Dir) ->
    ok = erlbasic_accounts:create_account(5, 10, "PW", "Lookup User", "lookup1"),
    ?assertMatch({ok, {5, 10, _, _}}, erlbasic_accounts:find_by_username("LOOKUP1")).

acc_reject_reserved_username(_Dir) ->
    ?assertEqual({error, reserved_username},
                 erlbasic_accounts:create_account(7, 1, "PW", "Bad", "sysadmin")).

acc_allow_nonreserved_multi_letter_username(_Dir) ->
    ok = erlbasic_accounts:create_account(7, 11, "PW", "Docs User", "docs"),
    ok = erlbasic_accounts:create_account(7, 12, "PW", "Contains Token", "mysystempage"),
    ?assertMatch({ok, {7, 11, _, _}}, erlbasic_accounts:find_by_username("DOCS")),
    ?assertMatch({ok, {7, 12, _, _}}, erlbasic_accounts:find_by_username("MYSYSTEMPAGE")).

acc_reject_single_letter_username(_Dir) ->
    ?assertEqual({error, username_too_short},
                 erlbasic_accounts:create_account(7, 13, "PW", "Too Short", "d")).

acc_reject_duplicate_username(_Dir) ->
    ok = erlbasic_accounts:create_account(7, 2, "PW", "One", "dupeuser"),
    ?assertEqual({error, username_taken},
                 erlbasic_accounts:create_account(7, 3, "PW", "Two", "DUPEUSER")).

acc_delete_account(_Dir) ->
    ok = erlbasic_accounts:create_account(20, 1, "PW", "Temp"),
    ?assertMatch({ok, _}, erlbasic_accounts:authenticate(20, 1, "PW")),
    ok = erlbasic_accounts:delete_account(20, 1),
    ?assertEqual({error, bad_credentials},
                 erlbasic_accounts:authenticate(20, 1, "PW")).

acc_change_password(_Dir) ->
    ok = erlbasic_accounts:create_account(30, 1, "OLDPASS", "ChPwUser"),        
    ok = erlbasic_accounts:change_password(30, 1, "NEWPASS"),
    ?assertEqual({error, bad_credentials},
                 erlbasic_accounts:authenticate(30, 1, "OLDPASS")),
    ?assertMatch({ok, _}, erlbasic_accounts:authenticate(30, 1, "NEWPASS")).    

acc_change_password_not_found(_Dir) ->
    ?assertEqual({error, not_found},
                 erlbasic_accounts:change_password(99, 88, "PW")).

acc_default_accounts_seeded(_Dir) ->
    ?assertMatch({ok, _}, erlbasic_accounts:authenticate(0, 1, "SYSTEM")),      
    ?assertMatch({ok, _}, erlbasic_accounts:authenticate(1, 1, "SYSTEM")).      

is_privileged_test() ->
    ?assert(erlbasic_accounts:is_privileged(0, 1)),
    ?assert(erlbasic_accounts:is_privileged(1, 1)),
    ?assert(erlbasic_accounts:is_privileged(0, 99)),
    ?assertNot(erlbasic_accounts:is_privileged(2, 1)),
    ?assertNot(erlbasic_accounts:is_privileged(100, 1)).

%% ===========================================================================
%% Session counter tests (issue: stale sessions not decrementing count)
%% ===========================================================================

session_counter_cleanup_on_process_exit_test() ->
    %% When a monitored session process exits, the mem_watchdog should
    %% automatically decrement the PPN counter via the DOWN handler.
    PPN = {2, 1},
    MaxSessions = 3,
    
    %% Start the watchdog
    WatchdogState = ensure_mem_watchdog_started(),
    
    try
        %% Register a session for 2,1
        Pid1 = spawn(fun() -> timer:sleep(infinity) end),
        ok = erlbasic_mem_watchdog:try_register_session(
                 Pid1, unlimited, PPN, MaxSessions),
        
        %% Verify count is 1
        Stats1 = erlbasic_mem_watchdog:get_stats(),
        ?assertEqual(1, maps:get(active_sessions, Stats1)),
        
        %% Kill the session
        exit(Pid1, kill),
        timer:sleep(100),  %% Let DOWN handler fire
        
        %% Verify count went back to 0
        Stats2 = erlbasic_mem_watchdog:get_stats(),
        ?assertEqual(0, maps:get(active_sessions, Stats2)),
        
        %% Now we should be able to register again for the same PPN
        Pid2 = spawn(fun() -> timer:sleep(infinity) end),
        Result = erlbasic_mem_watchdog:try_register_session(
                     Pid2, unlimited, PPN, MaxSessions),
        ?assertEqual(ok, Result),
        
        %% Cleanup
        exit(Pid2, kill),
        timer:sleep(100)
    after
        cleanup_mem_watchdog(WatchdogState)
    end.

%% ===========================================================================  
%% parse_hello / login syntax tests
%% ===========================================================================  

parse_hello_bare_hello_test() ->
    ?assertEqual(hello_prompt, erlbasic_conn:parse_hello("HELLO")).

parse_hello_bare_lowercase_test() ->
    ?assertEqual(hello_prompt, erlbasic_conn:parse_hello("hello")).

parse_hello_bare_login_test() ->
    ?assertEqual(hello_prompt, erlbasic_conn:parse_hello("LOGIN")).

parse_hello_bare_i_test() ->
    ?assertEqual(hello_prompt, erlbasic_conn:parse_hello("I")).

parse_hello_with_ppn_test() ->
    ?assertEqual({hello, 1, 1}, erlbasic_conn:parse_hello("HELLO 1,1")).        

parse_hello_lowercase_with_ppn_test() ->
    ?assertEqual({hello, 1, 1}, erlbasic_conn:parse_hello("hello 1,1")).        

parse_hello_login_with_ppn_test() ->
    ?assertEqual({hello, 2, 5}, erlbasic_conn:parse_hello("LOGIN 2,5")).        

parse_hello_i_with_ppn_test() ->
    ?assertEqual({hello, 10, 3}, erlbasic_conn:parse_hello("I 10,3")).

parse_hello_slash_separator_test() ->
    ?assertEqual({hello, 1, 1}, erlbasic_conn:parse_hello("HELLO 1/1")).        

parse_hello_oneline_password_test() ->
    ?assertEqual({hello, 1, 1, {password, "SYSTEM"}},
                 erlbasic_conn:parse_hello("HELLO 1,1;SYSTEM")).

parse_hello_oneline_lowercase_test() ->
    ?assertEqual({hello, 1, 1, {password, "secret"}},
                 erlbasic_conn:parse_hello("hello 1,1;secret")).

parse_hello_not_hello_test() ->
    ?assertEqual(not_hello, erlbasic_conn:parse_hello("PRINT X")),
    ?assertEqual(not_hello, erlbasic_conn:parse_hello("RUN")),
    ?assertEqual(not_hello, erlbasic_conn:parse_hello("")).

parse_ppn_only_comma_test() ->
    ?assertEqual({ok, 1, 1}, erlbasic_conn:parse_ppn_only("1,1")).

parse_ppn_only_slash_test() ->
    ?assertEqual({ok, 10, 5}, erlbasic_conn:parse_ppn_only("10/5")).

parse_ppn_only_spaces_test() ->
    ?assertEqual({ok, 2, 3}, erlbasic_conn:parse_ppn_only("  2 , 3  ")).        

parse_ppn_only_invalid_test() ->
    ?assertEqual(error, erlbasic_conn:parse_ppn_only("notanumber")),
    ?assertEqual(error, erlbasic_conn:parse_ppn_only("1")).

%% ===========================================================================  
%% parse_credentials tests
%% ===========================================================================  

parse_credentials_empty_test() ->
    ?assertEqual([], erlbasic_accounts:parse_credentials("")).

parse_credentials_comments_test() ->
    Text = "# this is a comment\n% also a comment\n\n",
    ?assertEqual([], erlbasic_accounts:parse_credentials(Text)).

parse_credentials_basic_test() ->
    Text = "[1,1] SYSTEM",
    ?assertEqual([{1, 1, "SYSTEM", "Account [1,1]"}],
                 erlbasic_accounts:parse_credentials(Text)).

parse_credentials_with_name_test() ->
    Text = "[0,1] MYPASS, System Account",
    ?assertEqual([{0, 1, "MYPASS", "System Account"}],
                 erlbasic_accounts:parse_credentials(Text)).

parse_credentials_with_extra_fields_test() ->
    %% Extra comma-separated fields after name are silently ignored
    Text = "[2,3] PASS, Alice Smith, some extra, data",
    ?assertEqual([{2, 3, "PASS", "Alice Smith"}],
                 erlbasic_accounts:parse_credentials(Text)).

parse_credentials_multiple_test() ->
    Text = "[0,1] SYSTEM, System Account\n[1,1] SYSTEM, System Manager\n",      
    ?assertEqual(
        [{0, 1, "SYSTEM", "System Account"},
         {1, 1, "SYSTEM", "System Manager"}],
        erlbasic_accounts:parse_credentials(Text)).

parse_credentials_mixed_test() ->
    Text = "# comment\n[1,2] PASS, Alice\n\n% skip me\n[3,4] SECRET",
    ?assertEqual(
        [{1, 2, "PASS", "Alice"},
         {3, 4, "SECRET", "Account [3,4]"}],
        erlbasic_accounts:parse_credentials(Text)).

%% ===========================================================================  
%% parse_os_command tests
%% ===========================================================================  

parse_os_command_bye_test() ->
    ?assertEqual(logout, erlbasic_conn:parse_os_command("BYE")).

parse_os_command_bye_lowercase_test() ->
    ?assertEqual(logout, erlbasic_conn:parse_os_command("bye")).

parse_os_command_bye_mixed_case_test() ->
    ?assertEqual(logout, erlbasic_conn:parse_os_command("Bye")).

parse_os_command_bye_whitespace_test() ->
    ?assertEqual(logout, erlbasic_conn:parse_os_command("  BYE  ")).

parse_os_command_quit_test() ->
    ?assertEqual(quit, erlbasic_conn:parse_os_command("QUIT")).

parse_os_command_quit_lowercase_test() ->
    ?assertEqual(quit, erlbasic_conn:parse_os_command("quit")).

parse_os_command_quit_whitespace_test() ->
    ?assertEqual(quit, erlbasic_conn:parse_os_command("  QUIT  ")).

parse_os_command_basic_run_test() ->
    ?assertEqual(not_os_command, erlbasic_conn:parse_os_command("RUN")).        

parse_os_command_basic_print_test() ->
    ?assertEqual(not_os_command, erlbasic_conn:parse_os_command("PRINT X")).    

parse_os_command_basic_list_test() ->
    ?assertEqual(not_os_command, erlbasic_conn:parse_os_command("LIST")).       

%% HELLO, LOGIN, and I are OS commands that return {login, ...}
parse_os_command_hello_bare_test() ->
    ?assertEqual({login, hello_prompt}, erlbasic_conn:parse_os_command("HELLO")),
    ?assertEqual({login, hello_prompt}, erlbasic_conn:parse_os_command("hello")),
    ?assertEqual({login, hello_prompt}, erlbasic_conn:parse_os_command("LOGIN")),
    ?assertEqual({login, hello_prompt}, erlbasic_conn:parse_os_command("I")).   

parse_os_command_hello_ppn_test() ->
    ?assertEqual({login, {hello, 1, 1}},
                 erlbasic_conn:parse_os_command("HELLO 1,1")),
    ?assertEqual({login, {hello, 2, 5}},
                 erlbasic_conn:parse_os_command("login 2,5")).

parse_os_command_hello_inline_pw_test() ->
    ?assertEqual({login, {hello, 1, 1, {password, "SYSTEM"}}},
                 erlbasic_conn:parse_os_command("HELLO 1,1;SYSTEM")).

parse_os_command_empty_test() ->
    ?assertEqual(not_os_command, erlbasic_conn:parse_os_command("")).

%% ---- GET / GETKEY tests ----

%% GETKEY in a program suspends execution (awaiting_input = true),
%% then resumes when a line arrives; only the first character is stored.        
getkey_program_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 GETKEY K$", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT K$", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    %% RUN suspends at line 10 waiting for a key.
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    ?assert(erlbasic_interp:awaiting_input(S4)),
    ?assertNot(erlbasic_interp:awaiting_input_nonblocking(S4)),
    %% Supply "XYZ" ΓÇö only "X" should be assigned to K$.
    {S5, Output} = erlbasic_interp:handle_input("XYZ", S4),
    ?assertNot(erlbasic_interp:awaiting_input(S5)),
    ?assertEqual(match, re:run(lists:flatten(Output), "X\r\n", [{capture, none}])).

%% SPACE from GETKEY must remain a literal one-character string,
%% so ASC(A$) returns 32 instead of ILLEGAL FUNCTION CALL.
getkey_space_asc_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 GETKEY A$", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT ASC(A$)", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    ?assert(erlbasic_interp:awaiting_input(S4)),
    {S5, Output} = erlbasic_interp:handle_input(" ", S4),
    ?assertNot(erlbasic_interp:awaiting_input(S5)),
    ?assertEqual(match, re:run(lists:flatten(Output), "32\\r\\n", [{capture, none}])).

%% GET in a program sets pending_input = {get_nb,...} (non-blocking).
%% Sending "" (as the conn layer does on timeout) assigns "" to the variable.   
get_nonblocking_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 GET K$", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT \"[\" : PRINT K$ : PRINT \"]\"", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    ?assert(erlbasic_interp:awaiting_input(S4)),
    %% GET is non-blocking: the conn layer checks this flag.
    ?assert(erlbasic_interp:awaiting_input_nonblocking(S4)),
    %% Simulate the conn-layer timeout: pass "" to handle_input.
    {S5, Output} = erlbasic_interp:handle_input("", S4),
    ?assertNot(erlbasic_interp:awaiting_input(S5)),
    Text = lists:flatten(Output),
    %% K$ should be "" ΓÇö no characters between the brackets.
    ?assertEqual(match, re:run(Text, "\\[\\s*\\]", [{capture, none}])).

%% When GETKEY receives a multi-character line, the leftover characters
%% are stored in char_buffer and consumed by subsequent GET/GETKEY calls        
%% without any further suspension.
getkey_char_buffer_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 GETKEY A$", S0),
    {S2, _} = erlbasic_interp:handle_input("20 GET B$", S1),
    {S3, _} = erlbasic_interp:handle_input("30 PRINT A$", S2),
    {S4, _} = erlbasic_interp:handle_input("40 PRINT B$", S3),
    {S5, _} = erlbasic_interp:handle_input("50 END", S4),
    %% RUN suspends at line 10 (GETKEY).
    {S6, _} = erlbasic_interp:handle_input("RUN", S5),
    ?assert(erlbasic_interp:awaiting_input(S6)),
    %% Send "AB" ΓÇö A$ gets "A", "B" goes into char_buffer.
    %% Line 20 GET B$ then immediately consumes "B" from the buffer
    %% without suspending again.
    {S7, Output} = erlbasic_interp:handle_input("AB", S6),
    ?assertNot(erlbasic_interp:awaiting_input(S7)),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "A", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "B", [{capture, none}])).

%% GETKEY in immediate mode sets pending_input; resolves on next handle_input.  
getkey_immediate_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _Prompt} = erlbasic_interp:handle_input("GETKEY K$", S0),
    ?assert(erlbasic_interp:awaiting_input(S1)),
    {S2, _} = erlbasic_interp:handle_input("Z", S1),
    ?assertNot(erlbasic_interp:awaiting_input(S2)),
    %% Verify K$ was set by printing it.
    {_S3, Out} = erlbasic_interp:handle_input("PRINT K$", S2),
    ?assertEqual("Z\r\n", lists:flatten(Out)).

%% =============================================================================
%% HTTPS Configuration Tests
%% =============================================================================

%% Test that HTTPS is disabled by default
https_disabled_by_default_test() ->
    EnableHttps = application:get_env(erlbasic, enable_https, false),
    ?assertEqual(false, EnableHttps).

%% Test certificate file checking logic
https_cert_file_validation_test() ->
    %% Create test directory and files
    TestDir = "test_ssl_temp",
    file:make_dir(TestDir),
    CertFile = filename:join(TestDir, "test_cert.pem"),
    KeyFile = filename:join(TestDir, "test_key.pem"),

    try
        %% Both files missing
        ?assertEqual(false, filelib:is_file(CertFile)),
        ?assertEqual(false, filelib:is_file(KeyFile)),

        %% Create cert file only
        ok = file:write_file(CertFile, <<"test cert">>),
        ?assertEqual(true, filelib:is_file(CertFile)),
        ?assertEqual(false, filelib:is_file(KeyFile)),

        %% Create key file
        ok = file:write_file(KeyFile, <<"test key">>),
        ?assertEqual(true, filelib:is_file(CertFile)),
        ?assertEqual(true, filelib:is_file(KeyFile))
    after
        %% Cleanup
        file:delete(CertFile),
        file:delete(KeyFile),
        file:del_dir(TestDir)
    end.

%% Test that HTTPS config values can be read
https_config_reading_test() ->
    %% Save current env
    OldHttpPort = application:get_env(erlbasic, http_port, undefined),
    OldHttpsPort = application:get_env(erlbasic, https_port, undefined),        
    OldCertFile = application:get_env(erlbasic, certfile, undefined),
    OldKeyFile = application:get_env(erlbasic, keyfile, undefined),

    try
        %% Set test values
        application:set_env(erlbasic, http_port, 9081),
        application:set_env(erlbasic, https_port, 9443),
        application:set_env(erlbasic, certfile, "test/cert.pem"),
        application:set_env(erlbasic, keyfile, "test/key.pem"),

        %% Read them back
        ?assertEqual(9081, application:get_env(erlbasic, http_port, 8081)),     
        ?assertEqual(9443, application:get_env(erlbasic, https_port, 8443)),    
        ?assertEqual("test/cert.pem", application:get_env(erlbasic, certfile, "priv/ssl/cert.pem")),
        ?assertEqual("test/key.pem", application:get_env(erlbasic, keyfile, "priv/ssl/key.pem")),

        %% Test defaults when not set
        application:unset_env(erlbasic, http_port),
        ?assertEqual(8081, application:get_env(erlbasic, http_port, 8081)),     

        application:unset_env(erlbasic, https_port),
        ?assertEqual(8443, application:get_env(erlbasic, https_port, 8443))     
    after
        %% Restore original env
        case OldHttpPort of
            undefined -> application:unset_env(erlbasic, http_port);
            _ -> application:set_env(erlbasic, http_port, OldHttpPort)
        end,
        case OldHttpsPort of
            undefined -> application:unset_env(erlbasic, https_port);
            _ -> application:set_env(erlbasic, https_port, OldHttpsPort)        
        end,
        case OldCertFile of
            undefined -> application:unset_env(erlbasic, certfile);
            _ -> application:set_env(erlbasic, certfile, OldCertFile)
        end,
        case OldKeyFile of
            undefined -> application:unset_env(erlbasic, keyfile);
            _ -> application:set_env(erlbasic, keyfile, OldKeyFile)
        end
    end.

%% Test CA certificate file handling (optional parameter)
https_ca_cert_optional_test() ->
    %% Save current env
    OldCaCert = application:get_env(erlbasic, cacertfile, undefined),

    try
        %% Test undefined (default)
        application:unset_env(erlbasic, cacertfile),
        ?assertEqual(undefined, application:get_env(erlbasic, cacertfile, undefined)),

        %% Test with value
        application:set_env(erlbasic, cacertfile, "test/cacert.pem"),
        ?assertEqual("test/cacert.pem", application:get_env(erlbasic, cacertfile, undefined))
    after
        %% Restore
        case OldCaCert of
            undefined -> application:unset_env(erlbasic, cacertfile);
            _ -> application:set_env(erlbasic, cacertfile, OldCaCert)
        end
    end.
%% =============================================================================
%% ON...GOSUB and ON...GOTO Tests
%% =============================================================================

%% Test ON...GOSUB with valid index
on_gosub_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 LET X = 2", S0),
    {S2, _} = erlbasic_interp:handle_input("20 ON X GOSUB 100, 200, 300", S1),  
    {S3, _} = erlbasic_interp:handle_input("30 PRINT \"BACK\"", S2),
    {S4, _} = erlbasic_interp:handle_input("40 END", S3),
    {S5, _} = erlbasic_interp:handle_input("100 PRINT \"SUB1\" : RETURN", S4),  
    {S6, _} = erlbasic_interp:handle_input("200 PRINT \"SUB2\" : RETURN", S5),  
    {S7, _} = erlbasic_interp:handle_input("300 PRINT \"SUB3\" : RETURN", S6),  
    {_S8, Output} = erlbasic_interp:handle_input("RUN", S7),
    Text = lists:flatten(Output),
    %% Should call SUB2 (index 2), then continue to line 30
    ?assertEqual(match, re:run(Text, "SUB2", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "BACK", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "SUB1", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "SUB3", [{capture, none}])).

%% Test ON...GOSUB with out-of-range index (should continue)
on_gosub_out_of_range_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 LET X = 5", S0),
    {S2, _} = erlbasic_interp:handle_input("20 ON X GOSUB 100, 200", S1),       
    {S3, _} = erlbasic_interp:handle_input("30 PRINT \"CONTINUE\"", S2),        
    {S4, _} = erlbasic_interp:handle_input("40 END", S3),
    {S5, _} = erlbasic_interp:handle_input("100 PRINT \"SUB1\" : RETURN", S4),  
    {S6, _} = erlbasic_interp:handle_input("200 PRINT \"SUB2\" : RETURN", S5),  
    {_S7, Output} = erlbasic_interp:handle_input("RUN", S6),
    Text = lists:flatten(Output),
    %% Index 5 is out of range, should skip and continue to line 30
    ?assertEqual(match, re:run(Text, "CONTINUE", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "SUB1", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "SUB2", [{capture, none}])).

%% Test ON...GOTO with valid index
on_goto_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 LET X = 3", S0),
    {S2, _} = erlbasic_interp:handle_input("20 ON X GOTO 100, 200, 300", S1),   
    {S3, _} = erlbasic_interp:handle_input("30 PRINT \"SKIP\"", S2),
    {S4, _} = erlbasic_interp:handle_input("40 END", S3),
    {S5, _} = erlbasic_interp:handle_input("100 PRINT \"LINE1\" : END", S4),    
    {S6, _} = erlbasic_interp:handle_input("200 PRINT \"LINE2\" : END", S5),    
    {S7, _} = erlbasic_interp:handle_input("300 PRINT \"LINE3\" : END", S6),    
    {_S8, Output} = erlbasic_interp:handle_input("RUN", S7),
    Text = lists:flatten(Output),
    %% Should jump to line 300 (index 3)
    ?assertEqual(match, re:run(Text, "LINE3", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "LINE1", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "LINE2", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "SKIP", [{capture, none}])).

%% Test ON...GOTO with zero index (should continue)
on_goto_zero_index_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 LET X = 0", S0),
    {S2, _} = erlbasic_interp:handle_input("20 ON X GOTO 100, 200", S1),        
    {S3, _} = erlbasic_interp:handle_input("30 PRINT \"ZERO\"", S2),
    {S4, _} = erlbasic_interp:handle_input("40 END", S3),
    {S5, _} = erlbasic_interp:handle_input("100 PRINT \"LINE1\" : END", S4),    
    {S6, _} = erlbasic_interp:handle_input("200 PRINT \"LINE2\" : END", S5),    
    {_S7, Output} = erlbasic_interp:handle_input("RUN", S6),
    Text = lists:flatten(Output),
    %% Index 0 is out of range, should continue to line 30
    ?assertEqual(match, re:run(Text, "ZERO", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "LINE1", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "LINE2", [{capture, none}])).

if_then_line_number_implies_goto_test() ->
    ?assertEqual(
        {if_then_else, "X=1", "GOTO 200", undefined},
        erlbasic_parser:parse_statement("IF X=1 THEN 200")
    ),
    ?assertEqual(
        {if_then_else, "X=1", "GOTO 100", "GOTO 300"},
        erlbasic_parser:parse_statement("IF X=1 THEN 100 ELSE 300")
    ).

if_then_line_number_run_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 LET X = 1", S0),
    {S2, _} = erlbasic_interp:handle_input("20 IF X = 1 THEN 40", S1),
    {S3, _} = erlbasic_interp:handle_input("30 PRINT \"BAD\"", S2),
    {S4, _} = erlbasic_interp:handle_input("40 PRINT \"OK\"", S3),
    {S5, _} = erlbasic_interp:handle_input("50 END", S4),
    {_S6, Output} = erlbasic_interp:handle_input("RUN", S5),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "OK", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "BAD", [{capture, none}])).

elseif_parse_test() ->
    ?assertEqual(
        {if_then_else, "X=1", "PRINT \"ONE\"", "IF X=2 THEN PRINT \"TWO\" ELSE PRINT \"OTHER\""},
        erlbasic_parser:parse_statement("IF X=1 THEN PRINT \"ONE\" ELSEIF X=2 THEN PRINT \"TWO\" ELSE PRINT \"OTHER\"")
    ).

elseif_run_first_branch_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 LET X = 1", S0),
    {S2, _} = erlbasic_interp:handle_input("20 IF X=1 THEN PRINT \"ONE\" ELSEIF X=2 THEN PRINT \"TWO\" ELSE PRINT \"OTHER\"", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {_S4, Output} = erlbasic_interp:handle_input("RUN", S3),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "ONE", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "TWO", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "OTHER", [{capture, none}])).

elseif_run_middle_branch_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 LET X = 2", S0),
    {S2, _} = erlbasic_interp:handle_input("20 IF X=1 THEN PRINT \"ONE\" ELSEIF X=2 THEN PRINT \"TWO\" ELSE PRINT \"OTHER\"", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {_S4, Output} = erlbasic_interp:handle_input("RUN", S3),
    Text = lists:flatten(Output),
    ?assertEqual(nomatch, re:run(Text, "ONE", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "TWO", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "OTHER", [{capture, none}])).

elseif_run_else_branch_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 LET X = 9", S0),
    {S2, _} = erlbasic_interp:handle_input("20 IF X=1 THEN PRINT \"ONE\" ELSEIF X=2 THEN PRINT \"TWO\" ELSE PRINT \"OTHER\"", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {_S4, Output} = erlbasic_interp:handle_input("RUN", S3),
    Text = lists:flatten(Output),
    ?assertEqual(nomatch, re:run(Text, "ONE", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "TWO", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "OTHER", [{capture, none}])).

%% =============================================================================
%% COMMON / CHAIN Variable Persistence Tests
%% =============================================================================

%% COMMON statement parses to {common, [VarNames]}
common_statement_parse_test() ->
    ?assertEqual(
        {common, ["A", "B$"]},
        erlbasic_parser:parse_statement("COMMON A,B$")
    ),
    ?assertEqual(
        {common, ["X", "Y", "Z%"]},
        erlbasic_parser:parse_statement("COMMON X, Y, Z%")
    ).

%% Variables declared with COMMON persist through CHAIN; others are cleared.
%% Chains to examples/common_chain_target.bas which does: PRINT A / PRINT B
common_chain_persists_declared_vars_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 COMMON A", S0),
    {S2, _} = erlbasic_interp:handle_input("20 A = 42", S1),
    {S3, _} = erlbasic_interp:handle_input("30 B = 100", S2),
    {S4, _} = erlbasic_interp:handle_input("40 CHAIN \"common_chain_target\"", S3),
    {_S5, Output} = erlbasic_interp:handle_input("RUN", S4),
    Text = lists:flatten(Output),
    %% A was declared COMMON so it survives: PRINT A should give 42
    ?assertEqual(match, re:run(Text, "42", [{capture, none}])),
    %% B was not declared COMMON so it is cleared: PRINT B should give 0
    ?assertEqual(nomatch, re:run(Text, "100", [{capture, none}])).

%% An array declared with COMMON (using trailing parens) persists through CHAIN.
%% Chains to examples/common_chain_array_target.bas which does: PRINT A(1)
common_chain_preserves_arrays_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 COMMON A()", S0),
    {S2, _} = erlbasic_interp:handle_input("20 DIM A(5)", S1),
    {S3, _} = erlbasic_interp:handle_input("30 A(1) = 99", S2),
    {S4, _} = erlbasic_interp:handle_input("40 CHAIN \"common_chain_array_target\"", S3),
    {_S5, Output} = erlbasic_interp:handle_input("RUN", S4),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "99", [{capture, none}])).

immediate_chain_unquoted_filename_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("CHAIN chain_helper", S0),
    ?assertEqual("CHAINED\r\n", lists:flatten(Output)).

immediate_chain_quoted_filename_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("CHAIN \"chain_helper\"", S0),
    ?assertEqual("CHAINED\r\n", lists:flatten(Output)).

immediate_chain_sequence_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("PRINT \"BEFORE\":CHAIN \"chain_helper\"", S0),
    ?assertEqual("BEFORE\r\nCHAINED\r\n", lists:flatten(Output)).

immediate_if_then_chain_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("IF 1 THEN CHAIN \"chain_helper\"", S0),
    ?assertEqual("CHAINED\r\n", lists:flatten(Output)).

immediate_on_error_goto_rejected_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("ON ERROR GOTO 100", S0),
    ?assertEqual("?SYNTAX ERROR\r\n", lists:flatten(Output)).

immediate_resume_rejected_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("RESUME", S0),
    ?assertEqual("?SYNTAX ERROR\r\n", lists:flatten(Output)).

immediate_resume_next_rejected_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("RESUME NEXT", S0),
    ?assertEqual("?SYNTAX ERROR\r\n", lists:flatten(Output)).

immediate_resume_line_rejected_test() ->
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("RESUME 100", S0),
    ?assertEqual("?SYNTAX ERROR\r\n", lists:flatten(Output)).

%% =============================================================================
%% ON ERROR GOTO and RESUME Tests
%% =============================================================================

%% Test ON ERROR GOTO with RESUME NEXT
on_error_goto_resume_next_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 ON ERROR GOTO 100", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT \"START\"", S1),
    {S3, _} = erlbasic_interp:handle_input("30 X = 1 / 0", S2),
    {S4, _} = erlbasic_interp:handle_input("40 PRINT \"AFTER\"", S3),
    {S5, _} = erlbasic_interp:handle_input("50 END", S4),
    {S6, _} = erlbasic_interp:handle_input("100 PRINT \"ERROR\"; ERR", S5),     
    {S7, _} = erlbasic_interp:handle_input("110 RESUME NEXT", S6),
    {_S8, Output} = erlbasic_interp:handle_input("RUN", S7),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "START", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "ERROR11", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "AFTER", [{capture, none}])).

%% Test ON ERROR GOTO with RESUME (retry)
on_error_goto_resume_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 ON ERROR GOTO 100", S0),
    {S2, _} = erlbasic_interp:handle_input("20 X = 0", S1),
    {S3, _} = erlbasic_interp:handle_input("30 PRINT 10 / X", S2),
    {S4, _} = erlbasic_interp:handle_input("40 END", S3),
    {S5, _} = erlbasic_interp:handle_input("100 X = 5", S4),
    {S6, _} = erlbasic_interp:handle_input("110 RESUME", S5),
    {_S7, Output} = erlbasic_interp:handle_input("RUN", S6),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "2", [{capture, none}])).

%% Test ON ERROR GOTO with RESUME line
on_error_goto_resume_line_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 ON ERROR GOTO 100", S0),
    {S2, _} = erlbasic_interp:handle_input("20 X = 1 / 0", S1),
    {S3, _} = erlbasic_interp:handle_input("30 PRINT \"SKIP\"", S2),
    {S4, _} = erlbasic_interp:handle_input("40 END", S3),
    {S5, _} = erlbasic_interp:handle_input("50 PRINT \"TARGET\"", S4),
    {S6, _} = erlbasic_interp:handle_input("60 END", S5),
    {S7, _} = erlbasic_interp:handle_input("100 RESUME 50", S6),
    {_S8, Output} = erlbasic_interp:handle_input("RUN", S7),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "TARGET", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "SKIP", [{capture, none}])).

%% Test ON ERROR GOTO 0 (disable error handler)
on_error_goto_zero_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 ON ERROR GOTO 100", S0),
    {S2, _} = erlbasic_interp:handle_input("20 ON ERROR GOTO 0", S1),
    {S3, _} = erlbasic_interp:handle_input("30 X = 1 / 0", S2),
    {S4, _} = erlbasic_interp:handle_input("40 END", S3),
    {S5, _} = erlbasic_interp:handle_input("100 PRINT \"HANDLER\"", S4),        
    {S6, _} = erlbasic_interp:handle_input("110 END", S5),
    {_S7, Output} = erlbasic_interp:handle_input("RUN", S6),
    Text = lists:flatten(Output),
    %% Should get error, not handler
    ?assertEqual(match, re:run(Text, "DIVISION BY ZERO ERROR", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "HANDLER", [{capture, none}])).

%% Test ERR and ERL variables
err_erl_variables_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 ON ERROR GOTO 100", S0),
    {S2, _} = erlbasic_interp:handle_input("20 X = 1 / 0", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("100 PRINT ERR; ERL", S3),
    {S5, _} = erlbasic_interp:handle_input("110 END", S4),
    {_S6, Output} = erlbasic_interp:handle_input("RUN", S5),
    Text = lists:flatten(Output),
    %% ERR=11 (division by zero), ERL=20
    ?assertEqual(match, re:run(Text, "1120", [{capture, none}])).

%% Test RESUME without error
resume_without_error_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 RESUME", S0),
    {S2, _} = erlbasic_interp:handle_input("20 END", S1),
    {_S3, Output} = erlbasic_interp:handle_input("RUN", S2),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "RESUME WITHOUT ERROR", [{capture, none}])).

%% Test loading asciilife.bas from examples
asciilife_load_test() ->
    %% Read asciilife.bas and enter each line
    {ok, Content} = file:read_file("examples/asciilife.bas"),
    Lines = binary:split(Content, <<"\n">>, [global, trim_all]),

    State0 = erlbasic_interp:new_state(),

    %% Enter all lines from the file
    FinalState = lists:foldl(fun(Line, StateAcc) ->
        LineStr = unicode:characters_to_list(Line),
        case string:trim(LineStr) of
            "" -> StateAcc;  %% Skip empty lines
            NonEmpty ->
                {NewState, Output} = erlbasic_interp:handle_input(NonEmpty, StateAcc),
                %% Check for syntax error during program entry
                OutText = lists:flatten(Output),
                case re:run(OutText, "SYNTAX ERROR|ERROR", [{capture, none}]) of
                    match ->
                        io:format("~nError entering line: ~s~n", [NonEmpty]),   
                        io:format("Output: ~s~n", [OutText]),
                        error({syntax_error_during_load, NonEmpty, OutText});   
                    nomatch ->
                        NewState
                end
        end
    end, State0, Lines),

    %% Verify the program loaded
    {_FinalState, _ListOutput} = erlbasic_interp:handle_input("LIST 10", FinalState),

    %% Success - program loaded without syntax errors
    ok.

    %% Test loading stripesfx.bas from examples via LOAD command
    stripesfx_load_test() ->
        State0 = erlbasic_interp:new_state(),
        {State1, LoadOutput} = erlbasic_interp:handle_input("LOAD stripesfx", State0),
        ?assertEqual("OK\r\n", lists:flatten(LoadOutput)),

        %% Verify representative lines from the loaded program are present.
        {_State2, ListOutput} = erlbasic_interp:handle_input("LIST 3010", State1),
        ListText = lists:flatten(ListOutput),
        ?assertEqual(match, re:run(ListText, "SOUND CH, 0, 0, 0", [{capture, none}])),

        {_State3, ListOutput2} = erlbasic_interp:handle_input("LIST 9020", State1),
        ListText2 = lists:flatten(ListOutput2),
        ?assertEqual(match, re:run(ListText2, "READ N, L", [{capture, none}])),
        ok.

    sprites_examples_load_test() ->
        State0 = erlbasic_interp:new_state(),
        {State1, LoadSpritesOutput} = erlbasic_interp:handle_input("LOAD sprites", State0),
        ?assertEqual("OK\r\n", lists:flatten(LoadSpritesOutput)),
        {_State2, SpritesListOutput} = erlbasic_interp:handle_input("LIST 150", State1),
        SpritesListText = lists:flatten(SpritesListOutput),
        ?assertEqual(match, re:run(SpritesListText, "0x00018000", [{capture, none}])),

        {State3, LoadSpritesHgr2Output} = erlbasic_interp:handle_input("LOAD sprites_hgr2", State0),
        ?assertEqual("OK\r\n", lists:flatten(LoadSpritesHgr2Output)),
        {_State4, SpritesHgr2ListOutput} = erlbasic_interp:handle_input("LIST 150", State3),
        SpritesHgr2ListText = lists:flatten(SpritesHgr2ListOutput),
        ?assertEqual(match, re:run(SpritesHgr2ListText, "0x0000000000600000", [{capture, none}])),
        ok.

load_program_skips_bad_lines_test() ->
    ProgramText =
        "10 PRINT \"OK\"\n"
        "20 DIM NEXT(1)\n"
        "30 LET X =\n"
        "40 END\n",
    {syntax_errors, Program, ErrorLines} = erlbasic_commands:parse_bin_as_program(list_to_binary(ProgramText)),
    ?assertEqual([20, 30], ErrorLines),
    ?assertEqual("~ERR DIM NEXT(1)", proplists:get_value(20, Program)),
    ?assertEqual("~ERR LET X =", proplists:get_value(30, Program)),
    ?assertEqual("PRINT \"OK\"", proplists:get_value(10, Program)),
    ?assertEqual("END", proplists:get_value(40, Program)).

load_malformed_shared_example_reports_error_without_crash_test() ->
    BeamPath = code:which(erlbasic_commands),
    BeamDir = filename:dirname(BeamPath),
    RepoRoot = find_repo_root_from(BeamDir),
    ExamplesDir = filename:join(RepoRoot, "examples"),
    TempBase = "__badload_example_test__",
    TempFile = filename:join(ExamplesDir, TempBase ++ ".bas"),
    ProgramText =
        "10 PRINT \"OK\"\n"
        "20 LET X =\n"
        "30 END\n",
    try
        ok = file:write_file(TempFile, ProgramText),
        State0 = erlbasic_interp:new_state(),
        {State1, LoadOutput} = erlbasic_interp:handle_input("LOAD " ++ TempBase, State0),
        LoadText = lists:flatten(LoadOutput),
        ?assertEqual(match, re:run(LoadText, "SYNTAX ERROR IN 20", [{capture, none}])),
        {_State2, List10} = erlbasic_interp:handle_input("LIST 10", State1),
        {_State3, List20} = erlbasic_interp:handle_input("LIST 20", State1),
        {_State4, List30} = erlbasic_interp:handle_input("LIST 30", State1),
        {_State5, RunOutput} = erlbasic_interp:handle_input("RUN", State1),
        ?assertEqual(match, re:run(lists:flatten(List10), "PRINT \"OK\"", [{capture, none}])),
        ?assertEqual(match, re:run(lists:flatten(List20), "~ERR LET X =", [{capture, none}])),
        ?assertEqual(match, re:run(lists:flatten(List30), "END", [{capture, none}])),
        ?assertEqual(match, re:run(lists:flatten(RunOutput), "SYNTAX ERROR IN 20", [{capture, none}]))
    after
        _ = file:delete(TempFile)
    end.

err_marker_reload_preserved_test() ->
    ProgramText =
        "10 PRINT \"OK\"\n"
        "20 ~ERR LET X =\n"
        "30 END\n",
    {syntax_errors, Program, ErrorLines} = erlbasic_commands:parse_bin_as_program(list_to_binary(ProgramText)),
    ?assertEqual([20], ErrorLines),
    ?assertEqual("~ERR LET X =", proplists:get_value(20, Program)),
    State0 = erlbasic_interp:new_state(),
    State1 = State0#state{prog = Program},
    {_State2, ListOutput} = erlbasic_interp:handle_input("LIST", State1),
    ?assertEqual(match, re:run(lists:flatten(ListOutput), "20 ~ERR LET X =", [{capture, none}])).

run_with_err_marker_line_reports_syntax_error_test() ->
    State0 = erlbasic_interp:new_state(),
    {State1, _} = erlbasic_interp:handle_input("10 PRINT \"OK\"", State0),
    {State2, _} = erlbasic_interp:handle_input("20 ~ERR LET X =", State1),
    {State3, _} = erlbasic_interp:handle_input("30 END", State2),
    {_State4, Output} = erlbasic_interp:handle_input("RUN", State3),
    ?assertEqual(match, re:run(lists:flatten(Output), "SYNTAX ERROR IN 20", [{capture, none}])).


find_repo_root_from(Dir) ->
    ConfigPath = filename:join(Dir, "rebar.config"),
    case filelib:is_regular(ConfigPath) of
        true -> Dir;
        false ->
            Parent = filename:dirname(Dir),
            case Parent =:= Dir of
                true -> Dir;
                false -> find_repo_root_from(Parent)
            end
    end.

%% =============================================================================
%% INPUT Statement Tests (GW-BASIC Compatibility)
%% =============================================================================

%% Test single INPUT with string variable
input_single_string_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT N$", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT N$", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, Output1} = erlbasic_interp:handle_input("RUN", S3),
    ?assertEqual(match, re:run(lists:flatten(Output1), "\\?\\s", [{capture, none}])),
    {_S5, Output2} = erlbasic_interp:handle_input("hello", S4),
    Text = lists:flatten(Output2),
    ?assertEqual(match, re:run(Text, "hello", [{capture, none}])).

%% Test single INPUT with integer variable
input_single_integer_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT X%", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT X% + 1", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, Output1} = erlbasic_interp:handle_input("RUN", S3),
    ?assertEqual(match, re:run(lists:flatten(Output1), "\\?\\s", [{capture, none}])),
    {_S5, Output2} = erlbasic_interp:handle_input("41", S4),
    Text = lists:flatten(Output2),
    ?assertEqual(match, re:run(Text, "42", [{capture, none}])).

%% Test sequential INPUT statements (multiple INPUTs in program)
input_sequential_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT A$", S0),
    {S2, _} = erlbasic_interp:handle_input("20 INPUT B%", S1),
    {S3, _} = erlbasic_interp:handle_input("30 PRINT A$ ; \":\" ; B%", S2),
    {S4, _} = erlbasic_interp:handle_input("40 END", S3),
    {S5, Output1} = erlbasic_interp:handle_input("RUN", S4),
    ?assertEqual(match, re:run(lists:flatten(Output1), "\\?\\s", [{capture, none}])),
    {S6, Output2} = erlbasic_interp:handle_input("test", S5),
    ?assertEqual(match, re:run(lists:flatten(Output2), "\\?\\s", [{capture, none}])),
    {_S7, Output3} = erlbasic_interp:handle_input("99", S6),
    Text = lists:flatten(Output3),
    ?assertEqual(match, re:run(Text, "test:99", [{capture, none}])).

%% Test INPUT with string containing spaces (quoted)
input_string_with_spaces_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT S$", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT S$", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    {_S5, Output} = erlbasic_interp:handle_input("\"hello world\"", S4),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "hello world", [{capture, none}])).

%% Test INPUT with integer that gets stored in float variable
input_integer_to_float_conversion_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT X", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT X + 0.5", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    {_S5, Output} = erlbasic_interp:handle_input("10", S4),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "10.5", [{capture, none}])).

%% GW-BASIC/QBASIC accept scientific notation in INPUT numeric fields
%% using E/e with optional + or - sign in the exponent.
input_scientific_notation_positive_exponent_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT A", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT A/1E30", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    {_S5, Output} = erlbasic_interp:handle_input("2e+30", S4),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "2(\\.0+)?", [{capture, none}])).

input_scientific_notation_negative_exponent_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT N%", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT N%", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    {_S5, Output} = erlbasic_interp:handle_input("5E-1", S4),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "0", [{capture, none}])).

input_scientific_notation_to_integer_target_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT N%", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT N%", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    {_S5, Output} = erlbasic_interp:handle_input("2e2", S4),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "200", [{capture, none}])).

%% Test INPUT with byte variable
input_byte_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT B&", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT B&", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    {_S5, Output} = erlbasic_interp:handle_input("200", S4),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "200", [{capture, none}])).

%% Test INPUT followed by computation
input_with_arithmetic_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 INPUT N%", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT N% * 2 + 3", S1),
    {S3, _} = erlbasic_interp:handle_input("30 END", S2),
    {S4, _} = erlbasic_interp:handle_input("RUN", S3),
    {_S5, Output} = erlbasic_interp:handle_input("5", S4),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "13", [{capture, none}])).

%% Test INPUT with float value used as array index (tictactoe crash regression)
%% INPUT evaluates numeric input as floats (e.g., "9" becomes 9.0).
%% normalize_int must properly convert floats to integers for array indexing.
input_float_as_array_index_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 DIM B(9)", S0),
    {S2, _} = erlbasic_interp:handle_input("20 INPUT I", S1),
    {S3, _} = erlbasic_interp:handle_input("30 B(I) = 42", S2),
    {S4, _} = erlbasic_interp:handle_input("40 PRINT B(I)", S3),
    {S5, _} = erlbasic_interp:handle_input("50 END", S4),
    {S6, _} = erlbasic_interp:handle_input("RUN", S5),
    {_S7, Output} = erlbasic_interp:handle_input("9", S6),
    Text = lists:flatten(Output),
    %% Should print 42, not crash or print 0
    ?assertEqual(match, re:run(Text, "42", [{capture, none}])),
    %% Should not have any error messages
    ?assertEqual(nomatch, re:run(Text, "ERROR|SUBSCRIPT", [{capture, none}])).

tron_troff_trace_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 TRON", S0),
    {S2, _} = erlbasic_interp:handle_input("20 PRINT \"A\"", S1),
    {S3, _} = erlbasic_interp:handle_input("30 TROFF", S2),
    {S4, _} = erlbasic_interp:handle_input("40 PRINT \"B\"", S3),
    {S5, _} = erlbasic_interp:handle_input("50 END", S4),
    {_S6, Output} = erlbasic_interp:handle_input("RUN", S5),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "\\[20\\]", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "\\[30\\]", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "\\[40\\]", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "A", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "B", [{capture, none}])).

tron_troff_immediate_toggle_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 PRINT \"X\"", S0),
    {S2, _} = erlbasic_interp:handle_input("20 END", S1),

    {S3, _} = erlbasic_interp:handle_input("TRON", S2),
    {S4, Output1} = erlbasic_interp:handle_input("RUN", S3),
    Text1 = lists:flatten(Output1),
    ?assertEqual(match, re:run(Text1, "\\[10\\]", [{capture, none}])),
    ?assertEqual(match, re:run(Text1, "\\[20\\]", [{capture, none}])),

    {S5, _} = erlbasic_interp:handle_input("TROFF", S4),
    {_S6, Output2} = erlbasic_interp:handle_input("RUN", S5),
    Text2 = lists:flatten(Output2),
    ?assertEqual(nomatch, re:run(Text2, "\\[10\\]", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text2, "\\[20\\]", [{capture, none}])).

pos_immediate_print_column_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, Out1} = erlbasic_interp:handle_input("PRINT POS(0);", S0),
    ?assertEqual("1", lists:flatten(Out1)),
    {_S2, Out2} = erlbasic_interp:handle_input("PRINT POS(0)", S1),
    ?assertEqual("2\r\n", lists:flatten(Out2)).

%% =============================================================================
%% Security: path traversal and file channel limit tests
%% =============================================================================

%% OPEN with an absolute path must be rejected with TYPE MISMATCH ERROR.
open_absolute_path_rejected_test() ->
    AbsPath = case os:type() of
        {win32, _} -> "C:/evil/file.txt";
        _          -> "/etc/passwd"
    end,
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 OPEN \"" ++ AbsPath ++ "\" FOR INPUT AS #1", S0),
    {S2, _} = erlbasic_interp:handle_input("20 END", S1),
    {_, Output} = erlbasic_interp:handle_input("RUN", S2),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "ILLEGAL FILE NAME", [{capture, none}])).

%% OPEN with a ".." component must be rejected with ILLEGAL FILE NAME.
open_dotdot_path_rejected_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 OPEN \"../escape.txt\" FOR INPUT AS #1", S0),
    {S2, _} = erlbasic_interp:handle_input("20 END", S1),
    {_, Output} = erlbasic_interp:handle_input("RUN", S2),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "ILLEGAL FILE NAME", [{capture, none}])).

%% Opening a 16th file channel must be rejected with ILLEGAL FUNCTION CALL.
open_too_many_channels_test() ->
    S0 = erlbasic_interp:new_state(),
    %% Load 15 OPEN statements (FOR OUTPUT so no pre-existing file is needed)
    %% then attempt a 16th on a different channel.
    Lines = [
        {10,  "OPEN \"sec_ch01.tmp\" FOR OUTPUT AS #1"},
        {20,  "OPEN \"sec_ch02.tmp\" FOR OUTPUT AS #2"},
        {30,  "OPEN \"sec_ch03.tmp\" FOR OUTPUT AS #3"},
        {40,  "OPEN \"sec_ch04.tmp\" FOR OUTPUT AS #4"},
        {50,  "OPEN \"sec_ch05.tmp\" FOR OUTPUT AS #5"},
        {60,  "OPEN \"sec_ch06.tmp\" FOR OUTPUT AS #6"},
        {70,  "OPEN \"sec_ch07.tmp\" FOR OUTPUT AS #7"},
        {80,  "OPEN \"sec_ch08.tmp\" FOR OUTPUT AS #8"},
        {90,  "OPEN \"sec_ch09.tmp\" FOR OUTPUT AS #9"},
        {100, "OPEN \"sec_ch10.tmp\" FOR OUTPUT AS #10"},
        {110, "OPEN \"sec_ch11.tmp\" FOR OUTPUT AS #11"},
        {120, "OPEN \"sec_ch12.tmp\" FOR OUTPUT AS #12"},
        {130, "OPEN \"sec_ch13.tmp\" FOR OUTPUT AS #13"},
        {140, "OPEN \"sec_ch14.tmp\" FOR OUTPUT AS #14"},
        {150, "OPEN \"sec_ch15.tmp\" FOR OUTPUT AS #15"},
        {160, "OPEN \"sec_ch16.tmp\" FOR OUTPUT AS #16"},
        {170, "PRINT \"SHOULD NOT REACH\""}
    ],
    Loaded = lists:foldl(fun({LineNo, Stmt}, Acc) ->
        {Next, _} = erlbasic_interp:handle_input(
            integer_to_list(LineNo) ++ " " ++ Stmt, Acc),
        Next
    end, S0, Lines),
    {_, Output} = erlbasic_interp:handle_input("RUN", Loaded),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "ILLEGAL FUNCTION CALL", [{capture, none}])),
    ?assertEqual(nomatch, re:run(Text, "SHOULD NOT REACH", [{capture, none}])).

case_insensitive_program_filename_test() ->
    TempDir = temp_dir(),
    OldHome = os:getenv("HOME"),
    OldUserProfile = os:getenv("USERPROFILE"),
    UserDir = filename:join([TempDir, "ErlUsers", "88_9"]),
    FilePath = filename:join(UserDir, "HOME.BAS"),
    try
        true = os:putenv("HOME", TempDir),
        true = os:putenv("USERPROFILE", TempDir),
        erlang:put(erlbasic_ppn, {88, 9}),
        {ok, _} = erlbasic_storage:ensure_user_dir(),
        ok = file:write_file(FilePath, <<"10 PRINT \"HELLO\"\n">>),
        ?assertMatch({ok, _}, erlbasic_storage:read_program("home.bas")),
        ok = erlbasic_storage:delete_program("home.bas"),
        ?assertEqual({error, enoent}, erlbasic_storage:read_program("HOME.BAS"))
    after
        erlang:erase(erlbasic_ppn),
        restore_env("HOME", OldHome),
        restore_env("USERPROFILE", OldUserProfile),
        file:delete(FilePath),
        file:del_dir(UserDir),
        file:del_dir(filename:join(TempDir, "ErlUsers")),
        file:del_dir(TempDir)
    end.

homepage_render_home_publish_sections_regression_test() ->
    TempDir = temp_dir(),
    OldHome = os:getenv("HOME"),
    OldUserProfile = os:getenv("USERPROFILE"),
    OldHomepageCacheDir = application:get_env(erlbasic, homepage_cache_dir),
    CachePath = filename:join([TempDir, "home_cache", "88_9", ".home_cache"]),
    HomeBas = <<
        "10 COLOR 14,0\n",
        "20 PRINT \"FIRST PANEL\"\n",
        "30 HOME PUBLISH\n",
        "40 COLOR 11,0\n",
        "50 PRINT \"SECOND PANEL\"\n",
        "60 HOME PUBLISH\n",
        "70 END\n"
    >>,
    try
        true = os:putenv("HOME", TempDir),
        true = os:putenv("USERPROFILE", TempDir),
        ok = application:set_env(erlbasic, homepage_cache_dir, filename:join(TempDir, "home_cache")),
        BodyBin = erlbasic_homepage_handler:render_home_bas_html("alice", "Alice", 88, 9, HomeBas),
        Body = binary_to_list(BodyBin),
        ?assertEqual(match, re:run(Body, "FIRST PANEL", [{capture, none}])),
        ?assertEqual(match, re:run(Body, "SECOND PANEL", [{capture, none}])),
        ?assertEqual(match, re:run(Body, "home-section", [{capture, none}])),
        ?assertEqual(nomatch, re:run(Body, "\\e\\[", [{capture, none}])),
        ?assertEqual(nomatch, re:run(Body, "\\[Press any key to continue\\]", [{capture, none}]))
    after
        restore_env("HOME", OldHome),
        restore_env("USERPROFILE", OldUserProfile),
        case OldHomepageCacheDir of
            undefined -> application:unset_env(erlbasic, homepage_cache_dir);
            {ok, Dir} -> application:set_env(erlbasic, homepage_cache_dir, Dir)
        end,
        file:delete(CachePath),
        file:del_dir(filename:join([TempDir, "home_cache", "88_9"])),
        file:del_dir(filename:join(TempDir, "home_cache")),
        file:del_dir(TempDir)
    end.

homepage_render_text_gfx_text_sections_regression_test() ->
    TempDir = temp_dir(),
    OldHome = os:getenv("HOME"),
    OldUserProfile = os:getenv("USERPROFILE"),
    OldHomepageCacheDir = application:get_env(erlbasic, homepage_cache_dir),
    CachePath = filename:join([TempDir, "home_cache", "88_9", ".home_cache"]),
    HomeBas = <<
        "10 COLOR 14,0\n",
        "20 PRINT \"TEXT PANEL ONE\"\n",
        "30 HOME PUBLISH\n",
        "40 HGR\n",
        "50 RECT (10,10)-(60,60), 12\n",
        "60 LINE (0,0)-(799,599), 15\n",
        "70 HOME PUBLISH\n",
        "80 COLOR 11,0\n",
        "90 PRINT \"TEXT PANEL TWO\"\n",
        "100 HOME PUBLISH\n",
        "110 END\n"
    >>,
    try
        true = os:putenv("HOME", TempDir),
        true = os:putenv("USERPROFILE", TempDir),
        ok = application:set_env(erlbasic, homepage_cache_dir, filename:join(TempDir, "home_cache")),
        BodyBin = erlbasic_homepage_handler:render_home_bas_html("alice", "Alice", 88, 9, HomeBas),
        Body = binary_to_list(BodyBin),
        Text1Pos = string:str(Body, "TEXT PANEL ONE"),
        SvgPos = string:str(Body, "<svg"),
        Text2Pos = string:str(Body, "TEXT PANEL TWO"),
        ?assert(Text1Pos > 0),
        ?assert(SvgPos > Text1Pos),
        ?assert(Text2Pos > SvgPos),
        ?assertEqual(match, re:run(Body, "home-section-gfx", [{capture, none}])),
        ?assertEqual(nomatch, re:run(Body, "\\e\\[", [{capture, none}])),
        ?assertEqual(nomatch, re:run(Body, "\\[Press any key to continue\\]", [{capture, none}]))
    after
        restore_env("HOME", OldHome),
        restore_env("USERPROFILE", OldUserProfile),
        case OldHomepageCacheDir of
            undefined -> application:unset_env(erlbasic, homepage_cache_dir);
            {ok, Dir} -> application:set_env(erlbasic, homepage_cache_dir, Dir)
        end,
        file:delete(CachePath),
        file:del_dir(filename:join([TempDir, "home_cache", "88_9"])),
        file:del_dir(filename:join(TempDir, "home_cache")),
        file:del_dir(TempDir)
    end.

homepage_render_legacy_text_cache_is_ignored_test() ->
    TempDir = temp_dir(),
    OldHome = os:getenv("HOME"),
    OldUserProfile = os:getenv("USERPROFILE"),
    OldHomepageCacheDir = application:get_env(erlbasic, homepage_cache_dir),
    HomeBas = <<
        "10 PRINT \"FRESH PANEL\"\n",
        "20 HOME PUBLISH\n",
        "30 END\n"
    >>,
    CachePath = filename:join([TempDir, "home_cache", "88_9", ".home_cache"]),
    FileHash = crypto:hash(sha256, HomeBas),
    LegacyOutput = "\e[31mLEGACY TEXT\e[0m",
    LegacyTerm = {FileHash, erlang:system_time(second), infinity, LegacyOutput},
    try
        true = os:putenv("HOME", TempDir),
        true = os:putenv("USERPROFILE", TempDir),
        ok = application:set_env(erlbasic, homepage_cache_dir, filename:join(TempDir, "home_cache")),
        ok = filelib:ensure_dir(CachePath),
        ok = file:write_file(CachePath, term_to_binary(LegacyTerm)),
        BodyBin = erlbasic_homepage_handler:render_home_bas_html("alice", "Alice", 88, 9, HomeBas),
        Body = binary_to_list(BodyBin),
        ?assertEqual(match, re:run(Body, "FRESH PANEL", [{capture, none}])),
        ?assertEqual(nomatch, re:run(Body, "LEGACY TEXT", [{capture, none}])),
        ?assertEqual(nomatch, re:run(Body, "\\e\\[", [{capture, none}])),
        {ok, NewCacheBin} = file:read_file(CachePath),
        {FileHash, _CachedAt, _TTL, CachedSections} = binary_to_term(NewCacheBin, [safe]),
        ?assert(is_list(CachedSections)),
        ?assert(lists:any(fun({text, _}) -> true; (_) -> false end, CachedSections))
    after
        restore_env("HOME", OldHome),
        restore_env("USERPROFILE", OldUserProfile),
        case OldHomepageCacheDir of
            undefined -> application:unset_env(erlbasic, homepage_cache_dir);
            {ok, Dir} -> application:set_env(erlbasic, homepage_cache_dir, Dir)
        end,
        file:delete(CachePath),
        file:del_dir(filename:join([TempDir, "home_cache", "88_9"])),
        file:del_dir(filename:join(TempDir, "home_cache")),
        file:del_dir(TempDir)
    end.

homepage_render_malformed_cache_is_ignored_test() ->
    TempDir = temp_dir(),
    OldHome = os:getenv("HOME"),
    OldUserProfile = os:getenv("USERPROFILE"),
    OldHomepageCacheDir = application:get_env(erlbasic, homepage_cache_dir),
    HomeBas = <<
        "10 PRINT \"REBUILT\"\n",
        "20 HOME PUBLISH\n",
        "30 END\n"
    >>,
    CachePath = filename:join([TempDir, "home_cache", "88_9", ".home_cache"]),
    try
        true = os:putenv("HOME", TempDir),
        true = os:putenv("USERPROFILE", TempDir),
        ok = application:set_env(erlbasic, homepage_cache_dir, filename:join(TempDir, "home_cache")),
        ok = filelib:ensure_dir(CachePath),
        ok = file:write_file(CachePath, <<"not-a-valid-term">>),
        BodyBin = erlbasic_homepage_handler:render_home_bas_html("alice", "Alice", 88, 9, HomeBas),
        Body = binary_to_list(BodyBin),
        ?assertEqual(match, re:run(Body, "REBUILT", [{capture, none}])),
        ?assertEqual(nomatch, re:run(Body, "not-a-valid-term", [{capture, none}]))
    after
        restore_env("HOME", OldHome),
        restore_env("USERPROFILE", OldUserProfile),
        case OldHomepageCacheDir of
            undefined -> application:unset_env(erlbasic, homepage_cache_dir);
            {ok, Dir} -> application:set_env(erlbasic, homepage_cache_dir, Dir)
        end,
        file:delete(CachePath),
        file:del_dir(filename:join([TempDir, "home_cache", "88_9"])),
        file:del_dir(filename:join(TempDir, "home_cache")),
        file:del_dir(TempDir)
    end.

s3_config_loads_private_file_test() ->
    TempDir = temp_dir(),
    ConfigPath = filename:join(TempDir, ".s3.config"),
    OldConfigFile = application:get_env(erlbasic, storage_s3_config_file),
    OldEndpoint = application:get_env(erlbasic, storage_s3_endpoint),
    OldBucket = application:get_env(erlbasic, storage_s3_bucket),
    OldPrefix = application:get_env(erlbasic, storage_s3_prefix),
    OldRegion = application:get_env(erlbasic, storage_s3_region),
    OldAccessKey = application:get_env(erlbasic, storage_s3_access_key_id),
    OldSecretKey = application:get_env(erlbasic, storage_s3_secret_access_key),
    try
        ok = file:make_dir(TempDir),
        ok = file:write_file(ConfigPath, <<
            "[\n",
            "  {storage_s3_endpoint, \"https://minio.internal:9000\"},\n",
            "  {storage_s3_bucket, \"erlbasic-prod\"},\n",
            "  {storage_s3_prefix, \"tenant-a/users/\"},\n",
            "  {storage_s3_region, \"us-east-1\"},\n",
            "  {storage_s3_access_key_id, \"ACCESS123\"},\n",
            "  {storage_s3_secret_access_key, \"SECRET456\"}\n",
            "].\n"
        >>),
        ok = application:set_env(erlbasic, storage_s3_config_file, ConfigPath),
        application:unset_env(erlbasic, storage_s3_endpoint),
        application:unset_env(erlbasic, storage_s3_bucket),
        application:unset_env(erlbasic, storage_s3_prefix),
        application:unset_env(erlbasic, storage_s3_region),
        application:unset_env(erlbasic, storage_s3_access_key_id),
        application:unset_env(erlbasic, storage_s3_secret_access_key),
        ok = erlbasic_s3_config:load(),
        ?assertEqual({ok, "https://minio.internal:9000"}, application:get_env(erlbasic, storage_s3_endpoint)),
        ?assertEqual({ok, "erlbasic-prod"}, application:get_env(erlbasic, storage_s3_bucket)),
        ?assertEqual({ok, "tenant-a/users/"}, application:get_env(erlbasic, storage_s3_prefix)),
        ?assertEqual({ok, "us-east-1"}, application:get_env(erlbasic, storage_s3_region)),
        ?assertEqual({ok, "ACCESS123"}, application:get_env(erlbasic, storage_s3_access_key_id)),
        ?assertEqual({ok, "SECRET456"}, application:get_env(erlbasic, storage_s3_secret_access_key))
    after
        restore_app_env(storage_s3_config_file, OldConfigFile),
        restore_app_env(storage_s3_endpoint, OldEndpoint),
        restore_app_env(storage_s3_bucket, OldBucket),
        restore_app_env(storage_s3_prefix, OldPrefix),
        restore_app_env(storage_s3_region, OldRegion),
        restore_app_env(storage_s3_access_key_id, OldAccessKey),
        restore_app_env(storage_s3_secret_access_key, OldSecretKey),
        file:delete(ConfigPath),
        file:del_dir(TempDir)
    end.

s3_config_missing_file_is_ok_test() ->
    TempDir = temp_dir(),
    MissingPath = filename:join(TempDir, ".missing-s3.config"),
    OldConfigFile = application:get_env(erlbasic, storage_s3_config_file),
    try
        ok = file:make_dir(TempDir),
        ok = application:set_env(erlbasic, storage_s3_config_file, MissingPath),
        ?assertEqual(ok, erlbasic_s3_config:load())
    after
        restore_app_env(storage_s3_config_file, OldConfigFile),
        file:del_dir(TempDir)
    end.

s3_fileio_output_print_close_uploads_test() ->
    OldBackend = application:get_env(erlbasic, storage_backend),
    OldS3Module = application:get_env(erlbasic, storage_s3_module),
    try
        ok = erlbasic_storage_s3_test_backend:reset(),
        ok = application:set_env(erlbasic, storage_backend, s3),
        ok = application:set_env(erlbasic, storage_s3_module, erlbasic_storage_s3_test_backend),
        S0 = erlbasic_interp:new_state(),
        {S1, Out1} = erlbasic_interp:handle_input("OPEN \"S3CHAN.DAT\" FOR OUTPUT AS #1", S0),
        ?assertEqual("OK\r\n", lists:flatten(Out1)),
        {S2, Out2} = erlbasic_interp:handle_input("PRINT #1, \"HELLO S3\"", S1),
        ?assertEqual("OK\r\n", lists:flatten(Out2)),
        {_S3, Out3} = erlbasic_interp:handle_input("CLOSE #1", S2),
        ?assertEqual("OK\r\n", lists:flatten(Out3)),
        ?assertEqual({ok, <<"HELLO S3\r\n">>}, erlbasic_storage_s3_test_backend:fetch("default/S3CHAN.DAT"))
    after
        restore_app_env(storage_backend, OldBackend),
        restore_app_env(storage_s3_module, OldS3Module),
        ok = erlbasic_storage_s3_test_backend:reset()
    end.

s3_fileio_input_reads_seeded_content_test() ->
    OldBackend = application:get_env(erlbasic, storage_backend),
    OldS3Module = application:get_env(erlbasic, storage_s3_module),
    try
        ok = erlbasic_storage_s3_test_backend:reset(),
        ok = application:set_env(erlbasic, storage_backend, s3),
        ok = application:set_env(erlbasic, storage_s3_module, erlbasic_storage_s3_test_backend),
        ok = erlbasic_storage_s3_test_backend:seed("default/INCHAN.DAT", <<"alpha\r\n">>),
        S0 = erlbasic_interp:new_state(),
        {S1, Out1} = erlbasic_interp:handle_input("OPEN \"INCHAN.DAT\" FOR INPUT AS #1", S0),
        ?assertEqual("OK\r\n", lists:flatten(Out1)),
        {S2, Out2} = erlbasic_interp:handle_input("INPUT #1, A$", S1),
        ?assertEqual("OK\r\n", lists:flatten(Out2)),
        {S3, Out3} = erlbasic_interp:handle_input("CLOSE #1", S2),
        ?assertEqual("OK\r\n", lists:flatten(Out3)),
        {_S4, Out4} = erlbasic_interp:handle_input("PRINT A$", S3),
        ?assertEqual(match, re:run(lists:flatten(Out4), "alpha", [{capture, none}]))
    after
        restore_app_env(storage_backend, OldBackend),
        restore_app_env(storage_s3_module, OldS3Module),
        ok = erlbasic_storage_s3_test_backend:reset()
    end.

s3_fileio_close_reports_upload_failure_test() ->
    OldBackend = application:get_env(erlbasic, storage_backend),
    OldS3Module = application:get_env(erlbasic, storage_s3_module),
    try
        ok = erlbasic_storage_s3_test_backend:reset(),
        ok = application:set_env(erlbasic, storage_backend, s3),
        ok = application:set_env(erlbasic, storage_s3_module, erlbasic_storage_s3_test_backend),
        ok = erlbasic_storage_s3_test_backend:set_fail_writes(true),
        S0 = erlbasic_interp:new_state(),
        {S1, _} = erlbasic_interp:handle_input("OPEN \"FAILCLOSE.DAT\" FOR OUTPUT AS #1", S0),
        {S2, _} = erlbasic_interp:handle_input("PRINT #1, \"WILL FAIL\"", S1),
        {_S3, CloseOutput} = erlbasic_interp:handle_input("CLOSE #1", S2),
        ?assertEqual(match, re:run(lists:flatten(CloseOutput), "ILLEGAL FUNCTION CALL", [{capture, none}]))
    after
        restore_app_env(storage_backend, OldBackend),
        restore_app_env(storage_s3_module, OldS3Module),
        ok = erlbasic_storage_s3_test_backend:reset()
    end.

dir_groups_personal_and_example_files_test() ->
    TempDir = temp_dir(),
    OldHome = os:getenv("HOME"),
    OldUserProfile = os:getenv("USERPROFILE"),
    UserDir = filename:join([TempDir, "ErlUsers", "88_9"]),
    FilePath = filename:join(UserDir, "dirtest.bas"),
    try
        true = os:putenv("HOME", TempDir),
        true = os:putenv("USERPROFILE", TempDir),
        erlang:put(erlbasic_ppn, {88, 9}),
        {ok, _} = erlbasic_storage:ensure_user_dir(),
        ok = file:write_file(FilePath, <<"10 PRINT \"MINE\"\n">>),
        State0 = erlbasic_interp:new_state(),
        {_State1, Output} = erlbasic_interp:handle_input("DIR", State0),
        Text = lists:flatten(Output),
        LowerText = string:to_lower(Text),
        UserSectionPos = string:str(Text, "Your files:"),
        UserFilePos = string:str(LowerText, "dirtest"),
        ExamplesSectionPos = string:str(Text, "Shared examples:"),
        ExampleFilePos = string:str(LowerText, "life"),
        ?assertEqual(match, re:run(Text, "Your files:", [{capture, none}])),
        ?assertEqual(match, re:run(Text, "Shared examples:", [{capture, none}])),
        ?assert(UserSectionPos > 0),
        ?assert(UserFilePos > UserSectionPos),
        ?assert(ExamplesSectionPos > UserFilePos),
        ?assert(ExampleFilePos > ExamplesSectionPos),
        ?assertEqual(match, re:run(Text, "Total of", [{capture, none}]))
    after
        erlang:erase(erlbasic_ppn),
        restore_env("HOME", OldHome),
        restore_env("USERPROFILE", OldUserProfile),
        file:delete(FilePath),
        file:del_dir(UserDir),
        file:del_dir(filename:join(TempDir, "ErlUsers")),
        file:del_dir(TempDir)
    end.

%% SLEEP with a negative value must clamp to zero and complete immediately
%% (tests the max(0,...) half of the cap expression).
sleep_negative_clamped_test() ->
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 PRINT \"BEFORE\"", S0),
    {S2, _} = erlbasic_interp:handle_input("20 SLEEP -5", S1),
    {S3, _} = erlbasic_interp:handle_input("30 PRINT \"AFTER\"", S2),
    {S4, _} = erlbasic_interp:handle_input("40 END", S3),
    {_, Output} = erlbasic_interp:handle_input("RUN", S4),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "BEFORE", [{capture, none}])),
    ?assertEqual(match, re:run(Text, "AFTER",  [{capture, none}])).

ws_down_normal_is_not_reported_as_crash_test() ->
    Pid = self(),
    State = #{conn => Pid},
    ?assertEqual(
        {stop, State},
        erlbasic_ws_handler:websocket_info({'DOWN', make_ref(), process, Pid, normal}, State)
    ).

ws_down_error_is_reported_as_crash_test() ->
    Pid = self(),
    State = #{conn => Pid},
    {reply, {text, Utf8}, _} = erlbasic_ws_handler:websocket_info({'DOWN', make_ref(), process, Pid, badarg}, State),
    Text = binary_to_list(Utf8),
    ?assertEqual(match, re:run(Text, "Interpreter crashed - badarg", [{capture, none}])).

%% -------------------------------------------------------------------------
%% MML parser tests
%% -------------------------------------------------------------------------

mml_empty_string_test() ->
    ?assertEqual({ok, [], unchanged}, erlbasic_mml:parse("")).

mml_single_note_test() ->
    {ok, [{Hz, _Play, Total}], unchanged} = erlbasic_mml:parse("A"),
    %% A4 = 440 Hz, default L4 at T120 = 500 ms
    ?assertEqual(440, Hz),
    ?assertEqual(500, Total).

mml_sharp_flat_test() ->
    {ok, [{HzSharp, _, _}], unchanged} = erlbasic_mml:parse("A#"),
    {ok, [{HzFlat,  _, _}], unchanged} = erlbasic_mml:parse("B-"),
    %% A# and B- (B-flat) are enharmonic equivalents — same pitch
    ?assertEqual(HzSharp, HzFlat),
    ?assert(HzSharp > 440).

mml_octave_change_test() ->
    {ok, [{Hz4, _, _}], unchanged} = erlbasic_mml:parse("O4 A"),
    {ok, [{Hz5, _, _}], unchanged} = erlbasic_mml:parse("O5 A"),
    ?assertEqual(Hz4 * 2, Hz5).

mml_octave_up_down_test() ->
    {ok, [{HzBase, _, _}], unchanged} = erlbasic_mml:parse("O4 A"),
    {ok, [{HzUp,   _, _}], unchanged} = erlbasic_mml:parse("O4 > A"),
    {ok, [{HzDown, _, _}], unchanged} = erlbasic_mml:parse("O4 < A"),
    ?assertEqual(HzBase * 2, HzUp),
    %% Octave below is half frequency (allow 1 Hz rounding)
    ?assert(abs(HzDown * 2 - HzBase) =< 1).

mml_length_test() ->
    {ok, [{_, _, WholeMs}], unchanged} = erlbasic_mml:parse("L1 A"),
    {ok, [{_, _, HalfMs}],  unchanged} = erlbasic_mml:parse("L2 A"),
    ?assertEqual(WholeMs, HalfMs * 2).

mml_dotted_length_test() ->
    {ok, [{_, _, NormalMs}], unchanged} = erlbasic_mml:parse("L4 A"),
    {ok, [{_, _, DottedMs}], unchanged} = erlbasic_mml:parse("L4 A."),
    ?assertEqual(round(NormalMs * 1.5), DottedMs).

mml_tempo_test() ->
    {ok, [{_, _, Slow}], unchanged} = erlbasic_mml:parse("T60 A"),
    {ok, [{_, _, Fast}], unchanged} = erlbasic_mml:parse("T120 A"),
    ?assertEqual(Slow, Fast * 2).

mml_rest_test() ->
    {ok, [{0, 0, Total}], unchanged} = erlbasic_mml:parse("P4"),
    ?assert(Total > 0).

mml_note_number_test() ->
    %% N37 = MIDI 60 = C4 = 262 Hz
    {ok, [{Hz, _, _}], unchanged} = erlbasic_mml:parse("N37"),
    ?assert(abs(Hz - 262) =< 1).

mml_rest_note_number_test() ->
    {ok, [{0, 0, _Total}], unchanged} = erlbasic_mml:parse("N0").

mml_multiple_notes_test() ->
    {ok, Notes, unchanged} = erlbasic_mml:parse("CDEFGAB"),
    ?assertEqual(7, length(Notes)).

mml_background_mode_test() ->
    {ok, _Notes, background} = erlbasic_mml:parse("MB A"),
    {ok, _Notes2, foreground} = erlbasic_mml:parse("MB A MF").

mml_articulation_test() ->
    {ok, [{_HzN, PlayN, TotalN}], unchanged} = erlbasic_mml:parse("MN A"),
    {ok, [{_HzL, PlayL, TotalL}], unchanged} = erlbasic_mml:parse("ML A"),
    {ok, [{_HzS, PlayS, TotalS}], unchanged} = erlbasic_mml:parse("MS A"),
    ?assertEqual(TotalN, TotalL),        %% total duration is always the same
    ?assertEqual(TotalN, TotalS),
    ?assert(PlayL > PlayN),              %% legato: full duration played
    ?assert(PlayN > PlayS).             %% staccato: shorter than normal

%% -------------------------------------------------------------------------
%% PLAY parser / runtime tests (non-WebSocket path)
%% -------------------------------------------------------------------------

play_stmt_parses_test() ->
    ?assertEqual(ok, erlbasic_parser:validate_program_line("PLAY \"CDEFGAB\"")).

play_stmt_invalid_test() ->
    %% Missing expression — must be a syntax error
    ?assertEqual(error, erlbasic_parser:validate_program_line("PLAY")).

on_play_gosub_parses_test() ->
    ?assertEqual(ok, erlbasic_parser:validate_program_line("ON PLAY(5) GOSUB 100")).

on_timer_gosub_parses_test() ->
    ?assertEqual(ok, erlbasic_parser:validate_program_line("ON TIMER(0.05) GOSUB 100")).

play_is_reserved_variable_test() ->
    ?assertEqual({error, reserved_word},
        erlbasic_parser:validate_program_line("LET PLAY = 1")).

play_tty_error_test() ->
    %% On a non-WebSocket connection PLAY reports an error
    erlang:put(erlbasic_conn_type, tty),
    erlang:put(erlbasic_ppn, {1, 1}),
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("PLAY \"C\"", S0),
    erlang:erase(erlbasic_conn_type),
    erlang:erase(erlbasic_ppn),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "NOT SUPPORTED ON TTY", [{capture, none}])).

play_function_zero_on_tty_test() ->
    %% PLAY(n) should return 0 when there is no background queue
    erlang:put(erlbasic_conn_type, tty),
    erlang:put(erlbasic_ppn, {1, 1}),
    erlang:erase(erlbasic_play_schedule),
    S0 = erlbasic_interp:new_state(),
    {_S1, Output} = erlbasic_interp:handle_input("PRINT PLAY(0)", S0),
    erlang:erase(erlbasic_conn_type),
    erlang:erase(erlbasic_ppn),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "^0", [{capture, none}])).

on_play_gosub_sets_state_test() ->
    %% Verify ON PLAY(n) GOSUB stores handler in state without executing
    erlang:put(erlbasic_conn_type, tty),
    erlang:put(erlbasic_ppn, {1, 1}),
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("ON PLAY(3) GOSUB 100", S0),
    erlang:erase(erlbasic_conn_type),
    erlang:erase(erlbasic_ppn),
    ?assertMatch({_, _}, S1#state.on_play_gosub).

on_timer_gosub_sets_state_test() ->
    erlang:put(erlbasic_conn_type, tty),
    erlang:put(erlbasic_ppn, {1, 1}),
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("ON TIMER(0.05) GOSUB 100", S0),
    erlang:erase(erlbasic_conn_type),
    erlang:erase(erlbasic_ppn),
    ?assertMatch({_, _}, S1#state.on_timer_gosub).

on_play_gosub_cleared_by_end_test() ->
    erlang:put(erlbasic_conn_type, tty),
    erlang:put(erlbasic_ppn, {1, 1}),
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("ON PLAY(3) GOSUB 100", S0),
    %% Run a tiny program with END — state should be cleared
    {S2, _} = erlbasic_interp:handle_input("10 END", S1),
    {S3, _} = erlbasic_interp:handle_input("RUN", S2),
    erlang:erase(erlbasic_conn_type),
    erlang:erase(erlbasic_ppn),
    ?assertEqual(undefined, S3#state.on_play_gosub),
    ?assertEqual(-1, S3#state.on_play_return_depth).

on_timer_gosub_cleared_by_end_test() ->
    erlang:put(erlbasic_conn_type, tty),
    erlang:put(erlbasic_ppn, {1, 1}),
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("ON TIMER(0.05) GOSUB 100", S0),
    {S2, _} = erlbasic_interp:handle_input("10 END", S1),
    {S3, _} = erlbasic_interp:handle_input("RUN", S2),
    erlang:erase(erlbasic_conn_type),
    erlang:erase(erlbasic_ppn),
    ?assertEqual(undefined, S3#state.on_timer_gosub),
    ?assertEqual(-1, S3#state.on_timer_return_depth).

on_timer_gosub_fires_during_run_test() ->
    erlang:put(erlbasic_conn_type, tty),
    erlang:put(erlbasic_ppn, {1, 1}),
    S0 = erlbasic_interp:new_state(),
    {S1, _} = erlbasic_interp:handle_input("10 T%=0", S0),
    {S2, _} = erlbasic_interp:handle_input("20 ON TIMER(0.02) GOSUB 100", S1),
    {S3, _} = erlbasic_interp:handle_input("30 SLEEP 0.05", S2),
    {S4, _} = erlbasic_interp:handle_input("40 IF T%>0 THEN PRINT \"FIRED\"", S3),
    {S5, _} = erlbasic_interp:handle_input("50 END", S4),
    {S6, _} = erlbasic_interp:handle_input("100 T%=T%+1", S5),
    {S7, _} = erlbasic_interp:handle_input("110 RETURN", S6),
    {_S8, Output} = erlbasic_interp:handle_input("RUN", S7),
    erlang:erase(erlbasic_conn_type),
    erlang:erase(erlbasic_ppn),
    Text = lists:flatten(Output),
    ?assertEqual(match, re:run(Text, "FIRED", [{capture, none}])).

normalize_char_input_space_test() ->
    %% SPACE (ASCII 32) must survive normalization so GET K$ can match K$=" ".
    %% The browser sends key+newline; normalize_char_input strips only CR/LF.
    ?assertEqual(" ", erlbasic_conn:normalize_char_input(<<" \n">>)),
    ?assertEqual("A", erlbasic_conn:normalize_char_input(<<"A\n">>)),
    ?assertEqual("",  erlbasic_conn:normalize_char_input(<<"\n">>)).

tty_ctrl_c_interrupts_running_program_test() ->
    Dir = accounts_setup(),
    WdHandle = ensure_mem_watchdog_started(),
    Port = 20000 + (erlang:unique_integer([positive]) rem 10000),
    OldPort = application:get_env(erlbasic, port),
    try
        ok = application:set_env(erlbasic, port, Port),
        {ok, ConnSupPid} = erlbasic_conn_sup:start_link(),
        unlink(ConnSupPid),
        {ok, ListenerPid} = erlbasic_listener:start_link(),
        unlink(ListenerPid),
        try
            {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port,
                [binary, {packet, raw}, {active, false}], 5000),
            try
                _ = tty_tcp_recv_available(Socket, 200),
                ok = gen_tcp:send(Socket, <<"HELLO 1,1;SYSTEM\r\n">>),
                _ = tty_tcp_recv_available(Socket, 300),
                ok = gen_tcp:send(Socket, <<"10 A=A+1\r\n">>),
                _ = tty_tcp_recv_available(Socket, 100),
                ok = gen_tcp:send(Socket, <<"20 GOTO 10\r\n">>),
                _ = tty_tcp_recv_available(Socket, 100),
                ok = gen_tcp:send(Socket, <<"RUN\r\n">>),
                _ = tty_tcp_recv_available(Socket, 150),
                ok = gen_tcp:send(Socket, <<3>>),
                Text = binary_to_list(tty_tcp_recv_available(Socket, 400)),
                ?assertEqual(match, re:run(Text, "BREAK", [{capture, none}]))
            after
                gen_tcp:close(Socket)
            end
        after
            stop_process(ListenerPid),
            stop_process(ConnSupPid)
        end
    after
        restore_app_env(port, OldPort),
        cleanup_mem_watchdog(WdHandle),
        accounts_teardown(Dir)
    end.

tty_tcp_recv_available(Socket, WaitMs) ->
    receive after WaitMs -> ok end,
    tty_tcp_recv_available_loop(Socket, <<>>).

tty_tcp_recv_available_loop(Socket, Acc) ->
    case gen_tcp:recv(Socket, 0, 100) of
        {ok, Bin} ->
            tty_tcp_recv_available_loop(Socket, <<Acc/binary, Bin/binary>>);
        {error, timeout} ->
            Acc;
        {error, closed} ->
            Acc
    end.

stop_process(Pid) when is_pid(Pid) ->
    Ref = erlang:monitor(process, Pid),
    exit(Pid, shutdown),
    receive
        {'DOWN', Ref, process, Pid, _Reason} -> ok
    after 1000 ->
        ok
    end.

restore_env(Name, false) ->
    true = os:unsetenv(Name),
    ok;
restore_env(Name, Value) ->
    true = os:putenv(Name, Value),
    ok.

restore_app_env(Key, undefined) ->
    application:unset_env(erlbasic, Key),
    ok;
restore_app_env(Key, {ok, Value}) ->
    application:set_env(erlbasic, Key, Value),
    ok.

collect_output_messages() ->
    collect_output_messages([]).

collect_output_messages(Acc) ->
    receive
        {output, Text} -> collect_output_messages([Text | Acc])
    after 0 ->
        lists:reverse(Acc)
    end.

ensure_mem_watchdog_started() ->
    case whereis(erlbasic_mem_watchdog) of
        undefined ->
            {ok, Pid} = erlbasic_mem_watchdog:start_link(),
            unlink(Pid),
            {started, Pid};
        Pid ->
            {existing, Pid}
    end.

cleanup_mem_watchdog({started, Pid}) ->
    Ref = erlang:monitor(process, Pid),
    exit(Pid, shutdown),
    receive
        {'DOWN', Ref, process, Pid, _Reason} -> ok
    after 1000 ->
        ok
    end;
cleanup_mem_watchdog({existing, _Pid}) ->
    ok.

start_compressed_test_listener(ListenerRef) ->
    {ok, _} = application:ensure_all_started(cowboy),
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/ws", erlbasic_ws_handler, []}
        ]}
    ]),
    case whereis(ListenerRef) of
        undefined -> ok;
        _ -> cowboy:stop_listener(ListenerRef)
    end,
    {ok, _} = cowboy:start_clear(ListenerRef,
        [{port, 0}, {nodelay, true}],
        #{env => #{dispatch => Dispatch}}),
    ok.

ws_connect_with_compression(Port) ->
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port,
        [binary, {packet, raw}, {active, false}], 5000),
    Key = cow_ws:key(),
    Request = iolist_to_binary([
        "GET /ws HTTP/1.1\r\n",
        "Host: localhost:", integer_to_list(Port), "\r\n",
        "Upgrade: websocket\r\n",
        "Connection: Upgrade\r\n",
        "Sec-WebSocket-Version: 13\r\n",
        "Sec-WebSocket-Key: ", Key, "\r\n",
        "Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits\r\n",
        "\r\n"
    ]),
    ok = gen_tcp:send(Socket, Request),
    {ok, Response} = recv_http_response(Socket, <<>>),
    {StatusLine, Headers, Rest} = parse_http_response_headers(Response),
    ?assertEqual(<<"HTTP/1.1 101 Switching Protocols">>, StatusLine),
    ?assertEqual(cow_ws:encode_key(Key), maps:get(<<"sec-websocket-accept">>, Headers)),
    ExtValue = maps:get(<<"sec-websocket-extensions">>, Headers),
    [{<<"permessage-deflate">>, Params}] = cow_http_hd:parse_sec_websocket_extensions(ExtValue),
    ?assert(lists:member(<<"server_no_context_takeover">>, Params)),
    {ok, Extensions} = cow_ws:validate_permessage_deflate(Params, #{}, #{owner => self()}),
    {Socket, Extensions, Rest}.

recv_http_response(Socket, Acc) ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        {_, _} ->
            {ok, Acc};
        nomatch ->
            case gen_tcp:recv(Socket, 0, 5000) of
                {ok, Data} -> recv_http_response(Socket, <<Acc/binary, Data/binary>>);
                Error -> Error
            end
    end.

parse_http_response_headers(Response) ->
    {HeaderBlock, Rest} = split_http_headers(Response),
    [StatusLine | HeaderLines] = binary:split(HeaderBlock, <<"\r\n">>, [global]),
    Headers = maps:from_list([
        parse_http_header_line(Line)
        || Line <- HeaderLines,
           Line =/= <<>>
    ]),
    {StatusLine, Headers, Rest}.

split_http_headers(Response) ->
    {Pos, 4} = binary:match(Response, <<"\r\n\r\n">>),
    {
        binary:part(Response, 0, Pos),
        binary:part(Response, Pos + 4, byte_size(Response) - Pos - 4)
    }.

parse_http_header_line(Line) ->
    [Name, Value] = binary:split(Line, <<": ">>),
    {string:lowercase(Name), Value}.

ws_send_text(Socket, Extensions, Text) ->
    gen_tcp:send(Socket, cow_ws:masked_frame({text, Text}, Extensions)).

ws_collect_visible_text_until(Socket, Extensions, Buffer, Predicate) ->
    ws_collect_visible_text_until(Socket, Extensions, Buffer, Predicate, <<>>, 32).

ws_collect_text_until_close(Socket, Extensions, Buffer, MaxFrames) ->
    ws_collect_text_until_close(Socket, Extensions, Buffer, <<>>, MaxFrames).

ws_collect_text_until_close(_Socket, _Extensions, Buffer, Acc, 0) ->
    {Acc, false, Buffer};
ws_collect_text_until_close(Socket, Extensions, Buffer, Acc, Remaining) ->
    {Frame, Buffer1} = ws_recv_frame(Socket, Extensions, Buffer),
    case Frame of
        {text, Payload} ->
            Acc1 = case Payload of
                <<2, _/binary>> -> Acc;
                _ -> <<Acc/binary, Payload/binary>>
            end,
            ws_collect_text_until_close(Socket, Extensions, Buffer1, Acc1, Remaining - 1);
        {close, _Code, _Payload} ->
            {Acc, true, Buffer1};
        {close, _Payload} ->
            {Acc, true, Buffer1};
        close ->
            {Acc, true, Buffer1};
        _ ->
            ws_collect_text_until_close(Socket, Extensions, Buffer1, Acc, Remaining - 1)
    end.

ws_collect_visible_text_until(_Socket, _Extensions, Buffer, _Predicate, Acc, 0) ->
    {ok, Acc, Buffer};
ws_collect_visible_text_until(Socket, Extensions, Buffer, Predicate, Acc, Remaining) ->
    case Predicate(Acc) of
        true ->
            {ok, Acc, Buffer};
        false ->
            {Frame, Buffer1} = ws_recv_frame(Socket, Extensions, Buffer),
            case Frame of
                {text, Payload} ->
                    Acc1 = case Payload of
                        <<2, _/binary>> -> Acc;
                        _ -> <<Acc/binary, Payload/binary>>
                    end,
                    ws_collect_visible_text_until(Socket, Extensions, Buffer1, Predicate, Acc1, Remaining - 1);
                {close, Code, Payload} ->
                    erlang:error({unexpected_close, Code, Payload});
                {close, Payload} ->
                    erlang:error({unexpected_close, Payload});
                close ->
                    erlang:error(unexpected_close);
                _ ->
                    ws_collect_visible_text_until(Socket, Extensions, Buffer1, Predicate, Acc, Remaining - 1)
            end
    end.

ws_recv_frame(Socket, Extensions, Buffer) ->
    case ws_try_parse_frame(Buffer, Extensions) of
        {ok, Frame, Rest} ->
            {Frame, Rest};
        more ->
            {ok, Data} = gen_tcp:recv(Socket, 0, 5000),
            ws_recv_frame(Socket, Extensions, <<Buffer/binary, Data/binary>>)
    end.

ws_try_parse_frame(Buffer, Extensions) ->
    case cow_ws:parse_header(Buffer, Extensions, undefined) of
        {Type, FragState, Rsv, Len, MaskKey, Rest} ->
            case cow_ws:parse_payload(Rest, MaskKey, 0, 0, Type, Len, FragState, Extensions, Rsv) of
                {ok, CloseCode, Payload, _Utf8State, Remaining} ->
                    {ok, cow_ws:make_frame(Type, Payload, CloseCode, FragState), Remaining};
                {ok, Payload, _Utf8State, Remaining} ->
                    {ok, cow_ws:make_frame(Type, Payload, 1000, FragState), Remaining};
                {more, _, _} ->
                    more;
                {more, _, _, _} ->
                    more;
                {error, Reason} ->
                    erlang:error({bad_ws_payload, Reason})
            end;
        more ->
            more;
        error ->
            erlang:error(bad_ws_frame)
    end.

cleanup_ws_extensions(Extensions) ->
    cleanup_ws_zstream(maps:get(inflate, Extensions, undefined)),
    cleanup_ws_zstream(maps:get(deflate, Extensions, undefined)).

cleanup_ws_zstream(undefined) ->
    ok;
cleanup_ws_zstream(false) ->
    ok;
cleanup_ws_zstream(Z) ->
    catch zlib:close(Z),
    ok.
