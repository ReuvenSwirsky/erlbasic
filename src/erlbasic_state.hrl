%% Shared interpreter state record used by erlbasic_interp and erlbasic_runtime.
-record(state, {
    vars = #{},
    prog = [],
    funcs = #{},
    pending_input = undefined,
    immediate_for_buffer = undefined,
    data_items = [],
    data_index = 1,
    print_col = 0,
    continue_ctx = undefined,
    char_buffer = []
}).
