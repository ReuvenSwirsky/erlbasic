-module(erlbasic_parser_yecc_lexer).

-export([tokenize_statement/1]).

tokenize_statement(Text0) when is_list(Text0) ->
    Text = string:trim(Text0),
    case classify_statement(Text) of
        {token, kw_print, Rest} ->
            tokenize_print_statement(Rest);
        {token, kw_write, Rest} ->
            tokenize_write_statement(Rest);
        {token, kw_if, Rest} ->
            tokenize_if_statement(Rest);
        {token, kw_for, Rest} ->
            tokenize_for_statement(Rest);
        {token, kw_let, Rest} ->
            tokenize_let_statement(Rest);
        {token, kw_goto, Rest} ->
            tokenize_goto_statement(Rest);
        {token, kw_gosub, Rest} ->
            tokenize_gosub_statement(Rest);
        {token, kw_buffer, Rest} ->
            tokenize_buffer_statement(Rest);
        {token, kw_sleep, Rest} ->
            tokenize_sleep_statement(Rest);
        {token, kw_locate, Rest} ->
            tokenize_locate_statement(Rest);
        {token, kw_pset, Rest} ->
            tokenize_pset_statement(Rest);
        {token, kw_open, Rest} ->
            tokenize_open_statement(Rest);
        {token, kw_close, Rest} ->
            tokenize_close_statement(Rest);
        {token, kw_field, Rest} ->
            tokenize_field_statement(Rest);
        {token, kw_put, Rest} ->
            tokenize_put_statement(Rest);
        {token, kw_get, Rest} ->
            tokenize_get_statement(Rest);
        {token, kw_next, Rest} ->
            tokenize_next_statement(Rest);
        {token, kw_on, Rest} ->
            tokenize_on_statement(Rest);
        {token, kw_resume, Rest} ->
            tokenize_resume_statement(Rest);
        {token, kw_dim, Rest} ->
            tokenize_dim_statement(Rest);
        {token, kw_def, Rest} ->
            tokenize_def_fn_statement(Rest);
        {token, Token, Rest} when Token =:= kw_return; Token =:= kw_end; Token =:= kw_stop;
                                  Token =:= kw_cls; Token =:= kw_hgr; Token =:= kw_hgr2;
                                  Token =:= kw_textstmt; Token =:= kw_tron; Token =:= kw_troff;
                                  Token =:= kw_flush ->
            case string:trim(Rest) of
                "" ->
                    {ok, [{Token, 1}]};
                _ ->
                    {ok, [{Token, 1}, {text, 1, Rest}]}
            end;
        {token, Token, Rest} ->
            {ok, [{Token, 1}, {text, 1, Rest}]};
        qmark ->
            case Text of
                [$? | Rest] -> {ok, [{qmark, 1}, {text, 1, Rest}]};
                _ -> {ok, [{raw_stmt, 1, Text}]}
            end;
        raw ->
            {ok, [{raw_stmt, 1, Text}]}
    end;
tokenize_statement(_Other) ->
    error.

tokenize_print_statement(Rest) ->
    Trimmed = string:trim(Rest),
    case Trimmed of
        "" ->
            {ok, [{kw_print, 1}]};
        _ ->
            case re:run(Trimmed, "^(?i:USING)\\s+(.+)$", [{capture, [1], list}]) of
                {match, [UsingText]} ->
                    {ok, [{kw_print, 1}, {print_using, 1, string:trim(UsingText)}]};
                nomatch ->
            case re:run(Trimmed, "^#\\s*(.+?)(?:\\s*,\\s*(.*))?$", [{capture, all_but_first, list}]) of
                {match, [ChannelExpr]} ->
                    {ok, [{kw_print, 1}, {print_channel, 1, string:trim(ChannelExpr)}]};
                {match, [ChannelExpr, ItemsText]} ->
                    case string:trim(ItemsText) of
                        "" ->
                            {ok, [{kw_print, 1}, {print_channel, 1, string:trim(ChannelExpr)}]};
                        _ ->
                            {ok, [{kw_print, 1}, {print_channel, 1, string:trim(ChannelExpr)}, {print_items, 1, ItemsText}]}
                    end;
                nomatch ->
                    {ok, [{kw_print, 1}, {print_items, 1, Trimmed}]}
            end
            end
    end.

tokenize_write_statement(Rest) ->
    Trimmed = string:trim(Rest),
    case re:run(Trimmed, "^#\\s*(.+?)(?:\\s*,\\s*(.*))?$", [{capture, all_but_first, list}]) of
        {match, [ChannelExpr]} ->
            {ok, [{kw_write, 1}, {write_channel, 1, string:trim(ChannelExpr)}]};
        {match, [ChannelExpr, ItemsText]} ->
            case string:trim(ItemsText) of
                "" ->
                    {ok, [{kw_write, 1}, {write_channel, 1, string:trim(ChannelExpr)}]};
                _ ->
                    {ok, [{kw_write, 1}, {write_channel, 1, string:trim(ChannelExpr)}, {write_items, 1, ItemsText}]}
            end;
        nomatch ->
            {ok, [{kw_write, 1}, {text, 1, Rest}]}
    end.

tokenize_if_statement(Rest) ->
    Trimmed = string:trim(Rest),
    case re:run(Trimmed, "^(.+?)\\s+THEN\\s+(.+)$", [{capture, [1, 2], list}]) of
        {match, [CondExpr, ThenElseText]} ->
            Cond = string:trim(CondExpr),
            ThenElse = string:trim(ThenElseText),
            case {Cond, ThenElse} of
                {"", _} -> {ok, [{kw_if, 1}, {text, 1, Rest}]};
                {_, ""} -> {ok, [{kw_if, 1}, {text, 1, Rest}]};
                _ ->
                    case re:run(ThenElse, "^(.+?)\\s+ELSEIF\\s+(.+)$", [{capture, [1, 2], list}]) of
                        {match, [ThenText, ElseIfRest]} ->
                            ThenStmt = string:trim(ThenText),
                            ElseStmt = "IF " ++ string:trim(ElseIfRest),
                            case ThenStmt of
                                "" -> {ok, [{kw_if, 1}, {text, 1, Rest}]};
                                _ ->
                                    CondTokens = condition_tokens(Cond),
                                    {ok, [{kw_if, 1} | CondTokens] ++ [
                                        {kw_then, 1},
                                        {text, 1, ThenStmt},
                                        {kw_else, 1},
                                        {text, 1, ElseStmt}
                                    ]}
                            end;
                        nomatch ->
                            case re:run(ThenElse, "^(.+?)\\s+ELSE\\s+(.+)$", [{capture, [1, 2], list}]) of
                                {match, [ThenText, ElseText]} ->
                                    ThenStmt = string:trim(ThenText),
                                    ElseStmt = string:trim(ElseText),
                                    case {ThenStmt, ElseStmt} of
                                        {"", _} -> {ok, [{kw_if, 1}, {text, 1, Rest}]};
                                        {_, ""} -> {ok, [{kw_if, 1}, {text, 1, Rest}]};
                                        _ ->
                                            CondTokens = condition_tokens(Cond),
                                            {ok, [{kw_if, 1} | CondTokens] ++ [
                                                {kw_then, 1},
                                                {text, 1, ThenStmt},
                                                {kw_else, 1},
                                                {text, 1, ElseStmt}
                                            ]}
                                    end;
                                nomatch ->
                                    CondTokens = condition_tokens(Cond),
                                    {ok, [{kw_if, 1} | CondTokens] ++ [
                                        {kw_then, 1},
                                        {text, 1, ThenElse}
                                    ]}
                            end
                    end
            end;
        nomatch ->
            {ok, [{kw_if, 1}, {text, 1, Rest}]}
    end.

condition_tokens(Cond0) ->
    Cond = string:trim(Cond0),
    case re:run(Cond, "^(.+?)(<=|>=|<>|=|<|>)(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [LeftText, OpText, RightText]} ->
            Left = string:trim(LeftText),
            Right = string:trim(RightText),
            case {Left, Right, comparator_token(OpText)} of
                {"", _, _} -> [{text, 1, Cond}];
                {_, "", _} -> [{text, 1, Cond}];
                {_, _, undefined} -> [{text, 1, Cond}];
                {_, _, OpToken} -> [{text, 1, Left}, {OpToken, 1}, {text, 1, Right}]
            end;
        nomatch ->
            [{text, 1, Cond}]
    end.

comparator_token("<") -> op_lt;
comparator_token(">") -> op_gt;
comparator_token("=") -> op_eq;
comparator_token("<>") -> op_ne;
comparator_token("<=") -> op_le;
comparator_token(">=") -> op_ge;
comparator_token(_Other) -> undefined.

tokenize_for_statement(Rest) ->
    Trimmed = string:trim(Rest),
    Pattern = "^([A-Za-z][A-Za-z0-9_]*[%&#]?)\\s*=\\s*(.+)\\s+TO\\s+(.+?)(?:\\s+STEP\\s+(.+))?$",
    case re:run(Trimmed, Pattern, [{capture, all_but_first, list}]) of
        {match, [Var, StartExpr, EndExpr]} ->
            {ok, [
                {kw_for, 1},
                {ident, 1, Var},
                {eq, 1},
                {text, 1, string:trim(StartExpr)},
                {kw_to, 1},
                {text, 1, string:trim(EndExpr)}
            ]};
        {match, [Var, StartExpr, EndExpr, StepExpr]} ->
            {ok, [
                {kw_for, 1},
                {ident, 1, Var},
                {eq, 1},
                {text, 1, string:trim(StartExpr)},
                {kw_to, 1},
                {text, 1, string:trim(EndExpr)},
                {kw_step, 1},
                {text, 1, string:trim(StepExpr)}
            ]};
        nomatch ->
            {ok, [{kw_for, 1}, {text, 1, Rest}]}
    end.

tokenize_next_statement(Rest) ->
    case string:trim(Rest) of
        "" ->
            {ok, [{kw_next, 1}]};
        VarText ->
            case re:run(VarText, "^([A-Za-z][A-Za-z0-9_]*[\\$%&#]?)$", [{capture, [1], list}]) of
                {match, [Var]} -> {ok, [{kw_next, 1}, {ident, 1, Var}]};
                nomatch -> {ok, [{kw_next, 1}, {text, 1, Rest}]}
            end
    end.

tokenize_on_statement(Rest) ->
    Trimmed = string:trim(Rest),
    case re:run(Trimmed, "^ERROR\\s+GOTO\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetExpr]} ->
            {ok, [{kw_on, 1}, {kw_error, 1}, {kw_goto, 1}, {text, 1, string:trim(TargetExpr)}]};
        nomatch ->
            case re:run(Trimmed, "^SPRITE\\s+GOSUB\\s+(.+)$", [{capture, [1], list}]) of
                {match, [TargetExpr]} ->
                    {ok, [{kw_on, 1}, {kw_on_sprite, 1}, {kw_gosub, 1}, {text, 1, string:trim(TargetExpr)}]};
                nomatch ->
                    case re:run(Trimmed, "^PLAY\\s*\\(\\s*(.+?)\\s*\\)\\s+GOSUB\\s+(.+)$", [{capture, [1, 2], list}]) of
                        {match, [NExpr, TargetExpr]} ->
                            {ok, [{kw_on, 1}, {kw_on_play, 1}, {text, 1, string:trim(NExpr)}, {kw_gosub, 1}, {text, 1, string:trim(TargetExpr)}]};
                        nomatch ->
                            case re:run(Trimmed, "^TIMER\\s*\\(\\s*(.+?)\\s*\\)\\s+GOSUB\\s+(.+)$", [{capture, [1, 2], list}]) of
                                {match, [NExpr, TargetExpr]} ->
                                    {ok, [{kw_on, 1}, {kw_on_timer, 1}, {text, 1, string:trim(NExpr)}, {kw_gosub, 1}, {text, 1, string:trim(TargetExpr)}]};
                                nomatch ->
                                    case re:run(Trimmed, "^(.+?)\\s+GOSUB\\s+(.+)$", [{capture, [1, 2], list}]) of
                                        {match, [Expr, Targets]} ->
                                            {ok, [{kw_on, 1}, {text, 1, string:trim(Expr)}, {kw_gosub, 1}, {text, 1, string:trim(Targets)}]};
                                        nomatch ->
                                            case re:run(Trimmed, "^(.+?)\\s+GOTO\\s+(.+)$", [{capture, [1, 2], list}]) of
                                                {match, [Expr, Targets]} ->
                                                    {ok, [{kw_on, 1}, {text, 1, string:trim(Expr)}, {kw_goto, 1}, {text, 1, string:trim(Targets)}]};
                                                nomatch ->
                                                    {ok, [{kw_on, 1}, {text, 1, Rest}]}
                                            end
                                    end
                            end
                    end
            end
    end.

tokenize_resume_statement(Rest) ->
    case string:trim(Rest) of
        "" ->
            {ok, [{kw_resume, 1}]};
        TrimmedRest ->
            case string:to_upper(TrimmedRest) of
                "NEXT" -> {ok, [{kw_resume, 1}, {kw_next, 1}]};
                _ -> {ok, [{kw_resume, 1}, {line_number, 1, TrimmedRest}]}
            end
    end.

tokenize_goto_statement(Rest) ->
    case string:trim(Rest) of
        "" ->
            {error, "GOTO requires a line number"};
        LineExpr ->
            {ok, [{kw_goto, 1}, {line_number, 1, LineExpr}]}
    end.

tokenize_gosub_statement(Rest) ->
    case string:trim(Rest) of
        "" ->
            {error, "GOSUB requires a line number"};
        LineExpr ->
            {ok, [{kw_gosub, 1}, {line_number, 1, LineExpr}]}
    end.

tokenize_buffer_statement(Rest) ->
    case string:to_upper(string:trim(Rest)) of
        "ON" -> {ok, [{kw_buffer, 1}, {buffer_mode, 1, "ON"}]};
        "OFF" -> {ok, [{kw_buffer, 1}, {buffer_mode, 1, "OFF"}]};
        _ -> {error, "BUFFER requires ON or OFF"}
    end.

tokenize_sleep_statement(Rest) ->
    case string:trim(Rest) of
        "" -> {ok, [{kw_sleep, 1}]};
        Duration -> {ok, [{kw_sleep, 1}, {sleep_duration, 1, Duration}]}
    end.

tokenize_let_statement(Rest) ->
    case re:run(string:trim(Rest), "^(.+?)\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [TargetText, ExprText]} ->
            {ok, [
                {kw_let, 1},
                {assignment_target, 1, string:trim(TargetText)},
                {eq, 1},
                {assignment_expr, 1, string:trim(ExprText)}
            ]};
        nomatch ->
            {ok, [{kw_let, 1}, {text, 1, Rest}]}
    end.

tokenize_locate_statement(Rest) ->
    case re:run(string:trim(Rest), "^(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [Row, Col]} ->
            {ok, [{kw_locate, 1}, {coordinate, 1, string:trim(Row)}, {coordinate, 1, string:trim(Col)}]};
        nomatch ->
            {error, "LOCATE requires row, column"}
    end.

tokenize_pset_statement(Rest) ->
    case re:run(string:trim(Rest), "^\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [X, Y, Color]} ->
            {ok, [{kw_pset, 1}, {coordinate, 1, string:trim(X)}, {coordinate, 1, string:trim(Y)}, {pset_color, 1, string:trim(Color)}]};
        nomatch ->
            {error, "PSET requires (x, y), color"}
    end.

tokenize_open_statement(Rest) ->
    Trimmed = string:trim(Rest),
    Pattern = "^(?i)(.+?)\\s+FOR\\s+(INPUT|OUTPUT|APPEND|RANDOM)\\s+AS\\s*#\\s*(.+?)(?:\\s+LEN\\s*=\\s*(.+))?$",
    case re:run(Trimmed, Pattern, [{capture, all_but_first, list}]) of
        {match, [PathExpr, Mode, ChannelExpr]} ->
            {ok, [
                {kw_open, 1},
                {open_path, 1, string:trim(PathExpr)},
                {open_mode, 1, string:to_upper(Mode)},
                {file_channel, 1, string:trim(ChannelExpr)}
            ]};
        {match, [PathExpr, Mode, ChannelExpr, RecLenExpr]} ->
            {ok, [
                {kw_open, 1},
                {open_path, 1, string:trim(PathExpr)},
                {open_mode, 1, string:to_upper(Mode)},
                {file_channel, 1, string:trim(ChannelExpr)},
                {record_length, 1, string:trim(RecLenExpr)}
            ]};
        nomatch ->
            {ok, [{kw_open, 1}, {text, 1, Rest}]}
    end.

tokenize_close_statement(Rest) ->
    case string:trim(Rest) of
        "" -> {ok, [{kw_close, 1}]};
        ChannelsText -> {ok, [{kw_close, 1}, {close_channels, 1, ChannelsText}]}
    end.

tokenize_field_statement(Rest) ->
    Trimmed = string:trim(Rest),
    case re:run(Trimmed, "^(?i)#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, SpecsText]} ->
            {ok, [
                {kw_field, 1},
                {file_channel, 1, string:trim(ChannelExpr)},
                {field_specs, 1, string:trim(SpecsText)}
            ]};
        nomatch ->
            {ok, [{kw_field, 1}, {text, 1, Rest}]}
    end.

tokenize_put_statement(Rest) ->
    Trimmed = string:trim(Rest),
    case re:run(Trimmed, "^(?i)#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, RecordExpr]} ->
            {ok, [
                {kw_put, 1},
                {file_channel, 1, string:trim(ChannelExpr)},
                {file_record, 1, string:trim(RecordExpr)}
            ]};
        nomatch ->
            {ok, [{kw_put, 1}, {text, 1, Rest}]}
    end.

tokenize_get_statement(Rest) ->
    Trimmed = string:trim(Rest),
    case re:run(Trimmed, "^(?i)#\\s*(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [ChannelExpr, RecordExpr]} ->
            {ok, [
                {kw_get, 1},
                {file_channel, 1, string:trim(ChannelExpr)},
                {file_record, 1, string:trim(RecordExpr)}
            ]};
        nomatch ->
            {ok, [{kw_get, 1}, {text, 1, Rest}]}
    end.

tokenize_dim_statement(Rest) ->
    Trimmed = string:trim(Rest),
    case Trimmed of
        "" ->
            {ok, [{kw_dim, 1}]};
        _ ->
            {ok, [{kw_dim, 1}, {dim_declarations, 1, Trimmed}]}
    end.

tokenize_def_fn_statement(Rest) ->
    Trimmed = string:trim(Rest),
    case Trimmed of
        "" ->
            {ok, [{kw_def, 1}]};
        _ ->
            {ok, [{kw_def, 1}, {def_fn_spec, 1, Trimmed}]}
    end.

classify_statement(Text) ->
    case split_implicit_let(Text) of
        {match, Rest} ->
            {token, kw_implicit_let, Rest};
        nomatch ->
            classify_by_keywords(Text, keyword_splitters())
    end.

classify_by_keywords(Text, []) ->
    case Text of
        [$? | _] -> qmark;
        _ -> raw
    end;
classify_by_keywords(Text, [{Token, Fun} | Rest]) ->
    case Fun(Text) of
        {match, Tail} ->
            {token, Token, Tail};
        nomatch ->
            classify_by_keywords(Text, Rest)
    end.

keyword_splitters() ->
    [
        {kw_print, fun split_leading_print/1},
        {kw_write, fun split_leading_write/1},
        {kw_let, fun split_leading_let/1},
        {kw_rem, fun split_leading_rem/1},
        {kw_line_input, fun split_leading_line_input/1},
        {kw_input, fun split_leading_input/1},
        {kw_getkey, fun split_leading_getkey/1},
        {kw_getchar, fun split_leading_getchar/1},
        {kw_get, fun split_leading_get/1},
        {kw_goto, fun split_leading_goto/1},
        {kw_gosub, fun split_leading_gosub/1},
        {kw_if, fun split_leading_if/1},
        {kw_for, fun split_leading_for/1},
        {kw_next, fun split_leading_next/1},
        {kw_on, fun split_leading_on/1},
        {kw_resume, fun split_leading_resume/1},
        {kw_dim, fun split_leading_dim/1},
        {kw_def, fun split_leading_def/1},
        {kw_data, fun split_leading_data/1},
        {kw_read, fun split_leading_read/1},
        {kw_restore, fun split_leading_restore/1},
        {kw_return, fun split_leading_return/1},
        {kw_end, fun split_leading_end/1},
        {kw_stop, fun split_leading_stop/1},
        {kw_cls, fun split_leading_cls/1},
        {kw_hgr2, fun split_leading_hgr2/1},
        {kw_hgr, fun split_leading_hgr/1},
        {kw_textstmt, fun split_leading_textstmt/1},
        {kw_tron, fun split_leading_tron/1},
        {kw_troff, fun split_leading_troff/1},
        {kw_flush, fun split_leading_flush/1},
        {kw_buffer, fun split_leading_buffer/1},
        {kw_sleep, fun split_leading_sleep/1},
        {kw_sound, fun split_leading_sound/1},
        {kw_play, fun split_leading_play/1},
        {kw_chain, fun split_leading_chain/1},
        {kw_open, fun split_leading_open/1},
        {kw_close, fun split_leading_close/1},
        {kw_field, fun split_leading_field/1},
        {kw_put, fun split_leading_put/1},
        {kw_color, fun split_leading_color/1},
        {kw_locate, fun split_leading_locate/1},
        {kw_home, fun split_leading_home/1},
        {kw_pset, fun split_leading_pset/1},
        {kw_linegfx, fun split_leading_linegfx/1},
        {kw_lineto, fun split_leading_lineto/1},
        {kw_rect, fun split_leading_rect/1},
        {kw_circle, fun split_leading_circle/1},
        {kw_pget, fun split_leading_pget/1},
        {kw_sprite, fun split_leading_sprite/1}
    ].

split_leading_print(Text) ->
    split_leading_keyword(Text, "PRINT", allow_hash_boundary).

split_leading_write(Text) ->
    split_leading_keyword(Text, "WRITE", allow_hash_boundary).

split_leading_let(Text) ->
    split_leading_keyword(Text, "LET", whitespace_boundary).

split_leading_rem(Text) ->
    split_leading_keyword(Text, "REM", whitespace_boundary).

split_leading_line_input(Text) ->
    split_leading_prefix(Text, "LINE INPUT").

split_leading_input(Text) ->
    split_leading_keyword(Text, "INPUT", whitespace_boundary).

split_leading_getkey(Text) ->
    split_leading_keyword(Text, "GETKEY", whitespace_boundary).

split_leading_getchar(Text) ->
    split_leading_keyword(Text, "GETCHAR", whitespace_boundary).

split_leading_get(Text) ->
    split_leading_keyword(Text, "GET", whitespace_boundary).

split_leading_goto(Text) ->
    split_leading_keyword(Text, "GOTO", whitespace_boundary).

split_leading_gosub(Text) ->
    split_leading_keyword(Text, "GOSUB", whitespace_boundary).

split_leading_if(Text) ->
    split_leading_keyword(Text, "IF", whitespace_boundary).

split_leading_for(Text) ->
    split_leading_keyword(Text, "FOR", whitespace_boundary).

split_leading_next(Text) ->
    split_leading_keyword(Text, "NEXT", whitespace_boundary).

split_leading_on(Text) ->
    split_leading_keyword(Text, "ON", whitespace_boundary).

split_leading_resume(Text) ->
    split_leading_keyword(Text, "RESUME", whitespace_boundary).

split_leading_dim(Text) ->
    split_leading_keyword(Text, "DIM", whitespace_boundary).

split_leading_def(Text) ->
    split_leading_keyword(Text, "DEF", whitespace_boundary).

split_leading_data(Text) ->
    split_leading_keyword(Text, "DATA", whitespace_boundary).

split_leading_read(Text) ->
    split_leading_keyword(Text, "READ", whitespace_boundary).

split_leading_restore(Text) ->
    split_leading_keyword(Text, "RESTORE", whitespace_boundary).

split_leading_return(Text) ->
    split_leading_keyword(Text, "RETURN", whitespace_boundary).

split_leading_end(Text) ->
    split_leading_keyword(Text, "END", whitespace_boundary).

split_leading_stop(Text) ->
    split_leading_keyword(Text, "STOP", whitespace_boundary).

split_leading_cls(Text) ->
    split_leading_keyword(Text, "CLS", whitespace_boundary).

split_leading_hgr(Text) ->
    split_leading_keyword(Text, "HGR", whitespace_boundary).

split_leading_hgr2(Text) ->
    split_leading_keyword(Text, "HGR2", whitespace_boundary).

split_leading_textstmt(Text) ->
    split_leading_keyword(Text, "TEXT", whitespace_boundary).

split_leading_tron(Text) ->
    split_leading_keyword(Text, "TRON", whitespace_boundary).

split_leading_troff(Text) ->
    split_leading_keyword(Text, "TROFF", whitespace_boundary).

split_leading_flush(Text) ->
    split_leading_keyword(Text, "FLUSH", whitespace_boundary).

split_leading_buffer(Text) ->
    split_leading_keyword(Text, "BUFFER", whitespace_boundary).

split_leading_sleep(Text) ->
    split_leading_keyword(Text, "SLEEP", whitespace_boundary).

split_leading_sound(Text) ->
    split_leading_keyword(Text, "SOUND", whitespace_boundary).

split_leading_play(Text) ->
    split_leading_keyword(Text, "PLAY", whitespace_boundary).

split_leading_chain(Text) ->
    split_leading_keyword(Text, "CHAIN", whitespace_boundary).

split_leading_open(Text) ->
    split_leading_keyword(Text, "OPEN", whitespace_boundary).

split_leading_close(Text) ->
    split_leading_keyword(Text, "CLOSE", whitespace_boundary).

split_leading_field(Text) ->
    split_leading_keyword(Text, "FIELD", whitespace_boundary).

split_leading_put(Text) ->
    split_leading_keyword(Text, "PUT", whitespace_boundary).

split_leading_color(Text) ->
    split_leading_keyword(Text, "COLOR", whitespace_boundary).

split_leading_locate(Text) ->
    split_leading_keyword(Text, "LOCATE", whitespace_boundary).

split_leading_home(Text) ->
    split_leading_keyword(Text, "HOME", whitespace_boundary).

split_leading_pset(Text) ->
    split_leading_keyword(Text, "PSET", whitespace_boundary).

split_leading_linegfx(Text) ->
    split_leading_keyword(Text, "LINE", whitespace_boundary).

split_leading_lineto(Text) ->
    split_leading_keyword(Text, "LINETO", whitespace_boundary).

split_leading_rect(Text) ->
    split_leading_keyword(Text, "RECT", whitespace_boundary).

split_leading_circle(Text) ->
    split_leading_keyword(Text, "CIRCLE", whitespace_boundary).

split_leading_pget(Text) ->
    split_leading_keyword(Text, "PGET", whitespace_boundary).

split_leading_sprite(Text) ->
    split_leading_keyword(Text, "SPRITE", whitespace_boundary).

split_leading_prefix(Text, Prefix) ->
    Len = length(Text),
    PLen = length(Prefix),
    case Len < PLen of
        true ->
            nomatch;
        false ->
            Head = lists:sublist(Text, PLen),
            case string:to_upper(Head) =:= Prefix of
                false -> nomatch;
                true -> {match, lists:nthtail(PLen, Text)}
            end
    end.

split_implicit_let(Text) ->
    case re:run(Text, "^[A-Za-z][A-Za-z0-9_]*[\\$%&#]?(?:\\s*\\(.*\\))?\\s*=\\s*.+$", [{capture, none}]) of
        match -> {match, Text};
        nomatch -> nomatch
    end.

split_leading_keyword(Text, Keyword, BoundaryMode) ->
    Len = length(Text),
    KLen = length(Keyword),
    case Len < KLen of
        true ->
            nomatch;
        false ->
            Prefix = lists:sublist(Text, KLen),
            case string:to_upper(Prefix) =:= Keyword of
                false ->
                    nomatch;
                true ->
                    case Len =:= KLen of
                        true ->
                            {match, ""};
                        false ->
                            Next = lists:nth(KLen + 1, Text),
                            case is_keyword_boundary(Next, BoundaryMode) of
                                true -> {match, lists:nthtail(KLen, Text)};
                                false -> nomatch
                            end
                    end
            end
    end.

is_keyword_boundary($\s, _Mode) -> true;
is_keyword_boundary($\t, _Mode) -> true;
is_keyword_boundary($#, allow_hash_boundary) -> true;
is_keyword_boundary(_, _Mode) -> false.
