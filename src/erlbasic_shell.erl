-module(erlbasic_shell).

-export([
    banner/0,
    login_prompt_marker/0,
    user_prompt_message/0,
    password_prompt_message/0,
    please_say_hello_message/0,
    invalid_ppn_message/0,
    login_failure_message/0,
    too_many_sessions_message/0,
    bye_message/0,
    goodbye_message/0,
    logged_off_message/2,
    parse_hello/1,
    parse_ppn_only/1,
    parse_os_command/1,
    start_session/3,
    unregister_current_session/0
]).

banner() ->
    {{Y, Mo, D}, _} = calendar:local_time(),
    DateStr = io_lib:format("~2..0w-~s-~4..0w", [D, month_abbr(Mo), Y]),
    io_lib:format("\r\nRSTS/Erlang V1.0     ~s\r\n\r\n", [DateStr]).

login_prompt_marker() ->
    "#".

user_prompt_message() ->
    "\r\nUser: ".

password_prompt_message() ->
    "\r\nPassword: ".

please_say_hello_message() ->
    "?Please say HELLO\r\n".

invalid_ppn_message() ->
    "?Invalid PPN\r\n".

login_failure_message() ->
    "?Login failure\r\n".

too_many_sessions_message() ->
    "?Too many sessions for this account\r\n".

bye_message() ->
    "Bye\r\n".

goodbye_message() ->
    "Goodbye\r\n".

logged_off_message(P, N) ->
    io_lib:format(" ~s logged off\r\n\r\n", [format_ppn(P, N)]).

start_session(P, N, Pw) ->
    case erlbasic_accounts:authenticate(P, N, Pw) of
        {ok, Name} ->
            MaxSessions = max_sessions_for(P, N),
            case erlbasic_mem_watchdog:try_register_session(
                    self(), session_memory_limit(P, N), {P, N}, MaxSessions) of
                ok ->
                    InterpreterMod = select_interpreter(P, N),
                    erlang:put(erlbasic_ppn, {P, N}),
                    State = InterpreterMod:new_state(),
                    NameStr = binary_to_list(Name),
                    Welcome = [
                        io_lib:format(" ~s  ~s\r\n", [format_ppn(P, N), NameStr]),
                        quota_welcome_lines(P, N),
                        "\r\n Ready\r\n"
                    ],
                    {ok, #{
                        ppn => {P, N},
                        interpreter => InterpreterMod,
                        interpreter_state => State,
                        welcome => Welcome,
                        prompt => InterpreterMod:next_prompt(State)
                    }};
                {error, too_many_sessions} ->
                    {error, too_many_sessions}
            end;
        {error, _} ->
            {error, login_failure}
    end.

unregister_current_session() ->
    case erlang:get(erlbasic_ppn) of
        undefined -> ok;
        _ ->
            erlang:erase(erlbasic_ppn),
            erlbasic_mem_watchdog:unregister_session(self())
    end.

parse_hello(RawLine) ->
    Line = string:trim(RawLine),
    Upper = string:to_upper(Line),
    Cmds = ["HELLO", "LOGIN", "I"],
    case match_cmd_and_rest(Upper, Line, Cmds) of
        bare -> hello_prompt;
        {rest, Rest} -> parse_ppn_str(Rest);
        no_match -> not_hello
    end.

parse_ppn_only(Str) ->
    case re:split(string:trim(Str), "[,/]", [{return, list}, {parts, 2}]) of
        [PStr, NStr] ->
            try {ok, list_to_integer(string:trim(PStr)), list_to_integer(string:trim(NStr))}
            catch _:_ -> error
            end;
        _ -> error
    end.

parse_os_command(Line) ->
    case string:to_upper(string:trim(Line)) of
        "BYE" -> logout;
        "QUIT" -> quit;
        _ ->
            case parse_hello(Line) of
                not_hello -> not_os_command;
                Result -> {login, Result}
            end
    end.

select_interpreter(P, N) ->
    SelectorMod = application:get_env(
        erlbasic,
        interpreter_selector_module,
        erlbasic_default_interpreter_selector
    ),
    case SelectorMod:select_interpreter(P, N) of
        {ok, InterpreterMod} -> InterpreterMod;
        InterpreterMod when is_atom(InterpreterMod) -> InterpreterMod
    end.

month_abbr(1) -> "Jan"; month_abbr(2) -> "Feb"; month_abbr(3) -> "Mar";
month_abbr(4) -> "Apr"; month_abbr(5) -> "May"; month_abbr(6) -> "Jun";
month_abbr(7) -> "Jul"; month_abbr(8) -> "Aug"; month_abbr(9) -> "Sep";
month_abbr(10) -> "Oct"; month_abbr(11) -> "Nov"; month_abbr(12) -> "Dec".

format_ppn(P, N) ->
    io_lib:format("[~w,~w]", [P, N]).

quota_welcome_lines(P, N) ->
    StorageText =
        case erlbasic_limits:get_effective_limit_blocks(P, N) of
            unlimited -> "unlimited";
            Blocks when is_integer(Blocks), Blocks > 0 ->
                lists:flatten(io_lib:format("~w blocks (~wK)", [Blocks, Blocks]));
            _ ->
                "default"
        end,
    MemoryText =
        case erlbasic_limits:get_effective_memory_limit_kb(P, N) of
            unlimited -> "unlimited";
            KB when is_integer(KB), KB > 0 ->
                lists:flatten(io_lib:format("~wK", [KB]));
            _ ->
                "default"
        end,
    [
        " Storage quota: ", StorageText, "\r\n",
        " Memory quota: ", MemoryText, "\r\n"
    ].

session_memory_limit(P, N) ->
    case erlbasic_limits:get_effective_memory_limit_kb(P, N) of
        unlimited -> unlimited;
        KB when is_integer(KB), KB > 0 -> KB * 1024;
        _ -> erlbasic_limits:default_memory_limit_kb() * 1024
    end.

max_sessions_for(0, _) -> unlimited;
max_sessions_for(1, _) -> unlimited;
max_sessions_for(_, _) ->
    application:get_env(erlbasic, max_sessions_per_ppn, 3).

match_cmd_and_rest(_Upper, _Raw, []) -> no_match;
match_cmd_and_rest(Upper, Raw, [Cmd | Rest]) ->
    CLen = length(Cmd),
    case string:prefix(Upper, Cmd) of
        nomatch -> match_cmd_and_rest(Upper, Raw, Rest);
        Remaining ->
            case string:trim(Remaining) of
                "" -> bare;
                _ -> {rest, string:trim(string:slice(Raw, CLen))}
            end
    end.

parse_ppn_str(Str) ->
    {PPNStr, MaybePw} = case string:split(Str, ";") of
        [A, B] -> {A, {password, string:trim(B)}};
        [A] -> {A, none}
    end,
    PPNClean = string:trim(PPNStr),
    case re:split(PPNClean, "[,/]", [{return, list}, {parts, 2}]) of
        [PStr, NStr] ->
            try
                P = list_to_integer(string:trim(PStr)),
                N = list_to_integer(string:trim(NStr)),
                case MaybePw of
                    none -> {hello, P, N};
                    PW -> {hello, P, N, PW}
                end
            catch _:_ ->
                not_hello
            end;
        _ ->
            not_hello
    end.