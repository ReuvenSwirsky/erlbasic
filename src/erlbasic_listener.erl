-module(erlbasic_listener).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(DEFAULT_PORT, 5555).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    Port = application:get_env(erlbasic, port, ?DEFAULT_PORT),
    {ok, ListenSocket} = gen_tcp:listen(Port, [
        binary,
        {packet, line},
        {active, false},
        {reuseaddr, true}
    ]),
    _AcceptPid = spawn_link(fun() -> accept_loop(ListenSocket) end),
    io:format("erlbasic listening on port ~p~n", [Port]),
    {ok, #{listen_socket => ListenSocket, port => Port}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #{listen_socket := ListenSocket}) ->
    gen_tcp:close(ListenSocket),
    ok;
terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

accept_loop(ListenSocket) ->
    case gen_tcp:accept(ListenSocket) of
        {ok, Socket} ->
            spawn_link(fun() -> erlbasic_conn:start(Socket) end),
            accept_loop(ListenSocket);
        {error, closed} ->
            ok;
        {error, Reason} ->
            io:format("accept failed: ~p~n", [Reason]),
            ok
    end.