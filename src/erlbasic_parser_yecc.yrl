Nonterminals stmt.
Terminals raw_stmt kw_print kw_write kw_let kw_rem kw_implicit_let kw_line_input kw_input kw_get kw_getkey kw_getchar kw_goto kw_gosub kw_if kw_for kw_next kw_on kw_resume kw_dim kw_def kw_data kw_read kw_restore kw_return kw_end kw_stop kw_cls kw_hgr kw_hgr2 kw_textstmt kw_tron kw_troff kw_flush kw_buffer kw_sleep kw_sound kw_play kw_chain kw_open kw_close kw_field kw_put kw_color kw_locate kw_home kw_pset kw_linegfx kw_lineto kw_rect kw_circle kw_pget kw_sprite qmark text.
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
stmt -> kw_if text : parse_if_stmt('$2').
stmt -> kw_for text : parse_for_stmt('$2').
stmt -> kw_next text : parse_next_stmt('$2').
stmt -> kw_on text : parse_on_stmt('$2').
stmt -> kw_resume text : parse_resume_stmt('$2').
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

parse_rem_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_rem_stmt_yecc(Rest).

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

parse_goto_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_goto_stmt_yecc(Rest).

parse_gosub_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_gosub_stmt_yecc(Rest).

parse_if_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_if_stmt_yecc(Rest).

parse_for_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_for_stmt_yecc(Rest).

parse_next_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_next_stmt_yecc(Rest).

parse_on_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_on_stmt_yecc(Rest).

parse_resume_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_resume_stmt_yecc(Rest).

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

parse_return_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_return_stmt_yecc(Rest).

parse_end_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_end_stmt_yecc(Rest).

parse_stop_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_stop_stmt_yecc(Rest).

parse_cls_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_cls_stmt_yecc(Rest).

parse_hgr_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_hgr_stmt_yecc(Rest).

parse_hgr2_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_hgr2_stmt_yecc(Rest).

parse_text_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_text_stmt_yecc(Rest).

parse_tron_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_tron_stmt_yecc(Rest).

parse_troff_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_troff_stmt_yecc(Rest).

parse_flush_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_flush_stmt_yecc(Rest).

parse_buffer_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_buffer_stmt_yecc(Rest).

parse_sleep_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_sleep_stmt_yecc(Rest).

parse_sound_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_sound_stmt_yecc(Rest).

parse_play_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_play_stmt_yecc(Rest).

parse_chain_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_chain_stmt_yecc(Rest).

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

parse_home_stmt({text, _Line, Rest}) ->
    erlbasic_parser:parse_home_stmt_yecc(Rest).

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
