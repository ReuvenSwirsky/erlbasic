-module(erlbasic_eval_builtins).

-export([apply_math_function/2, is_builtin_function/1]).

is_builtin_function(Name) ->
    erlbasic_keywords:is_builtin_function_keyword(Name).

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
apply_math_function("FLOOR", [X]) ->
    apply_floor(X);
apply_math_function("CEIL", [X]) ->
    apply_ceil(X);
apply_math_function("LN", [X]) ->
    safe_math(fun() -> math:log(X) end);
apply_math_function("LOG", [X]) ->
    safe_math(fun() -> math:log(X) end);
apply_math_function("PI", []) ->
    {ok, math:pi()};
apply_math_function("POW", [X, Y]) ->
    apply_pow(X, Y);
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
apply_math_function("TERM$", []) ->
    case erlang:get(erlbasic_conn_type) of
        websocket -> {ok, "XTERM"};
        _         -> {ok, "TELNET"}
    end;
apply_math_function("TIMER", []) ->
    %% Seconds since midnight as a float, matching GW-BASIC behaviour.
    {_, {H, M, S}} = calendar:local_time(),
    {ok, H * 3600.0 + M * 60.0 + S * 1.0};
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
apply_math_function("ASC", [Text]) ->
    apply_asc(Text);
apply_math_function("CHR$", [Code]) ->
    apply_chr(Code);
apply_math_function("STR$", [Value]) ->
    apply_str(Value);
apply_math_function("STRING$", [Count, Code]) when is_number(Count), is_number(Code) ->
    N = trunc(Count),
    C = trunc(Code),
    if
        N < 0; C < 0; C > 255 -> {error, illegal_function_call};
        true -> {ok, lists:duplicate(N, C)}
    end;
apply_math_function("STRING$", [Count, Str]) when is_number(Count), is_list(Str) ->
    N = trunc(Count),
    if
        N < 0; Str =:= [] -> {error, illegal_function_call};
        true -> {ok, lists:duplicate(N, hd(Str))}
    end;
apply_math_function("VAL", [Value]) ->
    apply_val(Value);
apply_math_function(_, _Args) ->
    {error, illegal_function_call}.

safe_math(Fun) ->
    try
        {ok, Fun()}
    catch
        error:badarith -> {error, illegal_function_call}
    end.

floor_number(X) when is_integer(X) ->
    X;
floor_number(X) when is_float(X) ->
    T = trunc(X),
    case X < T of
        true -> T - 1;
        false -> T
    end.

ceil_number(X) when is_integer(X) ->
    X;
ceil_number(X) when is_float(X) ->
    T = trunc(X),
    case X > T of
        true -> T + 1;
        false -> T
    end.

apply_floor(X) when is_integer(X); is_float(X) ->
    {ok, floor_number(X)};
apply_floor(_X) ->
    {error, illegal_function_call}.

apply_ceil(X) when is_integer(X); is_float(X) ->
    {ok, ceil_number(X)};
apply_ceil(_X) ->
    {error, illegal_function_call}.

apply_pow(X, Y) when is_integer(X), is_integer(Y), Y >= 0 ->
    {ok, int_pow(X, Y)};
apply_pow(X, Y) when (is_integer(X) orelse is_float(X)) andalso
                    (is_integer(Y) orelse is_float(Y)) ->
    {ok, math:pow(X, Y)};
apply_pow(_X, _Y) ->
    {error, illegal_function_call}.

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

apply_asc(Text) ->
    Str = to_basic_string(Text),
    case Str of
        [] ->
            {error, illegal_function_call};
        [Ch | _] ->
            {ok, Ch}
    end.

apply_chr(Code) ->
    case normalize_int_arg(Code) of
        {ok, N} when N >= 0, N =< 255 ->
            {ok, [N]};
        _ ->
            {error, illegal_function_call}
    end.

apply_str(Value) when is_integer(Value); is_float(Value) ->
    {ok, format_number(Value)};
apply_str(_Value) ->
    {error, illegal_function_call}.

apply_val(Value) ->
    Text = string:trim(to_basic_string(Value)),
    case re:run(Text, "^([+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+))", [{capture, [1], list}]) of
        {match, [NumText]} ->
            case string:to_integer(NumText) of
                {Int, ""} -> {ok, Int};
                _ ->
                    case string:to_float(NumText) of
                        {Float, ""} -> {ok, Float};
                        _ -> {ok, 0}
                    end
            end;
        nomatch ->
            {ok, 0}
    end.

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

format_number(Value) when is_integer(Value) ->
    integer_to_list(Value);
format_number(Value) when is_float(Value) ->
    Raw = lists:flatten(io_lib:format("~.10f", [Value])),
    ensure_float_text(trim_float_string(Raw)).

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
