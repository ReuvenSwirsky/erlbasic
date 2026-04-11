Definitions.
WS = [\000-\s]+
HEX = 0[xX][0-9A-Fa-f]+
BADHEX = 0[xX]
FLOAT = ([0-9]+\.[0-9]*)|(\.[0-9]+)
INT = [0-9]+
ID = [A-Za-z][A-Za-z0-9_]*[\$%&#]?
STR = \"[^\"]*\"

Rules.
{WS} : skip_token.
\+ : {token, plus}.
\- : {token, minus}.
\* : {token, mul}.
\/ : {token, divi}.
[\134] : {token, intdiv}.
\^ : {token, pow}.
\, : {token, comma}.
\( : {token, lparen}.
\) : {token, rparen}.
{HEX} : {token, {num, hex_to_integer(string:substr(TokenChars, 3))}}.
{BADHEX} : {error, {invalid_hex_literal, TokenChars}}.
{FLOAT} :
    case safe_float(TokenChars) of
        {ok, Value} -> {token, {num, Value}};
        error -> {error, {invalid_float, TokenChars}}
    end.
{INT} : {token, {num, list_to_integer(TokenChars)}}.
{STR} : {token, {str, strip_quotes(TokenChars)}}.
{ID} :
    Upper = string:to_upper(TokenChars),
    case erlbasic_keywords:is_expr_keyword(Upper) of
        true -> {token, {kw, Upper}};
        false -> {token, {var, TokenChars}}
    end.

Erlang code.

hex_to_integer(HexChars) ->
    list_to_integer(HexChars, 16).

strip_quotes(TokenChars) ->
    Len = length(TokenChars),
    case Len of
        0 -> [];
        1 -> [];
        2 -> [];
        _ ->
            string:substr(TokenChars, 2, Len - 2)
    end.

safe_float(TokenChars) ->
    Normalized = normalize_float_text(TokenChars),
    try
        {ok, list_to_float(Normalized)}
    catch
        _:_ -> error
    end.

normalize_float_text(TokenChars) ->
    PrefixNormalized =
        case TokenChars of
            [$. | _] -> [$0 | TokenChars];
            _ -> TokenChars
        end,
    case lists:last(PrefixNormalized) of
        $. -> PrefixNormalized ++ "0";
        _ -> PrefixNormalized
    end.
