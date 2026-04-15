%% @doc Abstraction layer between BASIC runtime file I/O and the backing store.
%%
%% All OPEN/CLOSE channel operations go through this module so that the
%% backing store can be swapped (e.g. to Amazon S3, a database, or any other
%% storage service) without modifying the interpreter or file-I/O layers.
%%
%% Current backend: local disk.  Files are stored in the user's ErlUsers
%% directory as managed by erlbasic_storage.
%%
%% To implement a new backend, add a new open_<backend>/3 clause and route
%% open/3 to it based on configuration.
%%
%% Channel entry contract — the map returned by open/3 must contain at least:
%%
%%   #{mode    => input | output | append | random,
%%     io      => io_device(),      %% file descriptor or equivalent
%%     path    => string(),         %% opaque storage key used for quota checks
%%     eof     => boolean()}        %% input channels only (others omit)
%%
%% Random-mode entries additionally carry:
%%   #{rec_len => pos_integer(),    %% record length in bytes
%%     fields  => [field_def()]}    %% populated by FIELD statement

-module(erlbasic_filestore).

-export([validate_name/1, open/3, close/1]).

%% ===================================================================
%% Public API
%% ===================================================================

%% @doc Validate a BASIC filename.
%%
%% A valid BASIC filename must be a non-empty string that contains no path
%% separators ('/', '\') or drive-letter colons (':'), and is not '.' or '..'.
%%
%% Returns ok or {error, illegal_file_name}.
-spec validate_name(Name :: string()) -> ok | {error, illegal_file_name}.
validate_name(Name) when is_list(Name), Name =/= [] ->
    HasBadChar = lists:any(fun(C) -> C =:= $/ orelse C =:= $\\ orelse C =:= $: end, Name),
    IsDots = (Name =:= "." orelse Name =:= ".."),
    case HasBadChar orelse IsDots of
        true  -> {error, illegal_file_name};
        false -> ok
    end;
validate_name(_) ->
    {error, illegal_file_name}.

%% @doc Open a BASIC file channel for read, write, append, or random access.
%%
%% Name       - BASIC filename (validated; must pass validate_name/1)
%% Mode       - one of "INPUT" | "OUTPUT" | "APPEND" | "RANDOM"
%% RecLenValue - record length for random mode (integer, float, string,
%%              or 'undefined' to use the default of 128 bytes)
%%
%% Returns {ok, Entry} on success, or {error, Reason} where Reason is an
%% atom understood by erlbasic_eval:format_runtime_error/1.
-spec open(Name :: string(), Mode :: string(), RecLenValue :: term()) ->
        {ok, map()} | {error, atom()}.
open(Name, Mode, RecLenValue) ->
    case validate_name(Name) of
        {error, _} = Err ->
            Err;
        ok ->
            case resolve_open_path(Name, Mode) of
                {ok, Key} ->
                    open_backend(Key, Mode, RecLenValue);
                {error, _} ->
                    {error, illegal_function_call}
            end
    end.

close(Entry) ->
    case maps:get(backend, Entry, local) of
        s3 ->
            close_s3(Entry);
        _ ->
            close_local(Entry)
    end.

open_backend(Key, Mode, RecLenValue) ->
    case backend_kind() of
        s3 -> open_s3(Key, Mode, RecLenValue);
        _ -> open_local(Key, Mode, RecLenValue)
    end.

backend_kind() ->
    case application:get_env(erlbasic, storage_backend, local) of
        s3 -> s3;
        erlbasic_storage_s3 -> s3;
        Module when is_atom(Module), Module =/= local, Module =/= erlbasic_storage_local -> s3;
        _ -> local
    end.

%% ===================================================================
%% Local disk backend
%%
%% Replace these open_local/* clauses to implement an alternative backend
%% (e.g. open_s3/* that buffers to a temp file and uploads on close).
%% ===================================================================

open_local(Key, "INPUT", _RecLenValue) ->
    Path = erlbasic_storage_local:key_to_path(Key),
    case file:open(Path, [read]) of
        {ok, Io} ->
            {ok, #{mode => input, io => Io, path => Key, local_path => Path,
                   eof => false, backend => local}};
        {error, enoent} -> {error, illegal_function_call};
        _ -> {error, illegal_function_call}
    end;
open_local(Key, "OUTPUT", _RecLenValue) ->
    Path = erlbasic_storage_local:key_to_path(Key),
    case file:open(Path, [write]) of
        {ok, Io} ->
            {ok, #{mode => output, io => Io, path => Key, local_path => Path,
                   backend => local}};
        _ -> {error, illegal_function_call}
    end;
open_local(Key, "APPEND", _RecLenValue) ->
    Path = erlbasic_storage_local:key_to_path(Key),
    case file:open(Path, [append]) of
        {ok, Io} ->
            {ok, #{mode => append, io => Io, path => Key, local_path => Path,
                   backend => local}};
        _ -> {error, illegal_function_call}
    end;
open_local(Key, "RANDOM", RecLenValue) ->
    Path = erlbasic_storage_local:key_to_path(Key),
    RecLen = normalize_rec_len(RecLenValue),
    case file:open(Path, [read, write, binary]) of
        {ok, Io} ->
            {ok, #{mode => random, io => Io, path => Key, local_path => Path,
                   rec_len => RecLen, fields => [], backend => local}};
        {error, enoent} ->
            %% Create the file if it doesn't exist, then reopen read/write.
            case file:open(Path, [write, binary]) of
                {ok, Io0} ->
                    ok = file:close(Io0),
                    case file:open(Path, [read, write, binary]) of
                        {ok, Io1} ->
                            {ok, #{mode => random, io => Io1, path => Key,
                                   local_path => Path, rec_len => RecLen,
                                   fields => [], backend => local}};
                        _ ->
                            {error, illegal_function_call}
                    end;
                _ ->
                    {error, illegal_function_call}
            end;
        _ ->
            {error, illegal_function_call}
    end;
open_local(_Path, _Mode, _RecLenValue) ->
    {error, illegal_function_call}.

open_s3(Key, "INPUT", _RecLenValue) ->
    S3 = s3_module(),
    TempPath = temp_path_for_key(Key),
    case ensure_parent_dir(TempPath) of
        ok ->
            case S3:read(Key) of
                {ok, Bin} ->
                    case file:write_file(TempPath, Bin) of
                        ok ->
                            case file:open(TempPath, [read]) of
                                {ok, Io} ->
                                    {ok, #{mode => input, io => Io, path => Key,
                                           local_path => TempPath, eof => false,
                                           backend => s3, temp_path => TempPath,
                                           upload_on_close => false}};
                                _ ->
                                    cleanup_temp(TempPath),
                                    {error, illegal_function_call}
                            end;
                        _ ->
                            cleanup_temp(TempPath),
                            {error, illegal_function_call}
                    end;
                {error, enoent} ->
                    cleanup_temp(TempPath),
                    {error, illegal_function_call};
                _ ->
                    cleanup_temp(TempPath),
                    {error, illegal_function_call}
            end;
        _ ->
            {error, illegal_function_call}
    end;
open_s3(Key, "OUTPUT", _RecLenValue) ->
    TempPath = temp_path_for_key(Key),
    case ensure_parent_dir(TempPath) of
        ok ->
            case file:open(TempPath, [write]) of
                {ok, Io} ->
                    {ok, #{mode => output, io => Io, path => Key,
                           local_path => TempPath, backend => s3,
                           temp_path => TempPath, upload_on_close => true}};
                _ ->
                    cleanup_temp(TempPath),
                    {error, illegal_function_call}
            end;
        _ ->
            {error, illegal_function_call}
    end;
open_s3(Key, "APPEND", _RecLenValue) ->
    S3 = s3_module(),
    TempPath = temp_path_for_key(Key),
    case ensure_parent_dir(TempPath) of
        ok ->
            case S3:read(Key) of
                {ok, Bin} ->
                    case file:write_file(TempPath, Bin) of
                        ok -> open_s3_append_temp(Key, TempPath);
                        _ ->
                            cleanup_temp(TempPath),
                            {error, illegal_function_call}
                    end;
                {error, enoent} ->
                    open_s3_append_temp(Key, TempPath);
                _ ->
                    cleanup_temp(TempPath),
                    {error, illegal_function_call}
            end;
        _ ->
            {error, illegal_function_call}
    end;
open_s3(Key, "RANDOM", RecLenValue) ->
    S3 = s3_module(),
    TempPath = temp_path_for_key(Key),
    RecLen = normalize_rec_len(RecLenValue),
    case ensure_parent_dir(TempPath) of
        ok ->
            case S3:read(Key) of
                {ok, Bin} ->
                    case file:write_file(TempPath, Bin, [binary]) of
                        ok -> open_s3_random_temp(Key, TempPath, RecLen);
                        _ ->
                            cleanup_temp(TempPath),
                            {error, illegal_function_call}
                    end;
                {error, enoent} ->
                    case file:open(TempPath, [write, binary]) of
                        {ok, Io0} ->
                            ok = file:close(Io0),
                            open_s3_random_temp(Key, TempPath, RecLen);
                        _ ->
                            cleanup_temp(TempPath),
                            {error, illegal_function_call}
                    end;
                _ ->
                    cleanup_temp(TempPath),
                    {error, illegal_function_call}
            end;
        _ ->
            {error, illegal_function_call}
    end;
open_s3(_Key, _Mode, _RecLenValue) ->
    {error, illegal_function_call}.

open_s3_append_temp(Key, TempPath) ->
    case file:open(TempPath, [append]) of
        {ok, Io} ->
            {ok, #{mode => append, io => Io, path => Key,
                   local_path => TempPath, backend => s3,
                   temp_path => TempPath, upload_on_close => true}};
        _ ->
            cleanup_temp(TempPath),
            {error, illegal_function_call}
    end.

open_s3_random_temp(Key, TempPath, RecLen) ->
    case file:open(TempPath, [read, write, binary]) of
        {ok, Io} ->
            {ok, #{mode => random, io => Io, path => Key,
                   local_path => TempPath, rec_len => RecLen, fields => [],
                   backend => s3, temp_path => TempPath,
                   upload_on_close => true}};
        _ ->
            cleanup_temp(TempPath),
            {error, illegal_function_call}
    end.

close_local(Entry) ->
    case catch file:close(maps:get(io, Entry)) of
        ok -> ok;
        _ -> {error, illegal_function_call}
    end.

close_s3(Entry) ->
    S3 = s3_module(),
    _ = catch file:close(maps:get(io, Entry)),
    TempPath = maps:get(temp_path, Entry, undefined),
    Upload = maps:get(upload_on_close, Entry, false),
    Result =
        case Upload of
            true ->
                Key = maps:get(path, Entry),
                case file:read_file(TempPath) of
                    {ok, Bin} ->
                        case S3:write(Key, Bin) of
                            ok -> ok;
                            {error, _} -> {error, illegal_function_call}
                        end;
                    _ ->
                        {error, illegal_function_call}
                end;
            false ->
                ok
        end,
    _ = cleanup_temp(TempPath),
    Result.

%% ===================================================================
%% Internal helpers
%% ===================================================================

normalize_rec_len(undefined)                   -> 128;
normalize_rec_len(N) when is_integer(N), N > 0 -> N;
normalize_rec_len(F) when is_float(F),   F > 0 -> trunc(F);
normalize_rec_len(S) when is_list(S) ->
    case string:to_integer(string:trim(S)) of
        {N, ""} when N > 0 -> N;
        _                  -> 128
    end;
normalize_rec_len(_) -> 128.

temp_path_for_key(Key) ->
    Root = filename:join(temp_root(), "erlbasic_s3_channels"),
    filename:join([Root | string:split(Key, "/", all)]).

temp_root() ->
    case os:getenv("TMPDIR") of
        false ->
            case os:getenv("TMP") of
                false ->
                    case os:getenv("TEMP") of
                        false -> ".";
                        Dir3 -> Dir3
                    end;
                Dir2 -> Dir2
            end;
        Dir1 -> Dir1
    end.

ensure_parent_dir(Path) ->
    filelib:ensure_dir(Path).

cleanup_temp(undefined) ->
    ok;
cleanup_temp(Path) ->
    _ = file:delete(Path),
    ok.

s3_module() ->
    case application:get_env(erlbasic, storage_s3_module) of
        {ok, Module} when is_atom(Module) -> Module;
        _ -> erlbasic_storage_s3
    end.

resolve_open_path(Name, "INPUT") ->
    erlbasic_storage:resolve_existing_program_key(Name);
resolve_open_path(Name, _Mode) ->
    erlbasic_storage:program_key_for_write(Name).
