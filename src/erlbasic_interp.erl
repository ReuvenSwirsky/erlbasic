-module(erlbasic_interp).

-export([new_state/0, handle_input/2, next_prompt/1]).

-define(VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*[\\$%]?)").
-define(LOOP_VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*%?)").
-define(VAR_REFERENCE_PATTERN, "^[A-Za-z][A-Za-z0-9_]*[\\$%]?$").

-record(state, {
    vars = #{},
    prog = [],
    pending_input = undefined
}).

new_state() ->
    #state{}.

next_prompt(#state{pending_input = undefined}) ->
    "> ";
next_prompt(_State) ->
    "".

handle_input(Line, State) ->
    Trimmed = string:trim(Line),
    case State#state.pending_input of
        undefined ->
            case parse_program_line(Trimmed) of
                {program_line, Num, Code} ->
                    NextProgram = update_program(State#state.prog, Num, Code),
                    {State#state{prog = NextProgram}, ["OK\r\n"]};
                immediate ->
                    exec_immediate(Trimmed, State)
            end;
        _ ->
            handle_pending_input(Trimmed, State)
    end.

parse_program_line("") ->
    immediate;
parse_program_line(Line) ->
    case re:run(Line, "^(\\d+)\\s*(.*)$", [{capture, [1, 2], list}]) of
        {match, [LineNum, Code]} ->
            {program_line, list_to_integer(LineNum), string:trim(Code)};
        nomatch ->
            immediate
    end.

update_program(Program, LineNumber, "") ->
    lists:keydelete(LineNumber, 1, Program);
update_program(Program, LineNumber, Code) ->
    lists:keysort(1, [{LineNumber, Code} | lists:keydelete(LineNumber, 1, Program)]).

exec_immediate("", State) ->
    {State, []};
exec_immediate(Command, State) ->
    Upper = string:to_upper(Command),
    case Upper of
        "LIST" ->
            {State, format_program(State#state.prog)};
        "NEW" ->
            {State#state{prog = []}, ["Program cleared\r\n"]};
        "RUN" ->
            run_program(State#state.prog, State);
        _ ->
            case parse_renum_command(Command) of
                {ok, StartLine, Increment} ->
                    Renumbered = renumber_program(State#state.prog, StartLine, Increment),
                    {State#state{prog = Renumbered}, ["OK\r\n"]};
                error ->
                    normalize_immediate_result(execute_statement(Command, State), State)
            end
    end.

parse_renum_command(Command) ->
    Trimmed = string:trim(Command),
    case re:run(Trimmed, "(?i)^RENUM(?:\\s+(\\d+)(?:\\s*,\\s*(\\d+))?)?$", [{capture, all_but_first, list}]) of
        {match, []} ->
            {ok, 10, 10};
        {match, [StartText]} ->
            parse_renum_single_arg(StartText);
        {match, [StartText, IncText]} ->
            parse_renum_two_args(StartText, IncText);
        nomatch ->
            error
    end.

parse_renum_single_arg(StartText) ->
    case parse_positive_int(StartText) of
        {ok, StartLine} ->
            {ok, StartLine, 10};
        error ->
            error
    end.

parse_renum_two_args(StartText, IncText) ->
    case {parse_positive_int(StartText), parse_positive_int(IncText)} of
        {{ok, StartLine}, {ok, Increment}} ->
            {ok, StartLine, Increment};
        _ ->
            error
    end.

parse_positive_int(Text) ->
    case string:to_integer(Text) of
        {Value, ""} when Value > 0 ->
            {ok, Value};
        _ ->
            error
    end.

renumber_program([], _StartLine, _Increment) ->
    [];
renumber_program(Program, StartLine, Increment) ->
    LineMap = build_line_map(Program, StartLine, Increment),
    [{maps:get(OldLine, LineMap), rewrite_line_refs(Code, LineMap)} || {OldLine, Code} <- Program].

build_line_map(Program, StartLine, Increment) ->
    build_line_map(Program, StartLine, Increment, 0, #{}).

build_line_map([], _StartLine, _Increment, _Index, Acc) ->
    Acc;
build_line_map([{OldLine, _Code} | Rest], StartLine, Increment, Index, Acc) ->
    NewLine = StartLine + (Index * Increment),
    build_line_map(Rest, StartLine, Increment, Index + 1, maps:put(OldLine, NewLine, Acc)).

rewrite_line_refs(Code, LineMap) ->
    case should_split_top_level_sequence(Code) of
        true ->
            join_statements([rewrite_line_refs(Stmt, LineMap) || Stmt <- split_statements(Code)]);
        false ->
            rewrite_single_statement_line_refs(Code, LineMap)
    end.

rewrite_single_statement_line_refs(Code, LineMap) ->
    case parse_statement(Code) of
        {goto, LineExpr} ->
            "GOTO " ++ renumber_line_expr(LineExpr, LineMap);
        {gosub, LineExpr} ->
            "GOSUB " ++ renumber_line_expr(LineExpr, LineMap);
        {if_then_else, CondExpr, ThenStmt, undefined} ->
            "IF " ++ string:trim(CondExpr) ++ " THEN " ++ rewrite_line_refs(ThenStmt, LineMap);
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            "IF " ++ string:trim(CondExpr) ++ " THEN " ++ rewrite_line_refs(ThenStmt, LineMap) ++
                " ELSE " ++ rewrite_line_refs(ElseStmt, LineMap);
        _ ->
            Code
    end.

renumber_line_expr(LineExpr, LineMap) ->
    Trimmed = string:trim(LineExpr),
    case string:to_integer(Trimmed) of
        {OldLine, ""} ->
            case maps:find(OldLine, LineMap) of
                {ok, NewLine} -> integer_to_list(NewLine);
                error -> Trimmed
            end;
        _ ->
            Trimmed
    end.

join_statements([]) ->
    "";
join_statements([One]) ->
    One;
join_statements(Parts) ->
    string:join(Parts, ": ").

normalize_immediate_result({NextState, Output}, _State) ->
    {NextState, Output};
normalize_immediate_result(stop, State) ->
    {State, ["Program ended\r\n"]}.

format_program(Program) ->
    [integer_to_list(LineNumber) ++ " " ++ Code ++ "\r\n" || {LineNumber, Code} <- Program].

run_program(Program, State) ->
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

parse_statement(Command) ->
    Trimmed = string:trim(Command),
    parse_print_statement(Trimmed).

parse_print_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PRINT\\s+(.+)$", [{capture, [1], list}]) of
        {match, [Expr]} ->
            {print, Expr};
        nomatch ->
            parse_input_statement(Trimmed)
    end.

parse_input_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^INPUT\\s+" ++ ?VAR_PATTERN ++ "$", [{capture, [1], list}]) of
        {match, [Var]} ->
            {input, string:to_upper(Var)};
        nomatch ->
            parse_let_statement(Trimmed)
    end.

parse_let_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LET\\s+" ++ ?VAR_PATTERN ++ "\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [Var, Expr]} ->
            {'let', string:to_upper(Var), Expr};
        nomatch ->
            parse_if_statement(Trimmed)
    end.

parse_if_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^IF\\s+(.+?)\\s+THEN\\s+(.+?)(?:\\s+ELSE\\s+(.+))?$", [{capture, all_but_first, list}]) of
        {match, [CondExpr, ThenStmt]} ->
            {if_then_else, CondExpr, ThenStmt, undefined};
        {match, [CondExpr, ThenStmt, ElseStmt]} ->
            {if_then_else, CondExpr, ThenStmt, ElseStmt};
        nomatch ->
            parse_jump_statement(Trimmed)
    end.

parse_jump_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^GOTO\\s+(.+)$", [{capture, [1], list}]) of
        {match, [LineExpr]} ->
            {goto, LineExpr};
        nomatch ->
            case re:run(Trimmed, "(?i)^GOSUB\\s+(.+)$", [{capture, [1], list}]) of
                {match, [LineExpr]} ->
                    {gosub, LineExpr};
                nomatch ->
                    parse_loop_statement(Trimmed)
            end
    end.

parse_loop_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^FOR\\s+" ++ ?LOOP_VAR_PATTERN ++ "\\s*=\\s*(.+)\\s+TO\\s+(.+?)(?:\\s+STEP\\s+(.+))?$", [{capture, all_but_first, list}]) of
        {match, [Var, StartExpr, EndExpr]} ->
            {for_loop, string:to_upper(Var), StartExpr, EndExpr, undefined};
        {match, [Var, StartExpr, EndExpr, StepExpr]} ->
            {for_loop, string:to_upper(Var), StartExpr, EndExpr, StepExpr};
        nomatch ->
            parse_next_statement(Trimmed)
    end.

parse_next_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^NEXT(?:\\s+" ++ ?VAR_PATTERN ++ ")?$", [{capture, all_but_first, list}]) of
        {match, []} ->
            {next_loop, undefined};
        {match, [Var]} ->
            {next_loop, string:to_upper(Var)};
        nomatch ->
            parse_keyword_statement(Trimmed)
    end.

parse_keyword_statement(Trimmed) ->
    case string:to_upper(Trimmed) of
        "RETURN" -> {'return'};
        "END" -> {'end'};
        _ -> unknown
    end.

execute_program_line(Code, Program, State, Pc, LoopStack, CallStack) ->
    case should_split_top_level_sequence(Code) of
        true ->
            execute_program_line_statements(split_statements(Code), Program, State, Pc, LoopStack, CallStack, []);
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
    case parse_statement(Command) of
        {for_loop, Var, StartExpr, EndExpr, StepExpr} ->
            case eval_expr_result(StartExpr, State#state.vars) of
                {error, Reason, _} ->
                    {stop, [format_runtime_error(Reason)]};
                {ok, StartValue, Vars1} ->
                    case eval_expr_result(EndExpr, Vars1) of
                        {error, Reason, _} ->
                            {stop, [format_runtime_error(Reason)]};
                        {ok, EndValue, Vars2} ->
                            case StepExpr of
                                undefined ->
                                    finalize_for_loop(Var, StartValue, EndValue, 1, Vars2, State, Pc, LoopStack, CallStack);
                                Expr ->
                                    case eval_expr_result(Expr, Vars2) of
                                        {error, Reason, _} ->
                                            {stop, [format_runtime_error(Reason)]};
                                        {ok, RawStepValue, _} ->
                                            finalize_for_loop(Var, StartValue, EndValue, normalize_int(RawStepValue), Vars2, State, Pc, LoopStack, CallStack)
                                    end
                            end
                    end
            end;
        {next_loop, MaybeVar} ->
            handle_next_statement(MaybeVar, State, Pc, LoopStack, CallStack);
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case eval_condition_result(CondExpr, State#state.vars) of
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
                    {stop, [format_runtime_error(Reason)]}
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
            case execute_statement_single(Command, State) of
                {NextState, Output} ->
                    case is_runtime_error_output(Output) of
                        true ->
                            {stop, Output};
                        false ->
                            {continue, NextState, LoopStack, CallStack, Output}
                    end;
                stop ->
                    {'end', []}
            end
    end.

finalize_for_loop(Var, StartValue, EndValue, StepValue, Vars2, State, Pc, LoopStack, CallStack) ->
    NormalizedStep =
        case StepValue of
            0 -> 1;
            _ -> StepValue
        end,
    StartInt = normalize_int(StartValue),
    EndInt = normalize_int(EndValue),
    Vars3 = maps:put(Var, StartInt, Vars2),
    NextState = State#state{vars = Vars3},
    Frame = {Var, EndInt, NormalizedStep, Pc},
    {continue, NextState, [Frame | LoopStack], CallStack, []}.

execute_program_inline_sequence(StatementText, Program, State, Pc, LoopStack, CallStack) ->
    execute_program_line_statements(split_statements(StatementText), Program, State, Pc, LoopStack, CallStack, []).

execute_goto(LineExpr, Program, State, LoopStack, CallStack) ->
    case resolve_target_pc(LineExpr, Program, State#state.vars) of
        {error, Reason} ->
            {stop, [format_runtime_error(Reason)]};
        {ok, TargetPc} ->
            {jump, TargetPc, State, LoopStack, CallStack, []};
        missing ->
            {continue, State, LoopStack, CallStack, ["?SYNTAX ERROR\r\n"]}
    end.

execute_gosub(LineExpr, Program, State, Pc, LoopStack, CallStack) ->
    case resolve_target_pc(LineExpr, Program, State#state.vars) of
        {error, Reason} ->
            {stop, [format_runtime_error(Reason)]};
        {ok, TargetPc} ->
            {jump, TargetPc, State, LoopStack, [Pc + 1 | CallStack], []};
        missing ->
            {continue, State, LoopStack, CallStack, ["?SYNTAX ERROR\r\n"]}
    end.

resolve_target_pc(LineExpr, Program, Vars) ->
    case eval_expr_result(LineExpr, Vars) of
        {error, Reason, _} ->
            {error, Reason};
        {ok, LineValue, _} ->
            TargetLine = normalize_int(LineValue),
            case line_to_pc(Program, TargetLine) of
                {ok, TargetPc} -> {ok, TargetPc};
                error -> missing
            end
    end.

execute_return(State, LoopStack, []) ->
    {continue, State, LoopStack, [], ["?SYNTAX ERROR\r\n"]};
execute_return(State, LoopStack, [ReturnPc | Rest]) ->
    {jump, ReturnPc, State, LoopStack, Rest, []}.

handle_pending_input(Line, State = #state{pending_input = {Var, Continuation}}) ->
    Value = parse_input_value(Var, Line, State#state.vars),
    NextVars = maps:put(Var, Value, State#state.vars),
    ClearedState = State#state{vars = NextVars, pending_input = undefined},
    case Continuation of
        {immediate, RemainingStatements} ->
            resume_immediate_input(ClearedState, RemainingStatements);
        {program, Pc, RemainingStatements, LoopStack, CallStack} ->
            resume_program_input(ClearedState, Pc, RemainingStatements, LoopStack, CallStack)
    end.

resume_immediate_input(State, []) ->
    {State, []};
resume_immediate_input(State, RemainingStatements) ->
    finalize_statement_list(execute_statement_list(RemainingStatements, State, [])).

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

parse_input_value(Var, Line, Vars) ->
    case lists:last(Var) of
        $$ ->
            parse_string_input(Line);
        _ ->
            {Value, _} = eval_expr(Line, Vars),
            normalize_int(Value)
    end.

parse_string_input(Line) ->
    Trimmed = string:trim(Line),
    case re:run(Trimmed, "^\"(.*)\"$", [{capture, [1], list}]) of
        {match, [StringValue]} ->
            StringValue;
        nomatch ->
            Trimmed
    end.

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

execute_statement(Command, State) ->
    case should_split_top_level_sequence(Command) of
        true ->
            execute_statement_sequence(Command, State);
        false ->
            execute_statement_single(Command, State)
    end.

execute_statement_single(Command, State) ->
    case parse_statement(Command) of
        {print, Expr} ->
            case eval_expr_result(Expr, State#state.vars) of
                {ok, Value, Vars1} ->
                    {State#state{vars = Vars1}, [format_value(Value)]};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [format_runtime_error(Reason)]}
            end;
        {'let', Var, Expr} ->
            case eval_expr_result(Expr, State#state.vars) of
                {ok, Value, Vars1} ->
                    {State#state{vars = maps:put(Var, Value, Vars1)}, ["OK\r\n"]};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [format_runtime_error(Reason)]}
            end;
        {input, Var} ->
            {State#state{pending_input = {Var, {immediate, []}}}, [format_input_prompt(Var)]};
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case eval_condition_result(CondExpr, State#state.vars) of
                {ok, true} ->
                    case string:trim(ThenStmt) of
                        "" ->
                            {State, []};
                        SelectedThen ->
                            execute_statement_sequence(SelectedThen, State)
                    end;
                {ok, false} ->
                    case ElseStmt of
                        undefined ->
                            {State, []};
                        ElseBody ->
                            case string:trim(ElseBody) of
                                "" ->
                                    {State, []};
                                SelectedElse ->
                                    execute_statement_sequence(SelectedElse, State)
                            end
                    end;
                {error, Reason} ->
                    {State, [format_runtime_error(Reason)]}
            end;
        {'end'} ->
            stop;
        unknown ->
            {State, ["?SYNTAX ERROR\r\n"]};
        {for_loop, _Var, _StartExpr, _EndExpr, _StepExpr} ->
            {State, ["?SYNTAX ERROR\r\n"]};
        {next_loop, _MaybeVar} ->
            {State, ["?SYNTAX ERROR\r\n"]};
        {goto, _LineExpr} ->
            {State, ["?SYNTAX ERROR\r\n"]};
        {gosub, _LineExpr} ->
            {State, ["?SYNTAX ERROR\r\n"]};
        {'return'} ->
            {State, ["?SYNTAX ERROR\r\n"]}
    end.

is_runtime_error_output(["?DIVISION BY ZERO ERROR\r\n"]) ->
    true;
is_runtime_error_output(["?ILLEGAL FUNCTION CALL\r\n"]) ->
    true;
is_runtime_error_output(_) ->
    false.

should_split_top_level_sequence(Command) ->
    Statements = split_statements(Command),
    case length(Statements) > 1 of
        false ->
            false;
        true ->
            Trimmed = string:trim(Command),
            case re:run(Trimmed, "(?i)^IF\\s+", [{capture, none}]) of
                match -> false;
                nomatch -> true
            end
    end.

format_value(Value) when is_integer(Value) ->
    integer_to_list(Value) ++ "\r\n";
format_value(Value) when is_float(Value) ->
    format_number(Value) ++ "\r\n";
format_value(Value) when is_list(Value) ->
    Value ++ "\r\n".

format_number(Value) when is_integer(Value) ->
    integer_to_list(Value);
format_number(Value) when is_float(Value) ->
    Rounded = round(Value),
    case abs(Value - Rounded) < 1.0e-10 of
        true ->
            integer_to_list(Rounded);
        false ->
            Raw = lists:flatten(io_lib:format("~.10f", [Value])),
            trim_float_string(Raw)
    end.

trim_float_string(Text) ->
    trim_float_string_rev(lists:reverse(Text)).

trim_float_string_rev([$0 | Rest]) ->
    trim_float_string_rev(Rest);
trim_float_string_rev([$. | Rest]) ->
    lists:reverse(Rest);
trim_float_string_rev(Rest) ->
    lists:reverse(Rest).

eval_expr(Expr, Vars) ->
    case eval_expr_result(Expr, Vars) of
        {ok, Value, NextVars} ->
            {Value, NextVars};
        {error, _Reason, NextVars} ->
            {0, NextVars}
    end.

eval_expr_result(Expr, Vars) ->
    Trimmed = string:trim(Expr),
    case re:run(Trimmed, "^\"(.*)\"$", [{capture, [1], list}]) of
        {match, [StringValue]} ->
            {ok, StringValue, Vars};
        nomatch ->
            case string:to_integer(Trimmed) of
                {Int, ""} ->
                    {ok, Int, Vars};
                _ ->
                    case re:run(Trimmed, ?VAR_REFERENCE_PATTERN, [{capture, none}]) of
                        match ->
                            {ok, maps:get(string:to_upper(Trimmed), Vars, 0), Vars};
                        nomatch ->
                            case eval_arith_expr(Trimmed, Vars) of
                                {ok, NumValue} ->
                                    {ok, NumValue, Vars};
                                {error, Reason} ->
                                    {error, Reason, Vars}
                            end
                    end
            end
    end.

eval_arith_expr(Expr, Vars) ->
    case tokenize_expr(Expr) of
        {ok, Tokens} ->
            case parse_sum(Tokens, Vars) of
                {ok, Value, []} ->
                    {ok, Value};
                {error, Reason} ->
                    {error, Reason};
                _ ->
                    {error, syntax_error}
            end;
        error ->
            {error, syntax_error}
    end.

tokenize_expr(Text) ->
    tokenize_expr(Text, []).

tokenize_expr([], Acc) ->
    {ok, lists:reverse(Acc)};
tokenize_expr([Ch | Rest], Acc) when Ch =:= $\s; Ch =:= $\t ->
    tokenize_expr(Rest, Acc);
tokenize_expr([$+ | Rest], Acc) ->
    tokenize_expr(Rest, [plus | Acc]);
tokenize_expr([$- | Rest], Acc) ->
    tokenize_expr(Rest, [minus | Acc]);
tokenize_expr([$* | Rest], Acc) ->
    tokenize_expr(Rest, [mul | Acc]);
tokenize_expr([$/ | Rest], Acc) ->
    tokenize_expr(Rest, [divi | Acc]);
tokenize_expr([$\\ | Rest], Acc) ->
    tokenize_expr(Rest, [intdiv | Acc]);
tokenize_expr([$^ | Rest], Acc) ->
    tokenize_expr(Rest, [pow | Acc]);
tokenize_expr([$, | Rest], Acc) ->
    tokenize_expr(Rest, [comma | Acc]);
tokenize_expr([$( | Rest], Acc) ->
    tokenize_expr(Rest, [lparen | Acc]);
tokenize_expr([$) | Rest], Acc) ->
    tokenize_expr(Rest, [rparen | Acc]);
tokenize_expr([Ch | Rest], Acc) when Ch >= $0, Ch =< $9 ->
    {NumberChars, HasDot, Tail} = read_number([Ch | Rest], [], false),
    NumberToken =
        case HasDot of
            true -> {num, list_to_float(NumberChars)};
            false -> {num, list_to_integer(NumberChars)}
        end,
    tokenize_expr(Tail, [NumberToken | Acc]);
tokenize_expr([$. | Rest], Acc) ->
    case Rest of
        [Next | _] when Next >= $0, Next =< $9 ->
            {NumberChars, _HasDot, Tail} = read_number([$. | Rest], [], false),
            tokenize_expr(Tail, [{num, list_to_float(NumberChars)} | Acc]);
        _ ->
            error
    end;
tokenize_expr([Ch | Rest], Acc) when (Ch >= $A andalso Ch =< $Z) orelse (Ch >= $a andalso Ch =< $z) ->
    {NameChars, Tail} = read_identifier(Rest, [Ch]),
    Token =
        case string:to_upper(NameChars) of
            "MOD" -> mod;
            _ -> {var, NameChars}
        end,
    tokenize_expr(Tail, [Token | Acc]);
tokenize_expr(_, _Acc) ->
    error.

read_number([Ch | Rest], Acc, HasDot) when Ch >= $0, Ch =< $9 ->
    read_number(Rest, [Ch | Acc], HasDot);
read_number([$. | Rest], Acc, false) ->
    read_number(Rest, [$. | Acc], true);
read_number(Rest, Acc, HasDot) ->
    {lists:reverse(Acc), HasDot, Rest}.

read_identifier([Ch | Rest], Acc) when (Ch >= $A andalso Ch =< $Z) orelse (Ch >= $a andalso Ch =< $z) orelse (Ch >= $0 andalso Ch =< $9) orelse Ch =:= $_ ->
    read_identifier(Rest, Acc ++ [Ch]);
read_identifier([Suffix | Rest], Acc) when Suffix =:= $$; Suffix =:= $% ->
    {Acc ++ [Suffix], Rest};
read_identifier(Rest, Acc) ->
    {Acc, Rest}.

parse_sum(Tokens, Vars) ->
    case parse_term(Tokens, Vars) of
        {ok, Value, Rest} -> parse_sum_rest(Value, Rest, Vars);
        Error -> Error
    end.

parse_sum_rest(Value, [plus | Rest], Vars) ->
    case parse_term(Rest, Vars) of
        {ok, Right, Next} -> parse_sum_rest(Value + Right, Next, Vars);
        Error -> Error
    end;
parse_sum_rest(Value, [minus | Rest], Vars) ->
    case parse_term(Rest, Vars) of
        {ok, Right, Next} -> parse_sum_rest(Value - Right, Next, Vars);
        Error -> Error
    end;
parse_sum_rest(Value, Rest, _Vars) ->
    {ok, Value, Rest}.

parse_term(Tokens, Vars) ->
    case parse_unary(Tokens, Vars) of
        {ok, Value, Rest} -> parse_term_rest(Value, Rest, Vars);
        Error -> Error
    end.

parse_term_rest(Value, [mul | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, Right, Next} -> parse_term_rest(Value * Right, Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, [divi | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, 0, _Next} -> {error, division_by_zero};
        {ok, Right, Next} -> parse_term_rest(Value / Right, Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, [intdiv | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, 0, _Next} -> {error, division_by_zero};
        {ok, Right, Next} -> parse_term_rest(int_div(Value, Right), Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, [mod | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, 0, _Next} -> {error, division_by_zero};
        {ok, Right, Next} -> parse_term_rest(Value rem Right, Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, Rest, _Vars) ->
    {ok, Value, Rest}.

parse_unary([plus | Rest], Vars) ->
    parse_unary(Rest, Vars);
parse_unary([minus | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, Value, Next} -> {ok, -Value, Next};
        Error -> Error
    end;
parse_unary(Tokens, Vars) ->
    parse_power(Tokens, Vars).

parse_power(Tokens, Vars) ->
    case parse_primary(Tokens, Vars) of
        {ok, Left, [pow | Rest]} ->
            case parse_power(Rest, Vars) of
                {ok, Right, Next} -> {ok, math:pow(Left, Right), Next};
                Error -> Error
            end;
        Result ->
            Result
    end.

parse_primary([{num, Value} | Rest], _Vars) ->
    {ok, Value, Rest};
parse_primary([{var, Name}, lparen | Rest], Vars) ->
    case parse_call_args(Rest, Vars) of
        {ok, Args, Next} ->
            eval_builtin_call(Name, Args, Next);
        Error ->
            Error
    end;
parse_primary([{var, Name} | Rest], Vars) ->
    Raw = maps:get(string:to_upper(Name), Vars, 0),
    {ok, normalize_number(Raw), Rest};
parse_primary([lparen | Rest], Vars) ->
    case parse_sum(Rest, Vars) of
        {ok, Value, [rparen | Next]} -> {ok, Value, Next};
        _ -> error
    end;
parse_primary(_Tokens, _Vars) ->
    error.

parse_call_args([rparen | Rest], _Vars) ->
    {ok, [], Rest};
parse_call_args(Tokens, Vars) ->
    parse_call_args(Tokens, Vars, []).

parse_call_args(Tokens, Vars, Acc) ->
    case parse_sum(Tokens, Vars) of
        {ok, Value, [comma | Rest]} ->
            parse_call_args(Rest, Vars, [Value | Acc]);
        {ok, Value, [rparen | Rest]} ->
            {ok, lists:reverse([Value | Acc]), Rest};
        _ ->
            error
    end.

eval_builtin_call(Name, Args, Rest) ->
    UpperName = string:to_upper(Name),
    case apply_math_function(UpperName, Args) of
        {ok, Value} ->
            {ok, Value, Rest};
        {error, Reason} ->
            {error, Reason}
    end.

apply_math_function("ABS", [X]) ->
    {ok, abs(X)};
apply_math_function("ACOS", [X]) ->
    safe_math(fun() -> math:acos(X) end);
apply_math_function("ASIN", [X]) ->
    safe_math(fun() -> math:asin(X) end);
apply_math_function("ATAN", [X]) ->
    {ok, math:atan(X)};
apply_math_function("ATN", [X]) ->
    {ok, math:atan(X)};
apply_math_function("ATAN2", [Y, X]) ->
    {ok, math:atan2(Y, X)};
apply_math_function("COS", [X]) ->
    {ok, math:cos(X)};
apply_math_function("DEG", [X]) ->
    {ok, X * 180.0 / math:pi()};
apply_math_function("EXP", [X]) ->
    {ok, math:exp(X)};
apply_math_function("FIX", [X]) ->
    {ok, trunc(X)};
apply_math_function("INT", [X]) ->
    {ok, floor_number(X)};
apply_math_function("LN", [X]) ->
    safe_math(fun() -> math:log(X) end);
apply_math_function("LOG", [X]) ->
    safe_math(fun() -> math:log(X) end);
apply_math_function("PI", []) ->
    {ok, math:pi()};
apply_math_function("POW", [X, Y]) ->
    {ok, math:pow(X, Y)};
apply_math_function("RAD", [X]) ->
    {ok, X * math:pi() / 180.0};
apply_math_function("RND", []) ->
    gw_rnd();
apply_math_function("RND", [X]) ->
    gw_rnd(X);
apply_math_function("SGN", [X]) when X < 0 ->
    {ok, -1};
apply_math_function("SGN", [0]) ->
    {ok, 0};
apply_math_function("SGN", [_X]) ->
    {ok, 1};
apply_math_function("SIN", [X]) ->
    {ok, math:sin(X)};
apply_math_function("SQR", [X]) ->
    safe_math(fun() -> math:sqrt(X) end);
apply_math_function("SQRT", [X]) ->
    safe_math(fun() -> math:sqrt(X) end);
apply_math_function("TAN", [X]) ->
    {ok, math:tan(X)};
apply_math_function(_, _Args) ->
    {error, illegal_function_call}.

safe_math(Fun) ->
    try
        {ok, Fun()}
    catch
        error:badarith -> {error, illegal_function_call}
    end.

format_runtime_error(division_by_zero) ->
    "?DIVISION BY ZERO ERROR\r\n";
format_runtime_error(illegal_function_call) ->
    "?ILLEGAL FUNCTION CALL\r\n";
format_runtime_error(syntax_error) ->
    "?SYNTAX ERROR\r\n";
format_runtime_error(_) ->
    "?SYNTAX ERROR\r\n".

floor_number(X) when is_integer(X) ->
    X;
floor_number(X) when is_float(X) ->
    T = trunc(X),
    case X < T of
        true -> T - 1;
        false -> T
    end.

int_div(Left, Right) when is_integer(Left), is_integer(Right) ->
    Left div Right;
int_div(Left, Right) ->
    trunc(Left / Right).

gw_rnd() ->
    Value = rand:uniform(),
    put(gw_rnd_last, Value),
    {ok, Value}.

gw_rnd(X) when X < 0 ->
    SeedBase = erlang:phash2({gw_seed, X}, 16#7ffffffe) + 1,
    Seed2 = ((SeedBase * 1103515245) band 16#7fffffff) + 1,
    Seed3 = ((SeedBase * 12345) band 16#7fffffff) + 1,
    _ = rand:seed(exsplus, {SeedBase, Seed2, Seed3}),
    gw_rnd();
gw_rnd(X) when X =:= 0; X =:= +0.0 ->
    case get(gw_rnd_last) of
        undefined -> gw_rnd();
        Value -> {ok, Value}
    end;
gw_rnd(_X) ->
    gw_rnd().

normalize_int(Value) when is_integer(Value) ->
    Value;
normalize_int(Value) when is_list(Value) ->
    case string:to_integer(string:trim(Value)) of
        {Int, ""} -> Int;
        _ -> 0
    end;
normalize_int(_) ->
    0.

normalize_number(Value) when is_integer(Value); is_float(Value) ->
    Value;
normalize_number(Value) when is_list(Value) ->
    Trimmed = string:trim(Value),
    case string:to_float(Trimmed) of
        {Float, ""} -> Float;
        _ ->
            case string:to_integer(Trimmed) of
                {Int, ""} -> Int;
                _ -> 0
            end
    end;
normalize_number(_) ->
    0.

execute_statement_sequence(StatementText, State) ->
    Statements = split_statements(StatementText),
    finalize_statement_list(execute_statement_list(Statements, State, [])).

finalize_statement_list({continue, State, OutputAcc}) ->
    {State, OutputAcc};
finalize_statement_list({stop, State, OutputAcc}) ->
    {State, OutputAcc ++ ["Program ended\r\n"]}.

execute_statement_list([], State, OutputAcc) ->
    {continue, State, OutputAcc};
execute_statement_list([Stmt | Rest], State, OutputAcc) ->
    case execute_statement(Stmt, State) of
        {NextState, Output} ->
            case NextState#state.pending_input of
                undefined ->
                    execute_statement_list(Rest, NextState, OutputAcc ++ Output);
                _ ->
                    PendingState = update_pending_input_rest(NextState, Rest),
                    {continue, PendingState, OutputAcc ++ Output}
            end;
        stop ->
            {stop, State, OutputAcc}
    end.

split_statements(Text) ->
    split_statements(Text, [], [], false).

split_statements([], CurrentRev, PartsRev, _InString) ->
    FinalPart = string:trim(lists:reverse(CurrentRev)),
    lists:reverse(add_part(FinalPart, PartsRev));
split_statements([$" | Rest], CurrentRev, PartsRev, InString) ->
    split_statements(Rest, [$" | CurrentRev], PartsRev, not InString);
split_statements([$: | Rest], CurrentRev, PartsRev, false) ->
    Part = string:trim(lists:reverse(CurrentRev)),
    split_statements(Rest, [], add_part(Part, PartsRev), false);
split_statements([Ch | Rest], CurrentRev, PartsRev, InString) ->
    split_statements(Rest, [Ch | CurrentRev], PartsRev, InString).

add_part("", PartsRev) ->
    PartsRev;
add_part(Part, PartsRev) ->
    [Part | PartsRev].

eval_condition_result(CondExpr, Vars) ->
    Trimmed = string:trim(CondExpr),
    case re:run(Trimmed, "^(.*?)(<=|>=|<>|=|<|>)(.*)$", [{capture, [1, 2, 3], list}]) of
        {match, [LeftExpr, Op, RightExpr]} ->
            case eval_expr_result(LeftExpr, Vars) of
                {error, Reason, _} ->
                    {error, Reason};
                {ok, LeftVal, _} ->
                    case eval_expr_result(RightExpr, Vars) of
                        {error, Reason, _} ->
                            {error, Reason};
                        {ok, RightVal, _} ->
                            {ok, compare_values(LeftVal, RightVal, Op)}
                    end
            end;
        nomatch ->
            case eval_expr_result(Trimmed, Vars) of
                {error, Reason, _} ->
                    {error, Reason};
                {ok, Value, _} ->
                    {ok, truthy(Value)}
            end
    end.

truthy(Value) when is_integer(Value) ->
    Value =/= 0;
truthy(Value) when is_float(Value) ->
    Value =/= +0.0;
truthy(Value) when is_list(Value) ->
    string:trim(Value) =/= "";
truthy(_) ->
    false.

compare_values(LeftVal, RightVal, Op)
    when (is_integer(LeftVal) orelse is_float(LeftVal)) andalso
         (is_integer(RightVal) orelse is_float(RightVal)) ->
    case Op of
        "=" -> LeftVal =:= RightVal;
        "<>" -> LeftVal =/= RightVal;
        "<" -> LeftVal < RightVal;
        ">" -> LeftVal > RightVal;
        "<=" -> LeftVal =< RightVal;
        ">=" -> LeftVal >= RightVal
    end;
compare_values(LeftVal, RightVal, Op) ->
    L = to_string_value(LeftVal),
    R = to_string_value(RightVal),
    case Op of
        "=" -> L =:= R;
        "<>" -> L =/= R;
        "<" -> L < R;
        ">" -> L > R;
        "<=" -> L =< R;
        ">=" -> L >= R
    end.

to_string_value(Value) when is_list(Value) ->
    Value;
to_string_value(Value) when is_integer(Value) ->
    integer_to_list(Value);
to_string_value(Value) when is_float(Value) ->
    format_number(Value);
to_string_value(Value) ->
    lists:flatten(io_lib:format("~p", [Value])).