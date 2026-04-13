-module(erlbasic_eval_arrays).

-export([
    get_arrays/1,
    put_arrays/2,
    new_array_meta/2,
    get_array_value/3,
    put_array_value/4,
    normalize_dims/1,
    auto_array_dims/1,
    is_string_var/1,
    is_byte_var/1,
    is_float_var/1,
    normalize_byte_value/1,
    normalize_float_value/1
]).

-define(ARRAYS_KEY, '$ARRAYS$').

get_arrays(Vars) ->
    maps:get(?ARRAYS_KEY, Vars, #{}).

put_arrays(Vars, Arrays) ->
    maps:put(?ARRAYS_KEY, Arrays, Vars).

new_array_meta(Name, Dims) ->
    Extents = [Dim + 1 || Dim <- Dims],
    Size = lists:foldl(fun(Extent, Acc) -> Extent * Acc end, 1, Extents),
    #{
        dims => Dims,
        strides => compute_strides(Extents),
        data => array:new(Size, {default, default_scalar_value(Name)})
    }.

get_array_value(Name, Indices, Vars) ->
    Arrays = get_arrays(Vars),
    case maps:find(Name, Arrays) of
        {ok, ArrayMeta} ->
            read_array_meta(ArrayMeta, Name, Indices);
        error ->
            case auto_array_dims(Indices) of
                {ok, _} ->
                    {error, undimmed_array};
                error ->
                    {error, illegal_function_call}
            end
    end.

put_array_value(Name, Indices, Value, Vars) ->
    Arrays0 = get_arrays(Vars),
    case maps:find(Name, Arrays0) of
        {ok, ArrayMeta} ->
            case write_array_meta(ArrayMeta, Name, Indices, Value) of
                {ok, NextMeta} ->
                    Arrays1 = maps:put(Name, NextMeta, Arrays0),
                    {ok, put_arrays(Vars, Arrays1)};
                {error, Reason} ->
                    {error, Reason}
            end;
        error ->
            case auto_array_dims(Indices) of
                {ok, Dims} ->
                    NewMeta = new_array_meta(Name, Dims),
                    case write_array_meta(NewMeta, Name, Indices, Value) of
                        {ok, NextMeta} ->
                            Arrays1 = maps:put(Name, NextMeta, Arrays0),
                            {ok, put_arrays(Vars, Arrays1)};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                error ->
                    {error, illegal_function_call}
            end
    end.

read_array_meta(ArrayMeta, _Name, Indices) ->
    Dims = maps:get(dims, ArrayMeta),
    Strides = maps:get(strides, ArrayMeta),
    case flat_index(Dims, Strides, Indices) of
        {ok, Index} ->
            Data = maps:get(data, ArrayMeta),
            {ok, array:get(Index, Data)};
        error ->
            {error, subscript_out_of_range}
    end.

write_array_meta(ArrayMeta, Name, Indices, Value) ->
    Dims = maps:get(dims, ArrayMeta),
    Strides = maps:get(strides, ArrayMeta),
    case flat_index(Dims, Strides, Indices) of
        {ok, Index} ->
            StoredValue =
                case is_byte_var(Name) of
                    true -> normalize_byte_value(Value);
                    false ->
                        case is_float_var(Name) of
                            true -> normalize_float_value(Value);
                            false -> Value
                        end
                end,
            Data0 = maps:get(data, ArrayMeta),
            Data1 = array:set(Index, StoredValue, Data0),
            {ok, maps:put(data, Data1, ArrayMeta)};
        error ->
            {error, subscript_out_of_range}
    end.

auto_array_dims([_]) ->
    {ok, [10]};
auto_array_dims([_, _]) ->
    {ok, [10, 10]};
auto_array_dims([_, _, _]) ->
    {ok, [10, 10, 10]};
auto_array_dims(_) ->
    error.

compute_strides(Extents) ->
    compute_strides_rev(lists:reverse(Extents), 1, []).

compute_strides_rev([], _Stride, Acc) ->
    Acc;
compute_strides_rev([Extent | Rest], Stride, Acc) ->
    compute_strides_rev(Rest, Stride * Extent, [Stride | Acc]).

flat_index(Dims, Strides, Indices) ->
    flat_index(Dims, Strides, Indices, 0).

flat_index([], [], [], Acc) ->
    {ok, Acc};
flat_index([Max | RestDims], [Stride | RestStrides], [Index | RestIndices], Acc)
    when is_integer(Index), Index >= 0, Index =< Max ->
    flat_index(RestDims, RestStrides, RestIndices, Acc + Index * Stride);
flat_index(_, _, _, _) ->
    error.

default_scalar_value(Name) ->
    case is_string_var(Name) of
        true -> "";
        false ->
            case is_float_var(Name) of
                true -> 0.0;
                false -> 0
            end
    end.

is_string_var(Name) when is_list(Name) ->
    Name =/= [] andalso lists:last(Name) =:= $$.

is_byte_var(Name) when is_list(Name) ->
    Name =/= [] andalso lists:last(Name) =:= $&.

is_float_var(Name) when is_list(Name) ->
    Name =/= [] andalso lists:last(Name) =:= $#.

normalize_byte_value(Value) when is_integer(Value) ->
    clamp_byte(Value);
normalize_byte_value(Value) when is_float(Value) ->
    clamp_byte(trunc(Value));
normalize_byte_value(Value) ->
    Value.

normalize_float_value(Value) when is_integer(Value) ->
    float(Value);
normalize_float_value(Value) when is_float(Value) ->
    Value;
normalize_float_value(Value) ->
    Value.

clamp_byte(N) when N < 0 ->
    0;
clamp_byte(N) when N > 255 ->
    255;
clamp_byte(N) ->
    N.

normalize_dims(Dims) ->
    normalize_dims(Dims, []).

normalize_dims([], Acc) ->
    case lists:reverse(Acc) of
        [D1] when D1 >= 0 -> {ok, [D1]};
        [D1, D2] when D1 >= 0, D2 >= 0 -> {ok, [D1, D2]};
        [D1, D2, D3] when D1 >= 0, D2 >= 0, D3 >= 0 -> {ok, [D1, D2, D3]};
        _ -> error
    end;
normalize_dims([Dim | Rest], Acc) when is_integer(Dim) ->
    normalize_dims(Rest, [Dim | Acc]);
normalize_dims(_, _) ->
    error.
