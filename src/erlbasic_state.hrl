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
    open_files = #{},           % OPEN file channels (#n => file metadata)
    trace_enabled = false,      % TRON/TROFF runtime line tracing
    graphics_mode = false,      % false | hgr | hgr2 — active graphics mode (WebSocket only)
    graphics_pen = undefined,   % {X, Y} - last graphics endpoint (for LINETO)
    dblbuff = false,            % true when BUFFER mode is on (WebSocket only)
    sprites = #{},              % sprite id => #{w,h,pixels,x,y,visible,scale}
    sprite_active_collisions = [], % normalized [{Id1,Id2}] currently overlapping
    on_sprite_gosub = undefined, % <TargetExpr> | undefined — ON SPRITE GOSUB handler
    on_sprite_return_depth = -1, % -1 = not in sprite handler; >=0 = call stack depth at fire time
    play_background = false,    % true = MB (background) mode, false = MF (foreground)
    on_play_gosub = undefined,  % {NExpr, TargetExpr} | undefined — ON PLAY(n) GOSUB handler
    on_play_return_depth = -1   % -1 = not in handler; >=0 = call stack depth at fire time
}).
