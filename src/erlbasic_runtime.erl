-module(erlbasic_runtime).

-export([run_program/1, resume_program_input/5]).

-record(state, {
    vars = #{},
    prog = [],
    pending_input = undefined
}).

run_program(State = #state{prog = Program}) ->
    run_program_lines(Program, 1, State, [], [], []).

run_program_lines(Program, Pc, State, _LoopStack, _CallStack, Acc) when Pc > length(Program) ->
    {State, lists:reverse(Acc)};
run_program_lines(Program, Pc, State, LoopStack, CallStack, Acc) ->
    {_LineNumber, Code} = lists:nth(Pc, Program),
    case execute_program_line(Code, Program, State, Pc, LoopStack, CallStack) of
        {continue, NextState, NextLoopStack, NextCallStack, Output} ->
            case NextState#state.pending_input of
                undefined ->
                    run_program_lines(Program, Pc + 1, NextState, NextLoopStack, NextCallStack, lists:reverse(Output) ++ Acc);
                _ ->
                    {NextState, lists:reverse(lists:reverse(Output) ++ Acc)}
            end;
        {jump, TargetPc, NextState, NextLoopStack, NextCallStack, Output} ->
            case NextState#state.pending_input of
                undefined ->
                    run_program_lines(Program, TargetPc, NextState, NextLoopStack, NextCallStack, lists:reverse(Output) ++ Acc);
                _ ->
                    {NextState, lists:reverse(lists:reverse(Output) ++ Acc)}
            end;
        {'end', Output} ->
            {State, lists:reverse(["Program ended\r\n" | lists:reverse(Output) ++ Acc])};
        {stop, Output} ->
            {State, lists:reverse(lists:reverse(Output) ++ Acc)}
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
    case erlbasic_parser:parse_statement(Command) of
        {for_loop, Var, StartExpr, EndExpr, StepExpr} ->
            case erlbasic_eval:eval_expr_result(StartExpr, State#state.vars) of
                {error, Reason, _} ->
                    {stop, [erlbasic_eval:format_runtime_error(Reason)]};
                {ok, StartValue, Vars1} ->
                    case erlbasic_eval:eval_expr_result(EndExpr, Vars1) of
                        {error, Reason, _} ->
                            {stop, [erlbasic_eval:format_runtime_error(Reason)]};
                        {ok, EndValue, Vars2} ->
                            case StepExpr of
                                undefined ->
                                    finalize_for_loop(Var, StartValue, EndValue, 1, Vars2, State, Pc, LoopStack, CallStack);
                                Expr ->
                                    case erlbasic_eval:eval_expr_result(Expr, Vars2) of
                                        {error, Reason, _} ->
                                            {stop, [erlbasic_eval:format_runtime_error(Reason)]};
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
        {next_loop, MaybeVar} ->
            handle_next_statement(MaybeVar, State, Pc, LoopStack, CallStack);
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case erlbasic_eval:eval_condition_result(CondExpr, State#state.vars) of
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
                    {stop, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {goto, LineExpr} ->
            execute_goto(LineExpr, Program, State, LoopStack, CallStack);
        {gosub, LineExpr} ->
            execute_gosub(LineExpr, Program, State, Pc, LoopStack, CallStack);
        {'return'} ->
            execute_return(State, LoopStack, CallStack);
        {input, Var} ->
            PromptState = State#state{pending_input = {Var, {program, Pc, [], LoopStack, CallStack}}},
            {continue, PromptState, LoopStack, CallStack, [format_input_prompt(Var)]};
        {'end'} ->
            {'end', []};
        _ ->
            execute_basic_statement(Command, State, Pc, LoopStack, CallStack)
    end.

execute_basic_statement(Command, State, Pc, LoopStack, CallStack) ->
    case erlbasic_parser:parse_statement(Command) of
        {print, Expr} ->
            case erlbasic_eval:eval_expr_result(Expr, State#state.vars) of
                {ok, Value, Vars1} ->
                    {continue, State#state{vars = Vars1}, LoopStack, CallStack, [erlbasic_eval:format_value(Value)]};
                {error, Reason, _Vars1} ->
                    {stop, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {'let', Var, Expr} ->
            case erlbasic_eval:eval_expr_result(Expr, State#state.vars) of
                {ok, Value, Vars1} ->
                    {continue, State#state{vars = maps:put(Var, Value, Vars1)}, LoopStack, CallStack, ["OK\r\n"]};
                {error, Reason, _Vars1} ->
                    {stop, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {input, Var} ->
            PromptState = State#state{pending_input = {Var, {program, Pc, [], LoopStack, CallStack}}},
            {continue, PromptState, LoopStack, CallStack, [format_input_prompt(Var)]};
        {'end'} ->
            {'end', []};
        _ ->
            {continue, State, LoopStack, CallStack, ["?SYNTAX ERROR\r\n"]}
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

execute_goto(LineExpr, Program, State, LoopStack, CallStack) ->
    case resolve_target_pc(LineExpr, Program, State#state.vars) of
        {error, Reason} ->
            {stop, [erlbasic_eval:format_runtime_error(Reason)]};
        {ok, TargetPc} ->
            {jump, TargetPc, State, LoopStack, CallStack, []};
        missing ->
            {continue, State, LoopStack, CallStack, ["?SYNTAX ERROR\r\n"]}
    end.

execute_gosub(LineExpr, Program, State, Pc, LoopStack, CallStack) ->
    case resolve_target_pc(LineExpr, Program, State#state.vars) of
        {error, Reason} ->
            {stop, [erlbasic_eval:format_runtime_error(Reason)]};
        {ok, TargetPc} ->
            {jump, TargetPc, State, LoopStack, [Pc + 1 | CallStack], []};
        missing ->
            {continue, State, LoopStack, CallStack, ["?SYNTAX ERROR\r\n"]}
    end.

resolve_target_pc(LineExpr, Program, Vars) ->
    case erlbasic_eval:eval_expr_result(LineExpr, Vars) of
        {error, Reason, _} ->
            {error, Reason};
        {ok, LineValue, _} ->
            TargetLine = erlbasic_eval:normalize_int(LineValue),
            case line_to_pc(Program, TargetLine) of
                {ok, TargetPc} -> {ok, TargetPc};
                error -> missing
            end
    end.

execute_return(State, LoopStack, []) ->
    {continue, State, LoopStack, [], ["?SYNTAX ERROR\r\n"]};
execute_return(State, LoopStack, [ReturnPc | Rest]) ->
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

update_pending_input_rest(State = #state{pending_input = {Var, {immediate, _OldRemaining}}}, RemainingStatements) ->
    State#state{pending_input = {Var, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {Var, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) ->
    State#state{pending_input = {Var, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State, _RemainingStatements) ->
    State.

format_input_prompt(Var) ->
    Var ++ "? ".

handle_next_statement(_MaybeVar, State, _Pc, [], CallStack) ->
    {continue, State, [], CallStack, ["?SYNTAX ERROR\r\n"]};
handle_next_statement(MaybeVar, State, Pc, [{Var, EndInt, Step, ForPc} | Rest], CallStack) ->
    case MaybeVar of
        undefined ->
            continue_next(Var, EndInt, Step, ForPc, State, Pc, Rest, CallStack);
        Var ->
            continue_next(Var, EndInt, Step, ForPc, State, Pc, Rest, CallStack);
        _ ->
            {continue, State, [{Var, EndInt, Step, ForPc} | Rest], CallStack, ["?SYNTAX ERROR\r\n"]}
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
