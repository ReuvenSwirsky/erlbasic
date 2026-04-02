-module(erlbasic_runtime).

-export([run_program/1, continue_program/4, resume_program_input/5,
         update_pending_input_rest/2, format_input_prompt/1,
         collect_program_data/1, apply_read_vars/2, eval_locate/4,
         apply_dim_decls/3, render_print_items/4, cls_output/0,
         eval_color/4, render_print_using_items/5,
         hgr_output/0, text_output/0, eval_pset/4, eval_line/6, eval_lineto/6, eval_lineto/7, eval_rect/6, eval_circle/5]).

-define(FLUSH_OUTPUT_EVERY, 1).

-include("erlbasic_state.hrl").

run_program(State = #state{prog = Program}) ->
    DataItems = collect_program_data(Program),
    RunState = State#state{data_items = DataItems, data_index = 1, continue_ctx = undefined},
    erlang:put(line_exec_count, 0),
    Result = run_program_lines(Program, 1, RunState, [], [], []),
    erlang:erase(line_exec_count),
    Result.

continue_program(State = #state{prog = Program}, Pc, LoopStack, CallStack) ->
    erlang:put(line_exec_count, 0),
    Result = run_program_lines(Program, Pc, State, LoopStack, CallStack, []),
    erlang:erase(line_exec_count),
    Result.

run_program_lines([], _Pc, State, _LoopStack, _CallStack, Acc) ->
    {State, lists:reverse(Acc)};
run_program_lines(Program, Pc, State, _LoopStack, _CallStack, Acc) when Pc > length(Program) ->
    {State, lists:reverse(Acc)};
run_program_lines(Program, Pc, State, LoopStack, CallStack, Acc) ->
    Count = case erlang:get(line_exec_count) of undefined -> 0; N -> N end,
    erlang:put(line_exec_count, Count + 1),
    %% Check for interrupt message in mailbox (non-blocking)
    receive
        interrupt ->
            erlang:put(interrupted, true)
    after 0 ->
        ok
    end,
    %% Periodic flush for output during loops
    NewAcc = case should_flush_output() andalso (Count rem ?FLUSH_OUTPUT_EVERY =:= 0) andalso (Acc =/= []) of
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
            flush_output(NewAcc),
            BreakState = State#state{continue_ctx = {Pc, LoopStack, CallStack}},
            {BreakState, ["\r\n^C\r\nBREAK\r\n"]};
        _ ->
            run_program_lines_impl(Program, Pc, State, LoopStack, CallStack, NewAcc)
    end.

run_program_lines_impl(Program, Pc, State, LoopStack, CallStack, Acc) ->
    {_LineNumber, Code} = lists:nth(Pc, Program),
    case execute_program_line(Code, Program, State, Pc, LoopStack, CallStack) of
        {continue, NextState, NextLoopStack, NextCallStack, Output} ->
            %% Accumulate output
            CombinedOutput = lists:reverse(Output) ++ Acc,
            %% Flush if we have an output target
            NewAcc = case should_flush_output() of
                true ->
                    flush_output(CombinedOutput),
                    [];
                false ->
                    CombinedOutput
            end,
            case NextState#state.pending_input of
                undefined ->
                    run_program_lines(Program, Pc + 1, NextState, NextLoopStack, NextCallStack, NewAcc);
                _ ->
                    {NextState, lists:reverse(NewAcc)}
            end;
        {jump, TargetPc, NextState, NextLoopStack, NextCallStack, Output} ->
            %% Accumulate output
            CombinedOutput = lists:reverse(Output) ++ Acc,
            %% Flush if we have an output target
            NewAcc = case should_flush_output() of
                true ->
                    flush_output(CombinedOutput),
                    [];
                false ->
                    CombinedOutput
            end,
            case NextState#state.pending_input of
                undefined ->
                    run_program_lines(Program, TargetPc, NextState, NextLoopStack, NextCallStack, NewAcc);
                _ ->
                    {NextState, lists:reverse(NewAcc)}
            end;
        {'end', Output} ->
            %% Flush final output
            flush_output(lists:reverse(Output) ++ Acc),
            case should_flush_output() of
                true ->
                    {State, ["Program ended\r\n"]};
                false ->
                    {State, lists:reverse(["Program ended\r\n" | lists:reverse(Output) ++ Acc])}
            end;
        {stop, Output} ->
            CombinedOutput = lists:reverse(Output) ++ Acc,
            flush_output(CombinedOutput),
            case should_flush_output() of
                true ->
                    {State, []};
                false ->
                    {State, lists:reverse(CombinedOutput)}
            end
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
            case NextState#state.pending_input of
                undefined ->
                    execute_program_line_statements(Rest, Program, NextState, Pc, NextLoopStack, NextCallStack, OutputAcc ++ Output);
                _ ->
                    PendingState = update_pending_input_rest(NextState, Rest),
                    {continue, PendingState, NextLoopStack, NextCallStack, OutputAcc ++ Output}
            end;
        {jump, TargetPc, NextState, NextLoopStack, NextCallStack, Output} ->
            {jump, TargetPc, NextState, NextLoopStack, NextCallStack, OutputAcc ++ Output};
        {'end', Output} ->
            {'end', OutputAcc ++ Output};
        {stop, Output} ->
            {stop, OutputAcc ++ Output}
    end.

execute_program_line_statement(Command, Program, State, Pc, LoopStack, CallStack) ->
    LineNumber = get_line_number(Program, Pc),
    case erlbasic_parser:parse_statement(Command) of
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
            PromptState = State#state{pending_input = {Targets, {program, Pc, [], LoopStack, CallStack}}},
            {continue, PromptState, LoopStack, CallStack, [format_input_prompt(Targets)]};
        {input_line, Target} ->
            PromptState = State#state{pending_input = {input_line, Target, {program, Pc, [], LoopStack, CallStack}}},
            {continue, PromptState, LoopStack, CallStack, [format_input_prompt(Target)]};
        {get, Target} ->
            %% Non-blocking but cooperative: take first buffered char, or suspend
            %% so the conn layer can yield the CPU before returning "".
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
            end;
        {getkey, Target} ->
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
            end;
        {'end'} ->
            {'end', []};
        _ ->
            execute_basic_statement(Command, State, Pc, LoopStack, CallStack)
    end.

execute_basic_statement(Command, State, Pc, LoopStack, CallStack) ->
    Program = State#state.prog,
    LineNumber = get_line_number(Program, Pc),
    case erlbasic_parser:parse_statement(Command) of
        {data, _Items} ->
            {continue, State, LoopStack, CallStack, []};
        {read_data, Targets} ->
            case apply_read_vars(Targets, State) of
                {ok, NextState} ->
                    {continue, NextState, LoopStack, CallStack, []};
                {error, Reason} ->
                    handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
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
                    {continue, State#state{vars = Vars1, print_col = FinalCol}, LoopStack, CallStack, [FinalText]};
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
                            {continue, State#state{vars = Vars2, print_col = FinalCol}, LoopStack, CallStack, [FinalText]};
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
            {continue, State, LoopStack, CallStack, cls_output()};
        {hgr} ->
            case erlang:get(erlbasic_conn_type) of
                websocket ->
                    {continue, State#state{graphics_mode = true, graphics_pen = undefined}, LoopStack, CallStack, hgr_output()};
                _ ->
                    handle_runtime_error(graphics_not_supported_on_tty, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {text} ->
            case erlang:get(erlbasic_conn_type) of
                websocket ->
                    {continue, State#state{graphics_mode = false, graphics_pen = undefined}, LoopStack, CallStack, text_output()};
                _ ->
                    handle_runtime_error(graphics_not_supported_on_tty, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {pset, XExpr, YExpr, ColorExpr} ->
            case State#state.graphics_mode of
                true ->
                    case eval_pset(XExpr, YExpr, ColorExpr, State#state.vars, State#state.funcs) of
                        {ok, Vars1, Output} ->
                            {continue, State#state{vars = Vars1}, LoopStack, CallStack, Output};
                        {error, Reason, _Vars1} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end;
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {line, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr} ->
            case State#state.graphics_mode of
                true ->
                    case eval_line(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, State#state.vars, State#state.funcs) of
                        {ok, Vars1, Output, X2, Y2} ->
                            {continue, State#state{vars = Vars1, graphics_pen = {X2, Y2}}, LoopStack, CallStack, Output};
                        {error, Reason, _Vars1} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end;
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {lineto, XExpr, YExpr, ColorExpr} ->
            case State#state.graphics_mode of
                true ->
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
                    end;
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {rect, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr} ->
            case State#state.graphics_mode of
                true ->
                    case eval_rect(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, State#state.vars, State#state.funcs) of
                        {ok, Vars1, Output} ->
                            {continue, State#state{vars = Vars1}, LoopStack, CallStack, Output};
                        {error, Reason, _Vars1} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end;
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {circle, XExpr, YExpr, RadiusExpr, ColorExpr} ->
            case State#state.graphics_mode of
                true ->
                    case eval_circle(XExpr, YExpr, RadiusExpr, ColorExpr, State#state.vars, State#state.funcs) of
                        {ok, Vars1, Output} ->
                            {continue, State#state{vars = Vars1}, LoopStack, CallStack, Output};
                        {error, Reason, _Vars1} ->
                            handle_runtime_error(Reason, LineNumber, State, Pc, LoopStack, CallStack)
                    end;
                false ->
                    handle_runtime_error(no_graphics_mode, LineNumber, State, Pc, LoopStack, CallStack)
            end;
        {sleep, Expr} ->
            case erlbasic_eval:eval_expr_result(Expr, State#state.vars, State#state.funcs) of
                {ok, Value, Vars1} when is_number(Value) ->
                    Ms = max(0, trunc(Value * 1000)),
                    timer:sleep(Ms),
                    {continue, State#state{vars = Vars1}, LoopStack, CallStack, []};
                {ok, _Value, _Vars1} ->
                    handle_runtime_error(type_mismatch, LineNumber, State, Pc, LoopStack, CallStack);
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
        {on_error_goto, TargetExpr} ->
            execute_on_error_goto(TargetExpr, Program, State, Pc, LoopStack, CallStack);
        {resume} ->
            execute_resume(State, Pc, LoopStack, CallStack);
        {resume_next} ->
            execute_resume_next(State, Pc, LoopStack, CallStack);
        {resume_line, LineExpr} ->
            execute_resume_line(LineExpr, Program, State, Pc, LoopStack, CallStack);
        {'end'} ->
            {'end', []};
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
    Frame = {Var, EndInt, NormalizedStep, Pc},
    {continue, NextState, [Frame | LoopStack], CallStack, []}.

execute_program_inline_sequence(StatementText, Program, State, Pc, LoopStack, CallStack) ->
    execute_program_line_statements(erlbasic_parser:split_statements(StatementText), Program, State, Pc, LoopStack, CallStack, []).

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
    {jump, ReturnPc, State, LoopStack, Rest, []}.

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
update_pending_input_rest(State, _RemainingStatements) ->
    State.

format_input_prompt(_Targets) ->
    "? ".

collect_program_data(Program) ->
    collect_program_data(Program, []).

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
                {ok, Value, _} -> erlbasic_eval:normalize_int(Value);
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
handle_next_statement(MaybeVar, Program, State, Pc, [{Var, EndInt, Step, ForPc} | Rest], CallStack) ->
    LineNumber = get_line_number(Program, Pc),
    case MaybeVar of
        undefined ->
            continue_next(Var, EndInt, Step, ForPc, State, Pc, Rest, CallStack);
        Var ->
            continue_next(Var, EndInt, Step, ForPc, State, Pc, Rest, CallStack);
        _ ->
            {stop, [erlbasic_eval:format_runtime_error(next_without_for, LineNumber)]}
    end.

continue_next(Var, EndInt, Step, ForPc, State, _Pc, Rest, CallStack) ->
    Current = maps:get(Var, State#state.vars, 0),
    NextValue = Current + Step,
    Vars1 = maps:put(Var, NextValue, State#state.vars),
    Continue =
        case Step > 0 of
            true -> NextValue =< EndInt;
            false -> NextValue >= EndInt
        end,
    NextState = State#state{vars = Vars1},
    case Continue of
        true ->
            {jump, ForPc + 1, NextState, [{Var, EndInt, Step, ForPc} | Rest], CallStack, []};
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

get_line_number(Program, Pc) when Pc >= 1, Pc =< length(Program) ->
    {LineNumber, _Code} = lists:nth(Pc, Program),
    LineNumber;
get_line_number(_Program, _Pc) ->
    undefined.

should_flush_output() ->
    case erlang:get(output_socket) of
        undefined ->
            erlang:get(output_pid) =/= undefined;
        _ ->
            true
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
                    lists:foreach(fun(Text) -> Pid ! {output, Text} end, Output)
            end;
        Socket ->
            %% TCP mode - send directly to socket
            lists:foreach(fun(Text) -> gen_tcp:send(Socket, Text) end, Output)
    end.

render_print_items(Items, Vars, Funcs, StartCol) ->
    render_print_items(Items, Vars, Funcs, StartCol, [], StartCol).

render_print_items([], Vars, _Funcs, _StartCol, Acc, Col) ->
    {ok, Vars, lists:flatten(lists:reverse(Acc)), Col};
render_print_items([{Expr, Sep} | Rest], Vars, Funcs, StartCol, Acc, Col) ->
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

text_output() ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> ["\x02GFX:TEXT"];
        _ -> []
    end.

eval_pset(XExpr, YExpr, ColorExpr, Vars) ->
    eval_pset(XExpr, YExpr, ColorExpr, Vars, #{}).

eval_pset(XExpr, YExpr, ColorExpr, Vars, Funcs) ->
    case {erlbasic_eval:eval_expr_result(XExpr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(YExpr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(ColorExpr, Vars, Funcs)} of
        {{ok, X, _Vars1}, {ok, Y, _Vars2}, {ok, C, Vars3}} ->
            IX = erlbasic_eval:normalize_int(X),
            IY = erlbasic_eval:normalize_int(Y),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = case erlang:get(erlbasic_conn_type) of
                websocket -> [io_lib:format("\x02GFX:PSET:~B:~B:~B", [IX, IY, IC])];
                _ -> []
            end,
            {ok, Vars3, Output};
        {{error, Reason, VarsErr}, _, _} ->
            {error, Reason, VarsErr};
        {_, {error, Reason, VarsErr}, _} ->
            {error, Reason, VarsErr};
        {_, _, {error, Reason, VarsErr}} ->
            {error, Reason, VarsErr}
    end.

eval_line(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars) ->
    eval_line(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars, #{}).

eval_line(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars, Funcs) ->
    case {erlbasic_eval:eval_expr_result(X1Expr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(Y1Expr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(X2Expr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(Y2Expr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(ColorExpr, Vars, Funcs)} of
        {{ok, X1, _Vars1}, {ok, Y1, _Vars2}, {ok, X2, _Vars3}, {ok, Y2, _Vars4}, {ok, C, Vars5}} ->
            IX1 = erlbasic_eval:normalize_int(X1),
            IY1 = erlbasic_eval:normalize_int(Y1),
            IX2 = erlbasic_eval:normalize_int(X2),
            IY2 = erlbasic_eval:normalize_int(Y2),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = case erlang:get(erlbasic_conn_type) of
                websocket -> [io_lib:format("\x02GFX:LINE:~B:~B:~B:~B:~B", [IX1, IY1, IX2, IY2, IC])];
                _ -> []
            end,
            {ok, Vars5, Output, IX2, IY2};
        {{error, Reason, VarsErr}, _, _, _, _} ->
            {error, Reason, VarsErr};
        {_, {error, Reason, VarsErr}, _, _, _} ->
            {error, Reason, VarsErr};
        {_, _, {error, Reason, VarsErr}, _, _} ->
            {error, Reason, VarsErr};
        {_, _, _, {error, Reason, VarsErr}, _} ->
            {error, Reason, VarsErr};
        {_, _, _, _, {error, Reason, VarsErr}} ->
            {error, Reason, VarsErr}
    end.

eval_lineto(XExpr, YExpr, ColorExpr, X1, Y1, Vars) ->
    eval_lineto(XExpr, YExpr, ColorExpr, X1, Y1, Vars, #{}).

eval_lineto(XExpr, YExpr, ColorExpr, X1, Y1, Vars, Funcs) ->
    case {erlbasic_eval:eval_expr_result(XExpr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(YExpr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(ColorExpr, Vars, Funcs)} of
        {{ok, X2, _Vars1}, {ok, Y2, _Vars2}, {ok, C, Vars3}} ->
            IX1 = X1,  % Already normalized
            IY1 = Y1,  % Already normalized
            IX2 = erlbasic_eval:normalize_int(X2),
            IY2 = erlbasic_eval:normalize_int(Y2),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = case erlang:get(erlbasic_conn_type) of
                websocket -> [io_lib:format("\x02GFX:LINE:~B:~B:~B:~B:~B", [IX1, IY1, IX2, IY2, IC])];
                _ -> []
            end,
            {ok, Vars3, Output, IX2, IY2};
        {{error, Reason, VarsErr}, _, _} ->
            {error, Reason, VarsErr};
        {_, {error, Reason, VarsErr}, _} ->
            {error, Reason, VarsErr};
        {_, _, {error, Reason, VarsErr}} ->
            {error, Reason, VarsErr}
    end.

eval_rect(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars) ->
    eval_rect(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars, #{}).

eval_rect(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, Vars, Funcs) ->
    case {erlbasic_eval:eval_expr_result(X1Expr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(Y1Expr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(X2Expr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(Y2Expr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(ColorExpr, Vars, Funcs)} of
        {{ok, X1, _Vars1}, {ok, Y1, _Vars2}, {ok, X2, _Vars3}, {ok, Y2, _Vars4}, {ok, C, Vars5}} ->
            IX1 = erlbasic_eval:normalize_int(X1),
            IY1 = erlbasic_eval:normalize_int(Y1),
            IX2 = erlbasic_eval:normalize_int(X2),
            IY2 = erlbasic_eval:normalize_int(Y2),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = case erlang:get(erlbasic_conn_type) of
                websocket -> [io_lib:format("\x02GFX:RECT:~B:~B:~B:~B:~B", [IX1, IY1, IX2, IY2, IC])];
                _ -> []
            end,
            {ok, Vars5, Output};
        {{error, Reason, VarsErr}, _, _, _, _} ->
            {error, Reason, VarsErr};
        {_, {error, Reason, VarsErr}, _, _, _} ->
            {error, Reason, VarsErr};
        {_, _, {error, Reason, VarsErr}, _, _} ->
            {error, Reason, VarsErr};
        {_, _, _, {error, Reason, VarsErr}, _} ->
            {error, Reason, VarsErr};
        {_, _, _, _, {error, Reason, VarsErr}} ->
            {error, Reason, VarsErr}
    end.

eval_circle(XExpr, YExpr, RadiusExpr, ColorExpr, Vars) ->
    eval_circle(XExpr, YExpr, RadiusExpr, ColorExpr, Vars, #{}).

eval_circle(XExpr, YExpr, RadiusExpr, ColorExpr, Vars, Funcs) ->
    case {erlbasic_eval:eval_expr_result(XExpr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(YExpr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(RadiusExpr, Vars, Funcs),
          erlbasic_eval:eval_expr_result(ColorExpr, Vars, Funcs)} of
        {{ok, X, _Vars1}, {ok, Y, _Vars2}, {ok, R, _Vars3}, {ok, C, Vars4}} ->
            IX = erlbasic_eval:normalize_int(X),
            IY = erlbasic_eval:normalize_int(Y),
            IR = erlbasic_eval:normalize_int(R),
            IC = erlbasic_eval:normalize_int(C) band 15,
            Output = case erlang:get(erlbasic_conn_type) of
                websocket -> [io_lib:format("\x02GFX:CIRCLE:~B:~B:~B:~B", [IX, IY, IR, IC])];
                _ -> []
            end,
            {ok, Vars4, Output};
        {{error, Reason, VarsErr}, _, _, _} ->
            {error, Reason, VarsErr};
        {_, {error, Reason, VarsErr}, _, _} ->
            {error, Reason, VarsErr};
        {_, _, {error, Reason, VarsErr}, _} ->
            {error, Reason, VarsErr};
        {_, _, _, {error, Reason, VarsErr}} ->
            {error, Reason, VarsErr}
    end.

render_print_using_items(Items, FormatText, Vars, Funcs, StartCol) ->
    render_print_using_items(Items, FormatText, Vars, Funcs, StartCol, [], StartCol).

render_print_using_items([], _FormatText, Vars, _Funcs, _StartCol, Acc, Col) ->
    {ok, Vars, lists:flatten(lists:reverse(Acc)), Col};
render_print_using_items([{Expr, Sep} | Rest], FormatText, Vars, Funcs, StartCol, Acc, Col) ->
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
