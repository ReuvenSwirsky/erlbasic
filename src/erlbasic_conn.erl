-module(erlbasic_conn).

-export([start/1]).

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