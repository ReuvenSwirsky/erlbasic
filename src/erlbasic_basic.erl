-module(erlbasic_basic).
-behaviour(erlbasic_interpreter).

-export([
    new_state/0,
    handle_input/2,
    next_prompt/1,
    awaiting_input/1,
    awaiting_input_nonblocking/1,
    awaiting_input_getkey/1
]).

new_state() ->
    erlbasic_interp:new_state().

handle_input(Line, State) ->
    erlbasic_interp:handle_input(Line, State).

next_prompt(State) ->
    erlbasic_interp:next_prompt(State).

awaiting_input(State) ->
    erlbasic_interp:awaiting_input(State).

awaiting_input_nonblocking(State) ->
    erlbasic_interp:awaiting_input_nonblocking(State).

awaiting_input_getkey(State) ->
    erlbasic_interp:awaiting_input_getkey(State).