-module(erlbasic_storage_s3_test_backend).

-behaviour(erlbasic_storage_backend).

-export([read/1, write/2, list/1, delete/1, key_exists/1, ensure_bucket/0]).
-export([reset/0, seed/2, fetch/1, set_fail_writes/1, set_fail_lists/1, set_missing_bucket/1]).

-define(TABLE, erlbasic_s3_test_backend_table).

reset() ->
    ensure_table(),
    ets:delete_all_objects(?TABLE),
    persistent_term:put({?MODULE, fail_writes}, false),
    persistent_term:put({?MODULE, fail_lists}, false),
    persistent_term:put({?MODULE, missing_bucket}, false),
    ok.

seed(Key, Bin) when is_list(Key), is_binary(Bin) ->
    ensure_table(),
    ets:insert(?TABLE, {Key, Bin}),
    ok.

fetch(Key) ->
    case read(Key) of
        {ok, Bin} -> {ok, Bin};
        {error, enoent} -> {error, enoent};
        {error, Reason} -> {error, Reason}
    end.

set_fail_writes(Flag) when is_boolean(Flag) ->
    persistent_term:put({?MODULE, fail_writes}, Flag),
    ok.

set_fail_lists(Flag) when is_boolean(Flag) ->
    persistent_term:put({?MODULE, fail_lists}, Flag),
    ok.

set_missing_bucket(Flag) when is_boolean(Flag) ->
    persistent_term:put({?MODULE, missing_bucket}, Flag),
    ok.

read(Key) ->
    ensure_table(),
    case ets:lookup(?TABLE, Key) of
        [{Key, Bin}] -> {ok, Bin};
        [] -> {error, enoent}
    end.

write(Key, Bin) ->
    ensure_table(),
    case persistent_term:get({?MODULE, fail_writes}, false) of
        true ->
            {error, forced_write_failure};
        false ->
            ets:insert(?TABLE, {Key, iolist_to_binary(Bin)}),
            ok
    end.

list(Prefix) ->
    ensure_table(),
    case persistent_term:get({?MODULE, fail_lists}, false) of
        true ->
            {error, forced_list_failure};
        false ->
            case persistent_term:get({?MODULE, missing_bucket}, false) of
                true ->
                    {error, {aws_error, {http_error, 404, "NOT FOUND", <<"<Error><Code>NoSuchBucket</Code><Message>The specified bucket does not exist</Message></Error>">>}}};
                false ->
                    All = ets:tab2list(?TABLE),
                    PrefixSlash = Prefix ++ "/",
                    Entries =
                        lists:filtermap(
                            fun({Key, Bin}) ->
                                case lists:prefix(PrefixSlash, Key) of
                                    true ->
                                        Name = string:slice(Key, length(PrefixSlash)),
                                        case valid_name(Name) of
                                            true ->
                                                {true, {Name, byte_size(Bin), 0}};
                                            false ->
                                                false
                                        end;
                                    false ->
                                        false
                                end
                            end,
                            All),
                    {ok, lists:sort(Entries)}
            end
    end.

ensure_bucket() ->
    persistent_term:put({?MODULE, missing_bucket}, false),
    ok.

delete(Key) ->
    ensure_table(),
    case ets:lookup(?TABLE, Key) of
        [{Key, _}] ->
            ets:delete(?TABLE, Key),
            ok;
        [] ->
            {error, enoent}
    end.

key_exists(Key) ->
    ensure_table(),
    ets:member(?TABLE, Key).

valid_name([]) ->
    false;
valid_name(Name) ->
    hd(Name) =/= $. andalso not lists:member($/, Name).

ensure_table() ->
    case ets:info(?TABLE) of
        undefined ->
            ets:new(?TABLE, [named_table, public, set]),
            ok;
        _ ->
            ok
    end.
