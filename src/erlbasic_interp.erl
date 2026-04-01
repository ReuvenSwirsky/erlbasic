-module(erlbasic_interp).

-export([new_state/0, handle_input/2, next_prompt/1, awaiting_input/1, awaiting_input_nonblocking/1, awaiting_input_getkey/1]).


-include("erlbasic_state.hrl").

new_state() ->
    #state{}.

%% @doc True when the interpreter is paused waiting for an INPUT statement response.
awaiting_input(#state{pending_input = undefined}) -> false;
awaiting_input(_State) -> true.

%% @doc True only when paused on a non-blocking GET (conn layer uses a short
%% timeout so the Erlang scheduler can run other processes between polls).
awaiting_input_nonblocking(#state{pending_input = {get_nb, _, _}}) -> true;
awaiting_input_nonblocking(_State) -> false.

%% @doc True only when the interpreter is paused waiting for a GETKEY statement.
awaiting_input_getkey(#state{pending_input = {getkey, _, _}}) -> true;
awaiting_input_getkey(_State) -> false.

next_prompt(#state{pending_input = undefined}) ->
    "> ";
next_prompt(_State) ->
    "".

handle_input(Line, State) ->
    Trimmed = string:trim(Line),
    case State#state.pending_input of
        undefined ->
            case erlbasic_commands:parse_program_line(Trimmed) of
                {program_line, Num, Code} ->
                    handle_program_line(Num, Code, State);
                immediate ->
                    handle_immediate_or_buffer_line(Trimmed, State)
            end;
        _ ->
            handle_pending_input(Trimmed, State)
    end.

handle_program_line(LineNumber, "", State) ->
    NextProgram = update_program(State#state.prog, LineNumber, ""),
    {State#state{prog = NextProgram, data_items = [], data_index = 1, continue_ctx = undefined}, ["OK\r\n"]};
handle_program_line(LineNumber, Code, State) ->
    case erlbasic_parser:validate_program_line(Code) of
        ok ->
            NextProgram = update_program(State#state.prog, LineNumber, Code),
            {State#state{prog = NextProgram, data_items = [], data_index = 1, continue_ctx = undefined}, ["OK\r\n"]};
        error ->
            {State, ["?SYNTAX ERROR\r\n"]}
    end.

update_program(Program, LineNumber, "") ->
    lists:keydelete(LineNumber, 1, Program);
update_program(Program, LineNumber, Code) ->
    lists:keysort(1, [{LineNumber, Code} | lists:keydelete(LineNumber, 1, Program)]).

handle_immediate_or_buffer_line(Command, State = #state{immediate_for_buffer = undefined}) ->
    case should_start_immediate_for_buffer(Command) of
        true ->
            Depth = for_next_delta(Command),
            {State#state{immediate_for_buffer = {[Command], Depth}}, []};
        false ->
            exec_immediate(Command, State)
    end;
handle_immediate_or_buffer_line(Command, State = #state{immediate_for_buffer = {Lines, Depth}}) ->
    NewLines = Lines ++ [Command],
    NewDepth = Depth + for_next_delta(Command),
    case NewDepth of
        N when N > 0 ->
            {State#state{immediate_for_buffer = {NewLines, N}}, []};
        0 ->
            execute_immediate_for_block(NewLines, State#state{immediate_for_buffer = undefined});
        _ ->
            {State#state{immediate_for_buffer = undefined}, ["?SYNTAX ERROR\r\n"]}
    end.

should_start_immediate_for_buffer("") ->
    false;
should_start_immediate_for_buffer(Command) ->
    case erlbasic_parser:split_statements(Command) of
        [] ->
            false;
        [FirstStmt | _] ->
            case erlbasic_parser:parse_statement(FirstStmt) of
                {for_loop, _Var, _StartExpr, _EndExpr, _StepExpr} ->
                    for_next_delta(Command) > 0;
                _ ->
                    false
            end
    end.

for_next_delta(Command) ->
    Statements = erlbasic_parser:split_statements(Command),
    lists:sum([for_next_stmt_delta(Stmt) || Stmt <- Statements]).

for_next_stmt_delta(Stmt) ->
    case erlbasic_parser:parse_statement(Stmt) of
        {for_loop, _Var, _StartExpr, _EndExpr, _StepExpr} ->
            1;
        {next_loop, _MaybeVar} ->
            -1;
        _ ->
            0
    end.

execute_immediate_for_block(Lines, State) ->
    TempProgram = build_temp_program(Lines),
    TempState = State#state{prog = TempProgram},
    {RanState, Output} = erlbasic_runtime:run_program(TempState),
    {RanState#state{prog = State#state.prog}, Output}.

build_temp_program(Lines) ->
    Numbered = lists:seq(10, 10 * length(Lines), 10),
    CleanLines = [string:trim(Line) || Line <- Lines],
    lists:zip(Numbered, CleanLines).

exec_immediate("", State) ->
    {State, []};
exec_immediate(Command, State) ->
    Upper = string:to_upper(Command),
    case erlbasic_commands:parse_list_command(Upper) of
        {list, all} ->
            {State, erlbasic_commands:format_program(State#state.prog)};
        {list, StartLine, EndLine} ->
            Filtered = erlbasic_commands:filter_program_by_range(State#state.prog, StartLine, EndLine),
            {State, erlbasic_commands:format_program(Filtered)};
        nomatch ->
            case erlbasic_commands:parse_delete_command(Upper) of
                {delete, StartLine, EndLine} ->
                    NewProg = erlbasic_commands:delete_lines_by_range(State#state.prog, StartLine, EndLine),
                    {State#state{prog = NewProg, continue_ctx = undefined}, ["OK\r\n"]};
                nomatch ->
                    exec_immediate_other(Upper, Command, State)
            end
    end.

exec_immediate_other(Upper, Command, State) ->
    case Upper of
        "DIR" ->
            erlbasic_commands:handle_dir_command(State);
        "NEW" ->
            {State#state{prog = [], data_items = [], data_index = 1, continue_ctx = undefined}, ["Program cleared\r\n"]};
        "RUN" ->
            run_program(State);
        "CONT" ->
            continue_program(State);
        _ ->
            case erlbasic_commands:parse_file_command(Command) of
                {save, FileName} ->
                    erlbasic_commands:handle_save_command(State, FileName);
                {load, FileName} ->
                    erlbasic_commands:handle_load_command(State, FileName);
                {scratch, FileName} ->
                    erlbasic_commands:handle_scratch_command(State, FileName);
                nomatch ->
                    case erlbasic_commands:parse_renum_command(Command) of
                        {ok, StartLine, Increment} ->
                            Renumbered = erlbasic_commands:renumber_program(State#state.prog, StartLine, Increment),
                            {State#state{prog = Renumbered, continue_ctx = undefined}, ["OK\r\n"]};
                        error ->
                            normalize_immediate_result(execute_statement(Command, State), State)
                    end
            end
    end.

normalize_immediate_result({NextState, Output}, _State) ->
    {NextState, Output};
normalize_immediate_result(stop, State) ->
    {State, ["Program ended\r\n"]}.

run_program(State) ->
    erlbasic_runtime:run_program(State#state{continue_ctx = undefined}).

continue_program(State = #state{continue_ctx = undefined}) ->
    {State, [erlbasic_eval:format_runtime_error(cant_continue)]};
continue_program(State = #state{continue_ctx = {Pc, LoopStack, CallStack}}) ->
    erlbasic_runtime:continue_program(State#state{continue_ctx = undefined}, Pc, LoopStack, CallStack).

handle_pending_input(Line, State = #state{pending_input = {Targets, Continuation}}) when is_list(Targets) ->
    Fields = split_input_fields(Line),
    case apply_input_fields(Targets, Fields, State#state.vars, State#state.funcs) of
        {ok, NextVars} ->
            ClearedState = State#state{vars = NextVars, pending_input = undefined},
            resume_continuation(ClearedState, Continuation);
        redo ->
            {State, ["?Redo from start\r\n? "]};
        {error, Reason} ->
            {State#state{pending_input = undefined}, [erlbasic_eval:format_runtime_error(Reason)]}
    end;
handle_pending_input(Line, State = #state{pending_input = {input_line, Target, Continuation}}) ->
    case erlbasic_eval:assign_target(Target, Line, State#state.vars, State#state.funcs) of
        {ok, NextVars} ->
            ClearedState = State#state{vars = NextVars, pending_input = undefined},
            resume_continuation(ClearedState, Continuation);
        {error, Reason} ->
            {State#state{pending_input = undefined}, [erlbasic_eval:format_runtime_error(Reason)]}
    end;
handle_pending_input(Line, State = #state{pending_input = {get_nb, Target, Continuation}}) ->
    handle_getchar(Target, Line, State, Continuation);
handle_pending_input(Line, State = #state{pending_input = {getkey, Target, Continuation}}) ->
    handle_getchar(Target, Line, State, Continuation).

handle_getchar(Target, Line, State, Continuation) ->
    {Ch, Rest} = case Line of
        []      -> {"", []};
        [H | T] -> {[H], T}
    end,
    case erlbasic_eval:assign_target(Target, Ch, State#state.vars, State#state.funcs) of
        {ok, NextVars} ->
            ClearedState = State#state{vars = NextVars, pending_input = undefined, char_buffer = Rest},
            resume_continuation(ClearedState, Continuation);
        {error, Reason} ->
            {State#state{pending_input = undefined}, [erlbasic_eval:format_runtime_error(Reason)]}
    end.

resume_continuation(State, {immediate, RemainingStatements}) ->
    resume_immediate_input(State, RemainingStatements);
resume_continuation(State, {program, Pc, RemainingStatements, LoopStack, CallStack}) ->
    resume_program_input(State, Pc, RemainingStatements, LoopStack, CallStack).

%% Split user input by commas, respecting double-quoted strings.
split_input_fields(Line) ->
    split_input_fields(Line, [], [], false).

split_input_fields([], Current, Parts, _InQuote) ->
    lists:reverse([string:trim(lists:reverse(Current)) | Parts]);
split_input_fields([$" | Rest], Current, Parts, InQuote) ->
    split_input_fields(Rest, [$" | Current], Parts, not InQuote);
split_input_fields([$, | Rest], Current, Parts, false) ->
    Field = string:trim(lists:reverse(Current)),
    split_input_fields(Rest, [], [Field | Parts], false);
split_input_fields([Ch | Rest], Current, Parts, InQuote) ->
    split_input_fields(Rest, [Ch | Current], Parts, InQuote).

%% Assign each comma-field to the corresponding target.  Returns
%% {ok, NewVars}, redo (field count mismatch), or {error, Reason}.
apply_input_fields(Targets, Fields, Vars, Funcs) ->
    case length(Fields) =:= length(Targets) of
        false -> redo;
        true  -> apply_input_fields(Targets, Fields, Vars, Funcs, Vars)
    end.

apply_input_fields([], [], _Vars, _Funcs, AccVars) ->
    {ok, AccVars};
apply_input_fields([Target | RestTargets], [Field | RestFields], Vars, Funcs, AccVars) ->
    case parse_input_value(Target, Field, Vars, Funcs) of
        {ok, Value} ->
            case erlbasic_eval:assign_target(Target, Value, AccVars, Funcs) of
                {ok, NextVars} ->
                    apply_input_fields(RestTargets, RestFields, Vars, Funcs, NextVars);
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

resume_immediate_input(State, []) ->
    {State, []};
resume_immediate_input(State, RemainingStatements) ->
    finalize_statement_list(execute_statement_list(RemainingStatements, State, [])).

resume_program_input(State, Pc, RemainingStatements, LoopStack, CallStack) ->
    erlbasic_runtime:resume_program_input(State, Pc, RemainingStatements, LoopStack, CallStack).

parse_input_value(Target, Line, Vars, Funcs) ->
    case erlbasic_eval:target_is_string(Target) of
        true ->
            {ok, parse_string_input(Line)};
        false ->
            {Value, _} = erlbasic_eval:eval_expr(Line, Vars, Funcs),
            {ok, erlbasic_eval:normalize_int(Value)}
    end.

parse_string_input(Line) ->
    Trimmed = string:trim(Line),
    case re:run(Trimmed, "^\"(.*)\"$", [{capture, [1], list}]) of
        {match, [StringValue]} ->
            StringValue;
        nomatch ->
            Trimmed
    end.

execute_statement(Command, State) ->
    case erlbasic_parser:should_split_top_level_sequence(Command) of
        true ->
            execute_statement_sequence(Command, State);
        false ->
            execute_statement_single(Command, State)
    end.

execute_statement_single(Command, State) ->
    case erlbasic_parser:parse_statement(Command) of
        {print, Items, EndWithNewline} ->
            case erlbasic_runtime:render_print_items(Items, State#state.vars, State#state.funcs, State#state.print_col) of
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
                    {State#state{vars = Vars1, print_col = FinalCol}, [FinalText]};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {print_using, FormatExpr, Items, EndWithNewline} ->
            case erlbasic_eval:eval_expr_result(FormatExpr, State#state.vars, State#state.funcs) of
                {ok, FormatValue, Vars1} when is_list(FormatValue) ->
                    case erlbasic_runtime:render_print_using_items(Items, FormatValue, Vars1, State#state.funcs, State#state.print_col) of
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
                            {State#state{vars = Vars2, print_col = FinalCol}, [FinalText]};
                        {error, Reason, Vars2} ->
                            {State#state{vars = Vars2}, [erlbasic_eval:format_runtime_error(Reason)]}
                    end;
                {ok, _Other, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(type_mismatch)]};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {'let', Target, Expr} ->
            case erlbasic_eval:eval_expr_result(Expr, State#state.vars, State#state.funcs) of
                {ok, Value, Vars1} ->
                    case erlbasic_eval:assign_target(Target, Value, Vars1, State#state.funcs) of
                        {ok, Vars2} ->
                            {State#state{vars = Vars2}, []};
                        {error, Reason} ->
                            {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
                    end;
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {def_fn, FnName, ArgVar, FnExpr} ->
            NextFuncs = maps:put(FnName, {ArgVar, FnExpr}, State#state.funcs),
            {State#state{funcs = NextFuncs}, ["OK\r\n"]};
        {dim, Decls} ->
            case erlbasic_runtime:apply_dim_decls(Decls, State#state.vars, State#state.funcs) of
                {ok, Vars1} ->
                    {State#state{vars = Vars1}, ["OK\r\n"]};
                {error, Reason} ->
                    {State, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {data, _Items} ->
            {State, ["OK\r\n"]};
        {read_data, Targets} ->
            DataState = ensure_data_loaded(State),
            case erlbasic_runtime:apply_read_vars(Targets, DataState) of
                {ok, NextState} ->
                    {NextState, ["OK\r\n"]};
                {error, Reason} ->
                    {DataState, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {input, Targets} ->
            {State#state{pending_input = {Targets, {immediate, []}}}, [erlbasic_runtime:format_input_prompt(Targets)]};
        {input_line, Target} ->
            {State#state{pending_input = {input_line, Target, {immediate, []}}}, [erlbasic_runtime:format_input_prompt(Target)]};
        {get, Target} ->
            %% Non-blocking but cooperative: take first buffered char, or suspend
            %% so the conn layer can yield the CPU before returning "".
            case State#state.char_buffer of
                [Ch | Rest] ->
                    case erlbasic_eval:assign_target(Target, [Ch], State#state.vars, State#state.funcs) of
                        {ok, Vars1} -> {State#state{vars = Vars1, char_buffer = Rest}, []};
                        {error, Reason} -> {State, [erlbasic_eval:format_runtime_error(Reason)]}
                    end;
                [] ->
                    {State#state{pending_input = {get_nb, Target, {immediate, []}}}, []}
            end;
        {getkey, Target} ->
            case State#state.char_buffer of
                [Ch | Rest] ->
                    case erlbasic_eval:assign_target(Target, [Ch], State#state.vars, State#state.funcs) of
                        {ok, Vars1} -> {State#state{vars = Vars1, char_buffer = Rest}, []};
                        {error, Reason} -> {State, [erlbasic_eval:format_runtime_error(Reason)]}
                    end;
                [] ->
                    {State#state{pending_input = {getkey, Target, {immediate, []}}}, []}
            end;
        {locate, RowExpr, ColExpr} ->
            case erlbasic_runtime:eval_locate(RowExpr, ColExpr, State#state.vars, State#state.funcs) of
                {ok, Vars1, Output} ->
                    {State#state{vars = Vars1}, Output};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case erlbasic_eval:eval_condition_result(CondExpr, State#state.vars, State#state.funcs) of
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
            {State, [erlbasic_eval:format_runtime_error(next_without_for)]};
        {cls} ->
            {State, erlbasic_runtime:cls_output()};
        {sleep, Expr} ->
            case erlbasic_eval:eval_expr_result(Expr, State#state.vars, State#state.funcs) of
                {ok, Value, Vars1} when is_number(Value) ->
                    Ms = max(0, trunc(Value * 1000)),
                    timer:sleep(Ms),
                    {State#state{vars = Vars1}, []};
                {ok, _Value, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(type_mismatch)]};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {color, FgExpr, BgExpr} ->
            case erlbasic_runtime:eval_color(FgExpr, BgExpr, State#state.vars, State#state.funcs) of
                {ok, Vars1, Output} ->
                    {State#state{vars = Vars1}, Output};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {remark} ->
            {State, []};
        {goto, _LineExpr} ->
            {State, ["?SYNTAX ERROR\r\n"]};
        {gosub, _LineExpr} ->
            {State, ["?SYNTAX ERROR\r\n"]};
        {'return'} ->
            {State, ["?SYNTAX ERROR\r\n"]}
    end.

ensure_data_loaded(State = #state{data_items = []}) ->
    State#state{data_items = erlbasic_runtime:collect_program_data(State#state.prog), data_index = 1};
ensure_data_loaded(State) ->
    State.

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
                    PendingState = erlbasic_runtime:update_pending_input_rest(NextState, Rest),
                    {continue, PendingState, OutputAcc ++ Output}
            end;
        stop ->
            {stop, State, OutputAcc}
    end.
