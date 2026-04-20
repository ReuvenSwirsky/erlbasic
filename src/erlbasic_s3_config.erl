-module(erlbasic_s3_config).

-export([load/0, path/0]).

-define(ALLOWED_KEYS, [storage_s3_endpoint,
                       storage_s3_bucket,
                       storage_s3_prefix,
                       storage_s3_region,
                       storage_s3_access_key_id,
                       storage_s3_secret_access_key]).

load() ->
    ConfigPath = path(),
    case file:consult(ConfigPath) of
        {ok, Terms} ->
            apply_terms(Terms),
            maybe_warn_s3_startup(ConfigPath),
            ok;
        {error, enoent} ->
            maybe_warn_missing_config(ConfigPath),
            maybe_warn_s3_startup(ConfigPath),
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

maybe_warn_missing_config(ConfigPath) ->
    case application:get_env(erlbasic, storage_backend, local) of
        s3 ->
            logger:warning("event=s3_config_missing config_file=~ts", [ConfigPath]);
        _ ->
            ok
    end.

maybe_warn_s3_startup(ConfigPath) ->
    case application:get_env(erlbasic, storage_backend, local) of
        s3 ->
            maybe_warn_missing_required_settings(),
            maybe_warn_config_not_ignored(ConfigPath);
        _ ->
            ok
    end.

maybe_warn_missing_required_settings() ->
    case has_value(storage_s3_bucket, undefined) of
        true ->
            ok;
        false ->
            logger:warning("event=s3_bucket_missing")
    end,
    AccessSet = has_value(storage_s3_access_key_id, os:getenv("AWS_ACCESS_KEY_ID")),
    SecretSet = has_value(storage_s3_secret_access_key, os:getenv("AWS_SECRET_ACCESS_KEY")),
    case AccessSet andalso SecretSet of
        true ->
            ok;
        false ->
            logger:warning("event=s3_credentials_missing")
    end.

has_value(Key, Default) ->
    case application:get_env(erlbasic, Key) of
        {ok, undefined} -> false;
        {ok, []} -> false;
        {ok, <<>>} -> false;
        {ok, _} -> true;
        undefined ->
            case Default of
                undefined -> false;
                false -> false;
                [] -> false;
                <<>> -> false;
                _ -> true
            end
    end.

maybe_warn_config_not_ignored(ConfigPath) ->
    case file:read_file(".gitignore") of
        {ok, Bin} ->
            case config_ignored(ConfigPath, binary_to_list(Bin)) of
                true ->
                    ok;
                false ->
                    logger:warning("event=s3_config_not_ignored config_file=~ts", [ConfigPath])
            end;
        {error, _} ->
            logger:warning("event=gitignore_missing_for_s3_config config_file=~ts", [ConfigPath])
    end.

config_ignored(ConfigPath, GitignoreText) ->
    BaseName = filename:basename(ConfigPath),
    Lines = string:split(GitignoreText, "\n", all),
    lists:any(fun(Line) ->
                      Entry = string:trim(Line),
                      Entry =/= [] andalso
                      hd(Entry) =/= $# andalso
                      (Entry =:= ConfigPath orelse
                       Entry =:= BaseName orelse
                       Entry =:= "./" ++ ConfigPath)
              end, Lines).