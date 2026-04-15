-module(erlbasic_config_override).

-export([load/0, path/0]).

load() ->
    ConfigPath = path(),
    case file:consult(ConfigPath) of
        {ok, Terms} ->
            Count = apply_terms(Terms),
            io:format("Loaded config override file ~s (~B entr~s applied)~n",
                      [ConfigPath, Count, plural_suffix(Count)]),
            ok;
        {error, enoent} ->
            ok;
        {error, Reason} ->
            io:format("Warning: failed to load config override file ~s: ~p~n", [ConfigPath, Reason]),
            ok
    end.

path() ->
    case application:get_env(erlbasic, config_override_file) of
        {ok, ConfigPath} -> ConfigPath;
        undefined -> ".sys.override.config"
    end.

apply_terms(Terms) ->
    Entries = normalize_terms(Terms),
    lists:foreach(fun({Key, Value}) -> application:set_env(erlbasic, Key, Value) end, Entries),
    length(Entries).

normalize_terms([{erlbasic, Entries}]) when is_list(Entries) ->
    filter_entries(Entries);
normalize_terms([Entries]) when is_list(Entries) ->
    filter_entries(Entries);
normalize_terms(Entries) when is_list(Entries) ->
    filter_entries(Entries);
normalize_terms(_Other) ->
    [].

filter_entries(Entries) ->
    [{Key, Value} || {Key, Value} <- Entries, is_atom(Key)].

plural_suffix(1) -> "y";
plural_suffix(_) -> "ies".
