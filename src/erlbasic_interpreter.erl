-module(erlbasic_interpreter).

-callback new_state() -> term().
-callback handle_input(string(), term()) -> {term(), [iodata()]}.
-callback next_prompt(term()) -> iodata().
-callback awaiting_input(term()) -> boolean().
-callback awaiting_input_nonblocking(term()) -> boolean().
-callback awaiting_input_getkey(term()) -> boolean().