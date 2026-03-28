-module(erlbasic_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    ok = start_cowboy(),
    Listener = #{
        id => erlbasic_listener,
        start => {erlbasic_listener, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [erlbasic_listener]
    },
    {ok, {{one_for_one, 5, 10}, [Listener]}}.

start_cowboy() ->
    WebPort = application:get_env(erlbasic, web_port, 8080),
    PrivDir = code:priv_dir(erlbasic),
    WwwDir  = filename:join(PrivDir, "www"),
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/ws", erlbasic_ws_handler, []},
            {"/[...]", cowboy_static, {dir, WwwDir}}
        ]}
    ]),
    {ok, _} = cowboy:start_clear(erlbasic_http,
        [{port, WebPort}],
        #{env => #{dispatch => Dispatch}}
    ),
    io:format("erlbasic web server listening on port ~p~n", [WebPort]),
    ok.