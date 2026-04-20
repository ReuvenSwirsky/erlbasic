-module(erlbasic_listener).

-export([start_link/0, init/0]).

-define(DEFAULT_PORT, 5555).

start_link() ->
    proc_lib:start_link(?MODULE, init, []).

init() ->
    Port = application:get_env(erlbasic, port, ?DEFAULT_PORT),
    case gen_tcp:listen(Port, [
        binary,
        {packet, raw},
        {active, false},
        {reuseaddr, true},
        {nodelay, true}
    ]) of
        {ok, ListenSocket} ->
            proc_lib:init_ack({ok, self()}),
            io:format("erlbasic listening on port ~p~n", [Port]),
            accept_loop(ListenSocket);
        {error, Reason} ->
            proc_lib:init_ack({error, Reason}),
            exit(Reason)
    end.

accept_loop(ListenSocket) ->
    case gen_tcp:accept(ListenSocket) of
        {ok, Socket} ->
            case erlbasic_conn_sup:start_tcp_session(Socket) of
                {ok, Pid} ->
                    case gen_tcp:controlling_process(Socket, Pid) of
                        ok ->
                            accept_loop(ListenSocket);
                        {error, Reason} ->
                            io:format("failed to transfer TCP socket ownership: ~p~n", [Reason]),
                            exit(Pid, shutdown),
                            gen_tcp:close(Socket),
                            accept_loop(ListenSocket)
                    end;
                {error, Reason} ->
                    io:format("failed to start TCP session: ~p~n", [Reason]),
                    gen_tcp:close(Socket),
                    accept_loop(ListenSocket)
            end;
        {error, closed} ->
            ok;
        {error, Reason} ->
            exit({accept_failed, Reason})
    end.