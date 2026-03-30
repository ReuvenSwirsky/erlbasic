-module(erlbasic_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
    ok = erlbasic_accounts:init(),
    erlbasic_sup:start_link().

stop(_State) ->
    ok.