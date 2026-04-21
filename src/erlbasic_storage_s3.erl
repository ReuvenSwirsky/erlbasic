-module(erlbasic_storage_s3).

-behaviour(erlbasic_storage_backend).

-export([read/1, write/2, list/1, delete/1, key_exists/1, ensure_bucket/0]).

-include_lib("erlcloud/include/erlcloud_aws.hrl").

read(Key) ->
    with_s3(fun(Bucket, Prefix, Config) ->
        S3Key = object_key(Prefix, Key),
        case erlcloud_s3:get_object(Bucket, S3Key, Config) of
            Resp when is_list(Resp) ->
                case object_body(Resp) of
                    {ok, Bin} -> {ok, Bin};
                    {error, _} = Err -> Err
                end;
            {error, Reason} ->
                normalize_error(Reason);
            Other ->
                {error, {unexpected_s3_response, Other}}
        end
    end).

write(Key, Bin) ->
    with_s3(fun(Bucket, Prefix, Config) ->
        S3Key = object_key(Prefix, Key),
        case erlcloud_s3:put_object(Bucket, S3Key, Bin, Config) of
            Resp when is_list(Resp) -> ok;
            {error, Reason} -> normalize_error(Reason);
            Other -> {error, {unexpected_s3_response, Other}}
        end
    end).

list(Prefix) ->
    with_s3(fun(Bucket, RootPrefix, Config) ->
        ObjectPrefix = list_prefix(RootPrefix, Prefix),
        case erlcloud_s3:list_objects(Bucket, [{prefix, ObjectPrefix}], Config) of
            Resp when is_list(Resp) ->
                {ok, normalize_list_response(Resp, ObjectPrefix)};
            {error, Reason} ->
                normalize_error(Reason);
            Other ->
                {error, {unexpected_s3_response, Other}}
        end
    end).

delete(Key) ->
    with_s3(fun(Bucket, Prefix, Config) ->
        S3Key = object_key(Prefix, Key),
        case erlcloud_s3:delete_object(Bucket, S3Key, Config) of
            Resp when is_list(Resp) -> ok;
            {error, Reason} -> normalize_error(Reason);
            Other -> {error, {unexpected_s3_response, Other}}
        end
    end).

key_exists(Key) ->
    case with_s3(fun(Bucket, Prefix, Config) ->
        S3Key = object_key(Prefix, Key),
        case erlcloud_s3:get_object_metadata(Bucket, S3Key, Config) of
            Resp when is_list(Resp) -> true;
            {error, Reason} ->
                case is_not_found(Reason) of
                    true -> false;
                    false -> false
                end;
            _Other ->
                false
        end
    end) of
        true -> true;
        _ -> false
    end.

with_s3(Fun) ->
    _ = ensure_s3_apps_started(),
    case s3_settings() of
        {ok, Bucket, Prefix, Config} ->
            Fun(Bucket, Prefix, Config);
        {error, _} = Err ->
            Err
    end.

ensure_bucket() ->
    _ = ensure_s3_apps_started(),
    case s3_settings() of
        {ok, Bucket, _Prefix, Config} ->
            ensure_bucket(Bucket, Config);
        {error, _} = Err ->
            Err
    end.

s3_settings() ->
    Bucket = env_string(storage_s3_bucket, undefined),
    Prefix = env_string(storage_s3_prefix, ""),
    case Bucket of
        undefined ->
            {error, missing_s3_bucket};
        _ ->
            case aws_config() of
                {ok, Config} -> {ok, Bucket, normalize_prefix(Prefix), Config};
                {error, _} = Err -> Err
            end
    end.

aws_config() ->
    AccessKey = env_string(storage_s3_access_key_id, os:getenv("AWS_ACCESS_KEY_ID")),
    SecretKey = env_string(storage_s3_secret_access_key, os:getenv("AWS_SECRET_ACCESS_KEY")),
    Region = env_string(storage_s3_region, os:getenv("AWS_DEFAULT_REGION")),
    Endpoint = env_string(storage_s3_endpoint, undefined),
    EndpointConfigured = endpoint_is_set(Endpoint),
    case base_config(AccessKey, SecretKey, Endpoint) of
        {ok, Config0} ->
            Config1 =
                case EndpointConfigured of
                    true -> Config0;
                    false -> maybe_apply_region(Config0, Region)
                end,
            {ok, Config1};
        {error, _} = Err ->
            Err
    end.

base_config(AccessKey, SecretKey, Endpoint) when is_list(AccessKey), is_list(SecretKey),
                                                  AccessKey =/= [], SecretKey =/= [] ->
    case parse_endpoint(Endpoint) of
        {ok, Scheme, Host, Port} ->
            ok = erlcloud_s3:configure(AccessKey, SecretKey, Host, Port, Scheme),
            Config0 = erlcloud_aws:default_config(),
            Config1 = Config0#aws_config{s3_bucket_access_method = path,
                                         s3_bucket_after_host = false},
            {ok, Config1};
        error ->
            {ok, erlcloud_s3:new(AccessKey, SecretKey)}
    end;
base_config(_AccessKey, _SecretKey, Endpoint) ->
    case parse_endpoint(Endpoint) of
        {ok, _Scheme, _Host, _Port} ->
            {error, missing_s3_credentials};
        error ->
            case erlcloud_aws:auto_config() of
                {ok, Config} ->
                    {ok, Config};
                undefined ->
                    {error, missing_s3_credentials}
            end
    end.

maybe_apply_region(Config, undefined) ->
    Config;
maybe_apply_region(Config, []) ->
    Config;
maybe_apply_region(Config, Region) when is_list(Region) ->
    erlcloud_aws:service_config(s3, Region, Config).

ensure_bucket(Bucket, Config) ->
    try erlcloud_s3:create_bucket(Bucket, private, bucket_location_constraint(), Config) of
        ok -> ok;
        Other -> {error, {unexpected_s3_response, Other}}
    catch
        throw:{aws_error, Reason} ->
            case is_bucket_already_present(Reason) of
                true -> ok;
                false -> {error, Reason}
            end;
        error:{aws_error, Reason} ->
            case is_bucket_already_present(Reason) of
                true -> ok;
                false -> {error, Reason}
            end;
        Class:Reason ->
            {error, {Class, Reason}}
    end.

bucket_location_constraint() ->
    case env_string(storage_s3_region, os:getenv("AWS_DEFAULT_REGION")) of
        undefined -> none;
        [] -> none;
        "us-east-1" -> 'us-east-1';
        "us-east-2" -> 'us-east-2';
        "us-west-1" -> 'us-west-1';
        "us-west-2" -> 'us-west-2';
        "ca-central-1" -> 'ca-central-1';
        "eu-west-1" -> 'eu-west-1';
        "eu-west-2" -> 'eu-west-2';
        "eu-west-3" -> 'eu-west-3';
        "eu-north-1" -> 'eu-north-1';
        "eu-central-1" -> 'eu-central-1';
        "ap-south-1" -> 'ap-south-1';
        "ap-southeast-1" -> 'ap-southeast-1';
        "ap-southeast-2" -> 'ap-southeast-2';
        "ap-northeast-1" -> 'ap-northeast-1';
        "ap-northeast-2" -> 'ap-northeast-2';
        "ap-northeast-3" -> 'ap-northeast-3';
        "ap-east-1" -> 'ap-east-1';
        "me-south-1" -> 'me-south-1';
        "sa-east-1" -> 'sa-east-1';
        _ -> none
    end.

is_bucket_already_present(Reason) ->
    ReasonText = string:to_lower(lists:flatten(io_lib:format("~0p", [Reason]))),
    string:str(ReasonText, "bucketalreadyownedbyyou") > 0 orelse
        string:str(ReasonText, "bucket already owned by you") > 0 orelse
        string:str(ReasonText, "bucketalreadyexists") > 0.

env_string(Key, Default) ->
    case application:get_env(erlbasic, Key) of
        {ok, Value} when is_binary(Value) -> binary_to_list(Value);
        {ok, Value} when is_list(Value) -> Value;
        {ok, Value} when is_atom(Value) -> atom_to_list(Value);
        {ok, Value} -> lists:flatten(io_lib:format("~p", [Value]));
        undefined -> Default
    end.

object_key(Prefix, Key) ->
    normalize_prefix(Prefix) ++ Key.

list_prefix(RootPrefix, Prefix) ->
    KeyPrefix = normalize_prefix(RootPrefix) ++ Prefix,
    case lists:suffix("/", KeyPrefix) of
        true -> KeyPrefix;
        false -> KeyPrefix ++ "/"
    end.

normalize_prefix(undefined) ->
    "";
normalize_prefix(Prefix) when is_list(Prefix) ->
    case Prefix of
        [] -> [];
        _ ->
            case lists:suffix("/", Prefix) of
                true -> Prefix;
                false -> Prefix ++ "/"
            end
    end.

object_body(Resp) ->
    case proplists:get_value(content, Resp, undefined) of
        Bin when is_binary(Bin) -> {ok, Bin};
        _ ->
            case proplists:get_value(body, Resp, undefined) of
                Bin2 when is_binary(Bin2) -> {ok, Bin2};
                _ -> {error, bad_s3_body}
            end
    end.

normalize_list_response(Resp, ObjectPrefix) ->
    Entries = proplists:get_value(contents, Resp, []),
    Sorted = lists:sort([Entry || Entry <- [normalize_list_entry(E, ObjectPrefix) || E <- Entries], Entry =/= skip]),
    Sorted.

normalize_list_entry(Entry, ObjectPrefix) when is_list(Entry) ->
    Key0 = value_to_string(proplists:get_value(key, Entry, undefined)),
    case strip_list_prefix(ObjectPrefix, Key0) of
        {ok, Name} ->
            case valid_list_name(Name) of
                true ->
                    Size = value_to_non_neg_int(proplists:get_value(size, Entry, 0)),
                    MTimeRaw = proplists:get_value(last_modified, Entry, undefined),
                    {Name, Size, to_unix_time(MTimeRaw)};
                false ->
                    skip
            end;
        error ->
            skip
    end;
normalize_list_entry(_Entry, _ObjectPrefix) ->
    skip.

strip_list_prefix(Prefix, Key) when is_list(Prefix), is_list(Key) ->
    case lists:prefix(Prefix, Key) of
        true ->
            {ok, string:trim(string:slice(Key, length(Prefix)))};
        false ->
            error
    end.

valid_list_name([]) -> false;
valid_list_name(Name) when is_list(Name) ->
    hd(Name) =/= $. andalso not lists:member($/, Name).

value_to_non_neg_int(Value) when is_integer(Value), Value >= 0 -> Value;
value_to_non_neg_int(Value) when is_binary(Value) -> value_to_non_neg_int(binary_to_list(Value));
value_to_non_neg_int(Value) when is_list(Value) ->
    case string:to_integer(string:trim(Value)) of
        {N, ""} when N >= 0 -> N;
        _ -> 0
    end;
value_to_non_neg_int(_Value) -> 0.

value_to_string(undefined) -> [];
value_to_string(Value) when is_list(Value) -> Value;
value_to_string(Value) when is_binary(Value) -> binary_to_list(Value);
value_to_string(Value) when is_atom(Value) -> atom_to_list(Value);
value_to_string(Value) -> lists:flatten(io_lib:format("~p", [Value])).

to_unix_time({{Y, Mon, D}, {H, Min, S}}) ->
    calendar:datetime_to_gregorian_seconds({{Y, Mon, D}, {H, Min, S}}) - 62167219200;
to_unix_time(Bin) when is_binary(Bin) ->
    to_unix_time(binary_to_list(Bin));
to_unix_time(Str) when is_list(Str) ->
    case parse_iso8601_utc(Str) of
        {ok, DateTime} ->
            to_unix_time(DateTime);
        error ->
            0
    end;
to_unix_time(_Other) ->
    0.

parse_iso8601_utc(Str) ->
    case re:run(Str,
                "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(?:\\.\\d+)?Z$",
                [{capture, all_but_first, list}]) of
        {match, [YS, MS, DS, HS, MinS, SS]} ->
            {Y, ""} = string:to_integer(YS),
            {Mon, ""} = string:to_integer(MS),
            {D, ""} = string:to_integer(DS),
            {H, ""} = string:to_integer(HS),
            {Min, ""} = string:to_integer(MinS),
            {S, ""} = string:to_integer(SS),
            {ok, {{Y, Mon, D}, {H, Min, S}}};
        _ ->
            error
    end.

normalize_error(Reason) ->
    case is_not_found(Reason) of
        true -> {error, enoent};
        false -> {error, Reason}
    end.

is_not_found({http_error, 404, _Status, _Body}) -> true;
is_not_found({socket_error, _Reason}) -> false;
is_not_found({error, Inner}) -> is_not_found(Inner);
is_not_found({_, Inner}) -> is_not_found(Inner);
is_not_found([H | T]) -> is_not_found(H) orelse is_not_found(T);
is_not_found([]) -> false;
is_not_found(Reason) when is_atom(Reason) ->
    Reason =:= not_found orelse Reason =:= enoent orelse Reason =:= no_such_key;
is_not_found(Reason) when is_binary(Reason) ->
    is_not_found(binary_to_list(Reason));
is_not_found(Reason) when is_list(Reason) ->
    Lower = string:to_lower(Reason),
    string:str(Lower, "not found") > 0 orelse string:str(Lower, "no such key") > 0;
is_not_found(_Reason) ->
    false.

parse_endpoint(undefined) ->
    error;
parse_endpoint([]) ->
    error;
parse_endpoint(Endpoint) when is_list(Endpoint) ->
    case uri_string:parse(Endpoint) of
        #{host := Host} = Uri ->
            Scheme = maps:get(scheme, Uri, "https"),
            Port = maps:get(port, Uri, default_port(Scheme)),
            {ok, normalize_scheme(value_to_string(Scheme)), value_to_string(Host), Port};
        _ ->
            error
    end;
parse_endpoint(_Other) ->
    error.

default_port("http") -> 80;
default_port("https") -> 443;
default_port(_) -> 443.

normalize_scheme("http://") -> "http://";
normalize_scheme("https://") -> "https://";
normalize_scheme("http") -> "http://";
normalize_scheme("https") -> "https://";
normalize_scheme(Other) -> Other.

endpoint_is_set(undefined) ->
    false;
endpoint_is_set([]) ->
    false;
endpoint_is_set(_Value) ->
    true.

ensure_s3_apps_started() ->
    case application:ensure_all_started(erlcloud) of
        {ok, _} -> ok;
        {error, _} -> ok
    end.
