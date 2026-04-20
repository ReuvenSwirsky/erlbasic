-module(erlbasic_conn_sup).
-behaviour(supervisor).

-export([start_link/0, start_tcp_session/1, start_ws_session/1, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_tcp_session(Socket) ->
    supervisor:start_child(?MODULE, tcp_session_child_spec(Socket)).

start_ws_session(WsPid) ->
    supervisor:start_child(?MODULE, ws_session_child_spec(WsPid)).

init([]) ->
    {ok, {{one_for_one, 50, 10}, []}}.

tcp_session_child_spec(Socket) ->
    #{
        id => {erlbasic_tcp_session, make_ref()},
        start => {erlbasic_tcp_conn, start_link, [Socket]},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [erlbasic_tcp_conn]
    }.

ws_session_child_spec(WsPid) ->
    #{
        id => {erlbasic_ws_session, make_ref()},
        start => {erlbasic_ws_conn, start_link, [WsPid]},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [erlbasic_ws_conn]
    }.