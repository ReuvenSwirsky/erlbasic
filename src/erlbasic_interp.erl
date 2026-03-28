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
            run_program(State);
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
    case erlbasic_parser:should_split_top_level_sequence(Code) of
        true ->
            join_statements([rewrite_line_refs(Stmt, LineMap) || Stmt <- erlbasic_parser:split_statements(Code)]);
        false ->
            rewrite_single_statement_line_refs(Code, LineMap)
    end.

rewrite_single_statement_line_refs(Code, LineMap) ->
    case erlbasic_parser:parse_statement(Code) of
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

run_program(State) ->
    erlbasic_runtime:run_program(State).

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
    erlbasic_runtime:resume_program_input(State, Pc, RemainingStatements, LoopStack, CallStack).

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
            {Value, _} = erlbasic_eval:eval_expr(Line, Vars),
            erlbasic_eval:normalize_int(Value)
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

execute_statement(Command, State) ->
    case erlbasic_parser:should_split_top_level_sequence(Command) of
        true ->
            execute_statement_sequence(Command, State);
        false ->
            execute_statement_single(Command, State)
    end.

execute_statement_single(Command, State) ->
    case erlbasic_parser:parse_statement(Command) of
        {print, Expr} ->
            case erlbasic_eval:eval_expr_result(Expr, State#state.vars) of
                {ok, Value, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_value(Value)]};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {'let', Var, Expr} ->
            case erlbasic_eval:eval_expr_result(Expr, State#state.vars) of
                {ok, Value, Vars1} ->
                    {State#state{vars = maps:put(Var, Value, Vars1)}, ["OK\r\n"]};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {input, Var} ->
            {State#state{pending_input = {Var, {immediate, []}}}, [format_input_prompt(Var)]};
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case erlbasic_eval:eval_condition_result(CondExpr, State#state.vars) of
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
                    {State, [erlbasic_eval:format_runtime_error(Reason)]}
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

execute_statement_sequence(StatementText, State) ->
    Statements = erlbasic_parser:split_statements(StatementText),
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
