-module(erlbasic_interp).

-export([new_state/0, handle_input/2, next_prompt/1]).

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
    Sorted = lists:keysort(1, [{LineNumber, Code} | lists:keydelete(LineNumber, 1, Program)]),
    Sorted.

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
            normalize_immediate_result(execute_statement(Command, State), State)
    end.

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
        {stop, Output} ->
            {State, lists:reverse(["Program ended\r\n" | lists:reverse(Output) ++ Acc])}
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
        {stop, Output} ->
            {stop, OutputAcc ++ Output}
    end.

execute_program_line_statement(Command, Program, State, Pc, LoopStack, CallStack) ->
    case parse_statement(Command) of
        {for_loop, Var, StartExpr, EndExpr, StepExpr} ->
            {StartValue, Vars1} = eval_expr(StartExpr, State#state.vars),
            {EndValue, Vars2} = eval_expr(EndExpr, Vars1),
            StepValue =
                case StepExpr of
                    undefined ->
                        1;
                    Expr ->
                        {RawStepValue, _} = eval_expr(Expr, Vars2),
                        normalize_int(RawStepValue)
                end,
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
            {continue, NextState, [Frame | LoopStack], CallStack, []};
        {next_loop, MaybeVar} ->
            handle_next_statement(MaybeVar, State, Pc, LoopStack, CallStack);
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case eval_condition(CondExpr, State#state.vars) of
                true ->
                    case string:trim(ThenStmt) of
                        "" ->
                            {continue, State, LoopStack, CallStack, []};
                        SelectedThen ->
                            execute_program_inline_sequence(SelectedThen, Program, State, Pc, LoopStack, CallStack)
                    end;
                false ->
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
                    end
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
            {stop, []};
        _ ->
            case execute_statement_single(Command, State) of
                {NextState, Output} ->
                    {continue, NextState, LoopStack, CallStack, Output};
                stop ->
                    {stop, []}
            end
    end.

execute_program_inline_sequence(StatementText, Program, State, Pc, LoopStack, CallStack) ->
    execute_program_line_statements(split_statements(StatementText), Program, State, Pc, LoopStack, CallStack, []).

execute_goto(LineExpr, Program, State, LoopStack, CallStack) ->
    {LineValue, _} = eval_expr(LineExpr, State#state.vars),
    TargetLine = normalize_int(LineValue),
    case line_to_pc(Program, TargetLine) of
        {ok, TargetPc} ->
            {jump, TargetPc, State, LoopStack, CallStack, []};
        error ->
            {continue, State, LoopStack, CallStack, ["?SYNTAX ERROR\r\n"]}
    end.

execute_gosub(LineExpr, Program, State, Pc, LoopStack, CallStack) ->
    {LineValue, _} = eval_expr(LineExpr, State#state.vars),
    TargetLine = normalize_int(LineValue),
    case line_to_pc(Program, TargetLine) of
        {ok, TargetPc} ->
            {jump, TargetPc, State, LoopStack, [Pc + 1 | CallStack], []};
        error ->
            {continue, State, LoopStack, CallStack, ["?SYNTAX ERROR\r\n"]}
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
            {Value, Vars1} = eval_expr(Expr, State#state.vars),
            {State#state{vars = Vars1}, [format_value(Value)]};
        {'let', Var, Expr} ->
            {Value, Vars1} = eval_expr(Expr, State#state.vars),
            {State#state{vars = maps:put(Var, Value, Vars1)}, ["OK\r\n"]};
        {input, Var} ->
            {State#state{pending_input = {Var, {immediate, []}}}, [format_input_prompt(Var)]};
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case eval_condition(CondExpr, State#state.vars) of
                true ->
                    case string:trim(ThenStmt) of
                        "" ->
                            {State, []};
                        SelectedThen ->
                            execute_statement_sequence(SelectedThen, State)
                    end;
                false ->
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
                    end
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

parse_statement(Command) ->
    Trimmed = string:trim(Command),
    case re:run(Trimmed, "(?i)^PRINT\\s+(.+)$", [{capture, [1], list}]) of
        {match, [Expr]} ->
            {print, Expr};
        nomatch ->
            case re:run(Trimmed, "(?i)^INPUT\\s+([A-Za-z][A-Za-z0-9_]*\\$?)$", [{capture, [1], list}]) of
                {match, [Var]} ->
                    {input, string:to_upper(Var)};
                nomatch ->
                    case re:run(Trimmed, "(?i)^LET\\s+([A-Za-z][A-Za-z0-9_]*\\$?)\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
                {match, [Var, Expr]} ->
                    {'let', string:to_upper(Var), Expr};
                nomatch ->
                    case re:run(Trimmed, "(?i)^IF\\s+(.+?)\\s+THEN\\s+(.+?)(?:\\s+ELSE\\s+(.+))?$", [{capture, all_but_first, list}]) of
                        {match, [CondExpr, ThenStmt]} ->
                            {if_then_else, CondExpr, ThenStmt, undefined};
                        {match, [CondExpr, ThenStmt, ElseStmt]} ->
                            {if_then_else, CondExpr, ThenStmt, ElseStmt};
                        nomatch ->
                            case re:run(Trimmed, "(?i)^GOTO\\s+(.+)$", [{capture, [1], list}]) of
                                {match, [LineExpr]} ->
                                    {goto, LineExpr};
                                nomatch ->
                                    case re:run(Trimmed, "(?i)^GOSUB\\s+(.+)$", [{capture, [1], list}]) of
                                        {match, [LineExpr]} ->
                                            {gosub, LineExpr};
                                        nomatch ->
                                            case re:run(Trimmed, "(?i)^FOR\\s+([A-Za-z][A-Za-z0-9_]*)\\s*=\\s*(.+)\\s+TO\\s+(.+?)(?:\\s+STEP\\s+(.+))?$", [{capture, all_but_first, list}]) of
                                                {match, [Var, StartExpr, EndExpr]} ->
                                                    {for_loop, string:to_upper(Var), StartExpr, EndExpr, undefined};
                                                {match, [Var, StartExpr, EndExpr, StepExpr]} ->
                                                    {for_loop, string:to_upper(Var), StartExpr, EndExpr, StepExpr};
                                                nomatch ->
                                                    case re:run(Trimmed, "(?i)^NEXT(?:\\s+([A-Za-z][A-Za-z0-9_]*\\$?))?$", [{capture, all_but_first, list}]) of
                                                        {match, []} ->
                                                            {next_loop, undefined};
                                                        {match, [Var]} ->
                                                            {next_loop, string:to_upper(Var)};
                                                        nomatch ->
                                                            case string:to_upper(Trimmed) of
                                                                "RETURN" -> {'return'};
                                                                "END" -> {'end'};
                                                                _ -> unknown
                                                            end
                                                    end
                                            end
                                    end
                            end
                    end
                                    end
            end
    end.

format_value(Value) when is_integer(Value) ->
    integer_to_list(Value) ++ "\r\n";
format_value(Value) when is_list(Value) ->
    Value ++ "\r\n".

eval_expr(Expr, Vars) ->
    Trimmed = string:trim(Expr),
    case re:run(Trimmed, "^\"(.*)\"$", [{capture, [1], list}]) of
        {match, [StringValue]} ->
            {StringValue, Vars};
        nomatch ->
            case string:to_integer(Trimmed) of
                {Int, ""} ->
                    {Int, Vars};
                _ ->
                    case re:run(Trimmed, "^[A-Za-z][A-Za-z0-9_]*\\$?$", [{capture, none}]) of
                        match ->
                            {maps:get(string:to_upper(Trimmed), Vars, 0), Vars};
                        nomatch ->
                            case eval_arith_expr(Trimmed, Vars) of
                                {ok, IntValue} ->
                                    {IntValue, Vars};
                                error ->
                                    {maps:get(string:to_upper(Trimmed), Vars, 0), Vars}
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
                _ ->
                    error
            end;
        error ->
            error
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
tokenize_expr([$( | Rest], Acc) ->
    tokenize_expr(Rest, [lparen | Acc]);
tokenize_expr([$) | Rest], Acc) ->
    tokenize_expr(Rest, [rparen | Acc]);
tokenize_expr([Ch | Rest], Acc) when Ch >= $0, Ch =< $9 ->
    {NumberChars, Tail} = read_digits([Ch | Rest], []),
    tokenize_expr(Tail, [{int, list_to_integer(NumberChars)} | Acc]);
tokenize_expr([Ch | Rest], Acc) when (Ch >= $A andalso Ch =< $Z) orelse (Ch >= $a andalso Ch =< $z) ->
    {NameChars, Tail} = read_identifier(Rest, [Ch]),
    tokenize_expr(Tail, [{var, NameChars} | Acc]);
tokenize_expr(_, _Acc) ->
    error.

read_digits([Ch | Rest], Acc) when Ch >= $0, Ch =< $9 ->
    read_digits(Rest, [Ch | Acc]);
read_digits(Rest, Acc) ->
    {lists:reverse(Acc), Rest}.

read_identifier([Ch | Rest], Acc) when (Ch >= $A andalso Ch =< $Z) orelse (Ch >= $a andalso Ch =< $z) orelse (Ch >= $0 andalso Ch =< $9) orelse Ch =:= $_ ->
    read_identifier(Rest, Acc ++ [Ch]);
read_identifier([$$ | Rest], Acc) ->
    {Acc ++ [$$], Rest};
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
    case parse_factor(Tokens, Vars) of
        {ok, Value, Rest} -> parse_term_rest(Value, Rest, Vars);
        Error -> Error
    end.

parse_term_rest(Value, [mul | Rest], Vars) ->
    case parse_factor(Rest, Vars) of
        {ok, Right, Next} -> parse_term_rest(Value * Right, Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, [divi | Rest], Vars) ->
    case parse_factor(Rest, Vars) of
        {ok, 0, Next} -> parse_term_rest(0, Next, Vars);
        {ok, Right, Next} -> parse_term_rest(Value div Right, Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, Rest, _Vars) ->
    {ok, Value, Rest}.

parse_factor([plus | Rest], Vars) ->
    parse_factor(Rest, Vars);
parse_factor([minus | Rest], Vars) ->
    case parse_factor(Rest, Vars) of
        {ok, Value, Next} -> {ok, -Value, Next};
        Error -> Error
    end;
parse_factor([{int, Value} | Rest], _Vars) ->
    {ok, Value, Rest};
parse_factor([{var, Name} | Rest], Vars) ->
    Raw = maps:get(string:to_upper(Name), Vars, 0),
    {ok, normalize_int(Raw), Rest};
parse_factor([lparen | Rest], Vars) ->
    case parse_sum(Rest, Vars) of
        {ok, Value, [rparen | Next]} -> {ok, Value, Next};
        _ -> error
    end;
parse_factor(_Tokens, _Vars) ->
    error.

normalize_int(Value) when is_integer(Value) ->
    Value;
normalize_int(Value) when is_list(Value) ->
    case string:to_integer(string:trim(Value)) of
        {Int, ""} -> Int;
        _ -> 0
    end;
normalize_int(_) ->
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

eval_condition(CondExpr, Vars) ->
    Trimmed = string:trim(CondExpr),
    case re:run(Trimmed, "^(.*?)(<=|>=|<>|=|<|>)(.*)$", [{capture, [1, 2, 3], list}]) of
        {match, [LeftExpr, Op, RightExpr]} ->
            {LeftVal, _} = eval_expr(LeftExpr, Vars),
            {RightVal, _} = eval_expr(RightExpr, Vars),
            compare_values(LeftVal, RightVal, Op);
        nomatch ->
            {Value, _} = eval_expr(Trimmed, Vars),
            truthy(Value)
    end.

truthy(Value) when is_integer(Value) ->
    Value =/= 0;
truthy(Value) when is_list(Value) ->
    string:trim(Value) =/= "";
truthy(_) ->
    false.

compare_values(LeftVal, RightVal, Op) when is_integer(LeftVal), is_integer(RightVal) ->
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
to_string_value(Value) ->
    lists:flatten(io_lib:format("~p", [Value])).