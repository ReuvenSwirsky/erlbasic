-module(erlbasic_parser).

-export([
    parse_statement/1,
    set_parser_mode/1,
    clear_parser_mode/0,
    parse_statement_legacy/1,
    parse_statement_yecc/1,
    parse_print_stmt_yecc/1,
    parse_write_stmt_yecc/1,
    parse_qmark_stmt_yecc/1,
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
    parse_color_stmt_yecc/1,
    parse_locate_stmt_yecc/1,
    parse_home_stmt_yecc/1,
    parse_pset_stmt_yecc/1,
    parse_linegfx_stmt_yecc/1,
    parse_lineto_stmt_yecc/1,
    parse_rect_stmt_yecc/1,
    parse_circle_stmt_yecc/1,
    parse_pget_stmt_yecc/1,
    parse_sprite_stmt_yecc/1,
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
    Trimmed = string:trim(Command),
    case re:run(Trimmed, "(?i)^REM(\\s|$)", [{capture, none}]) of
        match  -> {remark};
        nomatch -> parse_print_statement(Trimmed)
    end.

parse_print_stmt_yecc(Rest) ->
    parse_print_statement(string:trim("PRINT" ++ Rest)).

parse_write_stmt_yecc(Rest) ->
    parse_print_statement(string:trim("WRITE" ++ Rest)).

parse_qmark_stmt_yecc(Rest) ->
    parse_print_or_qmark_statement(string:trim("?" ++ Rest)).

parse_let_stmt_yecc(Rest) ->
    parse_let_statement(string:trim("LET" ++ Rest)).

parse_rem_stmt_yecc(_Rest) ->
    {remark}.

parse_implicit_let_stmt_yecc(Rest) ->
    parse_implicit_let_statement(string:trim(Rest)).

parse_line_input_stmt_yecc(Rest) ->
    parse_input_statement(string:trim("LINE INPUT" ++ Rest)).

parse_input_stmt_yecc(Rest) ->
    parse_input_statement(string:trim("INPUT" ++ Rest)).

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
    parse_if_statement(string:trim("IF" ++ Rest)).

parse_for_stmt_yecc(Rest) ->
    parse_loop_statement(string:trim("FOR" ++ Rest)).

parse_next_stmt_yecc(Rest) ->
    parse_next_statement(string:trim("NEXT" ++ Rest)).

parse_on_stmt_yecc(Rest) ->
    parse_jump_statement(string:trim("ON" ++ Rest)).

parse_resume_stmt_yecc(Rest) ->
    parse_resume_statement(string:trim("RESUME" ++ Rest)).

parse_dim_stmt_yecc(Rest) ->
    parse_dim_statement(string:trim("DIM" ++ Rest)).

parse_def_stmt_yecc(Rest) ->
    parse_def_fn_statement(string:trim("DEF" ++ Rest)).

parse_data_stmt_yecc(Rest) ->
    parse_data_statement(string:trim("DATA" ++ Rest)).

parse_read_stmt_yecc(Rest) ->
    parse_read_statement(string:trim("READ" ++ Rest)).

parse_restore_stmt_yecc(Rest) ->
    parse_restore_statement(string:trim("RESTORE" ++ Rest)).

parse_return_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {'return'}).

parse_end_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, {'end'}).

parse_stop_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, stop_stmt).

parse_cls_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, cls).

parse_hgr_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, hgr).

parse_hgr2_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, hgr2).

parse_text_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, text).

parse_tron_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, tron).

parse_troff_stmt_yecc(Rest) ->
    parse_noarg_keyword_stmt(Rest, troff).

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

parse_color_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^(.+?)(?:\\s*,\\s*(.+))?$", [{capture, all_but_first, list}]) of
        {match, [FgExpr]} ->
            {color, FgExpr, undefined};
        {match, [FgExpr, BgExpr]} ->
            {color, FgExpr, BgExpr};
        nomatch ->
            unknown
    end.

parse_locate_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [RowExpr, ColExpr]} ->
            {locate, RowExpr, ColExpr};
        nomatch ->
            unknown
    end.

parse_home_stmt_yecc(Rest) ->
    case string:to_upper(string:trim(Rest)) of
        "PUBLISH" -> {home_publish};
        _ -> unknown
    end.

parse_pset_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^\(\s*(.+?)\s*,\s*(.+?)\s*\)\s*,\s*(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [XExpr, YExpr, ColorExpr]} ->
            {pset, XExpr, YExpr, ColorExpr};
        nomatch ->
            unknown
    end.

parse_linegfx_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^\(\s*(.+?)\s*,\s*(.+?)\s*\)\s*-\s*\(\s*(.+?)\s*,\s*(.+?)\s*\)\s*,\s*(.+)$", [{capture, [1, 2, 3, 4, 5], list}]) of
        {match, [X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr]} ->
            {line, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr};
        nomatch ->
            unknown
    end.

parse_lineto_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^\(\s*(.+?)\s*,\s*(.+?)\s*\)\s*,\s*(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [XExpr, YExpr, ColorExpr]} ->
            {lineto, XExpr, YExpr, ColorExpr};
        nomatch ->
            unknown
    end.

parse_rect_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^\(\s*(.+?)\s*,\s*(.+?)\s*\)\s*-\s*\(\s*(.+?)\s*,\s*(.+?)\s*\)\s*,\s*(.+)$", [{capture, [1, 2, 3, 4, 5], list}]) of
        {match, [X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr]} ->
            {rect, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr};
        nomatch ->
            unknown
    end.

parse_circle_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^\(\s*(.+?)\s*,\s*(.+?)\s*\)\s*,\s*(.+?)\s*,\s*(.+)$", [{capture, [1, 2, 3, 4], list}]) of
        {match, [XExpr, YExpr, RadiusExpr, ColorExpr]} ->
            {circle, XExpr, YExpr, RadiusExpr, ColorExpr};
        nomatch ->
            unknown
    end.

parse_pget_stmt_yecc(Rest) ->
    case re:run(string:trim(Rest), "^\\((.+),(.+)\\),(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [XExpr, YExpr, TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {pget, string:trim(XExpr), string:trim(YExpr), Target};
                _ -> unknown
            end;
        nomatch ->
            unknown
    end.

parse_sprite_stmt_yecc(Rest) ->
    parse_sprite_statement(string:trim("SPRITE" ++ Rest)).

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
                {ok, yecc} -> yecc;
                _ -> legacy
            end
    end.

%% Phase-1 yecc bridge: run statement text through yecc, then delegate
%% to legacy parser behavior via grammar actions for exact compatibility.
parse_statement_yecc(Command) ->
    Trimmed = string:trim(Command),
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

parse_print_statement(Trimmed) ->
    case parse_file_print_or_write_statement(Trimmed) of
        nomatch ->
            parse_print_statement_inner(Trimmed);
        Result ->
            Result
    end.

parse_print_statement_inner(Trimmed) ->
    case re:run(Trimmed, "(?i)^PRINT\\s+USING\\s+(.+)$", [{capture, [1], list}]) of
        {match, [UsingText]} ->
            case parse_print_using_items(UsingText) of
                {ok, FormatExpr, Items, EndWithNewline} -> {print_using, FormatExpr, Items, EndWithNewline};
                error -> unknown
            end;
        nomatch ->
            parse_print_or_qmark_statement(Trimmed)
    end.

parse_file_print_or_write_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PRINT\\s*#\\s*(.+?)(?:\\s*,\\s*(.*))?$", [{capture, all_but_first, list}]) of
        {match, [ChannelExpr]} ->
            {file_print, string:trim(ChannelExpr), [], true};
        {match, [ChannelExpr, ItemsText]} ->
            case parse_print_items(ItemsText) of
                {ok, Items, EndWithNewline} ->
                    {file_print, string:trim(ChannelExpr), Items, EndWithNewline};
                error ->
                    unknown
            end;
        nomatch ->
            case re:run(Trimmed, "(?i)^WRITE\\s*#\\s*(.+?)(?:\\s*,\\s*(.*))?$", [{capture, all_but_first, list}]) of
                {match, [ChannelExpr]} ->
                    {file_write, string:trim(ChannelExpr), []};
                {match, [ChannelExpr, ItemsText]} ->
                    case parse_write_items(ItemsText) of
                        {ok, Exprs} -> {file_write, string:trim(ChannelExpr), Exprs};
                        error -> unknown
                    end;
                nomatch ->
                    nomatch
            end
    end.

parse_write_items(Text) ->
    Parts = split_commas_top_level(Text),
    parse_write_items(Parts, []).

parse_write_items([], Acc) ->
    {ok, lists:reverse(Acc)};
parse_write_items([Part | Rest], Acc) ->
    Expr = string:trim(Part),
    case Expr of
        "" -> error;
        _ -> parse_write_items(Rest, [Expr | Acc])
    end.

parse_print_or_qmark_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PRINT(?:\\s+(.*))?$", [{capture, all_but_first, list}]) of
        {match, []} ->
            {print, [], true};
        {match, [ItemsText]} ->
            case parse_print_items(ItemsText) of
                {ok, Items, EndWithNewline} -> {print, Items, EndWithNewline};
                error -> unknown
            end;
        nomatch ->
            case re:run(Trimmed, "^\\?\\s*(.*)$", [{capture, [1], list}]) of
                {match, [ItemsText]} ->
                    case parse_print_items(ItemsText) of
                        {ok, Items, EndWithNewline} -> {print, Items, EndWithNewline};
                        error -> unknown
                    end;
                nomatch ->
                    parse_input_statement(Trimmed)
            end
    end.

parse_print_using_items(Text) ->
    case parse_print_items(Text) of
        {ok, [], _EndWithNewline} ->
            error;
        {ok, [{FormatExpr, _FmtSep} | Rest], EndWithNewline} ->
            {ok, FormatExpr, Rest, EndWithNewline};
        error ->
            error
    end.

parse_print_items(Text) ->
    parse_print_items(Text, [], [], false, 0).

parse_print_items([], CurrentRev, PartsRev, _InString, _Depth) ->
    FinalExpr = string:trim(lists:reverse(CurrentRev)),
    case {FinalExpr, PartsRev} of
        {"", []} ->
            {ok, [], true};
        {"", [{_Expr, semicolon} | _]} ->
            {ok, lists:reverse(PartsRev), false};
        {"", _} ->
            error;
        {_Expr, _} ->
            {ok, lists:reverse([{FinalExpr, none} | PartsRev]), true}
    end;
parse_print_items([$" | Rest], CurrentRev, PartsRev, InString, Depth) ->
    parse_print_items(Rest, [$" | CurrentRev], PartsRev, not InString, Depth);
parse_print_items([$( | Rest], CurrentRev, PartsRev, false, Depth) ->
    parse_print_items(Rest, [$( | CurrentRev], PartsRev, false, Depth + 1);
parse_print_items([$) | Rest], CurrentRev, PartsRev, false, Depth) when Depth > 0 ->
    parse_print_items(Rest, [$) | CurrentRev], PartsRev, false, Depth - 1);
parse_print_items([$, | Rest], CurrentRev, PartsRev, false, 0) ->
    push_print_part(Rest, CurrentRev, PartsRev, comma);
parse_print_items([$; | Rest], CurrentRev, PartsRev, false, 0) ->
    push_print_part(Rest, CurrentRev, PartsRev, semicolon);
parse_print_items([Ch | Rest], CurrentRev, PartsRev, InString, Depth) ->
    parse_print_items(Rest, [Ch | CurrentRev], PartsRev, InString, Depth).

push_print_part(Rest, CurrentRev, PartsRev, Sep) ->
    Expr = string:trim(lists:reverse(CurrentRev)),
    case Expr of
        "" ->
            error;
        _ ->
            parse_print_items(Rest, [], [{Expr, Sep} | PartsRev], false, 0)
    end.

parse_input_statement(Trimmed) ->
    %% INPUT LINE must be checked before plain INPUT to avoid prefix ambiguity.
    case re:run(Trimmed, "(?i)^LINE\\s+INPUT\\s*#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {file_line_input, string:trim(ChannelExpr), Target};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            parse_input_statement_inner(Trimmed)
    end.

parse_input_statement_inner(Trimmed) ->
    case re:run(Trimmed, "(?i)^INPUT\\s*#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, TargetsText]} ->
            case parse_input_target_list(split_commas_top_level(TargetsText), []) of
                {ok, Targets} -> {file_input, string:trim(ChannelExpr), Targets};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            parse_input_statement_console(Trimmed)
    end.

parse_input_statement_console(Trimmed) ->
    %% INPUT LINE must be checked before plain INPUT to avoid prefix ambiguity.
    case re:run(Trimmed, "(?i)^INPUT\\s+LINE\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {input_line, Target};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            case re:run(Trimmed, "(?i)^INPUT\\s+(.+)$", [{capture, [1], list}]) of
                {match, [TargetsText]} ->
                    case parse_input_target_list(split_commas_top_level(TargetsText), []) of
                        {ok, Targets} -> {input, Targets};
                        {error, Reason} -> {parse_error, Reason};
                        error -> unknown
                    end;
                nomatch ->
                    parse_get_statement(Trimmed)
            end
    end.

%% GETKEY must be matched before GET to avoid prefix collision.
parse_get_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^GET\\s*#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, RecordExpr]} ->
            {file_get_record, string:trim(ChannelExpr), string:trim(RecordExpr)};
        nomatch ->
            parse_get_statement_inner(Trimmed)
    end.

parse_get_statement_inner(Trimmed) ->
    case re:run(Trimmed, "(?i)^GETKEY\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {getkey, Target};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            case re:run(Trimmed, "(?i)^GET\\s+(.+)$", [{capture, [1], list}]) of
                {match, [TargetText]} ->
                    case parse_assignment_target(string:trim(TargetText)) of
                        {ok, Target} -> {get, Target};
                        {error, Reason} -> {parse_error, Reason};
                        error -> unknown
                    end;
                nomatch ->
                    parse_let_statement(Trimmed)
            end
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

parse_let_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LET\\s+(.+?)\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [TargetText, Expr]} ->
            case parse_assignment_target(TargetText) of
                {ok, Target} -> {'let', Target, Expr};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            parse_dim_statement(Trimmed)
    end.

parse_dim_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^DIM\\s+(.+)$", [{capture, [1], list}]) of
        {match, [DeclText]} ->
            case parse_dim_decls(DeclText) of
                {ok, Decls} -> {dim, Decls};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            parse_def_fn_statement(Trimmed)
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

parse_def_fn_statement(Trimmed) ->
    case re:run(
        Trimmed,
        "(?i)^DEF\\s+FN([A-Za-z][A-Za-z0-9_]*)(?:\\s*\\(\\s*" ++ ?VAR_PATTERN ++ "\\s*\\))?\\s*=\\s*(.+)$",
        [{capture, all_but_first, list}]) of
        {match, [FnSuffix, Expr]} ->
            {def_fn, "FN" ++ string:to_upper(FnSuffix), undefined, Expr};
        {match, [FnSuffix, ArgVar, Expr]} ->
            case is_reserved_variable_name(ArgVar) of
                true ->
                    {parse_error, reserved_word};
                false ->
                    {def_fn, "FN" ++ string:to_upper(FnSuffix), string:to_upper(ArgVar), Expr}
            end;
        nomatch ->
            parse_if_statement(Trimmed)
    end.

parse_if_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^IF\\s+(.+?)\\s+THEN\\s+(.+?)(?:\\s+ELSE\\s+(.+))?$", [{capture, all_but_first, list}]) of
        {match, [CondExpr, ThenStmt]} ->
            {if_then_else, CondExpr, normalize_if_branch_statement(ThenStmt), undefined};
        {match, [CondExpr, ThenStmt, ElseStmt]} ->
            {if_then_else, CondExpr,
             normalize_if_branch_statement(ThenStmt),
             normalize_if_branch_statement(ElseStmt)};
        nomatch ->
            parse_error_handler_statement(Trimmed)
    end.

normalize_if_branch_statement(Stmt) ->
    Trimmed = string:trim(Stmt),
    case re:run(Trimmed, "^(\\d+)$", [{capture, [1], list}]) of
        {match, [LineNumber]} ->
            "GOTO " ++ LineNumber;
        nomatch ->
            Trimmed
    end.

parse_error_handler_statement(Trimmed) ->
    %% Check for ON ERROR GOTO
    case re:run(Trimmed, "(?i)^ON\\s+ERROR\\s+GOTO\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetExpr]} ->
            {on_error_goto, string:trim(TargetExpr)};
        nomatch ->
            parse_resume_statement(Trimmed)
    end.

parse_resume_statement(Trimmed) ->
    %% Check for RESUME variants
    case re:run(Trimmed, "(?i)^RESUME\\s+NEXT$", [{capture, none}]) of
        match ->
            {resume_next};
        nomatch ->
            case re:run(Trimmed, "(?i)^RESUME\\s+(.+)$", [{capture, [1], list}]) of
                {match, [LineExpr]} ->
                    case string:trim(LineExpr) of
                        "0" -> {resume};  % RESUME 0 is same as RESUME
                        Other -> {resume_line, Other}
                    end;
                nomatch ->
                    case re:run(Trimmed, "(?i)^RESUME$", [{capture, none}]) of
                        match ->
                            {resume};
                        nomatch ->
                            parse_jump_statement(Trimmed)
                    end
            end
    end.

parse_jump_statement(Trimmed) ->
    %% Check for ON SPRITE GOSUB before generic ON...GOSUB.
    case re:run(Trimmed, "(?i)^ON\\s+SPRITE\\s+GOSUB\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetExpr]} ->
            {on_sprite_gosub, string:trim(TargetExpr)};
        nomatch ->
            %% Check for ON PLAY(n) GOSUB before general ON...GOSUB to avoid swallowing it
            case re:run(Trimmed, "(?i)^ON\\s+PLAY\\s*\\(\\s*(.+?)\\s*\\)\\s+GOSUB\\s+(.+)$", [{capture, [1, 2], list}]) of
                {match, [NExpr, TargetExpr]} ->
                    {on_play_gosub, string:trim(NExpr), string:trim(TargetExpr)};
                nomatch ->
                    %% Check for ON TIMER(n) GOSUB before general ON...GOSUB.
                    case re:run(Trimmed, "(?i)^ON\\s+TIMER\\s*\\(\\s*(.+?)\\s*\\)\\s+GOSUB\\s+(.+)$", [{capture, [1, 2], list}]) of
                        {match, [NExpr, TargetExpr]} ->
                            {on_timer_gosub, string:trim(NExpr), string:trim(TargetExpr)};
                        nomatch ->
                            %% Check for ON...GOSUB / ON...GOTO first (computed jump)
                            case re:run(Trimmed, "(?i)^ON\\s+(.+?)\\s+GOSUB\\s+(.+)$", [{capture, [1,2], list}]) of
                                {match, [Expr, Targets]} ->
                                    TargetList = parse_comma_separated_list(Targets),
                                    {on_gosub, Expr, TargetList};
                                nomatch ->
                                    case re:run(Trimmed, "(?i)^ON\\s+(.+?)\\s+GOTO\\s+(.+)$", [{capture, [1,2], list}]) of
                                        {match, [Expr, Targets]} ->
                                            TargetList = parse_comma_separated_list(Targets),
                                            {on_goto, Expr, TargetList};
                                        nomatch ->
                                            parse_simple_jump_statement(Trimmed)
                                    end
                            end
                    end
            end
    end.

parse_simple_jump_statement(Trimmed) ->
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

parse_comma_separated_list(Str) ->
    Parts = string:split(string:trim(Str), ",", all),
    [string:trim(P) || P <- Parts].

parse_loop_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^FOR\\s+" ++ ?LOOP_VAR_PATTERN ++ "\\s*=\\s*(.+)\\s+TO\\s+(.+?)(?:\\s+STEP\\s+(.+))?$", [{capture, all_but_first, list}]) of
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
            parse_next_statement(Trimmed)
    end.

parse_next_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^NEXT(?:\\s+" ++ ?VAR_PATTERN ++ ")?$", [{capture, all_but_first, list}]) of
        {match, []} ->
            {next_loop, undefined};
        {match, [Var]} ->
            case is_reserved_variable_name(Var) of
                true -> {parse_error, reserved_word};
                false -> {next_loop, string:to_upper(Var)}
            end;
        nomatch ->
            parse_locate_statement(Trimmed)
    end.

parse_locate_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LOCATE\\s+(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [RowExpr, ColExpr]} ->
            {locate, RowExpr, ColExpr};
        nomatch ->
            parse_data_or_read_statement(Trimmed)
    end.

parse_data_or_read_statement(Trimmed) ->
    case parse_read_statement(Trimmed) of
        nomatch ->
            parse_data_statement(Trimmed);
        Result ->
            Result
    end.

parse_read_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^READ\\s+(.+)$", [{capture, [1], list}]) of
        {match, [VarText]} ->
            case parse_read_vars(VarText) of
                {ok, Vars} -> {read_data, Vars};
                error -> unknown
            end;
        nomatch ->
            nomatch
    end.

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

parse_data_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^DATA(?:\\s+(.*))?$", [{capture, all_but_first, list}]) of
        {match, []} ->
            {data, []};
        {match, [DataText]} ->
            {data, normalize_data_items(split_commas_top_level(DataText))};
        nomatch ->
            parse_restore_statement(Trimmed)
    end.

parse_restore_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^RESTORE\\s+(.+)$", [{capture, [1], list}]) of
        {match, [LineExpr]} ->
            {restore, LineExpr};
        nomatch ->
            case re:run(Trimmed, "(?i)^RESTORE$", [{capture, none}]) of
                match   -> {restore, all};
                nomatch -> parse_home_statement(Trimmed)
            end
    end.

parse_home_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^HOME\\s+(\\S+)$", [{capture, [1], list}]) of
        {match, [Sub]} ->
            case string:to_upper(Sub) of
                "PUBLISH" -> {home_publish};
                _         -> unknown
            end;
        nomatch ->
            parse_keyword_statement(Trimmed)
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

parse_keyword_statement(Trimmed) ->
    case string:to_upper(Trimmed) of
        "CLS"  -> {cls};
        "HGR"  -> {hgr};
        "HGR2" -> {hgr2};
        "TEXT" -> {text};
        "STOP" -> {stop_stmt};
        "TRON" -> {tron};
        "TROFF" -> {troff};
        "RETURN" -> {'return'};
        "END" -> {'end'};
        _ -> parse_pset_statement(Trimmed)
    end.

parse_pset_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PSET\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [XExpr, YExpr, ColorExpr]} -> {pset, XExpr, YExpr, ColorExpr};
        nomatch -> parse_line_statement(Trimmed)
    end.

parse_line_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LINE\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*-\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+)$", 
                [{capture, [1, 2, 3, 4, 5], list}]) of
        {match, [X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr]} -> 
            {line, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr};
        nomatch -> parse_lineto_statement(Trimmed)
    end.

parse_lineto_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LINETO\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+)$", 
                [{capture, [1, 2, 3], list}]) of
        {match, [XExpr, YExpr, ColorExpr]} -> 
            {lineto, XExpr, YExpr, ColorExpr};
        nomatch -> parse_rect_statement(Trimmed)
    end.

parse_rect_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^RECT\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*-\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+)$", 
                [{capture, [1, 2, 3, 4, 5], list}]) of
        {match, [X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr]} -> 
            {rect, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr};
        nomatch -> parse_circle_statement(Trimmed)
    end.

parse_circle_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^CIRCLE\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+?)\\s*,\\s*(.+)$", 
                [{capture, [1, 2, 3, 4], list}]) of
        {match, [XExpr, YExpr, RadiusExpr, ColorExpr]} -> 
            {circle, XExpr, YExpr, RadiusExpr, ColorExpr};
        nomatch -> parse_sleep_statement(Trimmed)
    end.

parse_sleep_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^SLEEP\\s+(.+)$", [{capture, [1], list}]) of
        {match, [Expr]} -> {sleep, Expr};
        nomatch ->
            case re:run(Trimmed, "(?i)^SLEEP$", [{capture, none}]) of
                match   -> {sleep_keypress};
                nomatch -> parse_flush_buffer_statement(Trimmed)
            end
    end.

parse_flush_buffer_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^FLUSH$", [{capture, none}]) of
        match -> {flush_stmt};
        nomatch ->
            case re:run(Trimmed, "(?i)^BUFFER\\s+(ON|OFF)$", [{capture, [1], list}]) of
                {match, [OnOff]} ->
                    case string:to_upper(OnOff) of
                        "ON"  -> {buffer_mode, on};
                        "OFF" -> {buffer_mode, off}
                    end;
                nomatch -> parse_sound_statement(Trimmed)
            end
    end.

parse_sound_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^SOUND\\s+(.+?)\\s*,\\s*(.+?)\\s*,\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2, 3, 4], list}]) of
        {match, [VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr]} ->
            {sound, VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr};
        nomatch ->
            parse_play_statement(Trimmed)
    end.

parse_play_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PLAY\\s+(.+)$", [{capture, [1], list}]) of
        {match, [Expr]} -> {play_stmt, string:trim(Expr)};
        nomatch         -> parse_chain_statement(Trimmed)
    end.

parse_chain_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^CHAIN\\s+(.+)$", [{capture, [1], list}]) of
        {match, [FileExpr]} -> {chain, string:trim(FileExpr)};
        nomatch             -> parse_file_misc_statement(Trimmed)
    end.

parse_file_misc_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^OPEN\\s+(.+?)\\s+FOR\\s+(INPUT|OUTPUT|APPEND|RANDOM)\\s+AS\\s*#\\s*(.+?)(?:\\s+LEN\\s*=\\s*(.+))?$", [{capture, all_but_first, list}]) of
        {match, [PathExpr, Mode, ChannelExpr]} ->
            {file_open, string:trim(PathExpr), string:to_upper(Mode), string:trim(ChannelExpr), undefined};
        {match, [PathExpr, Mode, ChannelExpr, RecLenExpr]} ->
            {file_open, string:trim(PathExpr), string:to_upper(Mode), string:trim(ChannelExpr), string:trim(RecLenExpr)};
        nomatch ->
            case re:run(Trimmed, "(?i)^CLOSE(?:\\s+(.+))?$", [{capture, all_but_first, list}]) of
                {match, []} ->
                    {file_close, all};
                {match, [ChannelsText]} ->
                    case parse_file_channels(ChannelsText) of
                        {ok, Channels} -> {file_close, Channels};
                        error -> unknown
                    end;
                nomatch ->
                    case re:run(Trimmed, "(?i)^FIELD\\s*#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
                        {match, [ChannelExpr, SpecsText]} ->
                            case parse_field_specs(SpecsText) of
                                {ok, Specs} -> {file_field, string:trim(ChannelExpr), Specs};
                                error -> unknown
                            end;
                        nomatch ->
                            case re:run(Trimmed, "(?i)^PUT\\s*#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
                                {match, [ChannelExpr, RecordExpr]} ->
                                    {file_put_record, string:trim(ChannelExpr), string:trim(RecordExpr)};
                                nomatch ->
                                    parse_color_statement(Trimmed)
                            end
                    end
            end
    end.

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

parse_color_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^COLOR\\s+(.+?)(?:\\s*,\\s*(.+))?$", [{capture, all_but_first, list}]) of
        {match, [FgExpr]} ->
            {color, FgExpr, undefined};
        {match, [FgExpr, BgExpr]} ->
            {color, FgExpr, BgExpr};
        nomatch ->
            parse_pget_statement(Trimmed)
    end.

parse_pget_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PGET\\s*\\((.+),(.+)\\),(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [XExpr, YExpr, TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {pget, string:trim(XExpr), string:trim(YExpr), Target};
                _            -> unknown
            end;
        nomatch -> parse_sprite_statement(Trimmed)
    end.

parse_sprite_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^SPRITE\\s+CLEAR$", [{capture, none}]) of
        match -> {sprite_clear};
        nomatch ->
            case re:run(Trimmed, "(?i)^SPRITE\\s+HIDE\\s+(.+)$", [{capture, [1], list}]) of
                {match, [IdExpr]} ->
                    {sprite_hide, string:trim(IdExpr)};
                nomatch ->
                    case re:run(Trimmed, "(?i)^SPRITE\\s+SHOW\\s+(.+)$", [{capture, [1], list}]) of
                        {match, [IdExpr]} ->
                            {sprite_show, string:trim(IdExpr)};
                        nomatch ->
                            case re:run(Trimmed, "(?i)^SPRITE\\s+SCALE\\s+(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
                                {match, [IdExpr, ScaleExpr]} ->
                                    {sprite_scale, string:trim(IdExpr), string:trim(ScaleExpr)};
                                nomatch ->
                                    case re:run(Trimmed, "(?i)^SPRITE\\s+LOAD\\s+(.+?)\\s*,\\s*(.+?)\\s*,\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2, 3, 4], list}]) of
                                        {match, [IdExpr, WidthExpr, HeightExpr, SourceText]} ->
                                            case parse_sprite_load_source(SourceText) of
                                                {ok, SourceTarget} ->
                                                    {sprite_load, string:trim(IdExpr), string:trim(WidthExpr), string:trim(HeightExpr), SourceTarget};
                                                _ ->
                                                    unknown
                                            end;
                                        nomatch ->
                                            case re:run(Trimmed, "(?i)^SPRITE\\s+(.+?)\\s*,\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)$", [{capture, [1, 2, 3], list}]) of
                                                {match, [IdExpr, XExpr, YExpr]} ->
                                                    {sprite_move, string:trim(IdExpr), string:trim(XExpr), string:trim(YExpr)};
                                                nomatch ->
                                                    parse_getchar_statement(Trimmed)
                                            end
                                    end
                            end
                    end
            end
    end.

parse_sprite_load_source(Text) ->
    case parse_assignment_target(string:trim(Text)) of
        {ok, Target = {array_target, _Var, [_]}} ->
            {ok, Target};
        _ ->
            error
    end.

parse_getchar_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^GETCHAR\\s+(.+),(.+),(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [RowExpr, ColExpr, TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {getchar, string:trim(RowExpr), string:trim(ColExpr), Target};
                _            -> unknown
            end;
        nomatch -> parse_implicit_let_statement(Trimmed)
    end.

parse_implicit_let_statement(Trimmed) ->
    case re:run(Trimmed, "^(.+?)\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [TargetText, Expr]} ->
            case parse_assignment_target(TargetText) of
                {ok, Target} -> {'let', Target, Expr};
                {error, Reason} -> {parse_error, Reason};
                error -> unknown
            end;
        nomatch ->
            unknown
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
