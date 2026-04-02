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
    char_buffer = [],
    error_handler = undefined,  % Line number of error handler (or undefined)
    error_resume_pc = undefined, % PC where error occurred (for RESUME)
    error_code = 0,             % ERR - last error code
    error_line = 0,             % ERL - line number where error occurred
    graphics_mode = false,      % True when in HGR mode (WebSocket only)
    graphics_pen = undefined    % {X, Y} - last graphics endpoint (for LINETO)
}).
