-module(erlbasic_eval).

-export([
    format_value/1,
    eval_expr/2,
    eval_expr/3,
    eval_expr_result/2,
    eval_expr_result/3,
    eval_condition_result/2,
    eval_condition_result/3,
    assign_target/4,
    declare_array/3,
    target_is_string/1,
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
                            Upper = string:to_upper(Trimmed),
                            case is_string_var(Upper) of
                                true -> {ok, maps:get(Upper, Vars, ""), Vars};
                                false -> {ok, maps:get(Upper, Vars, 0), Vars}
                            end;
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
    case erlbasic_eval_lexer:tokenize_expr(Expr) of
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
parse_term_rest(Value, [{kw, "MOD"} | Rest], Vars) ->
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
parse_primary([{kw, Name}, lparen | Rest], Vars) ->
    case parse_call_args(Rest, Vars) of
        {ok, Args, Next} ->
            eval_callable(Name, Args, Next, Vars);
        Error ->
            Error
    end;
parse_primary([{var, Name}, lparen | Rest], Vars) ->
    case parse_call_args(Rest, Vars) of
        {ok, Args, Next} ->
            eval_callable(Name, Args, Next, Vars);
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

eval_callable(Name, Args, Rest, Vars) ->
    UpperName = string:to_upper(Name),
    case maps:find(UpperName, current_user_funcs()) of
        {ok, {ArgVar, FnExpr}} ->
            eval_user_function(ArgVar, FnExpr, Args, Vars, Rest);
        error ->
            case erlbasic_eval_builtins:apply_math_function(UpperName, Args) of
                {ok, Value} ->
                    {ok, Value, Rest};
                {error, illegal_function_call} ->
                    case erlbasic_eval_builtins:is_builtin_function(UpperName) of
                        true ->
                            {error, illegal_function_call};
                        false ->
                            case erlbasic_eval_arrays:get_array_value(UpperName, Args, Vars) of
                                {ok, Value} -> {ok, Value, Rest};
                                {error, Reason} -> {error, Reason}
                            end
                    end;
                {error, Reason} ->
                    {error, Reason}
            end
    end.

assign_target({var_target, Var}, Value, Vars, _Funcs) ->
    {ok, maps:put(Var, Value, Vars)};
assign_target({array_target, Var, IndexExprs}, Value, Vars, Funcs) ->
    case eval_indices(IndexExprs, Vars, Funcs) of
        {ok, Indices} ->
            erlbasic_eval_arrays:put_array_value(Var, Indices, Value, Vars);
        {error, Reason} ->
            {error, Reason}
    end.

declare_array(Name, Dims, Vars) when is_list(Dims) ->
    case erlbasic_eval_arrays:normalize_dims(Dims) of
        {ok, Normalized} ->
            Arrays0 = erlbasic_eval_arrays:get_arrays(Vars),
            ArrayMeta = #{dims => Normalized, values => #{}},
            Arrays1 = maps:put(Name, ArrayMeta, Arrays0),
            {ok, erlbasic_eval_arrays:put_arrays(Vars, Arrays1)};
        error ->
            {error, illegal_function_call}
    end.

target_is_string({var_target, Var}) ->
    is_string_var(Var);
target_is_string({array_target, Var, _}) ->
    is_string_var(Var).

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

format_runtime_error(division_by_zero) ->
    "?DIVISION BY ZERO ERROR\r\n";
format_runtime_error(out_of_data) ->
    "?OUT OF DATA ERROR\r\n";
format_runtime_error(illegal_function_call) ->
    "?ILLEGAL FUNCTION CALL\r\n";
format_runtime_error(syntax_error) ->
    "?SYNTAX ERROR\r\n";
format_runtime_error(_) ->
    "?SYNTAX ERROR\r\n".

int_div(Left, Right) when is_integer(Left), is_integer(Right) ->
    Left div Right;
int_div(Left, Right) ->
    trunc(Left / Right).

eval_indices(IndexExprs, Vars, Funcs) ->
    eval_indices(IndexExprs, Vars, Funcs, []).

eval_indices([], _Vars, _Funcs, Acc) ->
    {ok, lists:reverse(Acc)};
eval_indices([Expr | Rest], Vars, Funcs, Acc) ->
    case eval_expr_result(Expr, Vars, Funcs) of
        {ok, Value, _} ->
            eval_indices(Rest, Vars, Funcs, [normalize_int(Value) | Acc]);
        {error, Reason, _} ->
            {error, Reason}
    end.

is_string_var(Name) when is_list(Name) ->
    Name =/= [] andalso lists:last(Name) =:= $$.

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