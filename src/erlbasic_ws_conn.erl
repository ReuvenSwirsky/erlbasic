-module(erlbasic_ws_conn).

-export([start/1, start_link/1, init/1, send_input/2]).

start(WsPid) ->
    Pid = spawn(fun() -> start_ws_session(WsPid, false) end),
    {ok, Pid}.

start_link(WsPid) ->
    proc_lib:start_link(?MODULE, init, [WsPid]).

init(WsPid) ->
    start_ws_session(WsPid, true).

start_ws_session(WsPid, Ack) ->
    Session = erlbasic_session:new(),
    erlang:put(erlbasic_conn_type, websocket),
    case Ack of
        true -> proc_lib:init_ack({ok, self()});
        false -> ok
    end,
    WsPid ! {output, erlbasic_shell:banner()},
    send_outputs(WsPid, erlbasic_session:initial_output()),
    ws_loop(WsPid, Session).

send_input(Pid, Line) ->
    Pid ! {input, Line}.

ws_loop(WsPid, Session) ->
    case char_mode(Session) of
        true -> WsPid ! {output, "\x02CHAR_MODE_ON"};
        false -> ok
    end,
    Timeout = case erlbasic_session:awaiting_input_nonblocking(Session) of
        true -> 10;
        false -> infinity
    end,
    receive
        interrupt ->
            erlang:put(interrupted, true),
            ws_loop(WsPid, Session);
        memory_limit_exceeded ->
            ws_loop(WsPid, Session);
        close ->
            maybe_unregister(Session);
        {input, RawLine} ->
            InCharMode = char_mode(Session),
            Line = case InCharMode of
                true -> normalize_char_input(list_to_binary(RawLine));
                false -> normalize_input_line(list_to_binary(RawLine))
            end,
            handle_ws_line(WsPid, Session, Line)
    after Timeout ->
        handle_ws_line(WsPid, Session, "")
    end.

handle_ws_line(WsPid, Session, Line) ->
    OldPhase = erlbasic_session:phase(Session),
    OldCharMode = char_mode(Session),
    ExecFun = fun(InterpMod, InterpState, InputLine) ->
        ws_execute(WsPid, InterpMod, InterpState, InputLine)
    end,
    {NextSession, Output0, Control} = erlbasic_session:handle_line(Line, Session, ExecFun),
    Output1 = adjust_password_mode_output(OldPhase, erlbasic_session:phase(NextSession), Output0),
    Output2 = adjust_char_mode_output(OldCharMode, char_mode(NextSession), Output1),
    send_outputs(WsPid, Output2),
    maybe_delay(maps:get(delay_ms, Control, 0)),
    case maps:get(close, Control, false) of
        true ->
            WsPid ! close;
        false ->
            ws_loop(WsPid, NextSession)
    end.

ws_execute(WsPid, InterpMod, InterpState, Line) ->
    erlang:put(output_pid, WsPid),
    try InterpMod:handle_input(Line, InterpState) of
        {NextState, Output} ->
            erlang:erase(output_pid),
            {ok, NextState, Output};
        Other ->
            throw({bad_interp_return, Other})
    catch
        Class:Reason:Stacktrace ->
            logger:error("event=interpreter_crash conn_type=websocket class=~p reason=~p stacktrace=~p", [Class, Reason, Stacktrace]),
            erlang:erase(output_pid),
            {error, [format_interpreter_error(Reason), "> "]}
    end.

format_interpreter_error({bad_interp_return, {syntax_errors, _Program, _ErrorLines}}) ->
    "?SYNTAX ERROR\r\n";
format_interpreter_error({case_clause, {syntax_errors, _Program, _ErrorLines}}) ->
    "?SYNTAX ERROR\r\n";
format_interpreter_error(Reason) ->
    io_lib:format("?SYSTEM ERROR: error:~p\r\n", [Reason]).

adjust_password_mode_output({login_wait_password, _, _}, {login_wait_password, _, _}, Output) ->
    Output;
adjust_password_mode_output({login_wait_password, _, _}, _NewPhase, Output) ->
    ["\x02PASSWORD_OFF", "\r\n" | Output];
adjust_password_mode_output(_OldPhase, {login_wait_password, _, _}, Output) ->
    Output ++ ["\x02PASSWORD_ON"];
adjust_password_mode_output(_OldPhase, _NewPhase, Output) ->
    Output.

adjust_char_mode_output(true, false, Output) ->
    ["\x02CHAR_MODE_OFF" | Output];
adjust_char_mode_output(_OldMode, _NewMode, Output) ->
    Output.

char_mode(Session) ->
    erlbasic_session:awaiting_input_nonblocking(Session) orelse
    erlbasic_session:awaiting_input_getkey(Session).

maybe_unregister(Session) ->
    case erlbasic_session:phase(Session) of
        session -> erlbasic_shell:unregister_current_session();
        _ -> ok
    end.

normalize_input_line(Bin) ->
    normalize_input_chars(binary_to_list(Bin)).

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

send_outputs(_WsPid, []) ->
    ok;
send_outputs(WsPid, [Line | Rest]) ->
    WsPid ! {output, Line},
    send_outputs(WsPid, Rest).

maybe_delay(0) ->
    ok;
maybe_delay(Ms) ->
    receive after Ms -> ok end.