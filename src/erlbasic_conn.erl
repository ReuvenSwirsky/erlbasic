-module(erlbasic_conn).

-export([start/1, start_ws/1, send_input/2,
         parse_hello/1, parse_ppn_only/1, parse_os_command/1]).

%% ---- TCP mode ----

start(Socket) ->
    ok = gen_tcp:send(Socket, banner()),
    %% Spawn worker; it drives the login phase then the interpreter.
    WorkerPid = spawn_link(fun() ->
        erlang:put(erlbasic_conn_type, tcp),
        tcp_login_loop(Socket, 0)
    end),
    tcp_recv_loop(Socket, WorkerPid).

%% ---- RSTS/E login phase (TCP) ----

%% Up to 3 attempts; after that the worker exits and the link kills recv_loop.
tcp_login_loop(_Socket, 3) ->
    ok;
tcp_login_loop(Socket, Attempts) ->
    ok = gen_tcp:send(Socket, "#"),
    receive
        socket_closed -> ok;
        {input, Line} ->
            case parse_os_command(Line) of
                {login, hello_prompt} ->
                    ok = gen_tcp:send(Socket, "\r\nUser: "),
                    receive
                        socket_closed -> ok;
                        {input, PPNLine} ->
                            case parse_ppn_only(normalize_input_line(list_to_binary(PPNLine))) of
                                {ok, P, N} -> tcp_prompt_password(Socket, P, N, Attempts);
                                error ->
                                    ok = gen_tcp:send(Socket, "?Invalid PPN\r\n"),
                                    tcp_login_loop(Socket, Attempts + 1)
                            end
                    end;
                {login, {hello, P, N}} ->
                    tcp_prompt_password(Socket, P, N, Attempts);
                {login, {hello, P, N, {password, Pw}}} ->
                    tcp_try_login(Socket, P, N, Pw, Attempts);
                not_os_command ->
                    ok = gen_tcp:send(Socket, "?Please say HELLO\r\n"),
                    tcp_login_loop(Socket, Attempts + 1);
                _ -> %% logout or quit: at the OS prompt, both disconnect
                    gen_tcp:send(Socket, "Bye\r\n"),
                    gen_tcp:close(Socket)
            end
    end.

tcp_prompt_password(Socket, P, N, Attempts) ->
    ok = gen_tcp:send(Socket, "\r\nPassword: "),
    receive
        socket_closed -> ok;
        {input, PwLine} ->
            Pw = normalize_input_line(list_to_binary(PwLine)),
            tcp_try_login(Socket, P, N, Pw, Attempts)
    end.

tcp_try_login(Socket, P, N, Pw, Attempts) ->
    case erlbasic_accounts:authenticate(P, N, Pw) of
        {ok, Name} ->
            erlang:put(erlbasic_ppn, {P, N}),
            NameStr = binary_to_list(Name),
            Msg = io_lib:format(" ~s  ~s\r\n\r\n Ready\r\n",
                                [format_ppn(P, N), NameStr]),
            ok = gen_tcp:send(Socket, Msg),
            State = erlbasic_interp:new_state(),
            ok = gen_tcp:send(Socket, erlbasic_interp:next_prompt(State)),
            tcp_worker_loop(Socket, State, {P, N});
        {error, _} ->
            ok = gen_tcp:send(Socket, "\r\n?Login failure\r\n"),
            tcp_login_loop(Socket, Attempts + 1)
    end.

%% main TCP loop - receives data and forwards to worker
tcp_recv_loop(Socket, WorkerPid) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, Bin} ->
            %% Check for Ctrl-C (ASCII 3) or telnet interrupt (IAC IP: 255 244)
            case binary:match(Bin, <<3>>) of
                {_, _} ->
                    WorkerPid ! interrupt,
                    tcp_recv_loop(Socket, WorkerPid);
                nomatch ->
                    case binary:match(Bin, <<255, 244>>) of
                        {_, _} ->
                            %% Telnet interrupt protocol (IAC IP)
                            WorkerPid ! interrupt,
                            tcp_recv_loop(Socket, WorkerPid);
                        nomatch ->
                            Line = normalize_input_line(Bin),
                            WorkerPid ! {input, Line},
                            tcp_recv_loop(Socket, WorkerPid)
                    end
            end;
        {error, timeout} ->
            %% Check if worker is still alive
            case erlang:is_process_alive(WorkerPid) of
                true -> tcp_recv_loop(Socket, WorkerPid);
                false -> gen_tcp:close(Socket)
            end;
        {error, closed} ->
            WorkerPid ! socket_closed,
            ok
    end.

%% Worker process for TCP - runs interpreter.
%% OS-level commands (BYE, QUIT, HELLO, LOGIN, I) are intercepted here
%% before reaching the BASIC interpreter; everything else is forwarded
%% to handle_input/2.
tcp_worker_loop(Socket, State, {P, N} = PPN) ->
    receive
        socket_closed -> ok;
        interrupt ->
            erlang:put(interrupted, true),
            tcp_worker_loop(Socket, State, PPN);
        {input, Line} ->
            %% Only intercept OS commands when the BASIC interpreter is not
            %% waiting for an INPUT statement response.
            case erlbasic_interp:awaiting_input(State) of
                false ->
                    case parse_os_command(Line) of
                        logout ->
                            %% BYE: log off and return to the OS login prompt
                            erlang:erase(erlbasic_ppn),
                            ok = gen_tcp:send(Socket, io_lib:format(
                                    " ~s logged off\r\n\r\n", [format_ppn(P, N)])),
                            tcp_login_loop(Socket, 0);
                        quit ->
                            %% QUIT: disconnect entirely
                            erlang:erase(erlbasic_ppn),
                            ok = gen_tcp:send(Socket, "Goodbye\r\n"),
                            gen_tcp:close(Socket);
                        {login, HelloResult} ->
                            %% HELLO/LOGIN/I: log off current user and start a new login
                            erlang:erase(erlbasic_ppn),
                            ok = gen_tcp:send(Socket, io_lib:format(
                                    " ~s logged off\r\n\r\n", [format_ppn(P, N)])),
                            case HelloResult of
                                hello_prompt ->
                                    tcp_login_loop(Socket, 0);
                                {hello, NP, NN} ->
                                    tcp_prompt_password(Socket, NP, NN, 0);
                                {hello, NP, NN, {password, Pw}} ->
                                    tcp_try_login(Socket, NP, NN, Pw, 0)
                            end;
                        not_os_command ->
                            tcp_handle_basic(Socket, State, PPN, Line)
                    end;
                true ->
                    %% Interpreter is waiting for INPUT — pass directly through
                    tcp_handle_basic(Socket, State, PPN, Line)
            end
    end.

tcp_handle_basic(Socket, State, PPN, Line) ->
                    %% BASIC interpreter command
                    erlang:put(output_pid, self()),
                    erlang:put(output_socket, Socket),
                    try erlbasic_interp:handle_input(Line, State) of
                        {NextState, Output} ->
                            send_output(Socket, Output),
                            ok = gen_tcp:send(Socket, erlbasic_interp:next_prompt(NextState)),
                            erlang:erase(output_pid),
                            erlang:erase(output_socket),
                            tcp_worker_loop(Socket, NextState, PPN)
                    catch
                        Class:Reason:Stacktrace ->
                            io:format("ERROR in handle_input: ~p:~p~nStack: ~p~n",
                                      [Class, Reason, Stacktrace]),
                            ErrorMsg = io_lib:format("?SYSTEM ERROR: ~p:~p\r\n", [Class, Reason]),
                            ok = gen_tcp:send(Socket, ErrorMsg),
                            ok = gen_tcp:send(Socket, "> "),
                            erlang:erase(output_pid),
                            erlang:erase(output_socket),
                            tcp_worker_loop(Socket, State, PPN)
                    end.

%% ---- WebSocket mode ----

%% Spawn a connection process for a WebSocket session.
%% WsPid is the ws_handler process; output is sent as {output, Text}.
start_ws(WsPid) ->
    Pid = spawn_link(fun() ->
        erlang:put(erlbasic_conn_type, websocket),
        WsPid ! {output, banner()},
        ws_login_loop(WsPid, 0)
    end),
    {ok, Pid}.

%% Push a line of input from the browser into the connection process.
send_input(Pid, Line) ->
    Pid ! {input, Line}.

%% ---- RSTS/E login phase (WebSocket) ----

ws_login_loop(_WsPid, 3) ->
    ok;
ws_login_loop(WsPid, Attempts) ->
    WsPid ! {output, "#"},
    receive
        interrupt ->
            ws_login_loop(WsPid, Attempts);
        {input, RawLine} ->
            Line = normalize_input_line(list_to_binary(RawLine)),
            case parse_os_command(Line) of
                {login, hello_prompt} ->
                    WsPid ! {output, "\r\nUser: "},
                    receive
                        {input, PPNRaw} ->
                            PPNLine = normalize_input_line(list_to_binary(PPNRaw)),
                            case parse_ppn_only(PPNLine) of
                                {ok, P, N} ->
                                    ws_prompt_password(WsPid, P, N, Attempts);
                                error ->
                                    WsPid ! {output, "?Invalid PPN\r\n"},
                                    ws_login_loop(WsPid, Attempts + 1)
                            end
                    end;
                {login, {hello, P, N}} ->
                    ws_prompt_password(WsPid, P, N, Attempts);
                {login, {hello, P, N, {password, Pw}}} ->
                    ws_try_login(WsPid, P, N, Pw, Attempts);
                not_os_command ->
                    WsPid ! {output, "?Please say HELLO\r\n"},
                    ws_login_loop(WsPid, Attempts + 1);
                _ -> %% logout or quit: at the OS prompt, both disconnect
                    WsPid ! {output, "Bye\r\n"}
            end
    end.

ws_prompt_password(WsPid, P, N, Attempts) ->
    WsPid ! {output, "\r\nPassword: "},
    WsPid ! {output, "\x02PASSWORD_ON"},
    receive
        {input, PwRaw} ->
            Pw = normalize_input_line(list_to_binary(PwRaw)),
            WsPid ! {output, "\x02PASSWORD_OFF"},
            WsPid ! {output, "\r\n"},
            ws_try_login(WsPid, P, N, Pw, Attempts)
    end.

ws_try_login(WsPid, P, N, Pw, Attempts) ->
    case erlbasic_accounts:authenticate(P, N, Pw) of
        {ok, Name} ->
            erlang:put(erlbasic_ppn, {P, N}),
            NameStr = binary_to_list(Name),
            Msg = io_lib:format(" ~s  ~s\r\n\r\n Ready\r\n",
                                [format_ppn(P, N), NameStr]),
            WsPid ! {output, Msg},
            State = erlbasic_interp:new_state(),
            WsPid ! {output, erlbasic_interp:next_prompt(State)},
            ws_loop(WsPid, State, {P, N});
        {error, _} ->
            WsPid ! {output, "?Login failure\r\n"},
            ws_login_loop(WsPid, Attempts + 1)
    end.

%% Worker loop for WebSocket connections.
%% OS-level commands (BYE, QUIT, HELLO, LOGIN, I) are intercepted here
%% before reaching the BASIC interpreter; everything else is forwarded
%% to handle_input/2.
ws_loop(WsPid, State, {P, N} = PPN) ->
    receive
        interrupt ->
            erlang:put(interrupted, true),
            ws_loop(WsPid, State, PPN);
        {input, RawLine} ->
            Line = normalize_input_line(list_to_binary(RawLine)),
            %% Only intercept OS commands when the BASIC interpreter is not
            %% waiting for an INPUT statement response.
            case erlbasic_interp:awaiting_input(State) of
                false ->
                    case parse_os_command(Line) of
                        logout ->
                            %% BYE: log off and return to the OS login prompt
                            erlang:erase(erlbasic_ppn),
                            WsPid ! {output, io_lib:format(
                                        " ~s logged off\r\n\r\n", [format_ppn(P, N)])},
                            ws_login_loop(WsPid, 0);
                        quit ->
                            %% QUIT: disconnect entirely
                            erlang:erase(erlbasic_ppn),
                            WsPid ! {output, "Goodbye\r\n"};
                        {login, HelloResult} ->
                            %% HELLO/LOGIN/I: log off current user and start a new login
                            erlang:erase(erlbasic_ppn),
                            WsPid ! {output, io_lib:format(
                                        " ~s logged off\r\n\r\n", [format_ppn(P, N)])},
                            case HelloResult of
                                hello_prompt ->
                                    ws_login_loop(WsPid, 0);
                                {hello, NP, NN} ->
                                    ws_prompt_password(WsPid, NP, NN, 0);
                                {hello, NP, NN, {password, Pw}} ->
                                    ws_try_login(WsPid, NP, NN, Pw, 0)
                            end;
                        not_os_command ->
                            ws_handle_basic(WsPid, State, PPN, Line)
                    end;
                true ->
                    %% Interpreter is waiting for INPUT — pass directly through
                    ws_handle_basic(WsPid, State, PPN, Line)
            end
    end.

ws_handle_basic(WsPid, State, PPN, Line) ->
                    %% BASIC interpreter command
                    erlang:put(output_pid, WsPid),
                    try erlbasic_interp:handle_input(Line, State) of
                        {NextState, Output} ->
                            lists:foreach(fun(T) -> WsPid ! {output, T} end, Output),
                            WsPid ! {output, erlbasic_interp:next_prompt(NextState)},
                            erlang:erase(output_pid),
                            ws_loop(WsPid, NextState, PPN)
                    catch
                        Class:Reason:_ ->
                            ErrorMsg = io_lib:format("?SYSTEM ERROR: ~p:~p\r\n", [Class, Reason]),
                            WsPid ! {output, ErrorMsg},
                            WsPid ! {output, "> "},
                            erlang:erase(output_pid),
                            ws_loop(WsPid, State, PPN)
                    end.

%% ---- Shared helpers ----

normalize_input_line(Bin) ->
    EditedChars = apply_line_editing(binary_to_list(Bin), []),
    string:trim(lists:reverse(EditedChars)).

apply_line_editing([], Acc) ->
    Acc;
apply_line_editing([Ch | Rest], [_ | AccRest]) when Ch =:= $\b; Ch =:= 127 ->
    apply_line_editing(Rest, AccRest);
apply_line_editing([Ch | Rest], []) when Ch =:= $\b; Ch =:= 127 ->
    apply_line_editing(Rest, []);
apply_line_editing([Ch | Rest], Acc) when Ch =:= $\r; Ch =:= $\n ->
    apply_line_editing(Rest, Acc);
apply_line_editing([Ch | Rest], Acc) when Ch < 32 ->
    apply_line_editing(Rest, Acc);
apply_line_editing([Ch | Rest], Acc) ->
    apply_line_editing(Rest, [Ch | Acc]).

send_output(_Socket, []) ->
    ok;
send_output(Socket, [Line | Rest]) ->
    ok = gen_tcp:send(Socket, Line),
    send_output(Socket, Rest).

%% ---- RSTS/E login helpers ----

banner() ->
    {{Y, Mo, D}, _} = calendar:local_time(),
    DateStr = io_lib:format("~2..0w-~s-~4..0w",
        [D, month_abbr(Mo), Y]),
    io_lib:format("\r\nRSTS/E V10.1-06     ~s\r\n\r\n", [DateStr]).

month_abbr(1)  -> "Jan"; month_abbr(2)  -> "Feb"; month_abbr(3)  -> "Mar";
month_abbr(4)  -> "Apr"; month_abbr(5)  -> "May"; month_abbr(6)  -> "Jun";
month_abbr(7)  -> "Jul"; month_abbr(8)  -> "Aug"; month_abbr(9)  -> "Sep";
month_abbr(10) -> "Oct"; month_abbr(11) -> "Nov"; month_abbr(12) -> "Dec".

format_ppn(P, N) ->
    io_lib:format("[~w,~w]", [P, N]).

%% parse_hello/1 – internal helper used by parse_os_command/1.
%% Parses the PPN/password arguments of a login OS command.  Returns:
%%   hello_prompt                    – bare HELLO/LOGIN/I (prompt for PPN)
%%   {hello, P, N}                   – PPN given, prompt for password
%%   {hello, P, N, {password, Pw}}  – one-line: HELLO P,N;PASSWORD
%%   not_hello                       – not a login OS command
%%
%% Matching is case-insensitive; the password portion retains its original case
%% (though erlbasic_accounts:authenticate/3 will uppercase it anyway).
parse_hello(RawLine) ->
    Line  = string:trim(RawLine),
    Upper = string:to_upper(Line),
    Cmds  = ["HELLO", "LOGIN", "I"],
    case match_cmd_and_rest(Upper, Line, Cmds) of
        bare         -> hello_prompt;
        {rest, Rest} -> parse_ppn_str(Rest);
        no_match     -> not_hello
    end.

match_cmd_and_rest(_Upper, _Raw, []) -> no_match;
match_cmd_and_rest(Upper, Raw, [Cmd | Rest]) ->
    CLen = length(Cmd),
    case string:prefix(Upper, Cmd) of
        nomatch   -> match_cmd_and_rest(Upper, Raw, Rest);
        Remaining ->
            case string:trim(Remaining) of
                "" -> bare;
                _  -> {rest, string:trim(string:slice(Raw, CLen))}
            end
    end.

parse_ppn_str(Str) ->
    %% Split on ";" to extract optional inline password (original case preserved)
    {PPNStr, MaybePw} = case string:split(Str, ";") of
        [A, B] -> {A, {password, string:trim(B)}};
        [A]    -> {A, none}
    end,
    PPNClean = string:trim(PPNStr),
    case re:split(PPNClean, "[,/]", [{return, list}, {parts, 2}]) of
        [PStr, NStr] ->
            try
                P = list_to_integer(string:trim(PStr)),
                N = list_to_integer(string:trim(NStr)),
                case MaybePw of
                    none -> {hello, P, N};
                    PW   -> {hello, P, N, PW}
                end
            catch _:_ ->
                not_hello
            end;
        _ ->
            not_hello
    end.

parse_ppn_only(Str) ->
    case re:split(string:trim(Str), "[,/]", [{return, list}, {parts, 2}]) of
        [PStr, NStr] ->
            try {ok, list_to_integer(string:trim(PStr)), list_to_integer(string:trim(NStr))}
            catch _:_ -> error
            end;
        _ -> error
    end.

%% parse_os_command/1 – classifies RSTS/E OS-level commands handled at the
%% connection layer, above the BASIC interpreter.  OS commands operate on the
%% session itself; BASIC commands are forwarded to handle_input/2.  Returns:
%%
%%   logout                                  – BYE: log off, return to login prompt
%%   quit                                    – QUIT: disconnect the session entirely
%%   {login, hello_prompt}                   – bare HELLO/LOGIN/I (prompt for PPN)
%%   {login, {hello, P, N}}                  – PPN given, prompt for password
%%   {login, {hello, P, N, {password, Pw}}}  – inline PPN + password
%%   not_os_command                          – BASIC interpreter command
parse_os_command(Line) ->
    case string:to_upper(string:trim(Line)) of
        "BYE"  -> logout;
        "QUIT" -> quit;
        _      ->
            case parse_hello(Line) of
                not_hello -> not_os_command;
                Result    -> {login, Result}
            end
    end.