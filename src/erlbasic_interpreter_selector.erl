-module(erlbasic_interpreter_selector).

-callback select_interpreter(non_neg_integer(), non_neg_integer()) -> module() | {ok, module()}.