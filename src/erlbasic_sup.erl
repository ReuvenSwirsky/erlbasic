-module(erlbasic_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Listener = #{
        id => erlbasic_listener,
        start => {erlbasic_listener, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [erlbasic_listener]
    },
    {ok, {{one_for_one, 5, 10}, [Listener]}}.