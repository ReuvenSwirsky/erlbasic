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
                            case erlbasic_eval_arrays:is_string_var(Upper) of
                                true -> {ok, maps:get(Upper, Vars, ""), Vars};
                                false -> {ok, maps:get(Upper, Vars, 0), Vars}
                            end;
                        nomatch ->
                            case erlbasic_eval_expr:eval_arith_expr(Trimmed, Vars) of
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

with_user_funcs(Funcs, Fun) ->
    Prev = get(erlbasic_user_funcs),
    put(erlbasic_user_funcs, Funcs),
    try
        Fun()
    after
        put(erlbasic_user_funcs, Prev)
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
    erlbasic_eval_arrays:is_string_var(Var);
target_is_string({array_target, Var, _}) ->
    erlbasic_eval_arrays:is_string_var(Var).

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

normalize_int(Value) when is_integer(Value) ->
    Value;
normalize_int(Value) when is_list(Value) ->
    case string:to_integer(string:trim(Value)) of
        {Int, ""} -> Int;
        _ -> 0
    end;
normalize_int(_) ->
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