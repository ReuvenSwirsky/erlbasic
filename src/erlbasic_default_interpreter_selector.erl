-module(erlbasic_default_interpreter_selector).
-behaviour(erlbasic_interpreter_selector).

-export([select_interpreter/2]).

select_interpreter(_P, _N) ->
    application:get_env(erlbasic, interpreter_module, erlbasic_basic).