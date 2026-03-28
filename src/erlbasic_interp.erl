-module(erlbasic_interp).

-export([new_state/0, handle_input/2]).

-record(state, {
    vars = #{},
    prog = []
}).

new_state() ->
    #state{}.

handle_input(Line, State) ->
    Trimmed = string:trim(Line),
    case parse_program_line(Trimmed) of
        {program_line, Num, Code} ->
            NextProgram = update_program(State#state.prog, Num, Code),
            {State#state{prog = NextProgram}, ["OK\r\n"]};
        immediate ->
            exec_immediate(Trimmed, State)
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
            execute_statement(Command, State)
    end.

format_program(Program) ->
    [integer_to_list(LineNumber) ++ " " ++ Code ++ "\r\n" || {LineNumber, Code} <- Program].

run_program(Program, State) ->
    run_program_lines(Program, 1, State, [], []).

run_program_lines(Program, Pc, State, _LoopStack, Acc) when Pc > length(Program) ->
    {State, lists:reverse(Acc)};
run_program_lines(Program, Pc, State, LoopStack, Acc) ->
    {_LineNumber, Code} = lists:nth(Pc, Program),
    case execute_program_statement(Code, State, Pc, LoopStack) of
        {continue, NextPc, NextState, NextLoopStack, Output} ->
            run_program_lines(Program, NextPc, NextState, NextLoopStack, lists:reverse(Output) ++ Acc);
        stop ->
            {State, lists:reverse(["Program ended\r\n" | Acc])}
    end.

execute_program_statement(Command, State, Pc, LoopStack) ->
    case should_split_top_level_sequence(Command) of
        true ->
            execute_program_branch_sequence(Command, State, Pc, LoopStack);
        false ->
            execute_program_statement_single(Command, State, Pc, LoopStack)
    end.

execute_program_statement_single(Command, State, Pc, LoopStack) ->
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
            {continue, Pc + 1, NextState, [Frame | LoopStack], []};
        {next_loop, MaybeVar} ->
            handle_next_statement(MaybeVar, State, Pc, LoopStack);
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case eval_condition(CondExpr, State#state.vars) of
                true ->
                    case string:trim(ThenStmt) of
                        "" ->
                            {continue, Pc + 1, State, LoopStack, []};
                        SelectedThen ->
                            execute_program_branch_sequence(SelectedThen, State, Pc, LoopStack)
                    end;
                false ->
                    case ElseStmt of
                        undefined ->
                            {continue, Pc + 1, State, LoopStack, []};
                        ElseBody ->
                            case string:trim(ElseBody) of
                                "" ->
                                    {continue, Pc + 1, State, LoopStack, []};
                                SelectedElse ->
                                    execute_program_branch_sequence(SelectedElse, State, Pc, LoopStack)
                            end
                    end
            end;
        {'end'} ->
            stop;
        _ ->
            case execute_statement(Command, State) of
                {NextState, Output} ->
                    {continue, Pc + 1, NextState, LoopStack, Output};
                stop ->
                    stop
            end
    end.

handle_next_statement(_MaybeVar, State, Pc, []) ->
    {continue, Pc + 1, State, [], ["?SYNTAX ERROR\r\n"]};
handle_next_statement(MaybeVar, State, Pc, [{Var, EndInt, Step, ForPc} | Rest]) ->
    case MaybeVar of
        undefined ->
            continue_next(Var, EndInt, Step, ForPc, State, Pc, Rest);
        Var ->
            continue_next(Var, EndInt, Step, ForPc, State, Pc, Rest);
        _ ->
            {continue, Pc + 1, State, [{Var, EndInt, Step, ForPc} | Rest], ["?SYNTAX ERROR\r\n"]}
    end.

continue_next(Var, EndInt, Step, ForPc, State, Pc, Rest) ->
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
            {continue, ForPc + 1, NextState, [{Var, EndInt, Step, ForPc} | Rest], []};
        false ->
            {continue, Pc + 1, NextState, Rest, []}
    end.

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
            case re:run(Trimmed, "(?i)^LET\\s+([A-Za-z][A-Za-z0-9_]*)\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
                {match, [Var, Expr]} ->
                    {'let', string:to_upper(Var), Expr};
                nomatch ->
                    case re:run(Trimmed, "(?i)^IF\\s+(.+?)\\s+THEN\\s+(.+?)(?:\\s+ELSE\\s+(.+))?$", [{capture, all_but_first, list}]) of
                        {match, [CondExpr, ThenStmt]} ->
                            {if_then_else, CondExpr, ThenStmt, undefined};
                        {match, [CondExpr, ThenStmt, ElseStmt]} ->
                            {if_then_else, CondExpr, ThenStmt, ElseStmt};
                        nomatch ->
                            case re:run(Trimmed, "(?i)^FOR\\s+([A-Za-z][A-Za-z0-9_]*)\\s*=\\s*(.+)\\s+TO\\s+(.+?)(?:\\s+STEP\\s+(.+))?$", [{capture, all_but_first, list}]) of
                                {match, [Var, StartExpr, EndExpr]} ->
                                    {for_loop, string:to_upper(Var), StartExpr, EndExpr, undefined};
                                {match, [Var, StartExpr, EndExpr, StepExpr]} ->
                                    {for_loop, string:to_upper(Var), StartExpr, EndExpr, StepExpr};
                                nomatch ->
                                    case re:run(Trimmed, "(?i)^NEXT(?:\\s+([A-Za-z][A-Za-z0-9_]*))?$", [{capture, all_but_first, list}]) of
                                        {match, []} ->
                                            {next_loop, undefined};
                                        {match, [Var]} ->
                                            {next_loop, string:to_upper(Var)};
                                        nomatch ->
                                            case string:to_upper(Trimmed) of
                                                "END" -> {'end'};
                                                _ -> unknown
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
                    {maps:get(string:to_upper(Trimmed), Vars, 0), Vars}
            end
    end.

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
    execute_statement_list(Statements, State, []).

execute_statement_list([], State, OutputAcc) ->
    {State, OutputAcc};
execute_statement_list([Stmt | Rest], State, OutputAcc) ->
    case execute_statement(Stmt, State) of
        {NextState, Output} ->
            execute_statement_list(Rest, NextState, OutputAcc ++ Output);
        stop ->
            stop
    end.

execute_program_branch_sequence(StatementText, State, Pc, LoopStack) ->
    Statements = split_statements(StatementText),
    execute_program_branch_list(Statements, State, Pc, LoopStack, []).

execute_program_branch_list([], State, Pc, LoopStack, OutputAcc) ->
    {continue, Pc + 1, State, LoopStack, OutputAcc};
execute_program_branch_list([Stmt | Rest], State, Pc, LoopStack, OutputAcc) ->
    case execute_statement(Stmt, State) of
        {NextState, Output} ->
            execute_program_branch_list(Rest, NextState, Pc, LoopStack, OutputAcc ++ Output);
        stop ->
            stop
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
    io_lib:format("~p", [Value]).