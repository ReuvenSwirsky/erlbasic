-module(erlbasic_eval_arrays).

-export([
    get_arrays/1,
    put_arrays/2,
    get_array_value/3,
    put_array_value/4,
    normalize_dims/1,
    auto_array_dims/1,
    is_string_var/1
]).

-define(ARRAYS_KEY, '$ARRAYS$').

get_arrays(Vars) ->
    maps:get(?ARRAYS_KEY, Vars, #{}).

put_arrays(Vars, Arrays) ->
    maps:put(?ARRAYS_KEY, Arrays, Vars).

get_array_value(Name, Indices, Vars) ->
    Arrays = get_arrays(Vars),
    case maps:find(Name, Arrays) of
        {ok, ArrayMeta} ->
            read_array_meta(ArrayMeta, Name, Indices);
        error ->
            case auto_array_dims(Indices) of
                {ok, _} ->
                    {ok, default_scalar_value(Name)};
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
                    NewMeta = #{dims => Dims, values => #{}},
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

read_array_meta(ArrayMeta, Name, Indices) ->
    Dims = maps:get(dims, ArrayMeta),
    case validate_indices(Dims, Indices) of
        ok ->
            Values = maps:get(values, ArrayMeta, #{}),
            Key = indices_key(Indices),
            {ok, maps:get(Key, Values, default_scalar_value(Name))};
        error ->
            {error, illegal_function_call}
    end.

write_array_meta(ArrayMeta, _Name, Indices, Value) ->
    Dims = maps:get(dims, ArrayMeta),
    case validate_indices(Dims, Indices) of
        ok ->
            Values0 = maps:get(values, ArrayMeta, #{}),
            Key = indices_key(Indices),
            Values1 = maps:put(Key, Value, Values0),
            {ok, maps:put(values, Values1, ArrayMeta)};
        error ->
            {error, illegal_function_call}
    end.

auto_array_dims([_]) ->
    {ok, [10]};
auto_array_dims([_, _]) ->
    {ok, [10, 10]};
auto_array_dims([_, _, _]) ->
    {ok, [10, 10, 10]};
auto_array_dims(_) ->
    error.

validate_indices([Max], [I]) ->
    validate_index(I, Max);
validate_indices([Max1, Max2], [I, J]) ->
    case {validate_index(I, Max1), validate_index(J, Max2)} of
        {ok, ok} -> ok;
        _ -> error
    end;
validate_indices([Max1, Max2, Max3], [I, J, K]) ->
    case {validate_index(I, Max1), validate_index(J, Max2), validate_index(K, Max3)} of
        {ok, ok, ok} -> ok;
        _ -> error
    end;
validate_indices(_, _) ->
    error.

validate_index(Index, Max) when is_integer(Index), is_integer(Max), Index >= 0, Index =< Max ->
    ok;
validate_index(_, _) ->
    error.

indices_key([I]) ->
    I;
indices_key([I, J]) ->
    {I, J};
indices_key([I, J, K]) ->
    {I, J, K}.

default_scalar_value(Name) ->
    case is_string_var(Name) of
        true -> "";
        false -> 0
    end.

is_string_var(Name) when is_list(Name) ->
    Name =/= [] andalso lists:last(Name) =:= $$.

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
