-module(erlbasic_conn).

-export([start/1, start_ws/1, send_input/2]).

%% ---- TCP mode (existing) ----

start(Socket) ->
    ok = gen_tcp:send(Socket, "Welcome to Erlang BASIC\r\n"),
    ok = gen_tcp:send(Socket, "Type QUIT to disconnect.\r\n> "),
    State = erlbasic_interp:new_state(),
    loop(Socket, State).

loop(Socket, State) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Bin} ->
            Line = normalize_input_line(Bin),
            case string:to_upper(Line) of
                "QUIT" ->
                    ok = gen_tcp:send(Socket, "Goodbye\r\n"),
                    gen_tcp:close(Socket);
                _ ->
                    {NextState, Output} = erlbasic_interp:handle_input(Line, State),
                    send_output(Socket, Output),
                    ok = gen_tcp:send(Socket, erlbasic_interp:next_prompt(NextState)),
                    loop(Socket, NextState)
            end;
        {error, closed} ->
            ok
    end.

%% ---- WebSocket mode ----

%% Spawn a connection process for a WebSocket session.
%% WsPid is the ws_handler process; output is sent as {output, Text}.
start_ws(WsPid) ->
    Pid = spawn_link(fun() ->
        State = erlbasic_interp:new_state(),
        WsPid ! {output, "Welcome to Erlang BASIC\r\nType QUIT to disconnect.\r\n> "},
        ws_loop(WsPid, State)
    end),
    {ok, Pid}.

%% Push a line of input from the browser into the connection process.
send_input(Pid, Line) ->
    Pid ! {input, Line}.

ws_loop(WsPid, State) ->
    receive
        {input, RawLine} ->
            Line = normalize_input_line(list_to_binary(RawLine)),
            case string:to_upper(Line) of
                "QUIT" ->
                    WsPid ! {output, "Goodbye\r\n"};
                _ ->
                    {NextState, Output} = erlbasic_interp:handle_input(Line, State),
                    lists:foreach(fun(T) -> WsPid ! {output, T} end, Output),
                    WsPid ! {output, erlbasic_interp:next_prompt(NextState)},
                    ws_loop(WsPid, NextState)
            end
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