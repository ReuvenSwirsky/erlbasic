-module(erlbasic_s3_config).

-export([load/0, path/0]).

-define(ALLOWED_KEYS, [storage_s3_endpoint,
                       storage_s3_bucket,
                       storage_s3_prefix,
                       storage_s3_region,
                       storage_s3_access_key_id,
                       storage_s3_secret_access_key]).

load() ->
    case file:consult(path()) of
        {ok, Terms} ->
            apply_terms(Terms);
        {error, enoent} ->
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

path() ->
    case application:get_env(erlbasic, storage_s3_config_file) of
        {ok, ConfigPath} -> ConfigPath;
        undefined -> ".s3.config"
    end.

apply_terms(Terms) ->
    Entries = normalize_terms(Terms),
    lists:foreach(fun({Key, Value}) -> application:set_env(erlbasic, Key, Value) end, Entries),
    ok.

normalize_terms([{erlbasic, Entries}]) when is_list(Entries) ->
    filter_allowed_entries(Entries);
normalize_terms([Entries]) when is_list(Entries) ->
    filter_allowed_entries(Entries);
normalize_terms(Entries) when is_list(Entries) ->
    filter_allowed_entries(Entries);
normalize_terms(_Other) ->
    [].

filter_allowed_entries(Entries) ->
    [{Key, Value} || {Key, Value} <- Entries, lists:member(Key, ?ALLOWED_KEYS)].