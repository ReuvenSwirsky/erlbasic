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
apply_math_function("CDBL", [X]) when is_integer(X) ->
    {ok, float(X)};
apply_math_function("CDBL", [X]) when is_float(X) ->
    {ok, X};
apply_math_function("CDBL", [_]) ->
    {error, illegal_function_call};
apply_math_function("CINT", [X]) when is_number(X) ->
    {ok, round(X)};
apply_math_function("CINT", [_]) ->
    {error, illegal_function_call};
apply_math_function("CSNG", [X]) when is_integer(X) ->
    {ok, float(X)};
apply_math_function("CSNG", [X]) when is_float(X) ->
    {ok, X};
apply_math_function("CSNG", [_]) ->
    {error, illegal_function_call};
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
apply_math_function("MEM_USED", []) ->
    {ok, approximate_current_memory_bytes()};
apply_math_function("FREE", []) ->
    {ok, free_memory_value()};
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
apply_math_function("INSTR", [Text, Pattern]) ->
    apply_instr(1, Text, Pattern);
apply_math_function("INSTR", [Start, Text, Pattern]) ->
    apply_instr(Start, Text, Pattern);
apply_math_function("ASC", [Text]) ->
    apply_asc(Text);
apply_math_function("CHR$", [Code]) ->
    apply_chr(Code);
apply_math_function("STR$", [Value]) ->
    apply_str(Value);
apply_math_function("SPACE$", [Count]) ->
    apply_space(Count);
apply_math_function("POS", []) ->
    {ok, current_pos()};
apply_math_function("POS", [Arg]) when is_number(Arg) ->
    {ok, current_pos()};
apply_math_function("EOF", [Channel]) ->
    erlbasic_fileio:eof(Channel);
apply_math_function("LOF", [Channel]) ->
    erlbasic_fileio:lof(Channel);
apply_math_function("SEEK", [Channel]) ->
    erlbasic_fileio:seek(Channel);
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
apply_math_function("PLAY", [_N]) ->
    %% Returns the number of notes remaining in the background music queue.
    %% The argument is accepted for compatibility but ignored.
    Now = erlang:monotonic_time(millisecond),
    Count = case erlang:get(erlbasic_play_schedule) of
        undefined -> 0;
        List ->
            Remaining = [T || T <- List, T > Now],
            erlang:put(erlbasic_play_schedule, Remaining),
            length(Remaining)
    end,
    {ok, Count};
apply_math_function(_, _Args) ->
    {error, illegal_function_call}.

free_memory_value() ->
    case memory_limit_bytes() of
        unlimited ->
            2147483647;
        LimitBytes when is_integer(LimitBytes), LimitBytes > 0 ->
            UsedBytes = approximate_current_memory_bytes(),
            Free = LimitBytes - UsedBytes,
            case Free > 0 of
                true -> Free;
                false -> 0
            end;
        _ ->
            0
    end.

memory_limit_bytes() ->
    case erlang:get(erlbasic_ppn) of
        {P, N} ->
            case erlbasic_limits:get_effective_memory_limit_kb(P, N) of
                unlimited -> unlimited;
                KB when is_integer(KB), KB > 0 -> KB * 1024;
                _ -> erlbasic_limits:default_memory_limit_kb() * 1024
            end;
        _ ->
            erlbasic_limits:default_memory_limit_kb() * 1024
    end.

approximate_current_memory_bytes() ->
    Vars = erlang:get(erlbasic_mem_vars),
    Funcs = erlang:get(erlbasic_mem_funcs),
    Prog = erlang:get(erlbasic_mem_prog),
    DataItems = erlang:get(erlbasic_mem_data_items),
    LoopStack = erlang:get(erlbasic_mem_loopstack),
    CallStack = erlang:get(erlbasic_mem_callstack),
    size_or_zero(Vars)
    + size_or_zero(Funcs)
    + size_or_zero(Prog)
    + size_or_zero(DataItems)
    + size_or_zero(LoopStack)
    + size_or_zero(CallStack).

size_or_zero(undefined) ->
    0;
size_or_zero(Value) ->
    erlang:external_size(Value).

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

apply_instr(Start, Text, Pattern) ->
    case normalize_int_arg(Start) of
        {ok, StartPos} when StartPos > 0 ->
            Str = to_basic_string(Text),
            Pat = to_basic_string(Pattern),
            case Pat of
                [] ->
                    Len = length(Str),
                    if
                        StartPos =< Len + 1 -> {ok, StartPos};
                        true -> {ok, 0}
                    end;
                _ ->
                    {ok, instr_find(Str, Pat, StartPos)}
            end;
        _ ->
            {error, illegal_function_call}
    end.

instr_find(Str, Pat, StartPos) ->
    Len = length(Str),
    if
        StartPos > Len ->
            0;
        true ->
            Tail = lists:nthtail(StartPos - 1, Str),
            instr_find_from_tail(Tail, Pat, StartPos)
    end.

instr_find_from_tail([], _Pat, _Pos) ->
    0;
instr_find_from_tail(Tail, Pat, Pos) ->
    case lists:prefix(Pat, Tail) of
        true ->
            Pos;
        false ->
            case Tail of
                [_ | Rest] -> instr_find_from_tail(Rest, Pat, Pos + 1);
                [] -> 0
            end
    end.

apply_space(Count) ->
    case normalize_int_arg(Count) of
        {ok, N} when N >= 0 ->
            {ok, lists:duplicate(N, $\s)};
        _ ->
            {error, illegal_function_call}
    end.

current_pos() ->
    Col = case erlang:get(erlbasic_print_col) of
        N when is_integer(N), N >= 0 -> N;
        _ -> 0
    end,
    Col + 1.

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
    {ok, erlbasic_eval:format_number(Value)};
apply_str(_Value) ->
    {error, illegal_function_call}.

apply_val(Value) ->
    Text = string:trim(to_basic_string(Value)),
    case re:run(Text, "^([+-]?(?:(?:\\d+(?:\\.\\d*)?)|(?:\\.\\d+))(?:[EeDd][+-]?\\d+)?)", [{capture, [1], list}]) of
        {match, [NumText]} ->
            Normalized = normalize_val_number_text(NumText),
            case has_float_marker(Normalized) of
                false ->
                    case string:to_integer(Normalized) of
                        {Int, ""} -> {ok, Int};
                        _ -> {ok, 0}
                    end;
                true ->
                    case string:to_float(Normalized) of
                        {Float, ""} -> {ok, Float};
                        _ -> {ok, 0}
                    end
            end;
        nomatch ->
            {ok, 0}
    end.

has_float_marker(Text) ->
    lists:member($., Text) orelse lists:member($e, Text) orelse lists:member($E, Text).

normalize_val_number_text(Text) ->
    Canon = [case C of $D -> $e; $d -> $e; _ -> C end || C <- Text],
    case split_exp(Canon) of
        {Mantissa, ExpPart} ->
            NormMantissa = case lists:member($., Mantissa) of
                true ->
                    case lists:last(Mantissa) of
                        $. -> Mantissa ++ "0";
                        _ -> Mantissa
                    end;
                false -> Mantissa ++ ".0"
            end,
            NormMantissa ++ [$e | ExpPart];
        plain ->
            Canon
    end.

split_exp(Text) ->
    split_exp(Text, []).

split_exp([], _Acc) ->
    plain;
split_exp([C | Rest], Acc) when C =:= $e; C =:= $E ->
    {lists:reverse(Acc), Rest};
split_exp([C | Rest], Acc) ->
    split_exp(Rest, [C | Acc]).

normalize_int_arg(Value) when is_integer(Value) ->
    {ok, Value};
normalize_int_arg(Value) when is_float(Value) ->
    {ok, trunc(Value)};
normalize_int_arg(_) ->
    error.

to_basic_string(Value) when is_list(Value) ->
    Value;
to_basic_string(Value) when is_integer(Value) ->
    erlbasic_eval:format_print_value(Value);
to_basic_string(Value) when is_float(Value) ->
    erlbasic_eval:format_print_value(Value);
to_basic_string(Value) ->
    lists:flatten(io_lib:format("~p", [Value])).
