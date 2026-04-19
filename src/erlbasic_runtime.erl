-module(erlbasic_runtime).

-export([run_program/1, continue_program/4, resume_program_input/5,
         update_pending_input_rest/2, format_input_prompt/1,
         collect_program_data/1, collect_program_data_from_line/2, apply_read_vars/2, eval_locate/4,
         apply_dim_decls/3, render_print_items/4, cls_output/0,
         eval_color/4, render_print_using_items/5,
         hgr_output/0, hgr2_output/0, text_output/0,
         eval_pset/4, eval_line/6, eval_lineto/7, eval_rect/6, eval_circle/5,
         eval_sound/6, execute_play/2, execute_sprite_stmt/2]).

-define(FLUSH_OUTPUT_EVERY, 100).

-include("erlbasic_state.hrl").

run_program(State = #state{prog = Program}) ->
    DataItems = collect_program_data(Program),
    RunState = State#state{data_items = DataItems, data_index = 1, continue_ctx = undefined},
    erlang:put(line_exec_count, 0),
    erlang:put(stmt_parse_cache, #{}),
    erlang:put(expr_parse_cache, #{}),
    erlang:erase(interrupted),
    Result = run_program_lines(Program, 1, RunState, [], [], []),
    erlang:erase(line_exec_count),
    erlang:erase(stmt_parse_cache),
    erlang:erase(expr_parse_cache),
    Result.

continue_program(State = #state{prog = Program}, Pc, LoopStack, CallStack) ->
    erlang:put(line_exec_count, 0),
    erlang:put(stmt_parse_cache, #{}),
    erlang:put(expr_parse_cache, #{}),
    Result = run_program_lines(Program, Pc, State, LoopStack, CallStack, []),
    erlang:erase(line_exec_count),
    erlang:erase(stmt_parse_cache),
    erlang:erase(expr_parse_cache),
    Result.

run_program_lines([], _Pc, State, _LoopStack, _CallStack, Acc) ->
    {State, lists:reverse(Acc)};
run_program_lines(Program, Pc, State, _LoopStack, _CallStack, Acc) when Pc > length(Program) ->
    {State, lists:reverse(Acc)};
run_program_lines(Program, Pc, State, LoopStack, CallStack, Acc) ->
    Count = case erlang:get(line_exec_count) of undefined -> 0; N -> N end,
    erlang:put(line_exec_count, Count + 1),
    run_program_lines_continue(Program, Pc, State, LoopStack, CallStack, Acc, Count).

run_program_lines_continue(Program, Pc, State, LoopStack, CallStack, Acc, Count) ->
    %% Check for interrupt or memory-limit message in mailbox (non-blocking)
    receive
        interrupt ->
            erlang:put(interrupted, true);
        memory_limit_exceeded ->
            erlang:put(memory_limit_exceeded, true)
    after 0 ->
        ok
    end,
    %% Periodic flush for output during loops — suppressed in buffer mode
    NewAcc = case should_flush_output() andalso not State#state.dblbuff andalso (Count rem ?FLUSH_OUTPUT_EVERY =:= 0) andalso (Acc =/= []) of
        true ->
            flush_output(Acc),
            [];
        false ->
            Acc
    end,
    %% Check for Ctrl-C interrupt
    case erlang:get(interrupted) of
        true ->
            erlang:erase(interrupted),
            %% Drain any additional interrupt messages that queued up
            drain_interrupt_messages(),
            flush_output(NewAcc),
            music_reset(),
            BreakState = State#state{continue_ctx = {Pc, LoopStack, CallStack}},
            %% Include GFX:TEXT so the browser resets graphics state even if its
            %% Ctrl-C handler fires after these frames arrive.
            GfxReset = case State#state.graphics_mode of
                false -> [];
                _     -> text_output()
            end,
            ResetState = BreakState#state{
                graphics_mode = false,
                sprites = #{},
                sprite_active_collisions = [],
                on_sprite_return_depth = -1,
                on_play_return_depth = -1,
                on_timer_return_depth = -1
            },
            %% TCP/telnet clients rely on the server to echo ^C visually;
            %% WebSocket clients already display it client-side in the browser.
            CtrlCEcho = case erlang:get(erlbasic_conn_type) of
                websocket -> [];
                _         -> ["^C\r\n"]
            end,
            {ResetState,
             GfxReset ++ sound_stop_output() ++ music_stop_output() ++ sprite_clear_output() ++ ["\r\n"] ++ CtrlCEcho ++ ["BREAK\r\n"]};
        _ ->
            case erlang:get(memory_limit_exceeded) of
                true ->
                    erlang:erase(memory_limit_exceeded),
                    handle_memory_quota_error(Program, Pc, State, NewAcc);
                _ ->
                    run_program_lines_impl(Program, Pc, State, LoopStack, CallStack, NewAcc, Count)
            end
    end.

handle_memory_quota_error(Program, Pc, State, Acc) ->
    LineNumber = get_line_number(Program, Pc),
    ErrorOut = [erlbasic_eval:format_runtime_error(memory_quota_exceeded, LineNumber)],
    case should_flush_output() of
        true ->
            flush_output(Acc),
            {State, ErrorOut};
        false ->
            {State, lists:reverse(ErrorOut ++ Acc)}
    end.

run_program_lines_impl(Program, Pc, State, LoopStack, CallStack, Acc, _Count) ->
    TraceAcc = prepend_trace_output(State, Program, Pc, Acc),
    %% Clear any stale explicit_flush flag before executing this line, then
    %% re-read it after — so ExplicitFlush is true only when THIS line is FLUSH.
    erlang:erase(explicit_flush_requested),
    {_LineNumber, Code} = lists:nth(Pc, Program),
    case execute_program_line(Code, Program, State, Pc, LoopStack, CallStack) of
        {continue, NextState, NextLoopStack, NextCallStack, Output} ->
            ExplicitFlush = erlang:erase(explicit_flush_requested) =:= true,
            %% Accumulate output
            CombinedOutput = lists:reverse(Output) ++ TraceAcc,
            FlushNow = should_flush_output() andalso
                (needs_flush(Output, NextState#state.dblbuff, ExplicitFlush) orelse
                 should_flush_implicit_boundary(Output, NextState#state.dblbuff, TraceAcc)),
            NewAcc =
                case FlushNow of
                    true ->
                        flush_output(CombinedOutput),
                        [];
                    false ->
                        CombinedOutput
                end,
                case NextState#state.pending_input of
                    undefined ->
                        case event_gosub_trigger(NextState, NextLoopStack, NextCallStack) of
                            {gosub, TargetPc, FiredState} ->
                                run_program_lines(Program, TargetPc, FiredState, NextLoopStack, [Pc + 1 | NextCallStack], NewAcc);
                            {no_trigger, UpdatedState} ->
                                run_program_lines(Program, Pc + 1, UpdatedState, NextLoopStack, NextCallStack, NewAcc)
                        end;
                    PendingInput ->
                        case should_flush_output() andalso should_flush_for_pending_input(PendingInput) of
                            true ->
                                flush_output(NewAcc),
                                {NextState, []};
                            false ->
                                {NextState, lists:reverse(NewAcc)}
                        end
                end;
        {jump, TargetPc, NextState, NextLoopStack, NextCallStack, Output} ->
            ExplicitFlush = erlang:erase(explicit_flush_requested) =:= true,
            %% Accumulate output
            CombinedOutput = lists:reverse(Output) ++ TraceAcc,
            FlushNow = should_flush_output() andalso
                (needs_flush(Output, NextState#state.dblbuff, ExplicitFlush) orelse
                 should_flush_implicit_boundary(Output, NextState#state.dblbuff, TraceAcc)),
            NewAcc =
                case FlushNow of
                    true ->
                        flush_output(CombinedOutput),
                        [];
                    false ->
                        CombinedOutput
                end,
                case NextState#state.pending_input of
                    undefined ->
                        run_program_lines(Program, TargetPc, NextState, NextLoopStack, NextCallStack, NewAcc);
                    PendingInput ->
                        case should_flush_output() andalso should_flush_for_pending_input(PendingInput) of
                            true ->
                                flush_output(NewAcc),
                                {NextState, []};
                            false ->
                                {NextState, lists:reverse(NewAcc)}
                        end
                end;
        {'end', Output} ->
            %% Flush final output
            FinalOutput = sound_stop_output() ++ music_stop_output() ++ sprite_clear_output() ++ lists:reverse(Output) ++ TraceAcc,
            flush_output(FinalOutput),
            music_reset(),
            %% Clear all runtime state as other BASICs do on END:
            %% variables, user functions, data pointer, open files,
            %% error handler, keyboard buffer, and continuation context.
            EndedState = State#state{
                vars              = #{},
                funcs             = #{},
                data_items        = collect_program_data(State#state.prog),
                data_index        = 1,
                continue_ctx      = undefined,
                open_files        = #{},
                error_handler     = undefined,
                error_resume_pc   = undefined,
                error_code        = 0,
                error_line        = 0,
                char_buffer       = [],
                print_col         = 0,
                sprites           = #{},
                sprite_active_collisions = [],
                on_sprite_gosub   = undefined,
                on_sprite_return_depth = -1,
                play_background   = false,
                on_play_gosub     = undefined,
                on_play_return_depth = -1,
                on_timer_gosub    = undefined,
                on_timer_return_depth = -1,
                on_timer_last_ms  = undefined
            },
            case should_flush_output() of
                true ->
                    {EndedState, ["Program ended\r\n"]};
                false ->
                    {EndedState, lists:reverse(["Program ended\r\n" | FinalOutput])}
            end;
        {chain, NewState, Output} ->
            CombinedOutput = lists:reverse(Output) ++ TraceAcc,
            NewAcc =
                case should_flush_output() of
                    true ->
                        flush_output(CombinedOutput),
                        [];
                    false ->
                        CombinedOutput
                end,
            %% Start executing the new program from line 1
            run_program_lines(NewState#state.prog, 1, NewState, [], [], NewAcc);
        {break, BreakState, Output} ->
            CombinedOutput = lists:reverse(Output) ++ TraceAcc,
            flush_output(CombinedOutput),
            case should_flush_output() of
                true ->
                    {BreakState, []};
                false ->
                    {BreakState, lists:reverse(CombinedOutput)}
            end;
        {stop, Output} ->
            CombinedOutput = sound_stop_output() ++ music_stop_output() ++ sprite_clear_output() ++ lists:reverse(Output) ++ TraceAcc,
            flush_output(CombinedOutput),
            music_reset(),
            case should_flush_output() of
                true ->
                    {State, []};
                false ->
                    {State, lists:reverse(CombinedOutput)}
            end
    end.

prepend_trace_output(State, Program, Pc, Acc) ->
    case trace_line_output(State, Program, Pc) of
        [] ->
            Acc;
        Trace ->
            lists:reverse(Trace) ++ Acc
    end.

trace_line_output(#state{trace_enabled = false}, _Program, _Pc) ->
    [];
trace_line_output(#state{trace_enabled = true}, Program, Pc) ->
    case get_line_number(Program, Pc) of
        undefined ->
            [];
        LineNumber ->
            [io_lib:format("[~B]\r\n", [LineNumber])]
    end.

execute_program_line(Code, Program, State, Pc, LoopStack, CallStack) ->
    case erlbasic_parser:should_split_top_level_sequence(Code) of
        true ->
            execute_program_line_statements(erlbasic_parser:split_statements(Code), Program, State, Pc, LoopStack, CallStack, []);
        false ->
            execute_program_line_statement(Code, Program, State, Pc, LoopStack, CallStack)
    end.

execute_program_line_statements([], _Program, State, _Pc, LoopStack, CallStack, OutputAcc) ->
    {continue, State, LoopStack, CallStack, OutputAcc};
execute_program_line_statements([Stmt | Rest], Program, State, Pc, LoopStack, CallStack, OutputAcc) ->
    case execute_program_line_statement(Stmt, Program, State, Pc, LoopStack, CallStack) of
        {continue, NextState, NextLoopStack, NextCallStack, Output} ->
            %% If a FOR frame was just pushed for this Pc and there are remaining
            %% statements, inject them as BodyStmts so NEXT can loop back in-line.
            UpdatedLoopStack = maybe_inject_for_body(NextLoopStack, LoopStack, Pc, Rest),
            case NextState#state.pending_input of
                undefined ->
                    execute_program_line_statements(Rest, Program, NextState, Pc, UpdatedLoopStack, NextCallStack, OutputAcc ++ Output);
                _ ->
                    PendingState = update_pending_input_rest(NextState, Rest),
                    {continue, PendingState, UpdatedLoopStack, NextCallStack, OutputAcc ++ Output}
            end;
        {jump, TargetPc, NextState, NextLoopStack, NextCallStack, Output} ->
            {jump, TargetPc, NextState, NextLoopStack, NextCallStack, OutputAcc ++ Output};
        {'end', Output} ->
            {'end', OutputAcc ++ Output};
        {chain, NewState, Output} ->
            {chain, NewState, OutputAcc ++ Output};
        {break, BreakState, Output} ->
            {break, BreakState, OutputAcc ++ Output};
        {stop, Output} ->
            {stop, OutputAcc ++ Output}
    end.

execute_program_line_statement(Command, Program, State, Pc, LoopStack, CallStack) ->
    put(erlbasic_print_col, State#state.print_col),
    put(erlbasic_open_files, State#state.open_files),
    put(erlbasic_mem_vars, State#state.vars),
    put(erlbasic_mem_funcs, State#state.funcs),
    put(erlbasic_mem_prog, State#state.prog),
    put(erlbasic_mem_data_items, State#state.data_items),
    put(erlbasic_mem_loopstack, LoopStack),
    put(erlbasic_mem_callstack, CallStack),
    LineNumber = get_line_number(Program, Pc),
    ParsedStmt = parse_statement_cached(Command),
    case ParsedStmt of
        {for_loop, Var, StartExpr, EndExpr, StepExpr} ->
            case erlbasic_eval:eval_expr_result(StartExpr, State#state.vars, State#state.funcs) of
                {error, Reason, _} ->
                    {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]};
                {ok, StartValue, Vars1} ->
                    case erlbasic_eval:eval_expr_result(EndExpr, Vars1, State#state.funcs) of
                        {error, Reason, _} ->
                            {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]};
                        {ok, EndValue, Vars2} ->
                            case StepExpr of
                                undefined ->
                                    finalize_for_loop(Var, StartValue, EndValue, 1, Vars2, State, Pc, LoopStack, CallStack);
                                Expr ->
                                    case erlbasic_eval:eval_expr_result(Expr, Vars2, State#state.funcs) of
                                        {error, Reason, _} ->
                                            {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]};
                                        {ok, RawStepValue, _} ->
                                            finalize_for_loop(
                                                Var,
                                                StartValue,
                                                EndValue,
                                                erlbasic_eval:normalize_int(RawStepValue),
                                                Vars2,
                                                State,
                                                Pc,
                                                LoopStack,
                                                CallStack)
                                    end
                            end
                    end
            end;
        {def_fn, FnName, ArgVar, FnExpr} ->
            NextFuncs = maps:put(FnName, {ArgVar, FnExpr}, State#state.funcs),
            {continue, State#state{funcs = NextFuncs}, LoopStack, CallStack, []};
        {next_loop, MaybeVar} ->
            handle_next_statement(MaybeVar, Program, State, Pc, LoopStack, CallStack);
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case erlbasic_eval:eval_condition_result(CondExpr, State#state.vars, State#state.funcs) of
                {ok, true} ->
                    case string:trim(ThenStmt) of
                        "" ->
                            {continue, State, LoopStack, CallStack, []};
                        SelectedThen ->
                            execute_program_inline_sequence(SelectedThen, Program, State, Pc, LoopStack, CallStack)
                    end;
                {ok, false} ->
                    case ElseStmt of
                        undefined ->
                            {continue, State, LoopStack, CallStack, []};
                        ElseBody ->
                            case string:trim(ElseBody) of
                                "" ->
                                    {continue, State, LoopStack, CallStack, []};
                                SelectedElse ->
                                    execute_program_inline_sequence(SelectedElse, Program, State, Pc, LoopStack, CallStack)
                            end
                    end;
                {error, Reason} ->
                    {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]}
            end;
        {goto, LineExpr} ->
            execute_goto(LineExpr, Program, State, Pc, LoopStack, CallStack);
        {gosub, LineExpr} ->
            execute_gosub(LineExpr, Program, State, Pc, LoopStack, CallStack);
        {on_goto, Expr, Targets} ->
            execute_on_goto(Expr, Targets, Program, State, Pc, LoopStack, CallStack);
        {on_gosub, Expr, Targets} ->
            execute_on_gosub(Expr, Targets, Program, State, Pc, LoopStack, CallStack);
        {'return'} ->
            execute_return(Program, State, Pc, LoopStack, CallStack);
        {input, Targets} ->
            case erlang:get(erlbasic_conn_type) of
                home_bas ->
                    {continue, State, LoopStack, CallStack, []};
                _ ->
                    PromptState = State#state{pending_input = {Targets, {program, Pc, [], LoopStack, CallStack}}},
                    {continue, PromptState, LoopStack, CallStack, [format_input_prompt(Targets)]}
            end;
        {input_line, Target} ->
            case erlang:get(erlbasic_conn_type) of
                home_bas ->
                    {continue, State, LoopStack, CallStack, []};
                _ ->
                    PromptState = State#state{pending_input = {input_line, Target, {program, Pc, [], LoopStack, CallStack}}},
                    {continue, PromptState, LoopStack, CallStack, [format_input_prompt(Target)]}
            end;
        {get, Target} ->
            %% Non-blocking but cooperative: take first buffered char, or suspend
            %% so the conn layer can yield the CPU before returning "".
            case erlang:get(erlbasic_conn_type) of
                home_bas ->
                    {continue, State, LoopStack, CallStack, []};
                _ ->
                    case State#state.char_buffer of
                        [Ch | Rest] ->
                            case erlbasic_eval:assign_target(Target, [Ch], State#state.vars, State#state.funcs) of
                                {ok, Vars1} ->
                                    {continue, State#state{vars = Vars1, char_buffer = Rest}, LoopStack, CallStack, []};
                                {error, Reason} ->
                                    {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]}
                            end;
                        [] ->
                            PendingState = State#state{pending_input = {get_nb, Target, {program, Pc, [], LoopStack, CallStack}}},
                            {continue, PendingState, LoopStack, CallStack, []}
                    end
            end;
        {getkey, Target} ->
            case erlang:get(erlbasic_conn_type) of
                home_bas ->
                    {continue, State, LoopStack, CallStack, []};
                _ ->
                    case State#state.char_buffer of
                        [Ch | Rest] ->
                            case erlbasic_eval:assign_target(Target, [Ch], State#state.vars, State#state.funcs) of
                                {ok, Vars1} ->
                                    {continue, State#state{vars = Vars1, char_buffer = Rest}, LoopStack, CallStack, []};
                                {error, Reason} ->
                                    {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]}
                            end;
                        [] ->
                            PendingState = State#state{pending_input = {getkey, Target, {program, Pc, [], LoopStack, CallStack}}},
                            {continue, PendingState, LoopStack, CallStack, []}
                    end
            end;
        {sleep_keypress} ->
            case erlang:get(erlbasic_conn_type) of
                home_bas ->
                    {continue, State, LoopStack, CallStack, []};
                _ ->
                    case State#state.char_buffer of
                        [_ | Rest] ->
                            %% Buffered input available — consume one char and continue
                            {continue, State#state{char_buffer = Rest}, LoopStack, CallStack, []};
                        [] ->
                            PendingState = State#state{pending_input = {sleep_keypress, {program, Pc, [], LoopStack, CallStack}}},
                            {continue, PendingState, LoopStack, CallStack, []}
                    end
            end;
        {'end'} ->
            {'end', []};
        {parse_error, Reason} ->
            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack);
        _ ->
            execute_basic_statement(ParsedStmt, State, Pc, LoopStack, CallStack)
    end.

execute_basic_statement(ParsedStmt, State, Pc, LoopStack, CallStack) ->
    Program = State#state.prog,
    LineNumber = get_line_number(Program, Pc),
    case ParsedStmt of
        {data, _Items} ->
            {continue, State, LoopStack, CallStack, []};
        {restore, all} ->
            {continue, State#state{data_index = 1}, LoopStack, CallStack, []};
        {restore, LineExpr} ->
            case erlbasic_eval:eval_expr_result(LineExpr, State#state.vars, State#state.funcs) of
                {ok, LineNum, Vars1} ->
                    TargetLine = erlbasic_eval:normalize_int(LineNum),
                    NewItems = collect_program_data_from_line(State#state.prog, TargetLine),
                    {continue, State#state{vars = Vars1, data_items = NewItems, data_index = 1}, LoopStack, CallStack, []};
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {home_publish} ->
            case erlang:get(erlbasic_conn_type) of
                home_bas ->
                    erlbasic_home_screen:publish(),
                    {continue, State, LoopStack, CallStack, []};
                _ ->
                    case State#state.char_buffer of
                        [_ | Rest] ->
                            {continue, State#state{char_buffer = Rest}, LoopStack, CallStack, []};
                        [] ->
                            Prompt = "\r\n[Press any key to continue]\r\n",
                            PendingState = State#state{pending_input = {home_publish_keypress, {program, Pc, [], LoopStack, CallStack}}},
                            {continue, PendingState, LoopStack, CallStack, [Prompt]}
                    end
            end;
        {read_data, Targets} ->
            case apply_read_vars(Targets, State) of
                {ok, NextState} ->
                    {continue, NextState, LoopStack, CallStack, []};
                {error, Reason} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {file_open, PathExpr, Mode, ChannelExpr, RecLenExpr} ->
            case erlbasic_fileio:eval_file_open_args(PathExpr, ChannelExpr, RecLenExpr, State#state.vars, State#state.funcs) of
                {ok, PathValue, ChannelValue, RecLenValue, Vars1} ->
                    case erlbasic_fileio:open_file(PathValue, Mode, ChannelValue, RecLenValue, Vars1, State#state{vars = Vars1}) of
                        {ok, Vars2, NextState} ->
                            {continue, NextState#state{vars = Vars2}, LoopStack, CallStack, []};
                        {error, Reason, Vars2} ->
                            handle_runtime_error(Reason, LineNumber, State#state{vars = Vars2}, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {file_close, all} ->
            case erlbasic_fileio:close_file(all, State) of
                {ok, NextState} -> {continue, NextState, LoopStack, CallStack, []};
                {error, Reason, ErrState} -> handle_runtime_error(Reason, LineNumber, ErrState, Pc, LoopStack, CallStack)
            end;
        {file_close, ChannelExprs} ->
            case erlbasic_fileio:eval_file_close_channels(ChannelExprs, State#state.vars, State#state.funcs, []) of
                {ok, Channels, Vars1} ->
                    case erlbasic_fileio:close_file(Channels, State#state{vars = Vars1}) of
                        {ok, NextState} -> {continue, NextState#state{vars = Vars1}, LoopStack, CallStack, []};
                        {error, Reason, ErrState} -> handle_runtime_error(Reason, LineNumber, ErrState, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {file_print, ChannelExpr, Items, EndWithNewline} ->
            case erlbasic_eval:eval_expr_result(ChannelExpr, State#state.vars, State#state.funcs) of
                {ok, ChannelValue, Vars1} ->
                    case erlbasic_fileio:print_file(ChannelValue, Items, EndWithNewline, Vars1, State#state.funcs, State#state{vars = Vars1}, State#state.print_col) of
                        {ok, Vars2, NextState, _} ->
                            {continue, NextState#state{vars = Vars2}, LoopStack, CallStack, []};
                        {error, Reason, Vars2, NextState, _} ->
                            handle_runtime_error(Reason, LineNumber, NextState#state{vars = Vars2}, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {file_write, ChannelExpr, Exprs} ->
            case erlbasic_eval:eval_expr_result(ChannelExpr, State#state.vars, State#state.funcs) of
                {ok, ChannelValue, Vars1} ->
                    case erlbasic_fileio:write_file(ChannelValue, Exprs, Vars1, State#state.funcs, State#state{vars = Vars1}, State#state.print_col) of
                        {ok, Vars2, NextState} ->
                            {continue, NextState#state{vars = Vars2}, LoopStack, CallStack, []};
                        {error, Reason, Vars2, NextState} ->
                            handle_runtime_error(Reason, LineNumber, NextState#state{vars = Vars2}, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {file_input, ChannelExpr, Targets} ->
            case erlbasic_eval:eval_expr_result(ChannelExpr, State#state.vars, State#state.funcs) of
                {ok, ChannelValue, Vars1} ->
                    case erlbasic_fileio:input_file(ChannelValue, Targets, Vars1, State#state.funcs, State#state{vars = Vars1}, State#state.print_col) of
                        {ok, Vars2, NextState} ->
                            {continue, NextState#state{vars = Vars2}, LoopStack, CallStack, []};
                        {error, Reason, Vars2, NextState} ->
                            handle_runtime_error(Reason, LineNumber, NextState#state{vars = Vars2}, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {file_line_input, ChannelExpr, Target} ->
            case erlbasic_eval:eval_expr_result(ChannelExpr, State#state.vars, State#state.funcs) of
                {ok, ChannelValue, Vars1} ->
                    case erlbasic_fileio:line_input_file(ChannelValue, Target, Vars1, State#state.funcs, State#state{vars = Vars1}, State#state.print_col) of
                        {ok, Vars2, NextState} ->
                            {continue, NextState#state{vars = Vars2}, LoopStack, CallStack, []};
                        {error, Reason, Vars2, NextState} ->
                            handle_runtime_error(Reason, LineNumber, NextState#state{vars = Vars2}, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {file_field, ChannelExpr, Specs} ->
            case erlbasic_eval:eval_expr_result(ChannelExpr, State#state.vars, State#state.funcs) of
                {ok, ChannelValue, Vars1} ->
                    case erlbasic_fileio:field_file(ChannelValue, Specs, Vars1, State#state.funcs, State#state{vars = Vars1}) of
                        {ok, Vars2, NextState} ->
                            {continue, NextState#state{vars = Vars2}, LoopStack, CallStack, []};
                        {error, Reason, Vars2} ->
                            handle_runtime_error(Reason, LineNumber, State#state{vars = Vars2}, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {file_put_record, ChannelExpr, RecordExpr} ->
            case erlbasic_fileio:eval_channel_record(ChannelExpr, RecordExpr, State#state.vars, State#state.funcs) of
                {ok, ChannelValue, RecordValue, Vars1} ->
                    case erlbasic_fileio:put_record(ChannelValue, RecordValue, Vars1, State#state.funcs, State#state{vars = Vars1}) of
                        {ok, Vars2, NextState} ->
                            {continue, NextState#state{vars = Vars2}, LoopStack, CallStack, []};
                        {error, Reason, Vars2} ->
                            handle_runtime_error(Reason, LineNumber, State#state{vars = Vars2}, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {file_get_record, ChannelExpr, RecordExpr} ->
            case erlbasic_fileio:eval_channel_record(ChannelExpr, RecordExpr, State#state.vars, State#state.funcs) of
                {ok, ChannelValue, RecordValue, Vars1} ->
                    case erlbasic_fileio:get_record(ChannelValue, RecordValue, Vars1, State#state.funcs, State#state{vars = Vars1}, State#state.print_col) of
                        {ok, Vars2, NextState} ->
                            {continue, NextState#state{vars = Vars2}, LoopStack, CallStack, []};
                        {error, Reason, Vars2, NextState} ->
                            handle_runtime_error(Reason, LineNumber, NextState#state{vars = Vars2}, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State#state{vars = Vars1}, Pc, LoopStack, CallStack)
            end;
        {dim, Decls} ->
            case apply_dim_decls(Decls, State) of
                {ok, NextState} ->
                    {continue, NextState, LoopStack, CallStack, []};
                {error, Reason} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {print, Items, EndWithNewline} ->
            case render_print_items(Items, State#state.vars, State#state.funcs, State#state.print_col) of
                {ok, Vars1, Text, NextCol} ->
                    FinalText =
                        case EndWithNewline of
                            true -> Text ++ "\r\n";
                            false -> Text
                        end,
                    FinalCol =
                        case EndWithNewline of
                            true -> 0;
                            false -> NextCol
                        end,
                    case erlang:get(erlbasic_conn_type) of
                        home_bas ->
                            erlbasic_home_screen:write_text(FinalText),
                            {continue, State#state{vars = Vars1, print_col = FinalCol}, LoopStack, CallStack, []};
                        _ ->
                            {continue, State#state{vars = Vars1, print_col = FinalCol}, LoopStack, CallStack, [FinalText]}
                    end;
                {error, Reason, _Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {print_using, FormatExpr, Items, EndWithNewline} ->
            case erlbasic_eval:eval_expr_result(FormatExpr, State#state.vars, State#state.funcs) of
                {ok, FormatValue, Vars1} when is_list(FormatValue) ->
                    case render_print_using_items(Items, FormatValue, Vars1, State#state.funcs, State#state.print_col) of
                        {ok, Vars2, Text, NextCol} ->
                            FinalText =
                                case EndWithNewline of
                                    true -> Text ++ "\r\n";
                                    false -> Text
                                end,
                            FinalCol =
                                case EndWithNewline of
                                    true -> 0;
                                    false -> NextCol
                                end,
                            case erlang:get(erlbasic_conn_type) of
                                home_bas ->
                                    erlbasic_home_screen:write_text(FinalText),
                                    {continue, State#state{vars = Vars2, print_col = FinalCol}, LoopStack, CallStack, []};
                                _ ->
                                    {continue, State#state{vars = Vars2, print_col = FinalCol}, LoopStack, CallStack, [FinalText]}
                            end;
                        {error, Reason, _Vars2} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end;
                {ok, _Other, _Vars1} ->
                    handle_runtime_error(type_mismatch, LineNumber, State, Pc, LoopStack, CallStack);
                {error, Reason, _Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {'let', Target, Expr} ->
            case erlbasic_eval:eval_expr_result(Expr, State#state.vars, State#state.funcs) of
                {ok, Value, Vars1} ->
                    case erlbasic_eval:assign_target(Target, Value, Vars1, State#state.funcs) of
                        {ok, Vars2} ->
                            {continue, State#state{vars = Vars2}, LoopStack, CallStack, []};
                        {error, Reason} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end;
                {error, Reason, _Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {locate, RowExpr, ColExpr} ->
            case eval_locate(RowExpr, ColExpr, State#state.vars, State#state.funcs) of
                {ok, Vars1, Output} ->
                    {continue, State#state{vars = Vars1}, LoopStack, CallStack, Output};
                {error, Reason, _Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {input, Targets} ->
            PromptState = State#state{pending_input = {Targets, {program, Pc, [], LoopStack, CallStack}}},
            {continue, PromptState, LoopStack, CallStack, [format_input_prompt(Targets)]};
        {input_line, Target} ->
            PromptState = State#state{pending_input = {input_line, Target, {program, Pc, [], LoopStack, CallStack}}},
            {continue, PromptState, LoopStack, CallStack, [format_input_prompt(Target)]};
        {cls} ->
            case erlang:get(erlbasic_conn_type) of
                home_bas ->
                    erlbasic_home_screen:cls(),
                    {continue, State, LoopStack, CallStack, []};
                _ ->
                    {continue, State, LoopStack, CallStack, cls_output()}
            end;
        {hgr} ->
            case erlang:get(erlbasic_conn_type) of
                websocket ->
                    {continue,
                     State#state{graphics_mode = hgr, graphics_pen = undefined, sprites = #{}, sprite_active_collisions = []},
                     LoopStack,
                     CallStack,
                     hgr_output() ++ sprite_clear_output()};
                home_bas ->
                    erlbasic_home_screen:set_gfx_mode(hgr),
                    {continue,
                     State#state{graphics_mode = hgr, graphics_pen = undefined},
                     LoopStack, CallStack, []};
                _ ->
                    handle_runtime_error(graphics_not_supported_on_tty, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {hgr2} ->
            case erlang:get(erlbasic_conn_type) of
                websocket ->
                    {continue,
                     State#state{graphics_mode = hgr2, graphics_pen = undefined, sprites = #{}, sprite_active_collisions = []},
                     LoopStack,
                     CallStack,
                     hgr2_output() ++ sprite_clear_output()};
                home_bas ->
                    erlbasic_home_screen:set_gfx_mode(hgr2),
                    {continue,
                     State#state{graphics_mode = hgr2, graphics_pen = undefined},
                     LoopStack, CallStack, []};
                _ ->
                    handle_runtime_error(graphics_not_supported_on_tty, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {text} ->
            case erlang:get(erlbasic_conn_type) of
                websocket ->
                    {continue,
                     State#state{graphics_mode = false, graphics_pen = undefined, sprites = #{}, sprite_active_collisions = []},
                     LoopStack,
                     CallStack,
                     text_output() ++ sprite_clear_output()};
                home_bas ->
                    erlbasic_home_screen:gfx_text_mode(),
                    {continue,
                     State#state{graphics_mode = false, graphics_pen = undefined},
                     LoopStack, CallStack, []};
                _ ->
                    handle_runtime_error(graphics_not_supported_on_tty, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {pset, XExpr, YExpr, ColorExpr} ->
            case State#state.graphics_mode of
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack);
                _ ->
                    case eval_pset(XExpr, YExpr, ColorExpr, State#state.vars, State#state.funcs) of
                        {ok, Vars1, Output} ->
                            {continue, State#state{vars = Vars1}, LoopStack, CallStack, Output};
                        {error, Reason, _Vars1} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end
            end;
        {line, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr} ->
            case State#state.graphics_mode of
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack);
                _ ->
                    case eval_line(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, State#state.vars, State#state.funcs) of
                        {ok, Vars1, Output, X2, Y2} ->
                            {continue, State#state{vars = Vars1, graphics_pen = {X2, Y2}}, LoopStack, CallStack, Output};
                        {error, Reason, _Vars1} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end
            end;
        {lineto, XExpr, YExpr, ColorExpr} ->
            case State#state.graphics_mode of
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack);
                _ ->
                    case State#state.graphics_pen of
                        {X1, Y1} ->
                            case eval_lineto(XExpr, YExpr, ColorExpr, X1, Y1, State#state.vars, State#state.funcs) of
                                {ok, Vars1, Output, X2, Y2} ->
                                    {continue, State#state{vars = Vars1, graphics_pen = {X2, Y2}}, LoopStack, CallStack, Output};
                                {error, Reason, _Vars1} ->
                                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                            end;
                        undefined ->
                            handle_runtime_error(no_previous_line, LineNumber, State, Pc, LoopStack, CallStack)
                    end
            end;
        {rect, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr} ->
            case State#state.graphics_mode of
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack);
                _ ->
                    case eval_rect(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, State#state.vars, State#state.funcs) of
                        {ok, Vars1, Output} ->
                            {continue, State#state{vars = Vars1}, LoopStack, CallStack, Output};
                        {error, Reason, _Vars1} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end
            end;
        {circle, XExpr, YExpr, RadiusExpr, ColorExpr} ->
            case State#state.graphics_mode of
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack);
                _ ->
                    case eval_circle(XExpr, YExpr, RadiusExpr, ColorExpr, State#state.vars, State#state.funcs) of
                        {ok, Vars1, Output} ->
                            {continue, State#state{vars = Vars1}, LoopStack, CallStack, Output};
                        {error, Reason, _Vars1} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end
            end;
        {sleep, Expr} ->
            case erlbasic_eval:eval_expr_result(Expr, State#state.vars, State#state.funcs) of
                {ok, Value, Vars1} when is_number(Value) ->
                    case erlang:get(erlbasic_conn_type) of
                        home_bas ->
                            %% Skip sleeping when rendering the homepage.
                            {continue, State#state{vars = Vars1}, LoopStack, CallStack, []};
                        _ ->
                            %% BUFFER mode still flushes before SLEEP so paused frames/text are visible.
                            erlang:put(explicit_flush_requested, true),
                            Ms = min(300000, max(0, trunc(Value * 1000))),
                            receive
                                interrupt             -> erlang:put(interrupted, true);
                                memory_limit_exceeded -> erlang:put(memory_limit_exceeded, true)
                            after Ms -> ok end,
                            {continue, State#state{vars = Vars1}, LoopStack, CallStack, []}
                    end;
                {ok, _Value, _Vars1} ->
                    handle_runtime_error(type_mismatch, LineNumber, State, Pc, LoopStack, CallStack);
                {error, Reason, _Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {sound, VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr} ->
            case eval_sound(VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr, State#state.vars, State#state.funcs) of
                {ok, Vars1, Output} ->
                    {continue, State#state{vars = Vars1}, LoopStack, CallStack, Output};
                {error, Reason, _Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {remark} ->
            {continue, State, LoopStack, CallStack, []};
        {color, FgExpr, BgExpr} ->
            case eval_color(FgExpr, BgExpr, State#state.vars, State#state.funcs) of
                {ok, Vars1, Output} ->
                    {continue, State#state{vars = Vars1}, LoopStack, CallStack, Output};
                {error, Reason, _Vars1} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {tron} ->
            {continue, State#state{trace_enabled = true}, LoopStack, CallStack, []};
        {troff} ->
            {continue, State#state{trace_enabled = false}, LoopStack, CallStack, []};
        {flush_stmt} ->
            %% Mark that the accumulator should be flushed after this line.
            %% No-op on non-WebSocket connections (nothing is buffered anyway).
            erlang:put(explicit_flush_requested, true),
            {continue, State, LoopStack, CallStack, []};
        {buffer_mode, on} ->
            case erlang:get(erlbasic_conn_type) of
                websocket ->
                    {continue, State#state{dblbuff = true}, LoopStack, CallStack, []};
                _ ->
                    handle_runtime_error(ws_only, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {buffer_mode, off} ->
            {continue, State#state{dblbuff = false}, LoopStack, CallStack, []};
        {pget, XExpr, YExpr, Target} ->
            case erlang:get(erlbasic_conn_type) of
                websocket ->
                    case State#state.graphics_mode of
                        false ->
                            handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack);
                        Mode ->
                            case eval_exprs([XExpr, YExpr], State#state.vars, State#state.funcs) of
                                {ok, [{X, _}, {Y, Vars1}]} when is_number(X), is_number(Y) ->
                                    Xi = trunc(X), Yi = trunc(Y),
                                    MaxY = case Mode of hgr -> 599; _ -> 479 end,
                                    case Xi >= 0 andalso Xi =< 799 andalso Yi >= 0 andalso Yi =< MaxY of
                                        true ->
                                            Output = [io_lib:format("\x02GFX:PGET:~B:~B", [Xi, Yi])],
                                            PendingState = State#state{
                                                vars = Vars1,
                                                pending_input = {pget_query, Target, {program, Pc, [], LoopStack, CallStack}}
                                            },
                                            {continue, PendingState, LoopStack, CallStack, Output};
                                        false ->
                                            handle_runtime_error(illegal_function_call, LineNumber, State, Pc, LoopStack, CallStack)
                                    end;
                                {ok, _} ->
                                    handle_runtime_error(type_mismatch, LineNumber, State, Pc, LoopStack, CallStack);
                                {error, Reason, _} ->
                                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                            end
                    end;
                _ ->
                    handle_runtime_error(ws_only, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {getchar, RowExpr, ColExpr, Target} ->
            case erlang:get(erlbasic_conn_type) of
                websocket ->
                    case eval_exprs([RowExpr, ColExpr], State#state.vars, State#state.funcs) of
                        {ok, [{Row, _}, {Col, Vars1}]} when is_number(Row), is_number(Col) ->
                            RowI = trunc(Row), ColI = trunc(Col),
                            Valid = case State#state.graphics_mode of
                                hgr  -> false;  %% full graphics — no text rows
                                hgr2 -> RowI >= 22 andalso RowI =< 25 andalso ColI >= 1 andalso ColI =< 80;
                                false -> RowI >= 1  andalso RowI =< 25 andalso ColI >= 1 andalso ColI =< 80
                            end,
                            case Valid of
                                true ->
                                    Output = [io_lib:format("\x02TXT:GETCHAR:~B:~B", [RowI, ColI])],
                                    PendingState = State#state{
                                        vars = Vars1,
                                        pending_input = {getchar_query, Target, {program, Pc, [], LoopStack, CallStack}}
                                    },
                                    {continue, PendingState, LoopStack, CallStack, Output};
                                false ->
                                    handle_runtime_error(illegal_function_call, LineNumber, State, Pc, LoopStack, CallStack)
                            end;
                        {ok, _} ->
                            handle_runtime_error(type_mismatch, LineNumber, State, Pc, LoopStack, CallStack);
                        {error, Reason, _} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end;
                _ ->
                    handle_runtime_error(ws_only, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {on_error_goto, TargetExpr} ->
            execute_on_error_goto(TargetExpr, Program, State, Pc, LoopStack, CallStack);
        {resume} ->
            execute_resume(State, Pc, LoopStack, CallStack);
        {resume_next} ->
            execute_resume_next(State, Pc, LoopStack, CallStack);
        {resume_line, LineExpr} ->
            execute_resume_line(LineExpr, Program, State, Pc, LoopStack, CallStack);
        {chain, FileExpr} ->
            execute_chain(FileExpr, LineNumber, State);
        {common, Names} ->
            Existing = State#state.common_vars,
            NewCommon = lists:usort(Existing ++ Names),
            {continue, State#state{common_vars = NewCommon}, LoopStack, CallStack, []};
        {sprite_clear} = Stmt ->
            case execute_sprite_stmt(Stmt, State) of
                {ok, NextState, Output} ->
                    {continue, NextState, LoopStack, CallStack, Output};
                {error, Reason, ErrState} ->
                    handle_runtime_error(Reason, LineNumber, ErrState, Pc, LoopStack, CallStack)
            end;
        {sprite_hide, _} = Stmt ->
            case execute_sprite_stmt(Stmt, State) of
                {ok, NextState, Output} ->
                    {continue, NextState, LoopStack, CallStack, Output};
                {error, Reason, ErrState} ->
                    handle_runtime_error(Reason, LineNumber, ErrState, Pc, LoopStack, CallStack)
            end;
        {sprite_show, _} = Stmt ->
            case execute_sprite_stmt(Stmt, State) of
                {ok, NextState, Output} ->
                    {continue, NextState, LoopStack, CallStack, Output};
                {error, Reason, ErrState} ->
                    handle_runtime_error(Reason, LineNumber, ErrState, Pc, LoopStack, CallStack)
            end;
        {sprite_scale, _, _} = Stmt ->
            case execute_sprite_stmt(Stmt, State) of
                {ok, NextState, Output} ->
                    {continue, NextState, LoopStack, CallStack, Output};
                {error, Reason, ErrState} ->
                    handle_runtime_error(Reason, LineNumber, ErrState, Pc, LoopStack, CallStack)
            end;
        {sprite_move, _, _, _} = Stmt ->
            case execute_sprite_stmt(Stmt, State) of
                {ok, NextState, Output} ->
                    {continue, NextState, LoopStack, CallStack, Output};
                {error, Reason, ErrState} ->
                    handle_runtime_error(Reason, LineNumber, ErrState, Pc, LoopStack, CallStack)
            end;
        {sprite_load, _, _, _, _} = Stmt ->
            case execute_sprite_stmt(Stmt, State) of
                {ok, NextState, Output} ->
                    {continue, NextState, LoopStack, CallStack, Output};
                {error, Reason, ErrState} ->
                    handle_runtime_error(Reason, LineNumber, ErrState, Pc, LoopStack, CallStack)
            end;
        {play_stmt, Expr} ->
            case erlang:get(erlbasic_conn_type) of
                websocket ->
                    case execute_play(Expr, State) of
                        {ok, NewState, Output} ->
                            {continue, NewState, LoopStack, CallStack, Output};
                        {error, Reason} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end;
                _ ->
                    handle_runtime_error(play_not_supported_on_tty, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {on_play_gosub, NExpr, TargetExpr} ->
            {continue, State#state{on_play_gosub = {NExpr, TargetExpr}}, LoopStack, CallStack, []};
        {on_timer_gosub, NExpr, TargetExpr} ->
            {continue, State#state{on_timer_gosub = {NExpr, TargetExpr}, on_timer_last_ms = undefined}, LoopStack, CallStack, []};
        {on_sprite_gosub, TargetExpr} ->
            {continue, State#state{on_sprite_gosub = TargetExpr}, LoopStack, CallStack, []};
        {stop_stmt} ->
            BreakState = State#state{continue_ctx = {Pc + 1, LoopStack, CallStack}},
            {break, BreakState, [io_lib:format("BREAK IN ~B\r\n", [LineNumber])]};
        {'end'} ->
            {'end', []};
        {parse_error, Reason} ->
            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack);
        _ ->
            handle_runtime_error(syntax_error, LineNumber, State, Pc, LoopStack, CallStack)
    end.

finalize_for_loop(Var, StartValue, EndValue, StepValue, Vars2, State, Pc, LoopStack, CallStack) ->
    NormalizedStep =
        case StepValue of
            0 -> 1;
            _ -> StepValue
        end,
    StartInt = erlbasic_eval:normalize_int(StartValue),
    EndInt = erlbasic_eval:normalize_int(EndValue),
    Vars3 = maps:put(Var, StartInt, Vars2),
    NextState = State#state{vars = Vars3},
    Frame = {Var, EndInt, NormalizedStep, Pc, []},
    {continue, NextState, [Frame | LoopStack], CallStack, []}.

execute_program_inline_sequence(StatementText, Program, State, Pc, LoopStack, CallStack) ->
    execute_program_line_statements(erlbasic_parser:split_statements(StatementText), Program, State, Pc, LoopStack, CallStack, []).

%% After a FOR statement fires, if there are remaining statements on the same program
%% line, inject them as BodyStmts in the top-of-stack frame so that NEXT can loop
%% back within the same line instead of jumping to the (non-existent) next line.
maybe_inject_for_body(NewLoopStack, OldLoopStack, Pc, Rest) ->
    case {Rest, NewLoopStack} of
        {[], _} ->
            NewLoopStack;
        {_, [{Var, EndInt, Step, Pc, []} | OldLoopStack]} ->
            [{Var, EndInt, Step, Pc, Rest} | OldLoopStack];
        _ ->
            NewLoopStack
    end.

execute_goto(LineExpr, Program, State, Pc, LoopStack, CallStack) ->
    LineNumber = get_line_number(Program, Pc),
    case resolve_target_pc(LineExpr, Program, State#state.vars, State#state.funcs) of
        {error, Reason} ->
            {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]};
        {ok, TargetPc} ->
            {jump, TargetPc, State, LoopStack, CallStack, []};
        missing ->
            {stop, [erlbasic_eval:format_runtime_error(syntax_error, LineNumber)]}
    end.

execute_gosub(LineExpr, Program, State, Pc, LoopStack, CallStack) ->
    LineNumber = get_line_number(Program, Pc),
    case resolve_target_pc(LineExpr, Program, State#state.vars, State#state.funcs) of
        {error, Reason} ->
            {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]};
        {ok, TargetPc} ->
            {jump, TargetPc, State, LoopStack, [Pc + 1 | CallStack], []};
        missing ->
            {stop, [erlbasic_eval:format_runtime_error(syntax_error, LineNumber)]}
    end.

execute_on_goto(Expr, Targets, Program, State, Pc, LoopStack, CallStack) ->
    LineNumber = get_line_number(Program, Pc),
    case erlbasic_eval:eval_expr_result(Expr, State#state.vars, State#state.funcs) of
        {error, Reason, _} ->
            {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]};
        {ok, IndexValue, _} ->
            Index = erlbasic_eval:normalize_int(IndexValue),
            if
                Index < 1 orelse Index > length(Targets) ->
                    %% Out of range: continue to next statement
                    {continue, State, LoopStack, CallStack, []};
                true ->
                    TargetExpr = lists:nth(Index, Targets),
                    execute_goto(TargetExpr, Program, State, Pc, LoopStack, CallStack)
            end
    end.

execute_on_gosub(Expr, Targets, Program, State, Pc, LoopStack, CallStack) ->
    LineNumber = get_line_number(Program, Pc),
    case erlbasic_eval:eval_expr_result(Expr, State#state.vars, State#state.funcs) of
        {error, Reason, _} ->
            {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]};
        {ok, IndexValue, _} ->
            Index = erlbasic_eval:normalize_int(IndexValue),
            if
                Index < 1 orelse Index > length(Targets) ->
                    %% Out of range: continue to next statement
                    {continue, State, LoopStack, CallStack, []};
                true ->
                    TargetExpr = lists:nth(Index, Targets),
                    execute_gosub(TargetExpr, Program, State, Pc, LoopStack, CallStack)
            end
    end.

resolve_target_pc(LineExpr, Program, Vars, Funcs) ->
    case erlbasic_eval:eval_expr_result(LineExpr, Vars, Funcs) of
        {error, Reason, _} ->
            {error, Reason};
        {ok, LineValue, _} ->
            TargetLine = erlbasic_eval:normalize_int(LineValue),
            case line_to_pc(Program, TargetLine) of
                {ok, TargetPc} -> {ok, TargetPc};
                error -> missing
            end
    end.

execute_return(Program, _State, Pc, _LoopStack, []) ->
    LineNumber = get_line_number(Program, Pc),
    {stop, [erlbasic_eval:format_runtime_error(return_without_gosub, LineNumber)]};
execute_return(_Program, State, _Pc, LoopStack, [ReturnPc | Rest]) ->
    NewState = update_event_return_depths(State, Rest),
    {jump, ReturnPc, NewState, LoopStack, Rest, []}.

resume_program_input(State, Pc, RemainingStatements, LoopStack, CallStack) ->
    Program = State#state.prog,
    case RemainingStatements of
        [] ->
            run_program_lines(Program, Pc + 1, State, LoopStack, CallStack, []);
        _ ->
            case execute_program_line_statements(RemainingStatements, Program, State, Pc, LoopStack, CallStack, []) of
                {continue, NextState, NextLoopStack, NextCallStack, Output} ->
                    case NextState#state.pending_input of
                        undefined ->
                            {FinalState, RestOutput} = run_program_lines(Program, Pc + 1, NextState, NextLoopStack, NextCallStack, []),
                            {FinalState, Output ++ RestOutput};
                        _ ->
                            {NextState, Output}
                    end;
                {jump, TargetPc, NextState, NextLoopStack, NextCallStack, Output} ->
                    case NextState#state.pending_input of
                        undefined ->
                            {FinalState, RestOutput} = run_program_lines(Program, TargetPc, NextState, NextLoopStack, NextCallStack, []),
                            {FinalState, Output ++ RestOutput};
                        _ ->
                            {NextState, Output}
                    end;
                {break, BreakState, Output} ->
                    {BreakState, Output};
                {stop, Output} ->
                    {State, Output};
                {'end', Output} ->
                    {State, Output ++ ["Program ended\r\n"]}
            end
    end.

update_pending_input_rest(State = #state{pending_input = {Targets, {immediate, _OldRemaining}}}, RemainingStatements) when is_list(Targets) ->
    State#state{pending_input = {Targets, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {Targets, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) when is_list(Targets) ->
    State#state{pending_input = {Targets, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State = #state{pending_input = {input_line, Target, {immediate, _OldRemaining}}}, RemainingStatements) ->
    State#state{pending_input = {input_line, Target, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {input_line, Target, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) ->
    State#state{pending_input = {input_line, Target, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State = #state{pending_input = {get_nb, Target, {immediate, _OldRemaining}}}, RemainingStatements) ->
    State#state{pending_input = {get_nb, Target, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {get_nb, Target, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) ->
    State#state{pending_input = {get_nb, Target, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State = #state{pending_input = {getkey, Target, {immediate, _OldRemaining}}}, RemainingStatements) ->
    State#state{pending_input = {getkey, Target, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {getkey, Target, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) ->
    State#state{pending_input = {getkey, Target, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State = #state{pending_input = {sleep_keypress, {immediate, _OldRemaining}}}, RemainingStatements) ->
    State#state{pending_input = {sleep_keypress, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {sleep_keypress, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) ->
    State#state{pending_input = {sleep_keypress, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State = #state{pending_input = {home_publish_keypress, {immediate, _OldRemaining}}}, RemainingStatements) ->
    State#state{pending_input = {home_publish_keypress, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {home_publish_keypress, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) ->
    State#state{pending_input = {home_publish_keypress, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State = #state{pending_input = {pget_query, Target, {immediate, _OldRemaining}}}, RemainingStatements) ->
    State#state{pending_input = {pget_query, Target, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {pget_query, Target, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) ->
    State#state{pending_input = {pget_query, Target, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State = #state{pending_input = {getchar_query, Target, {immediate, _OldRemaining}}}, RemainingStatements) ->
    State#state{pending_input = {getchar_query, Target, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {getchar_query, Target, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) ->
    State#state{pending_input = {getchar_query, Target, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State, _RemainingStatements) ->
    State.

format_input_prompt(_Targets) ->
    "? ".

collect_program_data(Program) ->
    collect_program_data(Program, []).

collect_program_data_from_line(Program, LineNum) ->
    Filtered = lists:dropwhile(fun({LN, _}) -> LN < LineNum end, Program),
    collect_program_data(Filtered).

collect_program_data([], Acc) ->
    lists:reverse(Acc);
collect_program_data([{_LineNumber, Code} | Rest], Acc) ->
    Statements =
        case erlbasic_parser:should_split_top_level_sequence(Code) of
            true -> erlbasic_parser:split_statements(Code);
            false -> [Code]
        end,
    NextAcc = collect_data_from_statements(Statements, Acc),
    collect_program_data(Rest, NextAcc).

collect_data_from_statements([], Acc) ->
    Acc;
collect_data_from_statements([Stmt | Rest], Acc) ->
    NextAcc =
        case erlbasic_parser:parse_statement(Stmt) of
            {data, Items} -> lists:reverse(Items) ++ Acc;
            _ -> Acc
        end,
    collect_data_from_statements(Rest, NextAcc).

apply_read_vars(Targets, State) ->
    apply_read_vars(Targets, State, State#state.vars).

apply_read_vars([], State, VarsAcc) ->
    {ok, State#state{vars = VarsAcc}};
apply_read_vars([Target | Rest], State, VarsAcc) ->
    case read_next_data_item(State) of
        {ok, Item, NextState} ->
            case erlbasic_eval:assign_target(Target, convert_read_item(Target, Item), VarsAcc, State#state.funcs) of
                {ok, NextVars} ->
                    apply_read_vars(Rest, NextState, NextVars);
                {error, Reason} ->
                    {error, Reason}
            end;
        error ->
            {error, out_of_data}
    end.

read_next_data_item(State = #state{data_items = Items, data_index = Index}) ->
    case Index =< length(Items) of
        true ->
            {ok, lists:nth(Index, Items), State#state{data_index = Index + 1}};
        false ->
            error
    end.

convert_read_item(Target, Item) ->
    case erlbasic_eval:target_is_string(Target) of
        true ->
            Item;
        false ->
            case erlbasic_eval:eval_expr_result(Item, #{}) of
                {ok, Value, _} ->
                    case erlbasic_eval:target_is_float(Target) of
                        true -> float(Value);
                        false -> erlbasic_eval:normalize_int(Value)
                    end;
                {error, _, _} -> 0
            end
    end.

eval_locate(RowExpr, ColExpr, Vars, Funcs) ->
    case erlbasic_eval:eval_expr_result(RowExpr, Vars, Funcs) of
        {error, Reason, Vars1} ->
            {error, Reason, Vars1};
        {ok, RowValue, Vars1} ->
            case erlbasic_eval:eval_expr_result(ColExpr, Vars1, Funcs) of
                {error, Reason, Vars2} ->
                    {error, Reason, Vars2};
                {ok, ColValue, Vars2} ->
                    Row = max(1, erlbasic_eval:normalize_int(RowValue)),
                    Col = max(1, erlbasic_eval:normalize_int(ColValue)),
                    case erlang:get(erlbasic_conn_type) of
                        websocket ->
                            {ok, Vars2, [io_lib:format("\e[~B;~BH", [Row, Col])]};
                        home_bas ->
                            erlbasic_home_screen:locate(Row, Col),
                            {ok, Vars2, []};
                        _ ->
                            {error, tty_no_cursor_movement, Vars2}
                    end
            end
    end.

apply_dim_decls(Decls, State) ->
    case apply_dim_decls(Decls, State#state.vars, State#state.funcs) of
        {ok, Vars1} ->
            {ok, State#state{vars = Vars1}};
        {error, Reason} ->
            {error, Reason}
    end.

apply_dim_decls([], VarsAcc, _Funcs) ->
    {ok, VarsAcc};
apply_dim_decls([{Name, DimExprs} | Rest], VarsAcc, Funcs) ->
    case eval_dim_values(DimExprs, VarsAcc, Funcs, []) of
        {ok, Dims} ->
            case erlbasic_eval:declare_array(Name, Dims, VarsAcc) of
                {ok, Vars1} ->
                    apply_dim_decls(Rest, Vars1, Funcs);
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

eval_dim_values([], _Vars, _Funcs, Acc) ->
    {ok, lists:reverse(Acc)};
eval_dim_values([Expr | Rest], Vars, Funcs, Acc) ->
    case erlbasic_eval:eval_expr_result(Expr, Vars, Funcs) of
        {ok, Value, _} ->
            eval_dim_values(Rest, Vars, Funcs, [erlbasic_eval:normalize_int(Value) | Acc]);
        {error, Reason, _} ->
            {error, Reason}
    end.

handle_next_statement(_MaybeVar, Program, _State, Pc, [], _CallStack) ->
    LineNumber = get_line_number(Program, Pc),
    {stop, [erlbasic_eval:format_runtime_error(next_without_for, LineNumber)]};
handle_next_statement(MaybeVar, Program, State, Pc, [{Var, EndInt, Step, ForPc, BodyStmts} | Rest], CallStack) ->
    LineNumber = get_line_number(Program, Pc),
    case MaybeVar of
        undefined ->
            continue_next(Var, EndInt, Step, ForPc, BodyStmts, State, Pc, Program, Rest, CallStack);
        Var ->
            continue_next(Var, EndInt, Step, ForPc, BodyStmts, State, Pc, Program, Rest, CallStack);
        _ ->
            {stop, [erlbasic_eval:format_runtime_error(next_without_for, LineNumber)]}
    end.

continue_next(Var, EndInt, Step, ForPc, BodyStmts, State, _Pc, Program, Rest, CallStack) ->
    Current = maps:get(Var, State#state.vars, 0),
    NextValue = Current + Step,
    Vars1 = maps:put(Var, NextValue, State#state.vars),
    Continue =
        case Step > 0 of
            true -> NextValue =< EndInt;
            false -> NextValue >= EndInt
        end,
    NextState = State#state{vars = Vars1},
    NewLoopStack = [{Var, EndInt, Step, ForPc, BodyStmts} | Rest],
    case Continue of
        true ->
            case BodyStmts of
                [] ->
                    %% Normal case: loop body is on following program lines
                    {jump, ForPc + 1, NextState, NewLoopStack, CallStack, []};
                _ ->
                    %% FOR/NEXT on the same program line: re-execute the body statements
                    execute_program_line_statements(BodyStmts, Program, NextState, ForPc, NewLoopStack, CallStack, [])
            end;
        false ->
            {continue, NextState, Rest, CallStack, []}
    end.

line_to_pc(Program, LineNumber) ->
    line_to_pc(Program, LineNumber, 1).

line_to_pc([{LineNumber, _Code} | _Rest], LineNumber, Index) ->
    {ok, Index};
line_to_pc([_ | Rest], LineNumber, Index) ->
    line_to_pc(Rest, LineNumber, Index + 1);
line_to_pc([], _LineNumber, _Index) ->
    error.

execute_chain(FileExpr, LineNumber, State) ->
    case erlbasic_eval:eval_expr_result(FileExpr, State#state.vars, State#state.funcs) of
        {error, Reason, _} ->
            {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]};
        {ok, FileValue, _} when is_list(FileValue) ->
            CommonNames = State#state.common_vars,
            ChainState = filter_vars_for_chain(State, CommonNames),
            case erlbasic_commands:handle_load_command(ChainState, FileValue) of
                {NewState, ["OK\r\n"]} ->
                    {chain, NewState#state{common_vars = []}, []};
                {_LoadState, ErrorOutput} ->
                    {stop, ErrorOutput}
            end;
        {ok, _Other, _} ->
            {stop, [erlbasic_eval:format_runtime_error(type_mismatch, LineNumber)]}
    end.

filter_vars_for_chain(State, []) ->
    %% No COMMON declared: clear all variables
    State#state{vars = #{}};
filter_vars_for_chain(State, CommonNames) ->
    Vars = State#state.vars,
    CommonSet = sets:from_list(CommonNames),
    %% Variable names are strings (lists); keep only those in CommonSet.
    %% Non-list keys (like the '$ARRAYS$' atom) are handled separately below.
    FilteredScalars = maps:filter(
        fun(Key, _Val) ->
            not is_list(Key) orelse sets:is_element(Key, CommonSet)
        end,
        Vars
    ),
    %% Filter the arrays sub-map to only keep arrays whose name is in CommonSet
    Arrays = erlbasic_eval_arrays:get_arrays(Vars),
    FilteredArrays = maps:filter(
        fun(ArrayName, _Meta) ->
            sets:is_element(ArrayName, CommonSet)
        end,
        Arrays
    ),
    State#state{vars = erlbasic_eval_arrays:put_arrays(FilteredScalars, FilteredArrays)}.

get_line_number(Program, Pc) when Pc >= 1, Pc =< length(Program) ->
    {LineNumber, _Code} = lists:nth(Pc, Program),
    LineNumber;
get_line_number(_Program, _Pc) ->
    undefined.

parse_statement_cached(Command) ->
    Cache0 =
        case erlang:get(stmt_parse_cache) of
            undefined -> #{};
            Cache when is_map(Cache) -> Cache
        end,
    case maps:find(Command, Cache0) of
        {ok, Parsed} ->
            Parsed;
        error ->
            Parsed = erlbasic_parser:parse_statement(Command),
            erlang:put(stmt_parse_cache, maps:put(Command, Parsed, Cache0)),
            Parsed
    end.

drain_interrupt_messages() ->
    receive
        interrupt -> drain_interrupt_messages()
    after 0 ->
        ok
    end.

should_flush_output() ->
    case erlang:get(output_socket) of
        undefined ->
            erlang:get(output_pid) =/= undefined;
        _ ->
            true
    end.

output_contains_newline(OutputParts) ->
    lists:any(fun part_contains_newline/1, OutputParts).

output_contains_control_frame(OutputParts) ->
    lists:any(fun part_is_control_frame/1, OutputParts).

%% Decide whether accumulated output should be flushed immediately.
%% ExplicitFlush: set by the FLUSH statement.
%% In buffer mode: flush only on explicit FLUSH.
%% In normal mode:  flush on newlines or any control frame (existing behaviour).
needs_flush(Output, _Dblbuff, true) ->
    %% Explicit FLUSH always drains the buffer
    _ = Output,
    true;
needs_flush(Output, true, false) ->
    _ = Output,
    false;
needs_flush(Output, false, false) ->
    output_contains_newline(Output) orelse output_contains_control_frame(Output).

%% In BUFFER OFF mode, flush accumulated output when the current statement
%% produced no output. This makes screen-update loops responsive (e.g. text
%% animation that prints with trailing ';' and then advances via NEXT/INPUT/GET).
should_flush_implicit_boundary(Output, Dblbuff, Acc) ->
    (not Dblbuff) andalso (Output =:= []) andalso (Acc =/= []).

%% In BUFFER mode, still flush when execution is waiting for interactive input
%% that should present prior output immediately.
should_flush_for_pending_input(PendingInput) when is_list(PendingInput) ->
    true;
should_flush_for_pending_input({input_line, _Target, _Continuation}) ->
    true;
should_flush_for_pending_input({sleep_keypress, _Continuation}) ->
    true;
should_flush_for_pending_input({home_publish_keypress, _Continuation}) ->
    true;
should_flush_for_pending_input({get_nb, _Target, _Continuation}) ->
    false;
should_flush_for_pending_input({getkey, _Target, _Continuation}) ->
    false;
should_flush_for_pending_input(_Other) ->
    true.

part_contains_newline(Part) ->
    Bin = iolist_to_binary(Part),
    case binary:match(Bin, [<<"\n">>, <<"\r">>]) of
        nomatch -> false;
        _ -> true
    end.

part_is_control_frame(Part) ->
    Bin = iolist_to_binary(Part),
    case Bin of
        <<2, _/binary>> -> true;
        _ -> false
    end.

%% Helper to generate graphics command output for WebSocket connections
graphics_output(Command, Args) ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> [io_lib:format("\x02GFX:" ++ Command, Args)];
        home_bas  -> record_home_gfx(Command, Args), [];
        _ -> []
    end.

%% Route a rendered graphics command to the home_bas display list.
record_home_gfx("PSET:~B:~B:~B", [X, Y, C]) ->
    erlbasic_home_screen:record_gfx({pset, X, Y, C});
record_home_gfx("LINE:~B:~B:~B:~B:~B", [X1, Y1, X2, Y2, C]) ->
    erlbasic_home_screen:record_gfx({line, X1, Y1, X2, Y2, C});
record_home_gfx("RECT:~B:~B:~B:~B:~B", [X1, Y1, X2, Y2, C]) ->
    erlbasic_home_screen:record_gfx({rect, X1, Y1, X2, Y2, C});
record_home_gfx("CIRCLE:~B:~B:~B:~B", [X, Y, R, C]) ->
    erlbasic_home_screen:record_gfx({circle, X, Y, R, C});
record_home_gfx(_, _) ->
    ok.

sound_stop_output() ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> ["\x02SND:STOPALL"];
        _ -> []
    end.

music_stop_output() ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> ["\x02MUS:STOP"];
        _ -> []
    end.

sprite_clear_output() ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> ["\x02GFX:SPRCLR"];
        _ -> []
    end.

music_reset() ->
    erlang:erase(erlbasic_play_schedule),
    erlang:erase(erlbasic_play_cursor).

notes_remaining() ->
    Now = erlang:monotonic_time(millisecond),
    case erlang:get(erlbasic_play_schedule) of
        undefined -> 0;
        List ->
            Remaining = [T || T <- List, T > Now],
            erlang:put(erlbasic_play_schedule, Remaining),
            length(Remaining)
    end.

schedule_notes_in_dict(Notes) ->
    Now = erlang:monotonic_time(millisecond),
    Cursor = case erlang:get(erlbasic_play_cursor) of
        undefined -> Now;
        C         -> max(C, Now)
    end,
    {EndTimes, NewCursor} = lists:foldl(
        fun({_Freq, _Play, TotalMs}, {Acc, Cur}) ->
            E = Cur + TotalMs,
            {[E | Acc], E}
        end,
        {[], Cursor},
        Notes),
    Prev = case erlang:get(erlbasic_play_schedule) of
        undefined -> [];
        S         -> [T || T <- S, T > Now]
    end,
    erlang:put(erlbasic_play_schedule, Prev ++ lists:reverse(EndTimes)),
    erlang:put(erlbasic_play_cursor, NewCursor).

format_mus_queue(Notes) ->
    Parts = [lists:flatten(io_lib:format("~B:~B:~B", [round(F), P, T])) || {F, P, T} <- Notes],
    "\x02MUS:QUEUE:" ++ string:join(Parts, ",").

new_play_background(background, _Current) -> true;
new_play_background(foreground, _Current) -> false;
new_play_background(unchanged, Current)   -> Current.

%% execute_play/2 — shared by program mode (execute_basic_statement) and
%% immediate mode (erlbasic_interp). Returns {ok, NewState, Output} | {error, Reason}.
execute_play(Expr, State) ->
    case erlbasic_eval:eval_expr_result(Expr, State#state.vars, State#state.funcs) of
        {ok, MmlStr, Vars1} when is_list(MmlStr) ->
            case erlbasic_mml:parse(MmlStr) of
                {ok, Notes, FinalMode} ->
                    NewBackground = new_play_background(FinalMode, State#state.play_background),
                    NewState = State#state{vars = Vars1, play_background = NewBackground},
                    case Notes of
                        [] ->
                            {ok, NewState, []};
                        _ ->
                            Output = format_mus_queue(Notes),
                            case NewBackground of
                                true ->
                                    schedule_notes_in_dict(Notes),
                                    {ok, NewState, [Output]};
                                false ->
                                    %% Foreground: flush queued output, then block for the duration.
                                    TotalMs = lists:sum([TMs || {_, _, TMs} <- Notes]),
                                    erlang:put(explicit_flush_requested, true),
                                    receive
                                        interrupt ->
                                            erlang:put(interrupted, true);
                                        memory_limit_exceeded ->
                                            erlang:put(memory_limit_exceeded, true)
                                    after TotalMs -> ok end,
                                    {ok, NewState, [Output]}
                            end
                    end;
                {error, _} ->
                    {error, syntax_error}
            end;
        {ok, _NotAString, _} ->
            {error, type_mismatch};
        {error, Reason, _} ->
            {error, Reason}
    end.

%% execute_sprite_stmt/2 — shared by program mode and immediate mode.
%% Returns {ok, NewState, Output} | {error, Reason, ErrState}.
execute_sprite_stmt(_Stmt, State) when State#state.graphics_mode =:= false ->
    {error, no_graphics_mode, State};
execute_sprite_stmt(_Stmt, State) ->
    try
        case erlang:get(erlbasic_conn_type) of
            websocket -> ok;
            _ -> throw({sprite_error, ws_only, State})
        end,
        execute_sprite_stmt_ws(_Stmt, State)
    catch
        throw:{sprite_error, Reason, ErrState} ->
            {error, Reason, ErrState}
    end.

execute_sprite_stmt_ws({sprite_clear}, State) ->
    {ok, State#state{sprites = #{}, sprite_active_collisions = []}, sprite_clear_output()};
execute_sprite_stmt_ws({sprite_hide, IdExpr}, State) ->
    case eval_exprs([IdExpr], State#state.vars, State#state.funcs) of
        {ok, [{IdV, Vars1}]} when is_number(IdV) ->
            Id = erlbasic_eval:normalize_int(IdV),
            case update_sprite(Id, fun(Spr) -> Spr#{visible => false} end, State#state{vars = Vars1}) of
                {ok, NextState, Spr} ->
                    {ok, NextState, [format_sprite_pos(Id, Spr)]};
                {error, Reason} ->
                    {error, Reason, State#state{vars = Vars1}}
            end;
        {ok, [{_, Vars1}]} ->
            {error, type_mismatch, State#state{vars = Vars1}};
        {error, Reason, Vars1} ->
            {error, Reason, State#state{vars = Vars1}}
    end;
execute_sprite_stmt_ws({sprite_show, IdExpr}, State) ->
    case eval_exprs([IdExpr], State#state.vars, State#state.funcs) of
        {ok, [{IdV, Vars1}]} when is_number(IdV) ->
            Id = erlbasic_eval:normalize_int(IdV),
            case update_sprite(Id, fun(Spr) -> Spr#{visible => true} end, State#state{vars = Vars1}) of
                {ok, NextState, Spr} ->
                    {ok, NextState, [format_sprite_pos(Id, Spr)]};
                {error, Reason} ->
                    {error, Reason, State#state{vars = Vars1}}
            end;
        {ok, [{_, Vars1}]} ->
            {error, type_mismatch, State#state{vars = Vars1}};
        {error, Reason, Vars1} ->
            {error, Reason, State#state{vars = Vars1}}
    end;
execute_sprite_stmt_ws({sprite_scale, IdExpr, ScaleExpr}, State) ->
    case eval_exprs([IdExpr, ScaleExpr], State#state.vars, State#state.funcs) of
        {ok, [{IdV, _}, {ScaleV, Vars1}]} when is_number(IdV), is_number(ScaleV) ->
            Id = erlbasic_eval:normalize_int(IdV),
            Scale = erlbasic_eval:normalize_int(ScaleV),
            if
                Scale < 1 orelse Scale > 64 ->
                    {error, illegal_function_call, State#state{vars = Vars1}};
                true ->
                    case update_sprite(Id, fun(Spr) -> Spr#{scale => Scale} end, State#state{vars = Vars1}) of
                        {ok, NextState, Spr} ->
                            {ok, NextState, [format_sprite_pos(Id, Spr)]};
                        {error, Reason} ->
                            {error, Reason, State#state{vars = Vars1}}
                    end
            end;
        {ok, [{_, _}, {_, Vars1}]} ->
            {error, type_mismatch, State#state{vars = Vars1}};
        {error, Reason, Vars1} ->
            {error, Reason, State#state{vars = Vars1}}
    end;
execute_sprite_stmt_ws({sprite_move, IdExpr, XExpr, YExpr}, State) ->
    case eval_exprs([IdExpr, XExpr, YExpr], State#state.vars, State#state.funcs) of
        {ok, [{IdV, _}, {XV, _}, {YV, Vars1}]} when is_number(IdV), is_number(XV), is_number(YV) ->
            Id = erlbasic_eval:normalize_int(IdV),
            X = erlbasic_eval:normalize_int(XV),
            Y = erlbasic_eval:normalize_int(YV),
            case update_sprite(Id, fun(Spr) -> Spr#{x => X, y => Y, visible => true} end, State#state{vars = Vars1}) of
                {ok, NextState, Spr} ->
                    {ok, NextState, [format_sprite_pos(Id, Spr)]};
                {error, Reason} ->
                    {error, Reason, State#state{vars = Vars1}}
            end;
        {ok, [{_, _}, {_, _}, {_, Vars1}]} ->
            {error, type_mismatch, State#state{vars = Vars1}};
        {error, Reason, Vars1} ->
            {error, Reason, State#state{vars = Vars1}}
    end;
execute_sprite_stmt_ws({sprite_load, IdExpr, WidthExpr, HeightExpr, {array_target, Var, [StartExpr]}}, State) ->
    case erlbasic_eval_arrays:is_byte_var(Var) of
        false ->
            {error, type_mismatch, State};
        true ->
            case eval_exprs([IdExpr, WidthExpr, HeightExpr, StartExpr], State#state.vars, State#state.funcs) of
                {ok, [{IdV, _}, {WV, _}, {HV, _}, {StartV, Vars1}]} when is_number(IdV), is_number(WV), is_number(HV), is_number(StartV) ->
                    Id = erlbasic_eval:normalize_int(IdV),
                    W = erlbasic_eval:normalize_int(WV),
                    H = erlbasic_eval:normalize_int(HV),
                    Start = erlbasic_eval:normalize_int(StartV),
                    if
                        Id < 0; W < 1; H < 1; W > 256; H > 256; Start < 0 ->
                            {error, illegal_function_call, State#state{vars = Vars1}};
                        true ->
                            Count = W * H,
                            case read_sprite_bytes(Var, Start, Count, Vars1, []) of
                                {ok, Pixels} ->
                                    Existing = maps:get(Id, State#state.sprites, #{x => 0, y => 0, visible => false, scale => 1}),
                                    Sprite = Existing#{w => W, h => H, pixels => Pixels},
                                    NextSprites = maps:put(Id, Sprite, State#state.sprites),
                                    NextState = State#state{vars = Vars1, sprites = NextSprites},
                                    {ok, NextState, [format_sprite_def(Id, Sprite), format_sprite_pos(Id, Sprite)]};
                                {error, Reason} ->
                                    {error, Reason, State#state{vars = Vars1}}
                            end
                    end;
                {ok, [{_, _}, {_, _}, {_, _}, {_, Vars1}]} ->
                    {error, type_mismatch, State#state{vars = Vars1}};
                {error, Reason, Vars1} ->
                    {error, Reason, State#state{vars = Vars1}}
            end
    end;
execute_sprite_stmt_ws(_, State) ->
    {error, syntax_error, State}.

update_sprite(Id, _Fun, _State) when Id < 0 ->
    {error, illegal_function_call};
update_sprite(Id, Fun, State) ->
    case maps:find(Id, State#state.sprites) of
        {ok, Sprite} ->
            case has_sprite_bitmap(Sprite) of
                false -> {error, illegal_function_call};
                true ->
                    NextSprite = Fun(Sprite),
                    {ok, State#state{sprites = maps:put(Id, NextSprite, State#state.sprites)}, NextSprite}
            end;
        error ->
            {error, illegal_function_call}
    end.

has_sprite_bitmap(Sprite) ->
    maps:is_key(w, Sprite) andalso maps:is_key(h, Sprite) andalso maps:is_key(pixels, Sprite).

read_sprite_bytes(_Var, _Index, 0, _Vars, Acc) ->
    {ok, lists:reverse(Acc)};
read_sprite_bytes(Var, Index, N, Vars, Acc) ->
    case erlbasic_eval_arrays:get_array_value(Var, [Index], Vars) of
        {ok, Value} when is_number(Value) ->
            B = erlbasic_eval_arrays:normalize_byte_value(Value),
            read_sprite_bytes(Var, Index + 1, N - 1, Vars, [B | Acc]);
        {ok, _} ->
            {error, type_mismatch};
        {error, Reason} ->
            {error, Reason}
    end.

format_sprite_def(Id, Sprite) ->
    W = maps:get(w, Sprite),
    H = maps:get(h, Sprite),
    Pixels = maps:get(pixels, Sprite),
    PixelText = string:join([integer_to_list(P) || P <- Pixels], ","),
    "\x02GFX:SPRDEF:" ++ integer_to_list(Id) ++ ":" ++ integer_to_list(W) ++ ":" ++ integer_to_list(H) ++ ":" ++ PixelText.

format_sprite_pos(Id, Sprite) ->
    X = maps:get(x, Sprite, 0),
    Y = maps:get(y, Sprite, 0),
    Scale = maps:get(scale, Sprite, 1),
    Visible = case maps:get(visible, Sprite, false) of true -> 1; false -> 0 end,
    "\x02GFX:SPRPOS:" ++ integer_to_list(Id) ++ ":" ++ integer_to_list(X) ++ ":" ++ integer_to_list(Y) ++ ":" ++ integer_to_list(Scale) ++ ":" ++ integer_to_list(Visible).

event_gosub_trigger(State, LoopStack, CallStack) ->
    case on_sprite_trigger(State, LoopStack, CallStack) of
        {gosub, TargetPc, FiredState} ->
            {gosub, TargetPc, FiredState};
        {no_trigger, State1} ->
            case on_play_trigger(State1, LoopStack, CallStack) of
                {gosub, TargetPc, FiredState} ->
                    {gosub, TargetPc, FiredState};
                {no_trigger, State2} ->
                    case on_timer_trigger(State2, LoopStack, CallStack) of
                        {gosub, TargetPc, FiredState} -> {gosub, TargetPc, FiredState};
                        {no_trigger, State3} -> {no_trigger, State3}
                    end
            end
    end.

on_sprite_trigger(State = #state{on_sprite_return_depth = D}, _LoopStack, _CallStack) when D >= 0 ->
    {no_trigger, update_sprite_collision_set(State)};
on_sprite_trigger(State, _LoopStack, CallStack) ->
    State1 = update_sprite_collision_set(State),
    case new_collision_pair(State#state.sprite_active_collisions, State1#state.sprite_active_collisions) of
        none ->
            {no_trigger, State1};
        {Id1, Id2} ->
            case State1#state.on_sprite_gosub of
                undefined ->
                    {no_trigger, State1};
                TargetExpr ->
                    case resolve_target_pc(TargetExpr, State1#state.prog, State1#state.vars, State1#state.funcs) of
                        {ok, TargetPc} ->
                            Vars1 = maps:put("SPRCOL2%", Id2, maps:put("SPRCOL1%", Id1, State1#state.vars)),
                            Depth = length(CallStack),
                            FiredState = State1#state{vars = Vars1, on_sprite_return_depth = Depth},
                            {gosub, TargetPc, FiredState};
                        _ ->
                            {no_trigger, State1}
                    end
            end
    end.

update_sprite_collision_set(State) ->
    Current = sprite_collisions(State#state.sprites),
    State#state{sprite_active_collisions = Current}.

new_collision_pair(Prev, Current) ->
    New = [P || P <- Current, not lists:member(P, Prev)],
    case New of
        [Pair | _] -> Pair;
        [] -> none
    end.

sprite_collisions(SpritesMap) ->
    Visible = [{Id, S} || {Id, S} <- maps:to_list(SpritesMap), maps:get(visible, S, false) =:= true, has_sprite_bitmap(S)],
    sprite_collisions(Visible, []).

sprite_collisions([], Acc) ->
    lists:usort(Acc);
sprite_collisions([{Id1, S1} | Rest], Acc) ->
    NextAcc = lists:foldl(
        fun({Id2, S2}, A) ->
            case sprites_overlap(S1, S2) of
                true -> [ordered_pair(Id1, Id2) | A];
                false -> A
            end
        end,
        Acc,
        Rest),
    sprite_collisions(Rest, NextAcc).

ordered_pair(A, B) when A =< B -> {A, B};
ordered_pair(A, B) -> {B, A}.

sprites_overlap(S1, S2) ->
    {X1, Y1, W1, H1} = sprite_bounds(S1),
    {X2, Y2, W2, H2} = sprite_bounds(S2),
    X1 < X2 + W2 andalso X2 < X1 + W1 andalso Y1 < Y2 + H2 andalso Y2 < Y1 + H1.

sprite_bounds(S) ->
    X = maps:get(x, S, 0),
    Y = maps:get(y, S, 0),
    Scale = max(1, maps:get(scale, S, 1)),
    W = maps:get(w, S, 0) * Scale,
    H = maps:get(h, S, 0) * Scale,
    {X, Y, W, H}.

update_event_return_depths(State, RestCallStack) ->
    RestDepth = length(RestCallStack),
    SpriteDepth = State#state.on_sprite_return_depth,
    NewSpriteDepth =
        case SpriteDepth of
            D1 when D1 >= 0, RestDepth =< D1 -> -1;
            D1 when D1 >= 0 -> D1;
            _ -> SpriteDepth
        end,
    PlayDepth = State#state.on_play_return_depth,
    NewPlayDepth =
        case PlayDepth of
            D2 when D2 >= 0, RestDepth =< D2 -> -1;
            D2 when D2 >= 0 -> D2;
            _ -> PlayDepth
        end,
    TimerDepth = State#state.on_timer_return_depth,
    NewTimerDepth =
        case TimerDepth of
            D3 when D3 >= 0, RestDepth =< D3 -> -1;
            D3 when D3 >= 0 -> D3;
            _ -> TimerDepth
        end,
    State#state{on_sprite_return_depth = NewSpriteDepth, on_play_return_depth = NewPlayDepth, on_timer_return_depth = NewTimerDepth}.

on_play_trigger(State = #state{on_play_gosub = undefined}, _LoopStack, _CallStack) ->
    {no_trigger, State};
on_play_trigger(State = #state{on_play_return_depth = D}, _LoopStack, _CallStack) when D >= 0 ->
    {no_trigger, State};  %% Re-entrancy guard: already executing the handler
on_play_trigger(State = #state{on_play_gosub = {NExpr, TargetExpr}}, _LoopStack, CallStack) ->
    Remaining = notes_remaining(),
    case erlbasic_eval:eval_expr_result(NExpr, State#state.vars, State#state.funcs) of
        {ok, NValue, _} ->
            N = erlbasic_eval:normalize_int(NValue),
            if N > 0, Remaining < N ->
                case resolve_target_pc(TargetExpr, State#state.prog, State#state.vars, State#state.funcs) of
                    {ok, TargetPc} ->
                        Depth = length(CallStack),
                        FiredState = State#state{on_play_return_depth = Depth},
                        {gosub, TargetPc, FiredState};
                    _ ->
                        {no_trigger, State}
                end;
            true ->
                {no_trigger, State}
            end;
        _ ->
            {no_trigger, State}
    end.

on_timer_trigger(State = #state{on_timer_gosub = undefined}, _LoopStack, _CallStack) ->
    {no_trigger, State};
on_timer_trigger(State = #state{on_timer_return_depth = D}, _LoopStack, _CallStack) when D >= 0 ->
    {no_trigger, State};
on_timer_trigger(State = #state{on_timer_gosub = {NExpr, TargetExpr}}, _LoopStack, CallStack) ->
    case erlbasic_eval:eval_expr_result(NExpr, State#state.vars, State#state.funcs) of
        {ok, NValue, _} when is_number(NValue) ->
            IntervalMs = trunc(NValue * 1000),
            if IntervalMs =< 0 ->
                {no_trigger, State};
            true ->
                NowMs = erlang:monotonic_time(millisecond),
                LastMs = case State#state.on_timer_last_ms of
                    undefined -> NowMs;
                    V -> V
                end,
                ArmedState = case State#state.on_timer_last_ms of
                    undefined -> State#state{on_timer_last_ms = LastMs};
                    _ -> State
                end,
                case NowMs - LastMs >= IntervalMs of
                    false ->
                        {no_trigger, ArmedState};
                    true ->
                        case resolve_target_pc(TargetExpr, ArmedState#state.prog, ArmedState#state.vars, ArmedState#state.funcs) of
                            {ok, TargetPc} ->
                                Depth = length(CallStack),
                                FiredState = ArmedState#state{on_timer_return_depth = Depth, on_timer_last_ms = NowMs},
                                {gosub, TargetPc, FiredState};
                            _ ->
                                {no_trigger, ArmedState#state{on_timer_last_ms = NowMs}}
                        end
                end
            end;
        _ ->
            {no_trigger, State}
    end.

%% Helper to evaluate multiple expressions and extract first error
eval_exprs(Exprs, Vars, Funcs) ->
    eval_exprs(Exprs, Vars, Funcs, []).

eval_exprs([], _Vars, _Funcs, Acc) ->
    {ok, lists:reverse(Acc)};
eval_exprs([Expr | Rest], Vars, Funcs, Acc) ->
    case erlbasic_eval:eval_expr_result(Expr, Vars, Funcs) of
        {ok, Value, NewVars} ->
            eval_exprs(Rest, NewVars, Funcs, [{Value, NewVars} | Acc]);
        {error, Reason, VarsErr} ->
            {error, Reason, VarsErr}
    end.


flush_output([]) ->
    ok;
flush_output(Acc) ->
    Output = lists:reverse(Acc),
    %% Check if output should go to WebSocket or TCP socket
    case erlang:get(output_socket) of
        undefined ->
            %% WebSocket mode - send to output_pid
            case erlang:get(output_pid) of
                undefined ->
                    ok;
                Pid ->
                    Packed = pack_websocket_output(Output),
                    lists:foreach(fun(Text) -> Pid ! {output, Text} end, Packed)
            end;
        Socket ->
            %% TCP mode - send directly to socket
            lists:foreach(fun(Text) -> gen_tcp:send(Socket, Text) end, Output)
    end.

%% Batch consecutive graphics control frames into a single websocket frame.
%% This drastically reduces per-frame overhead for large BUFFER+FLUSH updates.
pack_websocket_output(Output) ->
    lists:reverse(pack_websocket_output(Output, [], [])).

pack_websocket_output([], AccRev, []) ->
    AccRev;
pack_websocket_output([], AccRev, GfxCmdsRev) ->
    [make_gfx_batch_frame(GfxCmdsRev) | AccRev];
pack_websocket_output([Text | Rest], AccRev, GfxCmdsRev) ->
    Bin = iolist_to_binary(Text),
    case Bin of
        <<2, "GFX:", Cmd/binary>> ->
            pack_websocket_output(Rest, AccRev, [Cmd | GfxCmdsRev]);
        _ ->
            NextAccRev =
                case GfxCmdsRev of
                    [] -> AccRev;
                    _ -> [make_gfx_batch_frame(GfxCmdsRev) | AccRev]
                end,
            pack_websocket_output(Rest, [Bin | NextAccRev], [])
    end.

make_gfx_batch_frame([SingleCmd]) ->
    <<2, "GFX:", SingleCmd/binary>>;
make_gfx_batch_frame(GfxCmdsRev) ->
    Joined = iolist_to_binary(lists:join(<<"\n">>, lists:reverse(GfxCmdsRev))),
    <<2, "GFXB:", Joined/binary>>.

render_print_items(Items, Vars, Funcs, StartCol) ->
    render_print_items(Items, Vars, Funcs, StartCol, [], StartCol).

render_print_items([], Vars, _Funcs, _StartCol, Acc, Col) ->
    {ok, Vars, lists:flatten(lists:reverse(Acc)), Col};
render_print_items([{Expr, Sep} | Rest], Vars, Funcs, StartCol, Acc, Col) ->
    put(erlbasic_print_col, Col),
    case erlbasic_eval:eval_expr_result(Expr, Vars, Funcs) of
        {ok, Value, Vars1} ->
            Text = erlbasic_eval:format_print_value(Value),
            ColAfterText = Col + length(Text),
            {SepText, ColAfterSep} = print_sep_text(Sep, ColAfterText, StartCol),
            render_print_items(Rest, Vars1, Funcs, StartCol, [SepText, Text | Acc], ColAfterSep);
        {error, Reason, Vars1} ->
            {error, Reason, Vars1}
    end.

print_sep_text(none, Col, _StartCol) ->
    {"", Col};
print_sep_text(semicolon, Col, _StartCol) ->
    {"", Col};
print_sep_text(comma, Col, StartCol) ->
    ZoneWidth = 14,
    RelativeCol = Col - StartCol,
    Pad = ZoneWidth - (RelativeCol rem ZoneWidth),
    Spaces = lists:duplicate(Pad, $\s),
    {Spaces, Col + Pad}.

cls_output() ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> ["\e[0m\e[2J\e[H"];
        _ -> []
    end.

eval_color(FgExpr, BgExpr, Vars, Funcs) ->
    case erlbasic_eval:eval_expr_result(FgExpr, Vars, Funcs) of
        {error, Reason, Vars1} ->
            {error, Reason, Vars1};
        {ok, FgValue, Vars1} ->
            Fg = erlbasic_eval:normalize_int(FgValue),
            case BgExpr of
                undefined ->
                    {ok, Vars1, color_output(Fg, undefined)};
                _ ->
                    case erlbasic_eval:eval_expr_result(BgExpr, Vars1, Funcs) of
                        {error, Reason, Vars2} ->
                            {error, Reason, Vars2};
                        {ok, BgValue, Vars2} ->
                            Bg = erlbasic_eval:normalize_int(BgValue),
                            {ok, Vars2, color_output(Fg, Bg)}
                    end
            end
    end.

color_output(Fg, Bg) ->
    case erlang:get(erlbasic_conn_type) of
        websocket ->
            FgCode = ansi_fg_code(Fg band 15),
            BgCode = case Bg of
                undefined -> [];
                _ -> [io_lib:format("\e[~Bm", [ansi_bg_code(Bg band 7)])]
            end,
            [io_lib:format("\e[~Bm", [FgCode])] ++ BgCode;
        home_bas ->
            erlbasic_home_screen:set_color(Fg, Bg),
            [];
        _ ->
            []
    end.

ansi_fg_code(C) when C >= 8 -> 82 + C;   %% bright: 90-97
ansi_fg_code(C)              -> 30 + C.  %% normal: 30-37

ansi_bg_code(C) -> 40 + C.               %% background: 40-47

%% Graphics mode functions (WebSocket only)
hgr_output() ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> ["\x02GFX:HGR"];
        _ -> []
    end.

hgr2_output() ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> ["\x02GFX:HGR2"];
        _ -> []
    end.

text_output() ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> ["\x02GFX:TEXT"];
        _ -> []
    end.

eval_sound(VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr, Vars, Funcs) ->
    case erlang:get(erlbasic_conn_type) of
        websocket ->
            case eval_exprs([VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr], Vars, Funcs) of
                {ok, [{Voice, _}, {Pitch, _}, {Distortion, _}, {Volume, Vars4}]} ->
                    Ch = clamp(erlbasic_eval:normalize_int(Voice), 0, 3),
                    Pch = clamp(erlbasic_eval:normalize_int(Pitch), 0, 255),
                    Dist = clamp(erlbasic_eval:normalize_int(Distortion), 0, 15),
                    Vol = clamp(erlbasic_eval:normalize_int(Volume), 0, 15),
                    {ok, Vars4, [io_lib:format("\x02SND:~B:~B:~B:~B", [Ch, Pch, Dist, Vol])]};
                {error, Reason, VarsErr} ->
                    {error, Reason, VarsErr}
            end;
        _ ->
            {error, sound_not_supported_on_tty, Vars}
    end.

clamp(Value, Min, _Max) when Value < Min ->
    Min;
clamp(Value, _Min, Max) when Value > Max ->
    Max;
clamp(Value, _Min, _Max) ->
    Value.

eval_pset(XExpr, YExpr, ColorExpr, Vars) ->
    eval_pset(XExpr, YExpr, ColorExpr, Vars, #{}).

eval_pset(XExpr, YExpr, ColorExpr, Vars, Funcs) ->
    case eval_exprs([XExpr, YExpr, ColorExpr], Vars, Funcs) of
        {ok, [{X, _}, {Y, _}, {C, Vars3}]} ->
            IX = erlbasic_eval:normalize_int(X),
            IY = erlbasic_eval:normalize_int(Y),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = graphics_output("PSET:~B:~B:~B", [IX, IY, IC]),
            {ok, Vars3, Output};
        {error, Reason, VarsErr} ->
            {error, Reason, VarsErr}
    end.

eval_line(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars) ->
    eval_line(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars, #{}).

eval_line(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars, Funcs) ->
    case eval_exprs([X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr], Vars, Funcs) of
        {ok, [{X1, _}, {Y1, _}, {X2, _}, {Y2, _}, {C, Vars5}]} ->
            IX1 = erlbasic_eval:normalize_int(X1),
            IY1 = erlbasic_eval:normalize_int(Y1),
            IX2 = erlbasic_eval:normalize_int(X2),
            IY2 = erlbasic_eval:normalize_int(Y2),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = graphics_output("LINE:~B:~B:~B:~B:~B", [IX1, IY1, IX2, IY2, IC]),
            {ok, Vars5, Output, IX2, IY2};
        {error, Reason, VarsErr} ->
            {error, Reason, VarsErr}
    end.

eval_lineto(XExpr, YExpr, ColorExpr, X1, Y1, Vars, Funcs) ->
    case eval_exprs([XExpr, YExpr, ColorExpr], Vars, Funcs) of
        {ok, [{X2, _}, {Y2, _}, {C, Vars3}]} ->
            IX2 = erlbasic_eval:normalize_int(X2),
            IY2 = erlbasic_eval:normalize_int(Y2),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = graphics_output("LINE:~B:~B:~B:~B:~B", [X1, Y1, IX2, IY2, IC]),
            {ok, Vars3, Output, IX2, IY2};
        {error, Reason, VarsErr} ->
            {error, Reason, VarsErr}
    end.

eval_rect(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars) ->
    eval_rect(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars, #{}).

eval_rect(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars, Funcs) ->
    case eval_exprs([X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr], Vars, Funcs) of
        {ok, [{X1, _}, {Y1, _}, {X2, _}, {Y2, _}, {C, Vars5}]} ->
            IX1 = erlbasic_eval:normalize_int(X1),
            IY1 = erlbasic_eval:normalize_int(Y1),
            IX2 = erlbasic_eval:normalize_int(X2),
            IY2 = erlbasic_eval:normalize_int(Y2),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = graphics_output("RECT:~B:~B:~B:~B:~B", [IX1, IY1, IX2, IY2, IC]),
            {ok, Vars5, Output};
        {error, Reason, VarsErr} ->
            {error, Reason, VarsErr}
    end.

eval_circle(XExpr, YExpr, RadiusExpr, ColorExpr, Vars) ->
    eval_circle(XExpr, YExpr, RadiusExpr, ColorExpr, Vars, #{}).

eval_circle(XExpr, YExpr, RadiusExpr, ColorExpr, Vars, Funcs) ->
    case eval_exprs([XExpr, YExpr, RadiusExpr, ColorExpr], Vars, Funcs) of
        {ok, [{X, _}, {Y, _}, {R, _}, {C, Vars4}]} ->
            IX = erlbasic_eval:normalize_int(X),
            IY = erlbasic_eval:normalize_int(Y),
            IR = erlbasic_eval:normalize_int(R),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = graphics_output("CIRCLE:~B:~B:~B:~B", [IX, IY, IR, IC]),
            {ok, Vars4, Output};
        {error, Reason, VarsErr} ->
            {error, Reason, VarsErr}
    end.

render_print_using_items(Items, FormatText, Vars, Funcs, StartCol) ->
    render_print_using_items(Items, FormatText, Vars, Funcs, StartCol, [], StartCol).

render_print_using_items([], _FormatText, Vars, _Funcs, _StartCol, Acc, Col) ->
    {ok, Vars, lists:flatten(lists:reverse(Acc)), Col};
render_print_using_items([{Expr, Sep} | Rest], FormatText, Vars, Funcs, StartCol, Acc, Col) ->
    put(erlbasic_print_col, Col),
    case erlbasic_eval:eval_expr_result(Expr, Vars, Funcs) of
        {ok, Value, Vars1} ->
            case erlbasic_print_using:format_item(FormatText, Value) of
                {ok, Text} ->
                    ColAfterText = Col + length(Text),
                    {SepText, ColAfterSep} = print_sep_text(Sep, ColAfterText, StartCol),
                    render_print_using_items(Rest, FormatText, Vars1, Funcs, StartCol, [SepText, Text | Acc], ColAfterSep);
                {error, Reason} ->
                    {error, Reason, Vars1}
            end;
        {error, Reason, Vars1} ->
            {error, Reason, Vars1}
    end.


%% =============================================================================
%% Error Handler Support (ON ERROR GOTO / RESUME)
%% =============================================================================

%% Handle runtime errors - either call error handler or stop
handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack) ->
    case State#state.error_handler of
        undefined ->
            %% No error handler - stop with error message
            {stop, [erlbasic_eval:format_runtime_error(Reason, LineNumber)]};
        HandlerLine ->
            %% Error handler is set - jump to handler with error context
            Program = State#state.prog,
            ErrorCode = erlbasic_eval:error_code(Reason),
            %% Set ERR and ERL variables
            Vars1 = maps:put("ERR", ErrorCode, State#state.vars),
            Vars2 = maps:put("ERL", LineNumber, Vars1),
            %% Store error context for RESUME
            State1 = State#state{
                vars = Vars2,
                error_resume_pc = Pc,
                error_code = ErrorCode,
                error_line = LineNumber
            },
            %% Find error handler PC
            case resolve_target_pc(integer_to_list(HandlerLine), Program, Vars2, State#state.funcs) of
                {ok, HandlerPc} ->
                    {jump, HandlerPc, State1, LoopStack, CallStack, []};
                missing ->
                    {stop, [erlbasic_eval:format_runtime_error(syntax_error, LineNumber)]}
            end
    end.

%% ON ERROR GOTO line
execute_on_error_goto(TargetExpr, Program, State, Pc, LoopStack, CallStack) ->
    LineNumber = get_line_number(Program, Pc),
    case erlbasic_eval:eval_expr_result(TargetExpr, State#state.vars, State#state.funcs) of
        {error, Reason, _} ->
            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack);
        {ok, Value, Vars1} ->
            TargetLine = erlbasic_eval:normalize_int(Value),
            State1 = case TargetLine of
                0 ->
                    %% ON ERROR GOTO 0 - disable error handler
                    State#state{vars = Vars1, error_handler = undefined};
                _ ->
                    %% ON ERROR GOTO line - set error handler
                    State#state{vars = Vars1, error_handler = TargetLine}
            end,
            {continue, State1, LoopStack, CallStack, []}
    end.

%% RESUME - retry the statement that caused the error
execute_resume(State, _Pc, LoopStack, CallStack) ->
    case State#state.error_resume_pc of
        undefined ->
            {stop, ["?RESUME WITHOUT ERROR\r\n"]};
        ResumePc ->
            %% Clear error context and resume at the error PC
            State1 = State#state{
                error_resume_pc = undefined,
                error_code = 0,
                error_line = 0
            },
            {jump, ResumePc, State1, LoopStack, CallStack, []}
    end.

%% RESUME NEXT - continue with the statement after the error
execute_resume_next(State, _Pc, LoopStack, CallStack) ->
    case State#state.error_resume_pc of
        undefined ->
            {stop, ["?RESUME WITHOUT ERROR\r\n"]};
        ResumePc ->
            %% Clear error context and continue after the error PC
            State1 = State#state{
                error_resume_pc = undefined,
                error_code = 0,
                error_line = 0
            },
            %% Jump to the statement after the one that caused the error
            {jump, ResumePc + 1, State1, LoopStack, CallStack, []}
    end.

%% RESUME line - continue at a specific line
execute_resume_line(LineExpr, Program, State, Pc, LoopStack, CallStack) ->
    case State#state.error_resume_pc of
        undefined ->
            {stop, ["?RESUME WITHOUT ERROR\r\n"]};
        _ResumePc ->
            LineNumber = get_line_number(Program, Pc),
            case erlbasic_eval:eval_expr_result(LineExpr, State#state.vars, State#state.funcs) of
                {error, Reason, _} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack);
                {ok, Value, _Vars1} ->
                    TargetLine = erlbasic_eval:normalize_int(Value),
                    case resolve_target_pc(integer_to_list(TargetLine), Program, State#state.vars, State#state.funcs) of
                        {ok, TargetPc} ->
                            %% Clear error context and jump to target
                            State1 = State#state{
                                error_resume_pc = undefined,
                                error_code = 0,
                                error_line = 0
                            },
                            {jump, TargetPc, State1, LoopStack, CallStack, []};
                        missing ->
                            handle_runtime_error(syntax_error, LineNumber, State, Pc, LoopStack, CallStack)
                    end
            end
    end.
