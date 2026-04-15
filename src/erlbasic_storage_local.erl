-module(erlbasic_storage_local).

-behaviour(erlbasic_storage_backend).

-export([read/1, write/2, list/1, delete/1, key_exists/1]).
-export([key_to_path/1, user_dir/1, ensure_prefix/1]).

-include_lib("kernel/include/file.hrl").

read(Key) ->
    file:read_file(key_to_path(Key)).

write(Key, Bin) ->
    Path = key_to_path(Key),
    case filelib:ensure_dir(Path) of
        ok ->
            file:write_file(Path, Bin);
        Error ->
            Error
    end.

list(Prefix) ->
    Dir = key_to_path(Prefix),
    case file:list_dir(Dir) of
        {ok, Names} ->
            Visible = [Name || Name <- Names, Name =/= [], hd(Name) =/= $.],
            Infos = lists:filtermap(fun(Name) -> get_file_info(Dir, Name) end, Visible),
            {ok, lists:sort(Infos)};
        {error, enoent} ->
            {ok, []};
        {error, Reason} ->
            {error, Reason}
    end.

delete(Key) ->
    file:delete(key_to_path(Key)).

key_exists(Key) ->
    filelib:is_regular(key_to_path(Key)).

key_to_path("") ->
    root_dir();
key_to_path(Key) ->
    filename:join([root_dir() | string:split(Key, "/", all)]).

user_dir(Prefix) ->
    key_to_path(Prefix).

ensure_prefix(Prefix) ->
    Dir = key_to_path(Prefix),
    case filelib:ensure_dir(filename:join(Dir, ".keep")) of
        ok ->
            {ok, Dir};
        Error ->
            Error
    end.

root_dir() ->
    case application:get_env(erlbasic, storage_local_root) of
        {ok, Root} -> Root;
        undefined -> filename:join(home_dir(), "ErlUsers")
    end.

home_dir() ->
    case os:getenv("HOME") of
        false ->
            case os:getenv("USERPROFILE") of
                false -> ".";
                Path -> Path
            end;
        Path -> Path
    end.

get_file_info(Dir, Name) ->
    Path = filename:join(Dir, Name),
    case file:read_file_info(Path) of
        {ok, #file_info{type = regular, size = Size, mtime = MTime}} ->
            UnixTime = calendar:datetime_to_gregorian_seconds(MTime) - 62167219200,
            {true, {Name, Size, UnixTime}};
        _ ->
            false
    end.