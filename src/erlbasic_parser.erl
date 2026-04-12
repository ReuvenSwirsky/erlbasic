-module(erlbasic_parser).

-export([
    parse_statement/1,
    set_parser_mode/1,
    clear_parser_mode/0,
    parse_statement_legacy/1,
    parse_statement_yecc/1,
    parse_let_stmt_yecc/1,
    parse_rem_stmt_yecc/1,
    parse_implicit_let_stmt_yecc/1,
    parse_line_input_stmt_yecc/1,
    parse_input_stmt_yecc/1,
    parse_get_stmt_yecc/1,
    parse_getkey_stmt_yecc/1,
    parse_getchar_stmt_yecc/1,
    parse_goto_stmt_yecc/1,
    parse_gosub_stmt_yecc/1,
    parse_if_stmt_yecc/1,
    parse_for_stmt_yecc/1,
    parse_next_stmt_yecc/1,
    parse_on_stmt_yecc/1,
    parse_resume_stmt_yecc/1,
    parse_dim_stmt_yecc/1,
    parse_def_stmt_yecc/1,
    parse_data_stmt_yecc/1,
    parse_read_stmt_yecc/1,
    parse_restore_stmt_yecc/1,
    parse_return_stmt_yecc/1,
    parse_end_stmt_yecc/1,
    parse_stop_stmt_yecc/1,
    parse_cls_stmt_yecc/1,
    parse_hgr_stmt_yecc/1,
    parse_hgr2_stmt_yecc/1,
    parse_text_stmt_yecc/1,
    parse_tron_stmt_yecc/1,
    parse_troff_stmt_yecc/1,
    parse_flush_stmt_yecc/1,
    parse_buffer_stmt_yecc/1,
    parse_sleep_stmt_yecc/1,
    parse_sound_stmt_yecc/1,
    parse_play_stmt_yecc/1,
    parse_chain_stmt_yecc/1,
    parse_open_stmt_yecc/1,
    parse_close_stmt_yecc/1,
    parse_field_stmt_yecc/1,
    parse_put_stmt_yecc/1,
    should_split_top_level_sequence/1,
    split_statements/1,
    validate_program_line/1
]).

-define(VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*[\\$%&#]?)").
-define(VAR_BASE_PATTERN, "([A-Za-z][A-Za-z0-9_]*[\\$%&#]?)").
-define(LOOP_VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*[%&#]?)").

parse_statement(Command) ->
    case parser_mode() of
        yecc -> parse_statement_yecc(Command);
        _ -> parse_statement_legacy(Command)
    end.

set_parser_mode(Mode) when Mode =:= legacy; Mode =:= yecc ->
    put(erlbasic_parser_mode, Mode),
    ok.

clear_parser_mode() ->
    erase(erlbasic_parser_mode),
    ok.

parse_statement_legacy(Command) ->
    parse_statement_yecc(Command).

parse_let_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^(.+?)\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [TargetText, Expr]} ->
            case parse_assignment_target(TargetText) of
                {ok, Target} -> {'let', Target, Expr};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            unknown
    end.

parse_rem_stmt_yecc(_Rest) ->
    {remark}.

parse_implicit_let_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^(.+?)\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [TargetText, Expr]} ->
            case parse_assignment_target(TargetText) of
                {ok, Target} -> {'let', Target, Expr};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            unknown
    end.

parse_line_input_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {file_line_input, string:trim(ChannelExpr), Target};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            unknown
    end.

parse_input_stmt_yecc(Rest) ->
    TrimmedRest = string:trim(Rest),
    case re:run(TrimmedRest, "^#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, TargetsText]} ->
            case parse_input_target_list(split_commas_top_level(TargetsText), []) of
                {ok, Targets} -> {file_input, string:trim(ChannelExpr), Targets};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            case re:run(TrimmedRest, "(?i)^LINE\\s+(.+)$", [{capture, [1], list}]) of
                {match, [TargetText]} ->
                    case parse_assignment_target(string:trim(TargetText)) of
                        {ok, Target} -> {input_line, Target};
                        {error, Reason} -> {parse_error, Reason};
                        error -> unknown
                    end;
                nomatch ->
                    case TrimmedRest of
                        "" -> unknown;
                        TargetsText ->
                            case parse_input_target_list(split_commas_top_level(TargetsText), []) of
                                {ok, Targets} -> {input, Targets};
                                {error, Reason} -> {parse_error, Reason};
                                error -> unknown
                            end
                    end
            end
    end.

parse_get_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, RecordExpr]} ->
            {file_get_record, string:trim(ChannelExpr), string:trim(RecordExpr)};
        nomatch ->
            case parse_assignment_target(string:trim(Rest)) of
                {ok, Target} -> {get, Target};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end
    end.

parse_getkey_stmt_yecc(Rest) ->
    case parse_assignment_target(string:trim(Rest)) of
        {ok, Target} -> {getkey, Target};
        {error, Reason} -> {parse_error, Reason};
        error -> unknown
    end.

parse_getchar_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^(.+),(.+),(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [RowExpr, ColExpr, TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {getchar, string:trim(RowExpr), string:trim(ColExpr), Target};
                _ -> unknown
            end;
        nomatch ->
            unknown
    end.

parse_goto_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" -> unknown;
        LineExpr -> {goto, LineExpr}
    end.

parse_gosub_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" -> unknown;
        LineExpr -> {gosub, LineExpr}
    end.

parse_if_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^(.+?)\\s+THEN\\s+(.+?)(?:\\s+ELSE\\s+(.+))?$", [{capture, all_but_first, list}]) of
        {match, [CondExpr, ThenStmt]} ->
            {if_then_else, CondExpr, normalize_if_branch_statement(ThenStmt), undefined};
        {match, [CondExpr, ThenStmt, ElseStmt]} ->
            {if_then_else, CondExpr,
             normalize_if_branch_statement(ThenStmt),
             normalize_if_branch_statement(ElseStmt)};
        nomatch ->
            unknown
    end.

parse_for_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^" ++ ?LOOP_VAR_PATTERN ++ "\\s*=\\s*(.+)\\s+TO\\s+(.+?)(?:\\s+STEP\\s+(.+))?$", [{capture, all_but_first, list}]) of
        {match, [Var, StartExpr, EndExpr]} ->
            case is_reserved_variable_name(Var) of
                true -> {parse_error, reserved_word};
                false -> {for_loop, string:to_upper(Var), StartExpr, EndExpr, undefined}
            end;
        {match, [Var, StartExpr, EndExpr, StepExpr]} ->
            case is_reserved_variable_name(Var) of
                true -> {parse_error, reserved_word};
                false -> {for_loop, string:to_upper(Var), StartExpr, EndExpr, StepExpr}
            end;
        nomatch ->
            unknown
    end.

parse_next_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" ->
            {next_loop, undefined};
        VarText ->
            case re:run(VarText, "^" ++ ?VAR_PATTERN ++ "$", [{capture, all_but_first, list}]) of
                {match, [Var]} ->
                    case is_reserved_variable_name(Var) of
                        true -> {parse_error, reserved_word};
                        false -> {next_loop, string:to_upper(Var)}
                    end;
                nomatch ->
                    unknown
            end
    end.

parse_on_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "(?i)^ERROR\\s+GOTO\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetExpr]} ->
            {on_error_goto, string:trim(TargetExpr)};
        nomatch ->
            case re:run(string:trim(Rest), "(?i)^SPRITE\\s+GOSUB\\s+(.+)$", [{capture, [1], list}]) of
                {match, [TargetExpr]} ->
                    {on_sprite_gosub, string:trim(TargetExpr)};
                nomatch ->
                    case re:run(string:trim(Rest), "(?i)^PLAY\\s*\\(\\s*(.+?)\\s*\\)\\s+GOSUB\\s+(.+)$", [{capture, [1, 2], list}]) of
                        {match, [NExpr, TargetExpr]} ->
                            {on_play_gosub, string:trim(NExpr), string:trim(TargetExpr)};
                        nomatch ->
                            case re:run(string:trim(Rest), "(?i)^TIMER\\s*\\(\\s*(.+?)\\s*\\)\\s+GOSUB\\s+(.+)$", [{capture, [1, 2], list}]) of
                                {match, [NExpr, TargetExpr]} ->
                                    {on_timer_gosub, string:trim(NExpr), string:trim(TargetExpr)};
                                nomatch ->
                                    case re:run(string:trim(Rest), "(?i)^(.+?)\\s+GOSUB\\s+(.+)$", [{capture, [1, 2], list}]) of
                                        {match, [Expr, Targets]} ->
                                            {on_gosub, Expr, parse_comma_separated_list(Targets)};
                                        nomatch ->
                                            case re:run(string:trim(Rest), "(?i)^(.+?)\\s+GOTO\\s+(.+)$", [{capture, [1, 2], list}]) of
                                                {match, [Expr, Targets]} ->
                                                    {on_goto, Expr, parse_comma_separated_list(Targets)};
                                                nomatch ->
                                                    unknown
                                            end
                                    end
                            end
                    end
            end
    end.

parse_resume_stmt_yecc(Rest) ->
    case string:to_upper(string:trim(Rest)) of
        "NEXT" ->
            {resume_next};
        "" ->
            {resume};
        LineExpr ->
            {resume_line, LineExpr}
    end.

parse_dim_stmt_yecc(Rest) ->
    case parse_dim_decls(string:trim(Rest)) of
        {ok, Decls} -> {dim, Decls};
        {error, Reason} -> {parse_error, Reason};
        error -> unknown
    end.

parse_def_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "(?i)^FN([A-Za-z][A-Za-z0-9_]*)(?:\\s*\\(\\s*" ++ ?VAR_PATTERN ++ "\\s*\\))?\\s*=\\s*(.+)$", [{capture, all_but_first, list}]) of
        {match, [FnSuffix, Expr]} ->
            {def_fn, "FN" ++ string:to_upper(FnSuffix), undefined, Expr};
        {match, [FnSuffix, ArgVar, Expr]} ->
            case is_reserved_variable_name(ArgVar) of
                true -> {parse_error, reserved_word};
                false -> {def_fn, "FN" ++ string:to_upper(FnSuffix), string:to_upper(ArgVar), Expr}
            end;
        nomatch ->
            unknown
    end.

parse_data_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" ->
            {data, []};
        DataText ->
            {data, normalize_data_items(split_commas_top_level(DataText))}
    end.

parse_read_stmt_yecc(Rest) ->
    case parse_read_vars(string:trim(Rest)) of
        {ok, Vars} -> {read_data, Vars};
        {error, reserved_word} -> {parse_error, reserved_word};
        error -> unknown
    end.

parse_restore_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" -> {restore, all};
        LineExpr -> {restore, LineExpr}
    end.

parse_return_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {'return'}).

parse_end_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {'end'}).

parse_stop_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {stop_stmt}).

parse_cls_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {cls}).

parse_hgr_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {hgr}).

parse_hgr2_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {hgr2}).

parse_text_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {text}).

parse_tron_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {tron}).

parse_troff_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {troff}).

parse_flush_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" -> {flush_stmt};
        _ -> unknown
    end.

parse_buffer_stmt_yecc(Rest) ->
    case string:to_upper(string:trim(Rest)) of
        "ON" -> {buffer_mode, on};
        "OFF" -> {buffer_mode, off};
        _ -> unknown
    end.

parse_sleep_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" -> {sleep_keypress};
        Expr -> {sleep, Expr}
    end.

parse_sound_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^(.+?)\\s*,\\s*(.+?)\\s*,\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2, 3, 4], list}]) of
        {match, [VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr]} ->
            {sound, VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr};
        nomatch ->
            unknown
    end.

parse_play_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" -> unknown;
        Expr -> {play_stmt, Expr}
    end.

parse_chain_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" -> unknown;
        FileExpr -> {chain, FileExpr}
    end.

parse_open_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^(.+?)\\s+FOR\\s+(INPUT|OUTPUT|APPEND|RANDOM)\\s+AS\\s*#\\s*(.+?)(?:\\s+LEN\\s*=\\s*(.+))?$", [{capture, all_but_first, list}]) of
        {match, [PathExpr, Mode, ChannelExpr]} ->
            {file_open, string:trim(PathExpr), string:to_upper(Mode), string:trim(ChannelExpr), undefined};
        {match, [PathExpr, Mode, ChannelExpr, RecLenExpr]} ->
            {file_open, string:trim(PathExpr), string:to_upper(Mode), string:trim(ChannelExpr), string:trim(RecLenExpr)};
        nomatch ->
            unknown
    end.

parse_close_stmt_yecc(Rest) ->
    case string:trim(Rest) of
        "" ->
            {file_close, all};
        ChannelsText ->
            case parse_file_channels(ChannelsText) of
                {ok, Channels} -> {file_close, Channels};
                error -> unknown
            end
    end.

parse_field_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, SpecsText]} ->
            case parse_field_specs(SpecsText) of
                {ok, Specs} -> {file_field, string:trim(ChannelExpr), Specs};
                error -> unknown
            end;
        nomatch ->
            unknown
    end.

parse_put_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, RecordExpr]} ->
            {file_put_record, string:trim(ChannelExpr), string:trim(RecordExpr)};
        nomatch ->
            unknown
    end.

parse_noarg_keyword_stmt(Rest, Result) ->
    case string:trim(Rest) of
        "" -> Result;
        _ -> unknown
    end.

parser_mode() ->
    case get(erlbasic_parser_mode) of
        legacy ->
            legacy;
        yecc ->
            yecc;
        _ ->
            case application:get_env(erlbasic, parser_mode) of
                {ok, legacy} -> legacy;
                {ok, yecc} -> yecc;
                _ -> yecc
            end
    end.

%% Fold statement text to uppercase, preserving the content of string literals.
%% This normalises keywords typed in any case (e.g. "if", "then", "else",
%% "to", "step", "for", "as", "input", "output", "append", "random") so
%% that the yecc bridge regexes — which all expect UPPERCASE tokens — match
%% regardless of how the user typed the statement.
normalize_statement_case(Text) ->
    normalize_statement_case(Text, false, []).

normalize_statement_case([], _InStr, Acc) ->
    lists:reverse(Acc);
normalize_statement_case([$" | Rest], InStr, Acc) ->
    normalize_statement_case(Rest, not InStr, [$" | Acc]);
normalize_statement_case([C | Rest], false, Acc) when C >= $a, C =< $z ->
    normalize_statement_case(Rest, false, [C - 32 | Acc]);
normalize_statement_case([C | Rest], InStr, Acc) ->
    normalize_statement_case(Rest, InStr, [C | Acc]).

%% Phase-1 yecc bridge: run statement text through yecc, then delegate
%% to legacy parser behavior via grammar actions for exact compatibility.
parse_statement_yecc(Command) ->
    Trimmed = string:trim(normalize_statement_case(Command)),
    case erlbasic_parser_yecc_lexer:tokenize_statement(Trimmed) of
        {ok, Tokens} ->
            case erlbasic_parser_yecc:parse(Tokens) of
                {ok, Parsed} -> Parsed;
                _ -> unknown
            end;
        error ->
            unknown
    end.

validate_program_line(Command) ->
    Trimmed = string:trim(Command),
    case has_balanced_quotes(Trimmed) of
        false ->
            error;
        true ->
            validate_statement_sequence(Trimmed)
    end.

parse_input_target_list([], []) ->
    error;
parse_input_target_list([], Acc) ->
    {ok, lists:reverse(Acc)};
parse_input_target_list([Part | Rest], Acc) ->
    case parse_assignment_target(string:trim(Part)) of
        {ok, Target} -> parse_input_target_list(Rest, [Target | Acc]);
        {error, Reason} -> {error, Reason};
        error -> error
    end.

parse_dim_decls(Text) ->
    parse_dim_decls(split_commas_top_level(Text), []).

parse_dim_decls([], Acc) ->
    case Acc of
        [] -> error;
        _ -> {ok, lists:reverse(Acc)}
    end;
parse_dim_decls([Part | Rest], Acc) ->
    case parse_dim_decl(Part) of
        {ok, Decl} -> parse_dim_decls(Rest, [Decl | Acc]);
        {error, Reason} -> {error, Reason};
        error -> error
    end.

parse_dim_decl(Text) ->
    Trimmed = string:trim(Text),
    case re:run(Trimmed, "^" ++ ?VAR_BASE_PATTERN ++ "\\s*\\((.*)\\)$", [{capture, [1, 2], list}]) of
        {match, [Var, DimText]} ->
            case is_reserved_variable_name(Var) of
                true ->
                    {error, reserved_word};
                false ->
                    case parse_index_exprs(DimText) of
                        {ok, Dims} when length(Dims) =:= 1; length(Dims) =:= 2; length(Dims) =:= 3 ->
                            {ok, {string:to_upper(Var), Dims}};
                        _ ->
                            error
                    end
            end;
        nomatch ->
            error
    end.

normalize_if_branch_statement(Stmt) ->
    Trimmed = string:trim(Stmt),
    case re:run(Trimmed, "^(\\d+)$", [{capture, [1], list}]) of
        {match, [LineNumber]} ->
            "GOTO " ++ LineNumber;
        nomatch ->
            Trimmed
    end.

parse_comma_separated_list(Str) ->
    Parts = string:split(string:trim(Str), ",", all),
    [string:trim(P) || P <- Parts].

parse_read_vars(Text) ->
    Parts = split_commas_top_level(Text),
    parse_read_vars(Parts, []).

parse_read_vars([], Acc) ->
    case Acc of
        [] -> error;
        _ -> {ok, lists:reverse(Acc)}
    end;
parse_read_vars([Part | Rest], Acc) ->
    case parse_assignment_target(Part) of
        {ok, Target} ->
            parse_read_vars(Rest, [Target | Acc]);
        {error, Reason} ->
            {error, Reason};
        error ->
            error
    end.

split_commas_top_level(Text) ->
    split_commas_top_level(Text, [], [], false, 0).

split_commas_top_level([], CurrentRev, PartsRev, _InString, _Depth) ->
    lists:reverse([lists:reverse(CurrentRev) | PartsRev]);
split_commas_top_level([$" | Rest], CurrentRev, PartsRev, InString, Depth) ->
    split_commas_top_level(Rest, [$" | CurrentRev], PartsRev, not InString, Depth);
split_commas_top_level([$( | Rest], CurrentRev, PartsRev, false, Depth) ->
    split_commas_top_level(Rest, [$( | CurrentRev], PartsRev, false, Depth + 1);
split_commas_top_level([$) | Rest], CurrentRev, PartsRev, false, Depth) when Depth > 0 ->
    split_commas_top_level(Rest, [$) | CurrentRev], PartsRev, false, Depth - 1);
split_commas_top_level([$, | Rest], CurrentRev, PartsRev, false, 0) ->
    split_commas_top_level(Rest, [], [lists:reverse(CurrentRev) | PartsRev], false, 0);
split_commas_top_level([Ch | Rest], CurrentRev, PartsRev, InString, Depth) ->
    split_commas_top_level(Rest, [Ch | CurrentRev], PartsRev, InString, Depth).

parse_assignment_target(Text) ->
    Trimmed = string:trim(Text),
    case re:run(Trimmed, "^" ++ ?VAR_BASE_PATTERN ++ "(?:\\((.*)\\))?$", [{capture, all_but_first, list}]) of
        {match, [Var]} ->
            case is_reserved_variable_name(Var) of
                true ->
                    {error, reserved_word};
                false ->
                    {ok, {var_target, string:to_upper(Var)}}
            end;
        {match, [Var, IndexText]} ->
            case is_reserved_variable_name(Var) of
                true ->
                    {error, reserved_word};
                false ->
                    case parse_index_exprs(IndexText) of
                        {ok, IndexExprs} when length(IndexExprs) =:= 1; length(IndexExprs) =:= 2; length(IndexExprs) =:= 3 ->
                            {ok, {array_target, string:to_upper(Var), IndexExprs}};
                        _ ->
                            error
                    end
            end;
        nomatch ->
            error
    end.

parse_index_exprs(Text) ->
    Parts = split_commas_top_level(Text),
    parse_non_empty_parts(Parts, []).

parse_non_empty_parts([], Acc) ->
    case Acc of
        [] -> error;
        _ -> {ok, lists:reverse(Acc)}
    end;
parse_non_empty_parts([Part | Rest], Acc) ->
    Trimmed = string:trim(Part),
    case Trimmed of
        "" -> error;
        _ -> parse_non_empty_parts(Rest, [Trimmed | Acc])
    end.

normalize_data_items(Parts) ->
    [normalize_data_item(Part) || Part <- Parts].

normalize_data_item(Part) ->
    Trimmed = string:trim(Part),
    case unquote_data_item(Trimmed) of
        {ok, Value} -> Value;
        error -> Trimmed
    end.

unquote_data_item([$" | Rest]) ->
    case lists:reverse(Rest) of
        [$" | MiddleRev] ->
            {ok, lists:reverse(MiddleRev)};
        _ ->
            error
    end;
unquote_data_item(_Other) ->
    error.

parse_file_channels(Text) ->
    Parts = split_commas_top_level(Text),
    parse_file_channels(Parts, []).

parse_file_channels([], Acc) ->
    case Acc of
        [] -> error;
        _ -> {ok, lists:reverse(Acc)}
    end;
parse_file_channels([Part | Rest], Acc) ->
    Trimmed = string:trim(Part),
    case string:prefix(Trimmed, "#") of
        nomatch -> error;
        ChannelExpr ->
            Expr = string:trim(ChannelExpr),
            case Expr of
                "" -> error;
                _ -> parse_file_channels(Rest, [Expr | Acc])
            end
    end.

parse_field_specs(Text) ->
    Parts = split_commas_top_level(Text),
    parse_field_specs(Parts, []).

parse_field_specs([], Acc) ->
    case Acc of
        [] -> error;
        _ -> {ok, lists:reverse(Acc)}
    end;
parse_field_specs([Part | Rest], Acc) ->
    case re:run(string:trim(Part), "(?i)^(.+?)\\s+AS\\s+" ++ ?VAR_PATTERN ++ "$", [{capture, all_but_first, list}]) of
        {match, [LenExpr, Var]} ->
            case is_reserved_variable_name(Var) of
                true ->
                    error;
                false ->
                    case erlbasic_eval:target_is_string({var_target, string:to_upper(Var)}) of
                        true -> parse_field_specs(Rest, [{string:trim(LenExpr), string:to_upper(Var)} | Acc]);
                        false -> error
                    end
            end;
        nomatch ->
            error
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

split_statements(Text) ->
    split_statements(Text, [], [], false).

split_statements([], CurrentRev, PartsRev, _InString) ->
    FinalPart = string:trim(lists:reverse(CurrentRev)),
    lists:reverse(add_part(FinalPart, PartsRev));
split_statements([$" | Rest], CurrentRev, PartsRev, InString) ->
    split_statements(Rest, [$" | CurrentRev], PartsRev, not InString);
split_statements([$: | Rest], CurrentRev, PartsRev, false) ->
    Part = string:trim(lists:reverse(CurrentRev)),
    case re:run(Part, "(?i)^REM(\\s|$)", [{capture, none}]) of
        match   -> lists:reverse(add_part(Part, PartsRev));
        nomatch -> split_statements(Rest, [], add_part(Part, PartsRev), false)
    end;
split_statements([Ch | Rest], CurrentRev, PartsRev, InString) ->
    split_statements(Rest, [Ch | CurrentRev], PartsRev, InString).

add_part("", PartsRev) ->
    PartsRev;
add_part(Part, PartsRev) ->
    [Part | PartsRev].

validate_statement_sequence("") ->
    ok;
validate_statement_sequence(Command) ->
    Statements =
        case should_split_top_level_sequence(Command) of
            true -> split_statements(Command);
            false -> [string:trim(Command)]
        end,
    validate_statements(Statements).

validate_statements([]) ->
    ok;
validate_statements([Stmt | Rest]) ->
    case validate_statement(Stmt) of
        ok -> validate_statements(Rest);
        {error, Reason} -> {error, Reason};
        error -> error
    end.

validate_statement(Stmt) ->
    case parse_statement(Stmt) of
        {print, Items, _EndWithNewline} ->
            validate_print_items(Items);
        {print_using, FormatExpr, Items, _EndWithNewline} ->
            case validate_expr_syntax(FormatExpr) of
                ok -> validate_print_items(Items);
                error -> error
            end;
        {input, Targets} ->
            validate_input_targets(Targets);
        {input_line, Target} ->
            validate_target_syntax(Target);
        {get, Target} ->
            validate_target_syntax(Target);
        {getkey, Target} ->
            validate_target_syntax(Target);
        {'let', Target, Expr} ->
            case validate_target_syntax(Target) of
                ok -> validate_expr_syntax(Expr);
                error -> error
            end;
        {dim, Decls} ->
            validate_dim_decls(Decls);
        {def_fn, _FnName, _ArgVar, Expr} ->
            validate_expr_syntax(Expr);
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case validate_condition_syntax(CondExpr) of
                ok ->
                    case validate_statement_sequence(ThenStmt) of
                        ok -> validate_optional_statement_sequence(ElseStmt);
                        error -> error
                    end;
                error ->
                    error
            end;
        {goto, LineExpr} ->
            validate_expr_syntax(LineExpr);
        {gosub, LineExpr} ->
            validate_expr_syntax(LineExpr);
        {on_goto, Expr, Targets} ->
            case validate_expr_syntax(Expr) of
                ok -> validate_line_targets(Targets);
                error -> error
            end;
        {on_gosub, Expr, Targets} ->
            case validate_expr_syntax(Expr) of
                ok -> validate_line_targets(Targets);
                error -> error
            end;
        {on_error_goto, TargetExpr} ->
            validate_expr_syntax(TargetExpr);
        {resume} ->
            ok;
        {resume_next} ->
            ok;
        {resume_line, LineExpr} ->
            validate_expr_syntax(LineExpr);
        {for_loop, _Var, StartExpr, EndExpr, undefined} ->
            validate_expr_pair(StartExpr, EndExpr);
        {for_loop, _Var, StartExpr, EndExpr, StepExpr} ->
            case validate_expr_pair(StartExpr, EndExpr) of
                ok -> validate_expr_syntax(StepExpr);
                error -> error
            end;
        {next_loop, _MaybeVar} ->
            ok;
        {locate, RowExpr, ColExpr} ->
            validate_expr_pair(RowExpr, ColExpr);
        {data, _Items} ->
            ok;
        {restore, all} ->
            ok;
        {restore, LineExpr} ->
            validate_expr_syntax(LineExpr);
        {home_publish} ->
            ok;
        {read_data, Targets} ->
            validate_targets(Targets);
        {file_open, PathExpr, _Mode, ChannelExpr, undefined} ->
            validate_expr_pair(PathExpr, ChannelExpr);
        {file_open, PathExpr, _Mode, ChannelExpr, RecLenExpr} ->
            case validate_expr_pair(PathExpr, ChannelExpr) of
                ok -> validate_expr_syntax(RecLenExpr);
                error -> error
            end;
        {file_close, all} ->
            ok;
        {file_close, Channels} ->
            validate_exprs(Channels);
        {file_print, ChannelExpr, Items, _EndWithNewline} ->
            case validate_expr_syntax(ChannelExpr) of
                ok -> validate_print_items(Items);
                error -> error
            end;
        {file_write, ChannelExpr, Exprs} ->
            case validate_expr_syntax(ChannelExpr) of
                ok -> validate_exprs(Exprs);
                error -> error
            end;
        {file_input, ChannelExpr, Targets} ->
            case validate_expr_syntax(ChannelExpr) of
                ok -> validate_targets(Targets);
                error -> error
            end;
        {file_line_input, ChannelExpr, Target} ->
            case validate_expr_syntax(ChannelExpr) of
                ok -> validate_target_syntax(Target);
                error -> error
            end;
        {file_field, ChannelExpr, Specs} ->
            case validate_expr_syntax(ChannelExpr) of
                ok -> validate_field_specs(Specs);
                error -> error
            end;
        {file_put_record, ChannelExpr, RecordExpr} ->
            validate_expr_pair(ChannelExpr, RecordExpr);
        {file_get_record, ChannelExpr, RecordExpr} ->
            validate_expr_pair(ChannelExpr, RecordExpr);
        {'return'} ->
            ok;
        {cls} ->
            ok;
        {hgr} ->
            ok;
        {hgr2} ->
            ok;
        {text} ->
            ok;
        {tron} ->
            ok;
        {troff} ->
            ok;
        {pset, XExpr, YExpr, ColorExpr} ->
            case validate_expr_pair(XExpr, YExpr) of
                ok -> validate_expr_syntax(ColorExpr);
                error -> error
            end;
        {line, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr} ->
            case validate_expr_pair(X1Expr, Y1Expr) of
                ok ->
                    case validate_expr_pair(X2Expr, Y2Expr) of
                        ok -> validate_expr_syntax(ColorExpr);
                        error -> error
                    end;
                error -> error
            end;
        {lineto, XExpr, YExpr, ColorExpr} ->
            case validate_expr_pair(XExpr, YExpr) of
                ok -> validate_expr_syntax(ColorExpr);
                error -> error
            end;
        {rect, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr} ->
            case validate_expr_pair(X1Expr, Y1Expr) of
                ok ->
                    case validate_expr_pair(X2Expr, Y2Expr) of
                        ok -> validate_expr_syntax(ColorExpr);
                        error -> error
                    end;
                error -> error
            end;
        {circle, XExpr, YExpr, RadiusExpr, ColorExpr} ->
            case validate_expr_pair(XExpr, YExpr) of
                ok ->
                    case validate_expr_syntax(RadiusExpr) of
                        ok -> validate_expr_syntax(ColorExpr);
                        error -> error
                    end;
                error -> error
            end;
        {sleep, Expr} ->
            validate_expr_syntax(Expr);
        {sleep_keypress} ->
            ok;
        {flush_stmt} ->
            ok;
        {buffer_mode, on} ->
            ok;
        {buffer_mode, off} ->
            ok;
        {pget, XExpr, YExpr, Target} ->
            case validate_expr_pair(XExpr, YExpr) of
                ok    -> validate_target_syntax(Target);
                error -> error
            end;
        {getchar, RowExpr, ColExpr, Target} ->
            case validate_expr_pair(RowExpr, ColExpr) of
                ok    -> validate_target_syntax(Target);
                error -> error
            end;
        {on_sprite_gosub, TargetExpr} ->
            validate_expr_syntax(TargetExpr);
        {on_play_gosub, NExpr, TargetExpr} ->
            case validate_expr_syntax(NExpr) of
                ok    -> validate_expr_syntax(TargetExpr);
                error -> error
            end;
        {on_timer_gosub, NExpr, TargetExpr} ->
            case validate_expr_syntax(NExpr) of
                ok    -> validate_expr_syntax(TargetExpr);
                error -> error
            end;
        {sprite_clear} ->
            ok;
        {sprite_hide, IdExpr} ->
            validate_expr_syntax(IdExpr);
        {sprite_show, IdExpr} ->
            validate_expr_syntax(IdExpr);
        {sprite_scale, IdExpr, ScaleExpr} ->
            validate_expr_pair(IdExpr, ScaleExpr);
        {sprite_move, IdExpr, XExpr, YExpr} ->
            case validate_expr_pair(IdExpr, XExpr) of
                ok -> validate_expr_syntax(YExpr);
                error -> error
            end;
        {sprite_load, IdExpr, WidthExpr, HeightExpr, {array_target, _Var, [StartExpr]}} ->
            case validate_expr_pair(IdExpr, WidthExpr) of
                ok -> validate_expr_pair(HeightExpr, StartExpr);
                error -> error
            end;
        {play_stmt, Expr} ->
            validate_expr_syntax(Expr);
        {chain, FileExpr} ->
            validate_expr_syntax(FileExpr);
        {sound, VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr} ->
            case validate_expr_pair(VoiceExpr, PitchExpr) of
                ok -> validate_expr_pair(DistortionExpr, VolumeExpr);
                error -> error
            end;
        {stop_stmt} ->
            ok;
        {color, FgExpr, undefined} ->
            validate_expr_syntax(FgExpr);
        {color, FgExpr, BgExpr} ->
            validate_expr_pair(FgExpr, BgExpr);
        {remark} ->
            ok;
        {'end'} ->
            ok;
        {error, Reason} ->
            {error, Reason};
        {parse_error, Reason} ->
            {error, Reason};
        unknown ->
            error
    end.

is_reserved_variable_name(Name) ->
    erlbasic_keywords:is_reserved_variable_name(Name).

validate_optional_statement_sequence(undefined) ->
    ok;
validate_optional_statement_sequence(Stmt) ->
    validate_statement_sequence(Stmt).

validate_expr_pair(LeftExpr, RightExpr) ->
    case validate_expr_syntax(LeftExpr) of
        ok -> validate_expr_syntax(RightExpr);
        error -> error
    end.

validate_targets([]) ->
    ok;
validate_targets([Target | Rest]) ->
    case validate_target_syntax(Target) of
        ok -> validate_targets(Rest);
        error -> error
    end.

validate_dim_decls([]) ->
    ok;
validate_dim_decls([{_Name, DimExprs} | Rest]) ->
    case validate_exprs(DimExprs) of
        ok -> validate_dim_decls(Rest);
        error -> error
    end.

validate_input_targets([]) ->
    error;                              %% no targets at all: parse error
validate_input_targets(Targets) ->
    validate_input_targets_all(Targets).

validate_input_targets_all([]) -> ok;
validate_input_targets_all([Target | Rest]) ->
    case validate_target_syntax(Target) of
        ok    -> validate_input_targets_all(Rest);
        error -> error
    end.

validate_field_specs([]) ->
    ok;
validate_field_specs([{LenExpr, _Var} | Rest]) ->
    case validate_expr_syntax(LenExpr) of
        ok -> validate_field_specs(Rest);
        error -> error
    end.

validate_target_syntax({var_target, _Var}) ->
    ok;
validate_target_syntax({array_target, _Var, IndexExprs}) ->
    validate_exprs(IndexExprs).

validate_exprs([]) ->
    ok;
validate_exprs([Expr | Rest]) ->
    case validate_expr_syntax(Expr) of
        ok -> validate_exprs(Rest);
        error -> error
    end.

validate_expr_syntax(Expr) ->
    case erlbasic_eval:eval_expr_result(Expr, #{}, #{}) of
        {error, syntax_error, _} -> error;
        _ -> ok
    end.

validate_print_items([]) ->
    ok;
validate_print_items([{Expr, _Sep} | Rest]) ->
    case validate_expr_syntax(Expr) of
        ok -> validate_print_items(Rest);
        error -> error
    end.

validate_condition_syntax(CondExpr) ->
    case erlbasic_eval:eval_condition_result(CondExpr, #{}, #{}) of
        {error, syntax_error} -> error;
        _ -> ok
    end.

validate_line_targets([]) ->
    ok;
validate_line_targets([Target | Rest]) ->
    case validate_expr_syntax(Target) of
        ok -> validate_line_targets(Rest);
        error -> error
    end.

has_balanced_quotes(Text) ->
    has_balanced_quotes(Text, false).

has_balanced_quotes([], InString) ->
    not InString;
has_balanced_quotes([$" | Rest], InString) ->
    has_balanced_quotes(Rest, not InString);
has_balanced_quotes([_Ch | Rest], InString) ->
    has_balanced_quotes(Rest, InString).
