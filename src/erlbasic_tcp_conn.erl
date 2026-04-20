-module(erlbasic_tcp_conn).

-export([start/1, start_link/1, init/1]).

-define(TCP_RECV_TIMEOUT_MS, 1000).

start(Socket) ->
    start_tcp_session(Socket, false).

start_link(Socket) ->
    proc_lib:start_link(?MODULE, init, [Socket]).

init(Socket) ->
    start_tcp_session(Socket, true).

start_tcp_session(Socket, Ack) ->
    Session = erlbasic_session:new(),
    erlang:put(erlbasic_conn_type, tcp),
    ok = gen_tcp:send(Socket, erlbasic_shell:banner()),
    ok = send_output(Socket, erlbasic_session:initial_output()),
    case Ack of
        true -> proc_lib:init_ack({ok, self()});
        false -> ok
    end,
    tcp_session_loop(Socket, Session, <<>>).

tcp_session_loop(_Socket, stop, _Buffer) ->
    ok;
tcp_session_loop(Socket, Session0, Buffer0) ->
    Session1 = tcp_drain_control_messages(Session0),
    case Session1 of
        stop ->
            ok;
        _ ->
            case gen_tcp:recv(Socket, 0, tcp_phase_timeout(Session1)) of
                {ok, Bin} ->
                    {Session2, Buffer1} = tcp_handle_socket_data(Socket, Session1, Buffer0, Bin),
                    tcp_session_loop(Socket, Session2, Buffer1);
                {error, timeout} ->
                    Session2 = tcp_handle_timeout(Socket, Session1),
                    tcp_session_loop(Socket, Session2, Buffer0);
                {error, closed} ->
                    tcp_handle_socket_closed(Session1)
            end
    end.

tcp_phase_timeout(Session) ->
    case erlbasic_session:awaiting_input_nonblocking(Session) of
        true -> 10;
        false -> ?TCP_RECV_TIMEOUT_MS
    end.

tcp_handle_socket_data(Socket, Session, Buffer, Bin) ->
    {Interrupted, CleanBin} = strip_tcp_interrupt_bytes(binary_to_list(Bin), false, []),
    case Interrupted of
        true -> erlang:put(interrupted, true);
        false -> ok
    end,
    case CleanBin of
        <<>> ->
            {Session, Buffer};
        _ ->
            tcp_process_socket_bytes(Socket, Session, <<Buffer/binary, CleanBin/binary>>)
    end.

tcp_handle_timeout(Socket, Session) ->
    case erlbasic_session:awaiting_input_nonblocking(Session) of
        true -> tcp_handle_line(Socket, Session, "");
        false -> Session
    end.

tcp_handle_socket_closed(Session) ->
    case erlbasic_session:phase(Session) of
        session -> erlbasic_shell:unregister_current_session();
        _ -> ok
    end.

tcp_drain_control_messages(Session) ->
    receive
        interrupt ->
            erlang:put(interrupted, true),
            tcp_drain_control_messages(Session);
        memory_limit_exceeded ->
            tcp_drain_control_messages(Session)
    after 0 ->
        Session
    end.

tcp_process_socket_bytes(Socket, Session, Bin) ->
    InCharMode = erlbasic_session:awaiting_input_nonblocking(Session) orelse
                 erlbasic_session:awaiting_input_getkey(Session),
    case InCharMode of
        true ->
            Char = normalize_char_input(Bin),
            case Char of
                "" -> {Session, <<>>};
                _ -> {tcp_handle_line(Socket, Session, Char), <<>>}
            end;
        false ->
            tcp_process_line_mode_bytes(Socket, Session, Bin)
    end.

tcp_process_line_mode_bytes(Socket, Session, Bin) ->
    {Lines, Rest} = split_complete_lines(binary_to_list(Bin), [], [], false),
    {tcp_process_lines(Socket, Session, Lines), list_to_binary(Rest)}.

tcp_process_lines(_Socket, Session, []) ->
    Session;
tcp_process_lines(_Socket, stop, _Lines) ->
    stop;
tcp_process_lines(Socket, Session, [LineChars | Rest]) ->
    Line = normalize_input_chars(LineChars),
    tcp_process_lines(Socket, tcp_handle_line(Socket, Session, Line), Rest).

tcp_handle_line(Socket, Session, Line) ->
    ExecFun = fun(InterpMod, InterpState, InputLine) ->
        tcp_execute(Socket, InterpMod, InterpState, InputLine)
    end,
    {NextSession, Output0, Control} = erlbasic_session:handle_line(Line, Session, ExecFun),
    Output = tcp_adjust_output(Output0, Control),
    ok = send_output(Socket, Output),
    maybe_delay(maps:get(delay_ms, Control, 0)),
    case maps:get(close, Control, false) of
        true ->
            catch gen_tcp:close(Socket),
            stop;
        false ->
            NextSession
    end.

tcp_adjust_output(Output, Control) ->
    case maps:get(login_result, Control, undefined) of
        login_failure -> ["\r\n" | Output];
        too_many_sessions -> ["\r\n" | Output];
        _ -> Output
    end.

tcp_execute(Socket, InterpMod, InterpState, Line) ->
    erlang:put(output_pid, self()),
    erlang:put(output_socket, Socket),
    ok = inet:setopts(Socket, [{active, true}]),
    try InterpMod:handle_input(Line, InterpState) of
        {NextState, Output} ->
            ok = inet:setopts(Socket, [{active, false}]),
            case tcp_drain_async_socket_messages(Socket) of
                closed ->
                    erlang:erase(output_pid),
                    erlang:erase(output_socket),
                    {close, []};
                open ->
                    erlang:erase(output_pid),
                    erlang:erase(output_socket),
                    {ok, NextState, Output}
            end;
        Other ->
            throw({bad_interp_return, Other})
    catch
        Class:Reason:Stacktrace ->
            catch inet:setopts(Socket, [{active, false}]),
            tcp_drain_async_socket_messages(Socket),
            io:format("ERROR in handle_input: ~p:~p~nStack: ~p~n", [Class, Reason, Stacktrace]),
            erlang:erase(output_pid),
            erlang:erase(output_socket),
            {error, [format_interpreter_error(Reason), "> "]}
    end.

tcp_drain_async_socket_messages(Socket) ->
    receive
        {tcp, Socket, Bin} ->
            case binary:match(Bin, <<3>>) =/= nomatch orelse binary:match(Bin, <<255, 244>>) =/= nomatch of
                true -> erlang:put(interrupted, true);
                false -> ok
            end,
            tcp_drain_async_socket_messages(Socket);
        {tcp_closed, Socket} ->
            closed;
        {tcp_error, Socket, _Reason} ->
            closed
    after 0 ->
        open
    end.

format_interpreter_error({bad_interp_return, {syntax_errors, _Program, _ErrorLines}}) ->
    "?SYNTAX ERROR\r\n";
format_interpreter_error({case_clause, {syntax_errors, _Program, _ErrorLines}}) ->
    "?SYNTAX ERROR\r\n";
format_interpreter_error(Reason) ->
    io_lib:format("?SYSTEM ERROR: error:~p\r\n", [Reason]).

normalize_char_input(Bin) ->
    Chars = [C || C <- binary_to_list(Bin), C =/= $\r, C =/= $\n],
    case Chars of
        [Single | _] -> [Single];
        [] -> ""
    end.

normalize_input_chars(Chars) ->
    string:trim(lists:reverse(apply_line_editing(Chars, []))).

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

split_complete_lines([], CurrentRev, LinesRev, _SkipLf) ->
    {lists:reverse(LinesRev), lists:reverse(CurrentRev)};
split_complete_lines([$\n | Rest], CurrentRev, LinesRev, true) ->
    split_complete_lines(Rest, CurrentRev, LinesRev, false);
split_complete_lines([$\r | Rest], CurrentRev, LinesRev, _SkipLf) ->
    split_complete_lines(Rest, [], [lists:reverse(CurrentRev) | LinesRev], true);
split_complete_lines([$\n | Rest], CurrentRev, LinesRev, _SkipLf) ->
    split_complete_lines(Rest, [], [lists:reverse(CurrentRev) | LinesRev], false);
split_complete_lines([Ch | Rest], CurrentRev, LinesRev, _SkipLf) ->
    split_complete_lines(Rest, [Ch | CurrentRev], LinesRev, false).

strip_tcp_interrupt_bytes([], Interrupted, AccRev) ->
    {Interrupted, list_to_binary(lists:reverse(AccRev))};
strip_tcp_interrupt_bytes([255, 244 | Rest], _Interrupted, AccRev) ->
    strip_tcp_interrupt_bytes(Rest, true, AccRev);
strip_tcp_interrupt_bytes([3 | Rest], _Interrupted, AccRev) ->
    strip_tcp_interrupt_bytes(Rest, true, AccRev);
strip_tcp_interrupt_bytes([Ch | Rest], Interrupted, AccRev) ->
    strip_tcp_interrupt_bytes(Rest, Interrupted, [Ch | AccRev]).

send_output(_Socket, []) ->
    ok;
send_output(Socket, [Line | Rest]) ->
    ok = gen_tcp:send(Socket, Line),
    send_output(Socket, Rest).

maybe_delay(0) ->
    ok;
maybe_delay(Ms) ->
    receive after Ms -> ok end.