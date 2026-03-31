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

%% ===========================================================================
%% Accounts (DETS) tests — all run under a single setup/teardown
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
    %% Empty credentials file → triggers default account seeding.
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