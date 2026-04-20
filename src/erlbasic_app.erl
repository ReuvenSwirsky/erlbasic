-module(erlbasic_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
    ok = erlbasic_config_override:load(),
    ok = erlbasic_logging:configure(),
    ok = erlbasic_s3_config:load(),
    ok = erlbasic_limits:init(),
    ok = erlbasic_accounts:init(),
    ok = erlbasic_homepage_handler:init_cache(),
    erlbasic_sup:start_link().

stop(_State) ->
    ok.