-module(erlbasic_eval_expr).

-export([eval_arith_expr/2, is_user_fn_name/1]).
-define(MAX_INT_POW_BITS, 8192).

eval_arith_expr(Expr, Vars) ->
    case compile_expr_cached(Expr) of
        {ok, Ast} ->
            eval_ast(Ast, Vars);
        {error, Reason} ->
            {error, Reason}
    end.

compile_expr_cached(Expr) ->
    Cache0 =
        case get(expr_parse_cache) of
            undefined -> #{};
            Cache when is_map(Cache) -> Cache;
            _ -> #{}
        end,
    case maps:find(Expr, Cache0) of
        {ok, Compiled} ->
            Compiled;
        error ->
            Compiled = compile_expr(Expr),
            put(expr_parse_cache, maps:put(Expr, Compiled, Cache0)),
            Compiled
    end.

compile_expr(Expr) ->
    case erlbasic_eval_lexer:tokenize_expr(Expr) of
        {ok, Tokens} ->
            case parse_or(Tokens) of
                {ok, Ast, []} ->
                    {ok, Ast};
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

parse_or(Tokens) ->
    case parse_xor(Tokens) of
        {ok, Ast, Rest} -> parse_or_rest(Ast, Rest);
        Error -> Error
    end.

parse_or_rest(Ast, [{kw, "OR"} | Rest]) ->
    case parse_xor(Rest) of
        {ok, Right, Next} -> parse_or_rest({'or', Ast, Right}, Next);
        Error -> Error
    end;
parse_or_rest(Ast, Rest) ->
    {ok, Ast, Rest}.

parse_xor(Tokens) ->
    case parse_and(Tokens) of
        {ok, Ast, Rest} -> parse_xor_rest(Ast, Rest);
        Error -> Error
    end.

parse_xor_rest(Ast, [{kw, "XOR"} | Rest]) ->
    case parse_and(Rest) of
        {ok, Right, Next} -> parse_xor_rest({'xor', Ast, Right}, Next);
        Error -> Error
    end;
parse_xor_rest(Ast, Rest) ->
    {ok, Ast, Rest}.

parse_and(Tokens) ->
    case parse_not(Tokens) of
        {ok, Ast, Rest} -> parse_and_rest(Ast, Rest);
        Error -> Error
    end.

parse_and_rest(Ast, [{kw, "AND"} | Rest]) ->
    case parse_not(Rest) of
        {ok, Right, Next} -> parse_and_rest({'and', Ast, Right}, Next);
        Error -> Error
    end;
parse_and_rest(Ast, Rest) ->
    {ok, Ast, Rest}.

parse_not([{kw, "NOT"} | Rest]) ->
    case parse_not(Rest) of
        {ok, Ast, Next} -> {ok, {'not', Ast}, Next};
        Error -> Error
    end;
parse_not(Tokens) ->
    parse_sum(Tokens).

parse_sum(Tokens) ->
    case parse_term(Tokens) of
        {ok, Ast, Rest} -> parse_sum_rest(Ast, Rest);
        Error -> Error
    end.

parse_sum_rest(Ast, [plus | Rest]) ->
    case parse_term(Rest) of
        {ok, Right, Next} -> parse_sum_rest({plus, Ast, Right}, Next);
        Error -> Error
    end;
parse_sum_rest(Ast, [minus | Rest]) ->
    case parse_term(Rest) of
        {ok, Right, Next} -> parse_sum_rest({minus, Ast, Right}, Next);
        Error -> Error
    end;
parse_sum_rest(Ast, Rest) ->
    {ok, Ast, Rest}.

parse_term(Tokens) ->
    case parse_unary(Tokens) of
        {ok, Ast, Rest} -> parse_term_rest(Ast, Rest);
        Error -> Error
    end.

parse_term_rest(Ast, [mul | Rest]) ->
    case parse_unary(Rest) of
        {ok, Right, Next} -> parse_term_rest({mul, Ast, Right}, Next);
        Error -> Error
    end;
parse_term_rest(Ast, [divi | Rest]) ->
    case parse_unary(Rest) of
        {ok, Right, Next} -> parse_term_rest({divi, Ast, Right}, Next);
        Error -> Error
    end;
parse_term_rest(Ast, [intdiv | Rest]) ->
    case parse_unary(Rest) of
        {ok, Right, Next} -> parse_term_rest({intdiv, Ast, Right}, Next);
        Error -> Error
    end;
parse_term_rest(Ast, [{kw, "MOD"} | Rest]) ->
    case parse_unary(Rest) of
        {ok, Right, Next} -> parse_term_rest({'mod', Ast, Right}, Next);
        Error -> Error
    end;
parse_term_rest(Ast, Rest) ->
    {ok, Ast, Rest}.

parse_unary([plus | Rest]) ->
    parse_unary(Rest);
parse_unary([minus | Rest]) ->
    case parse_unary(Rest) of
        {ok, Ast, Next} -> {ok, {neg, Ast}, Next};
        Error -> Error
    end;
parse_unary(Tokens) ->
    parse_power(Tokens).

parse_power(Tokens) ->
    case parse_primary(Tokens) of
        {ok, Left, [pow | Rest]} ->
            case parse_power(Rest) of
                {ok, Right, Next} -> {ok, {pow, Left, Right}, Next};
                Error -> Error
            end;
        Result ->
            Result
    end.

parse_primary([{num, Value} | Rest]) ->
    {ok, {num, Value}, Rest};
parse_primary([{str, Value} | Rest]) ->
    {ok, {str, Value}, Rest};
parse_primary([{kw, Name}, lparen | Rest]) ->
    case parse_call_args(Rest) of
        {ok, Args, Next} -> {ok, {call, Name, Args}, Next};
        Error -> Error
    end;
parse_primary([{var, Name}, lparen | Rest]) ->
    case parse_call_args(Rest) of
        {ok, Args, Next} -> {ok, {call, string:to_upper(Name), Args}, Next};
        Error -> Error
    end;
parse_primary([{var, Name} | Rest]) ->
    {ok, {var, string:to_upper(Name)}, Rest};
parse_primary([lparen | Rest]) ->
    case parse_or(Rest) of
        {ok, Ast, [rparen | Next]} -> {ok, Ast, Next};
        _ -> {error, syntax_error}
    end;
parse_primary(_Tokens) ->
    {error, syntax_error}.

parse_call_args([rparen | Rest]) ->
    {ok, [], Rest};
parse_call_args(Tokens) ->
    parse_call_args(Tokens, []).

parse_call_args(Tokens, Acc) ->
    case parse_or(Tokens) of
        {ok, Ast, [comma | Rest]} ->
            parse_call_args(Rest, [Ast | Acc]);
        {ok, Ast, [rparen | Rest]} ->
            {ok, lists:reverse([Ast | Acc]), Rest};
        _ ->
            {error, syntax_error}
    end.

eval_ast({num, Value}, _Vars) ->
    {ok, Value};
eval_ast({str, Value}, _Vars) ->
    {ok, Value};
eval_ast({var, Name}, Vars) ->
    case erlbasic_eval_arrays:is_string_var(Name) of
        true ->
            {ok, maps:get(Name, Vars, "")};
        false ->
            {ok, normalize_number(maps:get(Name, Vars, 0))}
    end;
eval_ast({call, Name, ArgAsts}, Vars) ->
    case eval_ast_list(ArgAsts, Vars, []) of
        {ok, Args} ->
            eval_callable(Name, Args, Vars);
        Error ->
            Error
    end;
eval_ast({'or', Left, Right}, Vars) ->
    eval_binary(fun apply_logical_or/2, Left, Right, Vars);
eval_ast({'xor', Left, Right}, Vars) ->
    eval_binary(fun apply_logical_xor/2, Left, Right, Vars);
eval_ast({'and', Left, Right}, Vars) ->
    eval_binary(fun apply_logical_and/2, Left, Right, Vars);
eval_ast({'not', Expr}, Vars) ->
    case eval_ast(Expr, Vars) of
        {ok, Value} -> {ok, apply_logical_not(Value)};
        Error -> Error
    end;
eval_ast({plus, Left, Right}, Vars) ->
    eval_binary_result(fun add_values/2, Left, Right, Vars);
eval_ast({minus, Left, Right}, Vars) ->
    eval_numeric_binary(fun(L, R) -> L - R end, Left, Right, Vars);
eval_ast({mul, Left, Right}, Vars) ->
    eval_binary_result(fun mul_values/2, Left, Right, Vars);
eval_ast({divi, Left, Right}, Vars) ->
    eval_div_binary(Left, Right, Vars);
eval_ast({intdiv, Left, Right}, Vars) ->
    eval_intdiv_binary(Left, Right, Vars);
eval_ast({'mod', Left, Right}, Vars) ->
    eval_mod_binary(Left, Right, Vars);
eval_ast({pow, Left, Right}, Vars) ->
    eval_binary_result(fun pow_values/2, Left, Right, Vars);
eval_ast({neg, Expr}, Vars) ->
    case eval_ast(Expr, Vars) of
        {ok, Value} when is_integer(Value); is_float(Value) -> {ok, -Value};
        {ok, _Value} -> {error, type_mismatch};
        Error -> Error
    end.

eval_ast_list([], _Vars, Acc) ->
    {ok, lists:reverse(Acc)};
eval_ast_list([Ast | Rest], Vars, Acc) ->
    case eval_ast(Ast, Vars) of
        {ok, Value} -> eval_ast_list(Rest, Vars, [Value | Acc]);
        Error -> Error
    end.

eval_binary(Fun, Left, Right, Vars) ->
    case eval_ast(Left, Vars) of
        {ok, LeftValue} ->
            case eval_ast(Right, Vars) of
                {ok, RightValue} -> {ok, Fun(LeftValue, RightValue)};
                Error -> Error
            end;
        Error -> Error
    end.

eval_binary_result(Fun, Left, Right, Vars) ->
    case eval_ast(Left, Vars) of
        {ok, LeftValue} ->
            case eval_ast(Right, Vars) of
                {ok, RightValue} -> Fun(LeftValue, RightValue);
                Error -> Error
            end;
        Error -> Error
    end.

eval_numeric_binary(Fun, Left, Right, Vars) ->
    case eval_ast(Left, Vars) of
        {ok, LeftValue} when is_integer(LeftValue); is_float(LeftValue) ->
            case eval_ast(Right, Vars) of
                {ok, RightValue} when is_integer(RightValue); is_float(RightValue) ->
                    {ok, Fun(LeftValue, RightValue)};
                {ok, _Other} ->
                    {error, type_mismatch};
                Error ->
                    Error
            end;
        {ok, _Other} ->
            {error, type_mismatch};
        Error ->
            Error
    end.

eval_div_binary(Left, Right, Vars) ->
    case eval_ast(Left, Vars) of
        {ok, LeftValue} when is_integer(LeftValue); is_float(LeftValue) ->
            case eval_ast(Right, Vars) of
                {ok, 0} -> {error, division_by_zero};
                {ok, +0.0} -> {error, division_by_zero};
                {ok, RightValue} when is_integer(RightValue); is_float(RightValue) -> {ok, LeftValue / RightValue};
                {ok, _Other} -> {error, type_mismatch};
                Error -> Error
            end;
        {ok, _Other} -> {error, type_mismatch};
        Error -> Error
    end.

eval_intdiv_binary(Left, Right, Vars) ->
    case eval_ast(Left, Vars) of
        {ok, LeftValue} when is_integer(LeftValue); is_float(LeftValue) ->
            case eval_ast(Right, Vars) of
                {ok, 0} -> {error, division_by_zero};
                {ok, +0.0} -> {error, division_by_zero};
                {ok, RightValue} when is_integer(RightValue); is_float(RightValue) -> {ok, int_div(LeftValue, RightValue)};
                {ok, _Other} -> {error, type_mismatch};
                Error -> Error
            end;
        {ok, _Other} -> {error, type_mismatch};
        Error -> Error
    end.

eval_mod_binary(Left, Right, Vars) ->
    case eval_ast(Left, Vars) of
        {ok, LeftValue} when is_integer(LeftValue) ->
            case eval_ast(Right, Vars) of
                {ok, 0} -> {error, division_by_zero};
                {ok, RightValue} when is_integer(RightValue) -> {ok, LeftValue rem RightValue};
                {ok, _Other} -> {error, type_mismatch};
                Error -> Error
            end;
        {ok, _Other} -> {error, type_mismatch};
        Error -> Error
    end.

eval_callable(Name, Args, Vars) ->
    case maps:find(Name, current_user_funcs()) of
        {ok, {ArgVar, FnExpr}} ->
            eval_user_function(ArgVar, FnExpr, Args, Vars);
        error ->
            case is_user_fn_name(Name) of
                true ->
                    {error, undefined_function};
                false ->
            case erlbasic_eval_builtins:apply_math_function(Name, Args) of
                {ok, Value} ->
                    {ok, Value};
                {error, illegal_function_call} ->
                    case erlbasic_eval_builtins:is_builtin_function(Name) of
                        true ->
                            {error, illegal_function_call};
                        false ->
                            erlbasic_eval_arrays:get_array_value(Name, Args, Vars)
                    end;
                {error, Reason} ->
                    {error, Reason}
            end
            end
    end.

is_user_fn_name([$F, $N | Rest]) when Rest =/= [] ->
    lists:all(fun(C) ->
        (C >= $A andalso C =< $Z) orelse
        (C >= $0 andalso C =< $9) orelse
        C =:= $_ orelse
        C =:= $% orelse
        C =:= $& orelse
        C =:= $#
    end, Rest);
is_user_fn_name(_) ->
    false.

eval_user_function(undefined, FnExpr, [], Vars) ->
    case erlbasic_eval:eval_expr_result(FnExpr, Vars) of
        {ok, Value, _} -> {ok, Value};
        {error, Reason, _} -> {error, Reason}
    end;
eval_user_function(undefined, _FnExpr, _Args, _Vars) ->
    {error, illegal_function_call};
eval_user_function(ArgVar, FnExpr, [ArgValue], Vars) ->
    BoundVars = maps:put(ArgVar, ArgValue, Vars),
    case erlbasic_eval:eval_expr_result(FnExpr, BoundVars) of
        {ok, Value, _} -> {ok, Value};
        {error, Reason, _} -> {error, Reason}
    end;
eval_user_function(_ArgVar, _FnExpr, _Args, _Vars) ->
    {error, illegal_function_call}.

pow_values(Left, Right) when is_integer(Left), is_integer(Right), Right >= 0 ->
    safe_int_pow(Left, Right);
pow_values(Left, Right) when (is_integer(Left) orelse is_float(Left)) andalso
                            (is_integer(Right) orelse is_float(Right)) ->
    {ok, math:pow(Left, Right)};
pow_values(_Left, _Right) ->
    {error, type_mismatch}.

safe_int_pow(Base, Exp) ->
    case int_pow_too_large(Base, Exp) of
        true -> {error, range_exceeded};
        false -> {ok, int_pow(Base, Exp)}
    end.

int_pow(_Base, 0) ->
    1;
int_pow(Base, Exp) when Exp > 0 ->
    int_pow(Base, Exp, 1).

int_pow(_Base, 0, Acc) ->
    Acc;
int_pow(Base, Exp, Acc) when (Exp band 1) =:= 1 ->
    int_pow(Base * Base, Exp bsr 1, Acc * Base);
int_pow(Base, Exp, Acc) ->
    int_pow(Base * Base, Exp bsr 1, Acc).

int_pow_too_large(_Base, 0) ->
    false;
int_pow_too_large(0, _Exp) ->
    false;
int_pow_too_large(1, _Exp) ->
    false;
int_pow_too_large(-1, _Exp) ->
    false;
int_pow_too_large(Base, Exp) when Exp > 0 ->
    integer_bit_length(abs(Base)) * Exp > ?MAX_INT_POW_BITS.

integer_bit_length(0) ->
    0;
integer_bit_length(Int) when Int > 0 ->
    integer_bit_length(Int, 0).

integer_bit_length(0, Bits) ->
    Bits;
integer_bit_length(Int, Bits) ->
    integer_bit_length(Int bsr 1, Bits + 1).

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

add_values(Left, Right) when is_list(Left) andalso is_list(Right) ->
    {ok, Left ++ Right};
add_values(Left, Right) when (is_integer(Left) orelse is_float(Left)) andalso
                           (is_integer(Right) orelse is_float(Right)) ->
    {ok, Left + Right};
add_values(_Left, _Right) ->
    {error, type_mismatch}.

mul_values(Left, Right) when (is_integer(Left) orelse is_float(Left)) andalso
                           (is_integer(Right) orelse is_float(Right)) ->
    {ok, Left * Right};
mul_values(_Left, _Right) ->
    {error, type_mismatch}.

apply_logical_and(Left, Right) when is_integer(Left), is_integer(Right) ->
    Left band Right;
apply_logical_and(Left, Right) ->
    case (to_boolean(Left) andalso to_boolean(Right)) of
        true -> -1;
        false -> 0
    end.

apply_logical_or(Left, Right) when is_integer(Left), is_integer(Right) ->
    Left bor Right;
apply_logical_or(Left, Right) ->
    case (to_boolean(Left) orelse to_boolean(Right)) of
        true -> -1;
        false -> 0
    end.

apply_logical_xor(Left, Right) when is_integer(Left), is_integer(Right) ->
    Left bxor Right;
apply_logical_xor(Left, Right) ->
    case (to_boolean(Left) xor to_boolean(Right)) of
        true -> -1;
        false -> 0
    end.

apply_logical_not(Value) when is_integer(Value) ->
    bnot Value;
apply_logical_not(Value) ->
    case to_boolean(Value) of
        true -> 0;
        false -> -1
    end.

to_boolean(Value) when is_integer(Value) -> Value =/= 0;
to_boolean(Value) when is_float(Value) -> Value =/= +0.0;
to_boolean(Value) when is_list(Value) -> string:trim(Value) =/= "";
to_boolean(_) -> false.