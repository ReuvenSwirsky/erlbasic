-module(erlbasic_eval).

-export([
    format_value/1,
    format_print_value/1,
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
    format_runtime_error/1,
    format_runtime_error/2,
    error_code/1
]).

-define(VAR_REFERENCE_PATTERN, "^[A-Za-z][A-Za-z0-9_]*[\\$%]?$").

format_value(Value) when is_integer(Value) ->
    integer_to_list(Value) ++ "\r\n";
format_value(Value) when is_float(Value) ->
    format_number(Value) ++ "\r\n";
format_value(Value) when is_list(Value) ->
    Value ++ "\r\n".

format_print_value(Value) when is_integer(Value) ->
    integer_to_list(Value);
format_print_value(Value) when is_float(Value) ->
    format_number(Value);
format_print_value(Value) when is_list(Value) ->
    Value.

format_number(Value) when is_integer(Value) ->
    integer_to_list(Value);
format_number(Value) when is_float(Value) ->
    Abs = abs(Value),
    case (Abs >= 1.0e12) orelse (Abs =/= +0.0 andalso Abs < 1.0e-4) of
        true ->
            lists:flatten(io_lib:format("~.16e", [Value]));
        false ->
            Raw = lists:flatten(io_lib:format("~.10f", [Value])),
            ensure_float_text(trim_float_string(Raw))
    end.

trim_float_string(Text) ->
    trim_float_string_rev(lists:reverse(Text)).

ensure_float_text(Text) ->
    case lists:member($., Text) of
        true ->
            case lists:last(Text) of
                $. -> Text ++ "0";
                _ -> Text
            end;
        false ->
            Text ++ ".0"
    end.

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
    case re:run(Trimmed, "^\"([^\"]*)\"$", [{capture, [1], list}]) of
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
format_runtime_error(type_mismatch) ->
    "?TYPE MISMATCH ERROR\r\n";
format_runtime_error(cant_continue) ->
    "?CAN'T CONTINUE ERROR\r\n";
format_runtime_error(return_without_gosub) ->
    "?RETURN WITHOUT GOSUB ERROR\r\n";
format_runtime_error(next_without_for) ->
    "?NEXT WITHOUT FOR ERROR\r\n";
format_runtime_error(resume_without_error) ->
    "?RESUME WITHOUT ERROR\r\n";
format_runtime_error(tty_no_cursor_movement) ->
    "?TTY DOESN'T SUPPORT CURSOR MOVEMENT\r\n";
format_runtime_error(program_not_found) ->
    "?PROGRAM NOT FOUND\r\n";
format_runtime_error(syntax_error) ->
    "?SYNTAX ERROR\r\n";
format_runtime_error(_) ->
    "?SYNTAX ERROR\r\n".

%% Format runtime error with line number (for program execution)
format_runtime_error(Reason, LineNumber) when is_integer(LineNumber) ->
    ErrorType = case Reason of
        division_by_zero -> "DIVISION BY ZERO ERROR";
        out_of_data -> "OUT OF DATA ERROR";
        illegal_function_call -> "ILLEGAL FUNCTION CALL";
        type_mismatch -> "TYPE MISMATCH ERROR";
        cant_continue -> "CAN'T CONTINUE ERROR";
        return_without_gosub -> "RETURN WITHOUT GOSUB ERROR";
        next_without_for -> "NEXT WITHOUT FOR ERROR";
        resume_without_error -> "RESUME WITHOUT ERROR";
        tty_no_cursor_movement -> "TTY DOESN'T SUPPORT CURSOR MOVEMENT";
        program_not_found -> "PROGRAM NOT FOUND";
        syntax_error -> "SYNTAX ERROR";
        _ -> "SYNTAX ERROR"
    end,
    io_lib:format("?~s IN ~p\r\n", [ErrorType, LineNumber]);
format_runtime_error(Reason, _) ->
    format_runtime_error(Reason).

%% Map error reasons to ERR codes (GW-BASIC compatible)
error_code(division_by_zero) -> 11;
error_code(out_of_data) -> 4;
error_code(illegal_function_call) -> 5;
error_code(type_mismatch) -> 13;
error_code(cant_continue) -> 17;
error_code(return_without_gosub) -> 3;
error_code(next_without_for) -> 1;
error_code(resume_without_error) -> 20;
error_code(syntax_error) -> 2;
error_code(_) -> 255.  % Unknown error

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