-module(erlbasic_eval_expr).

-export([eval_arith_expr/2]).

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
    case erlbasic_eval_arrays:is_string_var(Upper) of
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

eval_user_function(undefined, FnExpr, [], Vars, Rest) ->
    case erlbasic_eval:eval_expr_result(FnExpr, Vars) of
        {ok, Value, _} -> {ok, Value, Rest};
        {error, Reason, _} -> {error, Reason}
    end;
eval_user_function(undefined, _FnExpr, _Args, _Vars, _Rest) ->
    {error, illegal_function_call};
eval_user_function(ArgVar, FnExpr, [ArgValue], Vars, Rest) ->
    BoundVars = maps:put(ArgVar, ArgValue, Vars),
    case erlbasic_eval:eval_expr_result(FnExpr, BoundVars) of
        {ok, Value, _} -> {ok, Value, Rest};
        {error, Reason, _} -> {error, Reason}
    end;
eval_user_function(_ArgVar, _FnExpr, _Args, _Vars, _Rest) ->
    {error, illegal_function_call}.

int_div(Left, Right) when is_integer(Left), is_integer(Right) ->
    Left div Right;
int_div(Left, Right) ->
    trunc(Left / Right).

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
