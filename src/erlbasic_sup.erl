-module(erlbasic_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    MemWatchdog = #{
        id => erlbasic_mem_watchdog,
        start => {erlbasic_mem_watchdog, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [erlbasic_mem_watchdog]
    },
    ConnSup = #{
        id => erlbasic_conn_sup,
        start => {erlbasic_conn_sup, start_link, []},
        restart => permanent,
        shutdown => infinity,
        type => supervisor,
        modules => [erlbasic_conn_sup]
    },
    HttpListener = #{
        id => erlbasic_http_listener,
        start => {erlbasic_web_listener, start_link, [http]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [erlbasic_web_listener]
    },
    Listener = #{
        id => erlbasic_listener,
        start => {erlbasic_listener, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [erlbasic_listener]
    },
    Children0 = [MemWatchdog, HttpListener, ConnSup, Listener],
    Children = case application:get_env(erlbasic, enable_https, false) of
        true ->
            HttpsListener = # {
                id => erlbasic_https_listener,
                start => {erlbasic_web_listener, start_link, [https]},
                restart => permanent,
                shutdown => 5000,
                type => worker,
                modules => [erlbasic_web_listener]
            },
            [MemWatchdog, HttpListener, HttpsListener, ConnSup, Listener];
        false ->
            Children0
    end,
    {ok, {{rest_for_one, 5, 10}, Children}}.