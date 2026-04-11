-module(erlbasic_parser_yecc_lexer).

-export([tokenize_statement/1]).

tokenize_statement(Text0) when is_list(Text0) ->
    Text = string:trim(Text0),
    case classify_statement(Text) of
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
