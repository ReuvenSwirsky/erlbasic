-module(erlbasic_conn).

-export([start/1, start_ws/1, send_input/2]).

%% ---- TCP mode (existing) ----

start(Socket) ->
    ok = gen_tcp:send(Socket, "Welcome to Erlang BASIC\r\n"),
    ok = gen_tcp:send(Socket, "Type QUIT to disconnect.\r\n> "),
    %% Spawn worker process for interpreter
    WorkerPid = spawn_link(fun() ->
        State = erlbasic_interp:new_state(),
        tcp_worker_loop(Socket, State)
    end),
    tcp_recv_loop(Socket, WorkerPid).

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
                            case string:to_upper(Line) of
                                "QUIT" ->
                                    ok = gen_tcp:send(Socket, "Goodbye\r\n"),
                                    gen_tcp:close(Socket);
                                _ ->
                                    WorkerPid ! {input, Line},
                                    tcp_recv_loop(Socket, WorkerPid)
                            end
                    end
            end;
        {error, timeout} ->
            %% Check if worker is still alive
            case erlang:is_process_alive(WorkerPid) of
                true -> tcp_recv_loop(Socket, WorkerPid);
                false -> gen_tcp:close(Socket)
            end;
        {error, closed} ->
            ok
    end.

%% Worker process for TCP - runs interpreter
tcp_worker_loop(Socket, State) ->
    receive
        interrupt ->
            erlang:put(interrupted, true),
            tcp_worker_loop(Socket, State);
        {input, Line} ->
            %% Set up for incremental output during RUN
            erlang:put(output_pid, self()),
            erlang:put(output_socket, Socket),
            try erlbasic_interp:handle_input(Line, State) of
                {NextState, Output} ->
                    send_output(Socket, Output),
                    ok = gen_tcp:send(Socket, erlbasic_interp:next_prompt(NextState)),
                    erlang:erase(output_pid),
                    erlang:erase(output_socket),
                    tcp_worker_loop(Socket, NextState)
            catch
                Class:Reason:Stacktrace ->
                    io:format("ERROR in handle_input: ~p:~p~nStack: ~p~n", [Class, Reason, Stacktrace]),
                    ErrorMsg = io_lib:format("?SYSTEM ERROR: ~p:~p\r\n", [Class, Reason]),
                    ok = gen_tcp:send(Socket, ErrorMsg),
                    ok = gen_tcp:send(Socket, "> "),
                    erlang:erase(output_pid),
                    erlang:erase(output_socket),
                    tcp_worker_loop(Socket, State)
            end
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
        interrupt ->
            erlang:put(interrupted, true),
            ws_loop(WsPid, State);
        {input, RawLine} ->
            Line = normalize_input_line(list_to_binary(RawLine)),
            case string:to_upper(Line) of
                "QUIT" ->
                    WsPid ! {output, "Goodbye\r\n"};
                _ ->
                    %% Set up for incremental output during RUN
                    erlang:put(output_pid, WsPid),
                    try erlbasic_interp:handle_input(Line, State) of
                        {NextState, Output} ->
                            lists:foreach(fun(T) -> WsPid ! {output, T} end, Output),
                            WsPid ! {output, erlbasic_interp:next_prompt(NextState)},
                            erlang:erase(output_pid),
                            ws_loop(WsPid, NextState)
                    catch
                        Class:Reason:_ ->
                            ErrorMsg = io_lib:format("?SYSTEM ERROR: ~p:~p\r\n", [Class, Reason]),
                            WsPid ! {output, ErrorMsg},
                            WsPid ! {output, "> "},
                            erlang:erase(output_pid),
                            ws_loop(WsPid, State)
                    end
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