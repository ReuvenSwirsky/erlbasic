Nonterminals stmt.
Terminals raw_stmt kw_print kw_write kw_let kw_rem kw_implicit_let kw_line_input kw_input kw_get kw_getkey kw_getchar kw_goto kw_gosub kw_if kw_then kw_else kw_for kw_to kw_step kw_next ident eq kw_on kw_error kw_on_sprite kw_on_play kw_on_timer kw_resume kw_dim kw_def kw_data kw_read kw_restore kw_return kw_end kw_stop kw_cls kw_hgr kw_hgr2 kw_textstmt kw_tron kw_troff kw_flush kw_buffer kw_sleep kw_sound kw_play kw_chain kw_open kw_close kw_field kw_put kw_color kw_locate kw_home kw_pset kw_linegfx kw_lineto kw_rect kw_circle kw_pget kw_sprite qmark text.
Rootsymbol stmt.

stmt -> kw_print text : parse_print_stmt('$2').
stmt -> kw_write text : parse_write_stmt('$2').
stmt -> kw_let text : parse_let_stmt('$2').
stmt -> kw_rem text : parse_rem_stmt('$2').
stmt -> kw_implicit_let text : parse_implicit_let_stmt('$2').
stmt -> kw_line_input text : parse_line_input_stmt('$2').
stmt -> kw_input text : parse_input_stmt('$2').
stmt -> kw_get text : parse_get_stmt('$2').
stmt -> kw_getkey text : parse_getkey_stmt('$2').
stmt -> kw_getchar text : parse_getchar_stmt('$2').
stmt -> kw_goto text : parse_goto_stmt('$2').
stmt -> kw_gosub text : parse_gosub_stmt('$2').
stmt -> kw_if text kw_then text :
    {if_then_else,
     text_value('$2'),
     normalize_if_branch_statement(text_value('$4')),
     undefined}.
stmt -> kw_if text kw_then text kw_else text :
    {if_then_else,
     text_value('$2'),
     normalize_if_branch_statement(text_value('$4')),
     normalize_if_branch_statement(text_value('$6'))}.
stmt -> kw_if text : parse_if_stmt('$2').
stmt -> kw_for ident eq text kw_to text : parse_for_tokens('$2', '$4', '$6', undefined).
stmt -> kw_for ident eq text kw_to text kw_step text : parse_for_tokens('$2', '$4', '$6', '$8').
stmt -> kw_for text : parse_for_stmt('$2').
stmt -> kw_next : {next_loop, undefined}.
stmt -> kw_next ident : parse_next_ident('$2').
stmt -> kw_next text : parse_next_stmt('$2').
stmt -> kw_on kw_error kw_goto text : {on_error_goto, text_value('$4')}.
stmt -> kw_on kw_on_sprite kw_gosub text : {on_sprite_gosub, text_value('$4')}.
stmt -> kw_on kw_on_play text kw_gosub text : {on_play_gosub, text_value('$3'), text_value('$5')}.
stmt -> kw_on kw_on_timer text kw_gosub text : {on_timer_gosub, text_value('$3'), text_value('$5')}.
stmt -> kw_on text kw_gosub text : {on_gosub, text_value('$2'), parse_on_targets(text_value('$4'))}.
stmt -> kw_on text kw_goto text : {on_goto, text_value('$2'), parse_on_targets(text_value('$4'))}.
stmt -> kw_on text : parse_on_stmt('$2').
stmt -> kw_resume : {resume}.
stmt -> kw_resume kw_next : {resume_next}.
stmt -> kw_resume text : {resume_line, text_value('$2')}.
stmt -> kw_dim text : parse_dim_stmt('$2').
stmt -> kw_def text : parse_def_stmt('$2').
stmt -> kw_data text : parse_data_stmt('$2').
stmt -> kw_read text : parse_read_stmt('$2').
stmt -> kw_restore text : parse_restore_stmt('$2').
stmt -> kw_return text : parse_return_stmt('$2').
stmt -> kw_end text : parse_end_stmt('$2').
stmt -> kw_stop text : parse_stop_stmt('$2').
stmt -> kw_cls text : parse_cls_stmt('$2').
stmt -> kw_hgr text : parse_hgr_stmt('$2').
stmt -> kw_hgr2 text : parse_hgr2_stmt('$2').
stmt -> kw_textstmt text : parse_text_stmt('$2').
stmt -> kw_tron text : parse_tron_stmt('$2').
stmt -> kw_troff text : parse_troff_stmt('$2').
stmt -> kw_flush text : parse_flush_stmt('$2').
stmt -> kw_buffer text : parse_buffer_stmt('$2').
stmt -> kw_sleep text : parse_sleep_stmt('$2').
stmt -> kw_sound text : parse_sound_stmt('$2').
stmt -> kw_play text : parse_play_stmt('$2').
stmt -> kw_chain text : parse_chain_stmt('$2').
stmt -> kw_open text : parse_open_stmt('$2').
stmt -> kw_close text : parse_close_stmt('$2').
stmt -> kw_field text : parse_field_stmt('$2').
stmt -> kw_put text : parse_put_stmt('$2').
stmt -> kw_color text : parse_color_stmt('$2').
stmt -> kw_locate text : parse_locate_stmt('$2').
stmt -> kw_home text : parse_home_stmt('$2').
stmt -> kw_pset text : parse_pset_stmt('$2').
stmt -> kw_linegfx text : parse_linegfx_stmt('$2').
stmt -> kw_lineto text : parse_lineto_stmt('$2').
stmt -> kw_rect text : parse_rect_stmt('$2').
stmt -> kw_circle text : parse_circle_stmt('$2').
stmt -> kw_pget text : parse_pget_stmt('$2').
stmt -> kw_sprite text : parse_sprite_stmt('$2').
stmt -> qmark text : parse_qmark_stmt('$2').
stmt -> raw_stmt : parse_raw_stmt('$1').

Erlang code.

parse_print_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_print_stmt_yecc(Rest).

parse_write_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_write_stmt_yecc(Rest).

parse_qmark_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_qmark_stmt_yecc(Rest).

parse_let_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_let_stmt_yecc(Rest).

parse_rem_stmt(_TextToken) ->
    {remark}.

parse_implicit_let_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_implicit_let_stmt_yecc(Rest).

parse_line_input_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_line_input_stmt_yecc(Rest).

parse_input_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_input_stmt_yecc(Rest).

parse_get_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_get_stmt_yecc(Rest).

parse_getkey_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_getkey_stmt_yecc(Rest).

parse_getchar_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_getchar_stmt_yecc(Rest).

parse_goto_stmt(TextToken) ->
    parse_required_expr_stmt(TextToken, goto).

parse_gosub_stmt(TextToken) ->
    parse_required_expr_stmt(TextToken, gosub).

parse_if_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_if_stmt_yecc(Rest).

parse_for_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_for_stmt_yecc(Rest).

parse_next_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_next_stmt_yecc(Rest).

parse_on_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_on_stmt_yecc(Rest).

parse_dim_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_dim_stmt_yecc(Rest).

parse_def_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_def_stmt_yecc(Rest).

parse_data_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_data_stmt_yecc(Rest).

parse_read_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_read_stmt_yecc(Rest).

parse_restore_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_restore_stmt_yecc(Rest).

parse_return_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {'return'}).

parse_end_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {'end'}).

parse_stop_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {stop_stmt}).

parse_cls_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {cls}).

parse_hgr_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {hgr}).

parse_hgr2_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {hgr2}).

parse_text_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {text}).

parse_tron_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {tron}).

parse_troff_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {troff}).

parse_flush_stmt(TextToken) ->
    parse_noarg_stmt(TextToken, {flush_stmt}).

parse_buffer_stmt(TextToken) ->
    case string:to_upper(trim_text(TextToken)) of
        "ON" -> {buffer_mode, on};
        "OFF" -> {buffer_mode, off};
        _ -> unknown
    end.

parse_sleep_stmt(TextToken) ->
    case trim_text(TextToken) of
        "" -> {sleep_keypress};
        Expr -> {sleep, Expr}
    end.

parse_sound_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_sound_stmt_yecc(Rest).

parse_play_stmt(TextToken) ->
    parse_required_expr_stmt(TextToken, play_stmt).

parse_chain_stmt(TextToken) ->
    parse_required_expr_stmt(TextToken, chain).

parse_open_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_open_stmt_yecc(Rest).

parse_close_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_close_stmt_yecc(Rest).

parse_field_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_field_stmt_yecc(Rest).

parse_put_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_put_stmt_yecc(Rest).

parse_color_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_color_stmt_yecc(Rest).

parse_locate_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_locate_stmt_yecc(Rest).

parse_home_stmt(TextToken) ->
    case string:to_upper(trim_text(TextToken)) of
        "PUBLISH" -> {home_publish};
        _ -> unknown
    end.

parse_pset_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_pset_stmt_yecc(Rest).

parse_linegfx_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_linegfx_stmt_yecc(Rest).

parse_lineto_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_lineto_stmt_yecc(Rest).

parse_rect_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_rect_stmt_yecc(Rest).

parse_circle_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_circle_stmt_yecc(Rest).

parse_pget_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_pget_stmt_yecc(Rest).

parse_sprite_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_sprite_stmt_yecc(Rest).

parse_raw_stmt({raw_stmt, _Line, Command}) ->
    _ = Command,
    unknown.

text_value({text, _Line, Rest}) ->
    string:trim(Rest).

normalize_if_branch_statement(Stmt) ->
    Trimmed = string:trim(Stmt),
    case re:run(Trimmed, "^(\\d+)$", [{capture, [1], list}]) of
        {match, [LineNumber]} -> "GOTO " ++ LineNumber;
        nomatch -> Trimmed
    end.

parse_for_tokens({ident, _Line, Var0}, StartTok, EndTok, undefined) ->
    Var = string:to_upper(Var0),
    case erlbasic_keywords:is_reserved_variable_name(Var) of
        true -> {parse_error, reserved_word};
        false -> {for_loop, Var, text_value(StartTok), text_value(EndTok), undefined}
    end;
parse_for_tokens({ident, _Line, Var0}, StartTok, EndTok, StepTok) ->
    Var = string:to_upper(Var0),
    case erlbasic_keywords:is_reserved_variable_name(Var) of
        true -> {parse_error, reserved_word};
        false -> {for_loop, Var, text_value(StartTok), text_value(EndTok), text_value(StepTok)}
    end.

parse_next_ident({ident, _Line, Var0}) ->
    Var = string:to_upper(Var0),
    case erlbasic_keywords:is_reserved_variable_name(Var) of
        true -> {parse_error, reserved_word};
        false -> {next_loop, Var}
    end.

parse_on_targets(TargetsText) ->
    Parts = string:split(string:trim(TargetsText), ",", all),
    [string:trim(P) || P <- Parts].

trim_text({text, _Line, Rest}) ->
    string:trim(Rest).

parse_noarg_stmt(TextToken, Result) ->
    case trim_text(TextToken) of
        "" -> Result;
        _ -> unknown
    end.

parse_required_expr_stmt(TextToken, Tag) ->
    case trim_text(TextToken) of
        "" -> unknown;
        Expr -> {Tag, Expr}
    end.
