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
%%     path    => string(),         %% opaque key used for quota checks
%%     eof     => boolean()}        %% input channels only (others omit)
%%
%% Random-mode entries additionally carry:
%%   #{rec_len => pos_integer(),    %% record length in bytes
%%     fields  => [field_def()]}    %% populated by FIELD statement

-module(erlbasic_filestore).

-export([validate_name/1, open/3]).

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
            case erlbasic_storage:ensure_user_dir() of
                {ok, UserDir} ->
                    Path = filename:join(UserDir, Name),
                    open_local(Path, Mode, RecLenValue);
                {error, _} ->
                    {error, illegal_function_call}
            end
    end.

%% ===================================================================
%% Local disk backend
%%
%% Replace these open_local/* clauses to implement an alternative backend
%% (e.g. open_s3/* that buffers to a temp file and uploads on close).
%% ===================================================================

open_local(Path, "INPUT", _RecLenValue) ->
    case file:open(Path, [read]) of
        {ok, Io} -> {ok, #{mode => input, io => Io, path => Path, eof => false}};
        {error, enoent} -> {error, illegal_function_call};
        _ -> {error, illegal_function_call}
    end;
open_local(Path, "OUTPUT", _RecLenValue) ->
    case file:open(Path, [write]) of
        {ok, Io} -> {ok, #{mode => output, io => Io, path => Path}};
        _ -> {error, illegal_function_call}
    end;
open_local(Path, "APPEND", _RecLenValue) ->
    case file:open(Path, [append]) of
        {ok, Io} -> {ok, #{mode => append, io => Io, path => Path}};
        _ -> {error, illegal_function_call}
    end;
open_local(Path, "RANDOM", RecLenValue) ->
    RecLen = normalize_rec_len(RecLenValue),
    case file:open(Path, [read, write, binary]) of
        {ok, Io} ->
            {ok, #{mode => random, io => Io, path => Path,
                   rec_len => RecLen, fields => []}};
        {error, enoent} ->
            %% Create the file if it doesn't exist, then reopen read/write.
            case file:open(Path, [write, binary]) of
                {ok, Io0} ->
                    ok = file:close(Io0),
                    case file:open(Path, [read, write, binary]) of
                        {ok, Io1} ->
                            {ok, #{mode => random, io => Io1, path => Path,
                                   rec_len => RecLen, fields => []}};
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
