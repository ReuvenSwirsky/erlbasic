-module(erlbasic_parser).

-export([
    parse_statement/1,
    parse_statement_yecc/1,
    should_split_top_level_sequence/1,
    split_statements/1,
    validate_program_line/1
]).


parse_statement(Command) ->
    parse_statement_yecc(Command).

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

%% Parse statement text through the yecc lexer+grammar.
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
