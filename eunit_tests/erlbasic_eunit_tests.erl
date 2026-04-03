-module(erlbasic_eunit_tests).

-include_lib("eunit/include/eunit.hrl").

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

keyword_category_intent_test() ->
    ?assert(erlbasic_keywords:is_expr_keyword("AND")),
    ?assert(erlbasic_keywords:is_expr_keyword("LEFT$")),
    ?assert(erlbasic_keywords:is_expr_keyword("TIMER")),
    ?assert(erlbasic_keywords:is_expr_keyword("STRING$")),
    ?assertNot(erlbasic_keywords:is_expr_keyword("PRINT")),
    ?assert(erlbasic_keywords:is_list_keyword("PRINT")),
    ?assert(erlbasic_keywords:is_list_keyword("INPUT")),
    ?assertNot(erlbasic_keywords:is_list_keyword("LEFT$")),
    ?assert(erlbasic_keywords:is_builtin_function_keyword("TIMER")),
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
        "ON", "ERROR", "RESUME", "HGR", "PSET", "STRING$"
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

immediate_print_test() ->
    State0 = erlbasic_interp:new_state(),
    {_State1, Output} = erlbasic_interp:handle_input("PRINT 1+1", State0),      
    ?assertEqual("2\r\n", lists:flatten(Output)),
    StateA = erlbasic_interp:new_state(),
    {_StateB, DotOutput} = erlbasic_interp:handle_input("PRINT .6", StateA),    
    ?assertEqual("0.6\r\n", lists:flatten(DotOutput)),
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
    PPNs = [PPN || {PPN, _} <- List],
    ?assert(lists:member({5, 1}, PPNs)),
    ?assert(lists:member({5, 2}, PPNs)).

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

%% Test loading textlife.bas from examples
textlife_load_test() ->
    %% Read textlife.bas and enter each line
    {ok, Content} = file:read_file("examples/textlife.bas"),
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

load_program_keeps_bad_lines_test() ->
    ProgramText =
        "10 PRINT \"OK\"\n"
        "20 DIM NEXT(1)\n"
        "30 LET X =\n"
        "40 END\n",
    {syntax_errors, Program, ErrorLines} = erlbasic_commands:parse_bin_as_program(list_to_binary(ProgramText)),
    ?assertEqual([20, 30], ErrorLines),
    ?assertEqual("DIM NEXT(1)", proplists:get_value(20, Program)),
    ?assertEqual("LET X =", proplists:get_value(30, Program)).
