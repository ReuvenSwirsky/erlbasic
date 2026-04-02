-module(erlbasic_eval_lexer).

-export([tokenize_expr/1]).

-define(EXPR_KEYWORDS, [
    "ABS", "ACOS", "ASIN", "ATAN", "ATN", "ATAN2", "COS", "DEG", "EXP", "FIX", "INT", "LN", "LOG",
    "PI", "POW", "RAD", "RND", "SGN", "SIN", "SQR", "SQRT", "TAN", "FLOOR", "CEIL", "VAL", "MOD",
    "LEFT$", "RIGHT$", "MID$", "LEN", "ASC", "CHR$", "STR$", "DATE$", "TIME$", "TERM$",
    "AND", "OR", "NOT", "XOR"
]).

tokenize_expr(Text) ->
    tokenize_expr(Text, []).

tokenize_expr([], Acc) ->
    {ok, lists:reverse(Acc)};
tokenize_expr([Ch | Rest], Acc) when Ch =:= $\s; Ch =:= $\t ->
    tokenize_expr(Rest, Acc);
tokenize_expr([$+ | Rest], Acc) ->
    tokenize_expr(Rest, [plus | Acc]);
tokenize_expr([$- | Rest], Acc) ->
    tokenize_expr(Rest, [minus | Acc]);
tokenize_expr([$* | Rest], Acc) ->
    tokenize_expr(Rest, [mul | Acc]);
tokenize_expr([$/ | Rest], Acc) ->
    tokenize_expr(Rest, [divi | Acc]);
tokenize_expr([$\\ | Rest], Acc) ->
    tokenize_expr(Rest, [intdiv | Acc]);
tokenize_expr([$^ | Rest], Acc) ->
    tokenize_expr(Rest, [pow | Acc]);
tokenize_expr([$, | Rest], Acc) ->
    tokenize_expr(Rest, [comma | Acc]);
tokenize_expr([$( | Rest], Acc) ->
    tokenize_expr(Rest, [lparen | Acc]);
tokenize_expr([$) | Rest], Acc) ->
    tokenize_expr(Rest, [rparen | Acc]);
tokenize_expr([$" | Rest], Acc) ->
    case read_string(Rest, []) of
        {ok, StringChars, Tail} ->
            tokenize_expr(Tail, [{str, StringChars} | Acc]);
        error ->
            error
    end;
tokenize_expr([Ch | Rest], Acc) when Ch >= $0, Ch =< $9 ->
    {NumberChars, HasDot, Tail} = read_number([Ch | Rest], [], false),
    NumberToken =
        case HasDot of
            true -> {num, list_to_float(normalize_float_text(NumberChars))};
            false -> {num, list_to_integer(NumberChars)}
        end,
    tokenize_expr(Tail, [NumberToken | Acc]);
tokenize_expr([$. | Rest], Acc) ->
    case Rest of
        [Next | _] when Next >= $0, Next =< $9 ->
            {NumberChars, _HasDot, Tail} = read_number([$. | Rest], [], false),
            tokenize_expr(Tail, [{num, list_to_float(normalize_float_text(NumberChars))} | Acc]);
        _ ->
            error
    end;
tokenize_expr([Ch | Rest], Acc) when (Ch >= $A andalso Ch =< $Z) orelse (Ch >= $a andalso Ch =< $z) ->
    {NameChars, Tail} = read_identifier(Rest, [Ch]),
    Token = keyword_or_var_token(NameChars),
    tokenize_expr(Tail, [Token | Acc]);
tokenize_expr(_, _Acc) ->
    error.

keyword_or_var_token(NameChars) ->
    Upper = string:to_upper(NameChars),
    case lists:member(Upper, ?EXPR_KEYWORDS) of
        true -> {kw, Upper};
        false -> {var, NameChars}
    end.

read_number([Ch | Rest], Acc, HasDot) when Ch >= $0, Ch =< $9 ->
    read_number(Rest, [Ch | Acc], HasDot);
read_number([$. | Rest], Acc, false) ->
    read_number(Rest, [$. | Acc], true);
read_number(Rest, Acc, HasDot) ->
    {lists:reverse(Acc), HasDot, Rest}.

normalize_float_text([$. | _] = NumberChars) ->
    [$0 | NumberChars];
normalize_float_text(NumberChars) ->
    NumberChars.

read_string([$" | Rest], Acc) ->
    {ok, lists:reverse(Acc), Rest};
read_string([Ch | Rest], Acc) ->
    read_string(Rest, [Ch | Acc]);
read_string([], _Acc) ->
    error.

read_identifier([Ch | Rest], Acc) when (Ch >= $A andalso Ch =< $Z) orelse (Ch >= $a andalso Ch =< $z) orelse (Ch >= $0 andalso Ch =< $9) orelse Ch =:= $_ ->
    read_identifier(Rest, Acc ++ [Ch]);
read_identifier([Suffix | Rest], Acc) when Suffix =:= $$; Suffix =:= $%; Suffix =:= $& ->
    {Acc ++ [Suffix], Rest};
read_identifier(Rest, Acc) ->
    {Acc, Rest}.
