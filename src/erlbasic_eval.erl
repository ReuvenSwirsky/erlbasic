-module(erlbasic_eval).

-export([
    format_value/1,
    eval_expr/2,
    eval_expr/3,
    eval_expr_result/2,
    eval_expr_result/3,
    eval_condition_result/2,
    eval_condition_result/3,
    normalize_int/1,
    format_runtime_error/1
]).

-define(VAR_REFERENCE_PATTERN, "^[A-Za-z][A-Za-z0-9_]*[\\$%]?$").

format_value(Value) when is_integer(Value) ->
    integer_to_list(Value) ++ "\r\n";
format_value(Value) when is_float(Value) ->
    format_number(Value) ++ "\r\n";
format_value(Value) when is_list(Value) ->
    Value ++ "\r\n".

format_number(Value) when is_integer(Value) ->
    integer_to_list(Value);
format_number(Value) when is_float(Value) ->
    Rounded = round(Value),
    case abs(Value - Rounded) < 1.0e-10 of
        true ->
            integer_to_list(Rounded);
        false ->
            Raw = lists:flatten(io_lib:format("~.10f", [Value])),
            trim_float_string(Raw)
    end.

trim_float_string(Text) ->
    trim_float_string_rev(lists:reverse(Text)).

trim_float_string_rev([$0 | Rest]) ->
    trim_float_string_rev(Rest);
trim_float_string_rev([$. | Rest]) ->
    lists:reverse(Rest);
trim_float_string_rev(Rest) ->
    lists:reverse(Rest).

eval_expr(Expr, Vars) ->
    eval_expr(Expr, Vars, #{}).

eval_expr(Expr, Vars, Funcs) ->
    with_user_funcs(Funcs,
        fun() ->
            case eval_expr_result(Expr, Vars) of
                {ok, Value, NextVars} ->
                    {Value, NextVars};
                {error, _Reason, NextVars} ->
                    {0, NextVars}
            end
        end).

eval_expr_result(Expr, Vars) ->
    Trimmed = string:trim(Expr),
    case re:run(Trimmed, "^\"(.*)\"$", [{capture, [1], list}]) of
        {match, [StringValue]} ->
            {ok, StringValue, Vars};
        nomatch ->
            case string:to_integer(Trimmed) of
                {Int, ""} ->
                    {ok, Int, Vars};
                _ ->
                    case re:run(Trimmed, ?VAR_REFERENCE_PATTERN, [{capture, none}]) of
                        match ->
                            {ok, maps:get(string:to_upper(Trimmed), Vars, 0), Vars};
                        nomatch ->
                            case eval_arith_expr(Trimmed, Vars) of
                                {ok, NumValue} ->
                                    {ok, NumValue, Vars};
                                {error, Reason} ->
                                    {error, Reason, Vars}
                            end
                    end
            end
    end.

eval_expr_result(Expr, Vars, Funcs) ->
    with_user_funcs(Funcs,
        fun() ->
            eval_expr_result(Expr, Vars)
        end).

eval_arith_expr(Expr, Vars) ->
    case tokenize_expr(Expr) of
        {ok, Tokens} ->
            case parse_sum(Tokens, Vars) of
                {ok, Value, []} ->
                    {ok, Value};
                {error, Reason} ->
                    {error, Reason};
                _ ->
                    {error, syntax_error}
            end;
        error ->
            {error, syntax_error}
    end.

with_user_funcs(Funcs, Fun) ->
    Prev = get(erlbasic_user_funcs),
    put(erlbasic_user_funcs, Funcs),
    try
        Fun()
    after
        put(erlbasic_user_funcs, Prev)
    end.

current_user_funcs() ->
    case get(erlbasic_user_funcs) of
        undefined -> #{};
        Funcs when is_map(Funcs) -> Funcs;
        _ -> #{}
    end.

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
            true -> {num, list_to_float(NumberChars)};
            false -> {num, list_to_integer(NumberChars)}
        end,
    tokenize_expr(Tail, [NumberToken | Acc]);
tokenize_expr([$. | Rest], Acc) ->
    case Rest of
        [Next | _] when Next >= $0, Next =< $9 ->
            {NumberChars, _HasDot, Tail} = read_number([$. | Rest], [], false),
            tokenize_expr(Tail, [{num, list_to_float(NumberChars)} | Acc]);
        _ ->
            error
    end;
tokenize_expr([Ch | Rest], Acc) when (Ch >= $A andalso Ch =< $Z) orelse (Ch >= $a andalso Ch =< $z) ->
    {NameChars, Tail} = read_identifier(Rest, [Ch]),
    Token =
        case string:to_upper(NameChars) of
            "MOD" -> mod;
            _ -> {var, NameChars}
        end,
    tokenize_expr(Tail, [Token | Acc]);
tokenize_expr(_, _Acc) ->
    error.

read_number([Ch | Rest], Acc, HasDot) when Ch >= $0, Ch =< $9 ->
    read_number(Rest, [Ch | Acc], HasDot);
read_number([$. | Rest], Acc, false) ->
    read_number(Rest, [$. | Acc], true);
read_number(Rest, Acc, HasDot) ->
    {lists:reverse(Acc), HasDot, Rest}.

read_string([$" | Rest], Acc) ->
    {ok, lists:reverse(Acc), Rest};
read_string([Ch | Rest], Acc) ->
    read_string(Rest, [Ch | Acc]);
read_string([], _Acc) ->
    error.

read_identifier([Ch | Rest], Acc) when (Ch >= $A andalso Ch =< $Z) orelse (Ch >= $a andalso Ch =< $z) orelse (Ch >= $0 andalso Ch =< $9) orelse Ch =:= $_ ->
    read_identifier(Rest, Acc ++ [Ch]);
read_identifier([Suffix | Rest], Acc) when Suffix =:= $$; Suffix =:= $% ->
    {Acc ++ [Suffix], Rest};
read_identifier(Rest, Acc) ->
    {Acc, Rest}.

parse_sum(Tokens, Vars) ->
    case parse_term(Tokens, Vars) of
        {ok, Value, Rest} -> parse_sum_rest(Value, Rest, Vars);
        Error -> Error
    end.

parse_sum_rest(Value, [plus | Rest], Vars) ->
    case parse_term(Rest, Vars) of
        {ok, Right, Next} -> parse_sum_rest(Value + Right, Next, Vars);
        Error -> Error
    end;
parse_sum_rest(Value, [minus | Rest], Vars) ->
    case parse_term(Rest, Vars) of
        {ok, Right, Next} -> parse_sum_rest(Value - Right, Next, Vars);
        Error -> Error
    end;
parse_sum_rest(Value, Rest, _Vars) ->
    {ok, Value, Rest}.

parse_term(Tokens, Vars) ->
    case parse_unary(Tokens, Vars) of
        {ok, Value, Rest} -> parse_term_rest(Value, Rest, Vars);
        Error -> Error
    end.

parse_term_rest(Value, [mul | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, Right, Next} -> parse_term_rest(Value * Right, Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, [divi | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, 0, _Next} -> {error, division_by_zero};
        {ok, Right, Next} -> parse_term_rest(Value / Right, Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, [intdiv | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, 0, _Next} -> {error, division_by_zero};
        {ok, Right, Next} -> parse_term_rest(int_div(Value, Right), Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, [mod | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, 0, _Next} -> {error, division_by_zero};
        {ok, Right, Next} -> parse_term_rest(Value rem Right, Next, Vars);
        Error -> Error
    end;
parse_term_rest(Value, Rest, _Vars) ->
    {ok, Value, Rest}.

parse_unary([plus | Rest], Vars) ->
    parse_unary(Rest, Vars);
parse_unary([minus | Rest], Vars) ->
    case parse_unary(Rest, Vars) of
        {ok, Value, Next} -> {ok, -Value, Next};
        Error -> Error
    end;
parse_unary(Tokens, Vars) ->
    parse_power(Tokens, Vars).

parse_power(Tokens, Vars) ->
    case parse_primary(Tokens, Vars) of
        {ok, Left, [pow | Rest]} ->
            case parse_power(Rest, Vars) of
                {ok, Right, Next} -> {ok, math:pow(Left, Right), Next};
                Error -> Error
            end;
        Result ->
            Result
    end.

parse_primary([{num, Value} | Rest], _Vars) ->
    {ok, Value, Rest};
parse_primary([{str, Value} | Rest], _Vars) ->
    {ok, Value, Rest};
parse_primary([{var, Name}, lparen | Rest], Vars) ->
    case parse_call_args(Rest, Vars) of
        {ok, Args, Next} ->
            eval_builtin_call(Name, Args, Next, Vars);
        Error ->
            Error
    end;
parse_primary([{var, Name} | Rest], Vars) ->
    Upper = string:to_upper(Name),
    case is_string_var(Upper) of
        true ->
            {ok, maps:get(Upper, Vars, ""), Rest};
        false ->
            Raw = maps:get(Upper, Vars, 0),
            {ok, normalize_number(Raw), Rest}
    end;
parse_primary([lparen | Rest], Vars) ->
    case parse_sum(Rest, Vars) of
        {ok, Value, [rparen | Next]} -> {ok, Value, Next};
        _ -> error
    end;
parse_primary(_Tokens, _Vars) ->
    error.

parse_call_args([rparen | Rest], _Vars) ->
    {ok, [], Rest};
parse_call_args(Tokens, Vars) ->
    parse_call_args(Tokens, Vars, []).

parse_call_args(Tokens, Vars, Acc) ->
    case parse_sum(Tokens, Vars) of
        {ok, Value, [comma | Rest]} ->
            parse_call_args(Rest, Vars, [Value | Acc]);
        {ok, Value, [rparen | Rest]} ->
            {ok, lists:reverse([Value | Acc]), Rest};
        _ ->
            error
    end.

eval_builtin_call(Name, Args, Rest, Vars) ->
    UpperName = string:to_upper(Name),
    case maps:find(UpperName, current_user_funcs()) of
        {ok, {ArgVar, FnExpr}} ->
            eval_user_function(ArgVar, FnExpr, Args, Vars, Rest);
        error ->
            case apply_math_function(UpperName, Args) of
                {ok, Value} ->
                    {ok, Value, Rest};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

eval_user_function(undefined, FnExpr, [], Vars, Rest) ->
    case eval_expr_result(FnExpr, Vars) of
        {ok, Value, _} -> {ok, Value, Rest};
        {error, Reason, _} -> {error, Reason}
    end;
eval_user_function(undefined, _FnExpr, _Args, _Vars, _Rest) ->
    {error, illegal_function_call};
eval_user_function(ArgVar, FnExpr, [ArgValue], Vars, Rest) ->
    BoundVars = maps:put(ArgVar, ArgValue, Vars),
    case eval_expr_result(FnExpr, BoundVars) of
        {ok, Value, _} -> {ok, Value, Rest};
        {error, Reason, _} -> {error, Reason}
    end;
eval_user_function(_ArgVar, _FnExpr, _Args, _Vars, _Rest) ->
    {error, illegal_function_call}.

apply_math_function("ABS", [X]) ->
    {ok, abs(X)};
apply_math_function("ACOS", [X]) ->
    safe_math(fun() -> math:acos(X) end);
apply_math_function("ASIN", [X]) ->
    safe_math(fun() -> math:asin(X) end);
apply_math_function("ATAN", [X]) ->
    {ok, math:atan(X)};
apply_math_function("ATN", [X]) ->
    {ok, math:atan(X)};
apply_math_function("ATAN2", [Y, X]) ->
    {ok, math:atan2(Y, X)};
apply_math_function("COS", [X]) ->
    {ok, math:cos(X)};
apply_math_function("DEG", [X]) ->
    {ok, X * 180.0 / math:pi()};
apply_math_function("EXP", [X]) ->
    {ok, math:exp(X)};
apply_math_function("FIX", [X]) ->
    {ok, trunc(X)};
apply_math_function("INT", [X]) ->
    {ok, floor_number(X)};
apply_math_function("LN", [X]) ->
    safe_math(fun() -> math:log(X) end);
apply_math_function("LOG", [X]) ->
    safe_math(fun() -> math:log(X) end);
apply_math_function("PI", []) ->
    {ok, math:pi()};
apply_math_function("POW", [X, Y]) ->
    {ok, math:pow(X, Y)};
apply_math_function("RAD", [X]) ->
    {ok, X * math:pi() / 180.0};
apply_math_function("RND", []) ->
    gw_rnd();
apply_math_function("RND", [X]) ->
    gw_rnd(X);
apply_math_function("DATE$", []) ->
    {ok, basic_date()};
apply_math_function("TIME$", []) ->
    {ok, basic_time()};
apply_math_function("SGN", [X]) when X < 0 ->
    {ok, -1};
apply_math_function("SGN", [0]) ->
    {ok, 0};
apply_math_function("SGN", [_X]) ->
    {ok, 1};
apply_math_function("SIN", [X]) ->
    {ok, math:sin(X)};
apply_math_function("SQR", [X]) ->
    safe_math(fun() -> math:sqrt(X) end);
apply_math_function("SQRT", [X]) ->
    safe_math(fun() -> math:sqrt(X) end);
apply_math_function("TAN", [X]) ->
    {ok, math:tan(X)};
apply_math_function("LEFT$", [Text, Count]) ->
    apply_left(Text, Count);
apply_math_function("RIGHT$", [Text, Count]) ->
    apply_right(Text, Count);
apply_math_function("MID$", [Text, Start]) ->
    apply_mid(Text, Start);
apply_math_function("MID$", [Text, Start, Count]) ->
    apply_mid(Text, Start, Count);
apply_math_function("LEN", [Text]) ->
    apply_len(Text);
apply_math_function(_, _Args) ->
    {error, illegal_function_call}.

safe_math(Fun) ->
    try
        {ok, Fun()}
    catch
        error:badarith -> {error, illegal_function_call}
    end.

format_runtime_error(division_by_zero) ->
    "?DIVISION BY ZERO ERROR\r\n";
format_runtime_error(illegal_function_call) ->
    "?ILLEGAL FUNCTION CALL\r\n";
format_runtime_error(syntax_error) ->
    "?SYNTAX ERROR\r\n";
format_runtime_error(_) ->
    "?SYNTAX ERROR\r\n".

floor_number(X) when is_integer(X) ->
    X;
floor_number(X) when is_float(X) ->
    T = trunc(X),
    case X < T of
        true -> T - 1;
        false -> T
    end.

int_div(Left, Right) when is_integer(Left), is_integer(Right) ->
    Left div Right;
int_div(Left, Right) ->
    trunc(Left / Right).

gw_rnd() ->
    Value = rand:uniform(),
    put(gw_rnd_last, Value),
    {ok, Value}.

gw_rnd(X) when X < 0 ->
    SeedBase = erlang:phash2({gw_seed, X}, 16#7ffffffe) + 1,
    Seed2 = ((SeedBase * 1103515245) band 16#7fffffff) + 1,
    Seed3 = ((SeedBase * 12345) band 16#7fffffff) + 1,
    _ = rand:seed(exsplus, {SeedBase, Seed2, Seed3}),
    gw_rnd();
gw_rnd(X) when X =:= 0; X =:= +0.0 ->
    case get(gw_rnd_last) of
        undefined -> gw_rnd();
        Value -> {ok, Value}
    end;
gw_rnd(_X) ->
    gw_rnd().

basic_date() ->
    {{Year, Month, Day}, _} = calendar:local_time(),
    lists:flatten(io_lib:format("~2..0B-~2..0B-~4..0B", [Month, Day, Year])).

basic_time() ->
    {_, {Hour, Minute, Second}} = calendar:local_time(),
    lists:flatten(io_lib:format("~2..0B:~2..0B:~2..0B", [Hour, Minute, Second])).

is_string_var(Name) when is_list(Name) ->
    Name =/= [] andalso lists:last(Name) =:= $$.

apply_left(Text, Count) ->
    Str = to_basic_string(Text),
    case normalize_int_arg(Count) of
        {ok, N} when N =< 0 ->
            {ok, ""};
        {ok, N} ->
            {ok, lists:sublist(Str, N)};
        error ->
            {error, illegal_function_call}
    end.

apply_right(Text, Count) ->
    Str = to_basic_string(Text),
    case normalize_int_arg(Count) of
        {ok, N} when N =< 0 ->
            {ok, ""};
        {ok, N} ->
            Len = length(Str),
            case N >= Len of
                true -> {ok, Str};
                false -> {ok, lists:nthtail(Len - N, Str)}
            end;
        error ->
            {error, illegal_function_call}
    end.

apply_mid(Text, Start) ->
    apply_mid(Text, Start, length(to_basic_string(Text))).

apply_mid(Text, Start, Count) ->
    Str = to_basic_string(Text),
    case {normalize_int_arg(Start), normalize_int_arg(Count)} of
        {{ok, StartPos}, {ok, N}} when StartPos < 1; N < 0 ->
            {error, illegal_function_call};
        {{ok, _StartPos}, {ok, 0}} ->
            {ok, ""};
        {{ok, StartPos}, {ok, N}} ->
            Len = length(Str),
            case StartPos > Len of
                true ->
                    {ok, ""};
                false ->
                    Tail = lists:nthtail(StartPos - 1, Str),
                    {ok, lists:sublist(Tail, N)}
            end;
        _ ->
            {error, illegal_function_call}
    end.

apply_len(Text) ->
    {ok, length(to_basic_string(Text))}.

normalize_int_arg(Value) when is_integer(Value) ->
    {ok, Value};
normalize_int_arg(Value) when is_float(Value) ->
    {ok, trunc(Value)};
normalize_int_arg(_) ->
    error.

to_basic_string(Value) when is_list(Value) ->
    Value;
to_basic_string(Value) when is_integer(Value) ->
    integer_to_list(Value);
to_basic_string(Value) when is_float(Value) ->
    format_number(Value);
to_basic_string(Value) ->
    lists:flatten(io_lib:format("~p", [Value])).

normalize_int(Value) when is_integer(Value) ->
    Value;
normalize_int(Value) when is_list(Value) ->
    case string:to_integer(string:trim(Value)) of
        {Int, ""} -> Int;
        _ -> 0
    end;
normalize_int(_) ->
    0.

normalize_number(Value) when is_integer(Value); is_float(Value) ->
    Value;
normalize_number(Value) when is_list(Value) ->
    Trimmed = string:trim(Value),
    case string:to_float(Trimmed) of
        {Float, ""} -> Float;
        _ ->
            case string:to_integer(Trimmed) of
                {Int, ""} -> Int;
                _ -> 0
            end
    end;
normalize_number(_) ->
    0.

eval_condition_result(CondExpr, Vars) ->
    Trimmed = string:trim(CondExpr),
    case re:run(Trimmed, "^(.*?)(<=|>=|<>|=|<|>)(.*)$", [{capture, [1, 2, 3], list}]) of
        {match, [LeftExpr, Op, RightExpr]} ->
            case eval_expr_result(LeftExpr, Vars) of
                {error, Reason, _} ->
                    {error, Reason};
                {ok, LeftVal, _} ->
                    case eval_expr_result(RightExpr, Vars) of
                        {error, Reason, _} ->
                            {error, Reason};
                        {ok, RightVal, _} ->
                            {ok, compare_values(LeftVal, RightVal, Op)}
                    end
            end;
        nomatch ->
            case eval_expr_result(Trimmed, Vars) of
                {error, Reason, _} ->
                    {error, Reason};
                {ok, Value, _} ->
                    {ok, truthy(Value)}
            end
    end.

eval_condition_result(CondExpr, Vars, Funcs) ->
    with_user_funcs(Funcs,
        fun() ->
            eval_condition_result(CondExpr, Vars)
        end).

truthy(Value) when is_integer(Value) ->
    Value =/= 0;
truthy(Value) when is_float(Value) ->
    Value =/= +0.0;
truthy(Value) when is_list(Value) ->
    string:trim(Value) =/= "";
truthy(_) ->
    false.

compare_values(LeftVal, RightVal, Op)
    when (is_integer(LeftVal) orelse is_float(LeftVal)) andalso
         (is_integer(RightVal) orelse is_float(RightVal)) ->
    case Op of
        "=" -> LeftVal =:= RightVal;
        "<>" -> LeftVal =/= RightVal;
        "<" -> LeftVal < RightVal;
        ">" -> LeftVal > RightVal;
        "<=" -> LeftVal =< RightVal;
        ">=" -> LeftVal >= RightVal
    end;
compare_values(LeftVal, RightVal, Op) ->
    L = to_string_value(LeftVal),
    R = to_string_value(RightVal),
    case Op of
        "=" -> L =:= R;
        "<>" -> L =/= R;
        "<" -> L < R;
        ">" -> L > R;
        "<=" -> L =< R;
        ">=" -> L >= R
    end.

to_string_value(Value) when is_list(Value) ->
    Value;
to_string_value(Value) when is_integer(Value) ->
    integer_to_list(Value);
to_string_value(Value) when is_float(Value) ->
    format_number(Value);
to_string_value(Value) ->
    lists:flatten(io_lib:format("~p", [Value])).