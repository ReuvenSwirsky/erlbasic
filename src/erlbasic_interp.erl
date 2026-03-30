-module(erlbasic_interp).

-include_lib("kernel/include/file.hrl").

-export([new_state/0, handle_input/2, next_prompt/1, awaiting_input/1]).


-record(state, {
    vars = #{},
    prog = [],
    funcs = #{},
    pending_input = undefined,
    immediate_for_buffer = undefined,
    data_items = [],
    data_index = 1,
    print_col = 0,
    continue_ctx = undefined
}).

new_state() ->
    #state{}.

%% @doc True when the interpreter is paused waiting for an INPUT statement response.
awaiting_input(#state{pending_input = undefined}) -> false;
awaiting_input(_State) -> true.

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
    case Upper of
        "LIST" ->
            {State, format_program(State#state.prog)};
        "DIR" ->
            handle_dir_command(State);
        "NEW" ->
            {State#state{prog = [], data_items = [], data_index = 1, continue_ctx = undefined}, ["Program cleared\r\n"]};
        "RUN" ->
            run_program(State);
        "CONT" ->
            continue_program(State);
        _ ->
            case parse_file_command(Command) of
                {save, FileName} ->
                    handle_save_command(State, FileName);
                {load, FileName} ->
                    handle_load_command(State, FileName);
                nomatch ->
                    case parse_renum_command(Command) of
                        {ok, StartLine, Increment} ->
                            Renumbered = renumber_program(State#state.prog, StartLine, Increment),
                            {State#state{prog = Renumbered, continue_ctx = undefined}, ["OK\r\n"]};
                        error ->
                            normalize_immediate_result(execute_statement(Command, State), State)
                    end
            end
    end.

parse_file_command(Command) ->
    Trimmed = string:trim(Command),
    case re:run(Trimmed, "(?i)^SAVE\\s+(.+)$", [{capture, [1], list}]) of
        {match, [Name]} ->
            {save, string:trim(Name)};
        nomatch ->
            case re:run(Trimmed, "(?i)^LOAD\\s+(.+)$", [{capture, [1], list}]) of
                {match, [Name]} ->
                    {load, string:trim(Name)};
                nomatch ->
                    nomatch
            end
    end.

handle_dir_command(State) ->
    case erlbasic_storage:list_programs() of
        {ok, UserFiles} ->
            case list_example_files() of
                {ok, ExampleFiles} ->
                    Output = format_dir_listing(UserFiles, ExampleFiles),
                    {State, Output};
                {error, _} ->
                    {State, ["?FILE ERROR\r\n"]}
            end;
        {error, _} ->
            {State, ["?FILE ERROR\r\n"]}
    end.

format_dir_listing([], []) ->
    ["No files\r\n"];
format_dir_listing(UserFiles, ExampleFiles) ->
    UserSection =
        case UserFiles of
            [] -> [];
            _  -> ["My programs:\r\n"] ++
                  ["  " ++ N ++ "\r\n" || N <- lists:sort(UserFiles)]
        end,
    ExampleSection =
        case ExampleFiles of
            [] -> [];
            _  -> ["\r\nExamples:\r\n"] ++
                  ["  " ++ N ++ "\r\n" || N <- lists:sort(ExampleFiles)]
        end,
    UserSection ++ ExampleSection.

handle_save_command(State, RawName) ->
    case normalize_program_filename(RawName) of
        {ok, FileName} ->
            Content = serialize_program(State#state.prog),
            case erlbasic_storage:write_program(FileName, Content) of
                ok           -> {State, ["Saved " ++ FileName ++ "\r\n"]};
                {error, _}   -> {State, ["?FILE ERROR\r\n"]}
            end;
        error ->
            {State, ["?FILE ERROR\r\n"]}
    end.

handle_load_command(State, RawName) ->
    case normalize_program_filename(RawName) of
        {ok, FileName} ->
            case load_program_file(FileName) of
                {ok, Program} ->
                    {State#state{prog = Program, data_items = [], data_index = 1, continue_ctx = undefined}, ["OK\r\n"]};
                {syntax_error, LineNumber} when is_integer(LineNumber) ->
                    {State, [erlbasic_eval:format_runtime_error(syntax_error, LineNumber)]};
                syntax_error ->
                    {State, ["?SYNTAX ERROR\r\n"]};
                {error, program_not_found} ->
                    {State, [erlbasic_eval:format_runtime_error(program_not_found)]};
                {error, _} ->
                    {State, ["?FILE ERROR\r\n"]}
            end;
        error ->
            {State, ["?FILE ERROR\r\n"]}
    end.

load_program_file(FileName) ->
    %% 1. Try the shared examples directory first.
    ExamplePath = filename:join(examples_program_dir(), FileName),
    case read_program_file(ExamplePath) of
        {ok, _} = Ok         -> Ok;
        {syntax_error, _} = E -> E;
        syntax_error          -> syntax_error;
        {error, enoent} ->
            %% 2. Fall back to the user's own storage area.
            case erlbasic_storage:read_program(FileName) of
                {ok, Bin} ->
                    parse_bin_as_program(Bin);
                {error, enoent} ->
                    {error, program_not_found};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

read_program_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> parse_bin_as_program(Bin);
        {error, Reason} -> {error, Reason}
    end.

parse_bin_as_program(Bin) ->
    case parse_program_text(binary_to_list(Bin)) of
        {ok, Program} ->
            {ok, Program};
        {error, {syntax_error, LineNumber}} when is_integer(LineNumber) ->
            {syntax_error, LineNumber};
        error ->
            syntax_error
    end.

serialize_program(Program) ->
    Lines = [integer_to_list(LineNumber) ++ " " ++ Code || {LineNumber, Code} <- Program],
    string:join(Lines, "\n") ++ "\n".

parse_program_text(Text) ->
    Lines = [string:trim(Line) || Line <- string:split(Text, "\n", all)],
    parse_program_lines(Lines, []).

parse_program_lines([], Acc) ->
    {ok, lists:keysort(1, Acc)};
parse_program_lines(["" | Rest], Acc) ->
    parse_program_lines(Rest, Acc);
parse_program_lines([Line | Rest], Acc) ->
    case parse_program_line(Line) of
        {program_line, Num, Code} ->
            case erlbasic_parser:validate_program_line(Code) of
                ok ->
                    parse_program_lines(Rest, [{Num, Code} | lists:keydelete(Num, 1, Acc)]);
                error ->
                    {error, {syntax_error, Num}}
            end;
        immediate ->
            error
    end.

%% ---- File-system helpers (examples dir and utilities) ----
%% Per-user file I/O is handled by erlbasic_storage.  Only shared
%% example files are accessed directly here.

list_regular_files(Dir) ->
    case file:list_dir(Dir) of
        {ok, Names} ->
            {ok, lists:sort([N || N <- Names, is_regular_file(Dir, N)])};
        {error, Reason} ->
            {error, Reason}
    end.

is_regular_file(Dir, Name) ->
    Path = filename:join(Dir, Name),
    case file:read_file_info(Path) of
        {ok, #file_info{type = regular}} -> true;
        _ -> false
    end.
normalize_program_filename(RawName) ->
    Name0 = string:trim(RawName),
    Name = keep_safe_chars(Name0),
    case Name of
        "" ->
            error;
        _ ->
            case filename:extension(Name) of
                "" -> {ok, Name ++ ".bas"};
                _ -> {ok, Name}
            end
    end.

keep_safe_chars(Text) ->
    Safe = [Ch || Ch <- Text,
        (Ch >= $A andalso Ch =< $Z) orelse
        (Ch >= $a andalso Ch =< $z) orelse
        (Ch >= $0 andalso Ch =< $9) orelse
        Ch =:= $_ orelse Ch =:= $- orelse Ch =:= $.],
    case Safe of
        [] -> "";
        _ -> Safe
    end.

list_example_files() ->
    Dir = examples_program_dir(),
    case file:list_dir(Dir) of
        {ok, _} ->
            list_regular_files(Dir);
        {error, enoent} ->
            {ok, []};
        {error, Reason} ->
            {error, Reason}
    end.

examples_program_dir() ->
    filename:join(repo_root_dir(), "examples").

repo_root_dir() ->
    BeamPath = code:which(?MODULE),
    case BeamPath of
        non_existing ->
            filename:absname(".");
        _ ->
            BeamDir = filename:dirname(BeamPath),
            find_repo_root(BeamDir)
    end.

find_repo_root(Dir) ->
    ConfigPath = filename:join(Dir, "rebar.config"),
    case filelib:is_regular(ConfigPath) of
        true ->
            Dir;
        false ->
            Parent = filename:dirname(Dir),
            case Parent =:= Dir of
                true -> filename:absname(".");
                false -> find_repo_root(Parent)
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
    [integer_to_list(LineNumber) ++ " " ++ normalize_keywords_for_list(Code) ++ "\r\n" || {LineNumber, Code} <- Program].

normalize_keywords_for_list(Code) ->
    lists:flatten(normalize_keywords_for_list(Code, [], false, [])).

normalize_keywords_for_list([], CurrentRev, _InString, AccRev) ->
    lists:reverse([flush_word(CurrentRev) | AccRev]);
normalize_keywords_for_list([$" | Rest], CurrentRev, false, AccRev) ->
    NextAccRev = [$" | [flush_word(CurrentRev) | AccRev]],
    normalize_keywords_for_list(Rest, [], true, NextAccRev);
normalize_keywords_for_list([$" | Rest], CurrentRev, true, AccRev) ->
    NextAccRev = [$" | [lists:reverse(CurrentRev) | AccRev]],
    normalize_keywords_for_list(Rest, [], false, NextAccRev);
normalize_keywords_for_list([Ch | Rest], CurrentRev, true, AccRev) ->
    normalize_keywords_for_list(Rest, [Ch | CurrentRev], true, AccRev);
normalize_keywords_for_list([Ch | Rest], CurrentRev, false, AccRev) when
    (Ch >= $A andalso Ch =< $Z) orelse
    (Ch >= $a andalso Ch =< $z) orelse
    (Ch >= $0 andalso Ch =< $9) orelse
    Ch =:= $_ orelse Ch =:= $$ orelse Ch =:= $% ->
    normalize_keywords_for_list(Rest, [Ch | CurrentRev], false, AccRev);
normalize_keywords_for_list([Ch | Rest], CurrentRev, false, AccRev) ->
    NextAccRev = [Ch | [flush_word(CurrentRev) | AccRev]],
    normalize_keywords_for_list(Rest, [], false, NextAccRev).

flush_word([]) ->
    [];
flush_word(CurrentRev) ->
    Word = lists:reverse(CurrentRev),
    case is_basic_keyword(Word) of
        true -> string:to_upper(Word);
        false -> Word
    end.

is_basic_keyword(Word) ->
    Upper = string:to_upper(Word),
    lists:member(Upper, [
    "PRINT", "USING", "LET", "INPUT", "LINE", "DEF", "IF", "THEN", "ELSE", "FOR", "TO", "STEP", "NEXT", "CLS", "COLOR", "LOCATE",
        "GOTO", "GOSUB", "RETURN", "END", "DATA", "READ", "DIM", "MOD", "REM"
    ]).

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

update_pending_input_rest(State = #state{pending_input = {Targets, {immediate, _OldRemaining}}}, RemainingStatements) when is_list(Targets) ->
    State#state{pending_input = {Targets, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {Targets, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) when is_list(Targets) ->
    State#state{pending_input = {Targets, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State = #state{pending_input = {input_line, Target, {immediate, _OldRemaining}}}, RemainingStatements) ->
    State#state{pending_input = {input_line, Target, {immediate, RemainingStatements}}};
update_pending_input_rest(State = #state{pending_input = {input_line, Target, {program, Pc, _OldRemaining, LoopStack, CallStack}}}, RemainingStatements) ->
    State#state{pending_input = {input_line, Target, {program, Pc, RemainingStatements, LoopStack, CallStack}}};
update_pending_input_rest(State, _RemainingStatements) ->
    State.

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

target_to_text({var_target, Var}) ->
    Var;
target_to_text({array_target, Var, IndexExprs}) ->
    Var ++ "(" ++ string:join(IndexExprs, ",") ++ ")".

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
                    {State#state{vars = Vars1, print_col = FinalCol}, [FinalText]};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
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
            case apply_dim_decls(Decls, State#state.vars, State#state.funcs) of
                {ok, Vars1} ->
                    {State#state{vars = Vars1}, ["OK\r\n"]};
                {error, Reason} ->
                    {State, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {data, _Items} ->
            {State, ["OK\r\n"]};
        {read_data, Targets} ->
            DataState = ensure_data_loaded(State),
            case apply_read_vars(Targets, DataState) of
                {ok, NextState} ->
                    {NextState, ["OK\r\n"]};
                {error, Reason} ->
                    {DataState, [erlbasic_eval:format_runtime_error(Reason)]}
            end;
        {input, Targets} ->
            {State#state{pending_input = {Targets, {immediate, []}}}, ["? "]};
        {input_line, Target} ->
            {State#state{pending_input = {input_line, Target, {immediate, []}}}, ["? "]};
        {locate, RowExpr, ColExpr} ->
            case eval_locate(RowExpr, ColExpr, State#state.vars, State#state.funcs) of
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
            {State, cls_output()};
        {color, FgExpr, BgExpr} ->
            case eval_color(FgExpr, BgExpr, State#state.vars, State#state.funcs) of
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

ensure_data_loaded(State = #state{data_items = []}) ->
    State#state{data_items = collect_program_data(State#state.prog), data_index = 1};
ensure_data_loaded(State) ->
    State.

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
