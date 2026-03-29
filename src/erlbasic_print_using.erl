-module(erlbasic_print_using).

-export([format_item/2]).

format_item(Format, Value) when is_list(Format) ->
    case has_ampersand_slot(Format) of
        true ->
            {ok, replace_first_ampersand(Format, to_print_text(Value))};
        false ->
            case parse_numeric_mask(Format) of
                {ok, Width, Decimals} ->
                    format_numeric_mask(Width, Decimals, Value);
                error ->
                    {error, type_mismatch}
            end
    end;
format_item(_Format, _Value) ->
    {error, type_mismatch}.

has_ampersand_slot(Format) ->
    lists:member($&, Format).

replace_first_ampersand([], ValueText) ->
    ValueText;
replace_first_ampersand([$& | Rest], ValueText) ->
    ValueText ++ Rest;
replace_first_ampersand([Ch | Rest], ValueText) ->
    [Ch | replace_first_ampersand(Rest, ValueText)].

parse_numeric_mask(Format) ->
    Trimmed = string:trim(Format),
    case string:split(Trimmed, ".", all) of
        [IntMask] ->
            case all_hashes(IntMask) andalso (IntMask =/= []) of
                true -> {ok, length(IntMask), 0};
                false -> error
            end;
        [IntMask, DecMask] ->
            case (IntMask =/= []) andalso (DecMask =/= []) andalso all_hashes(IntMask) andalso all_hashes(DecMask) of
                true -> {ok, length(IntMask) + 1 + length(DecMask), length(DecMask)};
                false -> error
            end;
        _ ->
            error
    end.

all_hashes(Text) ->
    lists:all(fun(Ch) -> Ch =:= $# end, Text).

format_numeric_mask(Width, Decimals, Value) when is_integer(Value); is_float(Value) ->
    NumericText =
        case Decimals of
            0 -> integer_to_list(round(Value));
            _ -> lists:flatten(io_lib:format("~.*f", [Decimals, Value + 0.0]))
        end,
    Padded =
        case length(NumericText) >= Width of
            true -> NumericText;
            false -> lists:duplicate(Width - length(NumericText), $\s) ++ NumericText
        end,
    {ok, Padded};
format_numeric_mask(_Width, _Decimals, _Value) ->
    {error, type_mismatch}.

to_print_text(Value) when is_list(Value) ->
    Value;
to_print_text(Value) when is_integer(Value) ->
    integer_to_list(Value);
to_print_text(Value) when is_float(Value) ->
    erlbasic_eval:format_print_value(Value);
to_print_text(Value) ->
    lists:flatten(io_lib:format("~p", [Value])).
