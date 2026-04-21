%% @doc Abstract file storage for per-user BASIC programs.
%%
%% All file I/O for saved/loaded BASIC programs goes through this module so
%% that the backing store can be swapped (e.g. to a cloud storage service)
%% without touching the interpreter or connection layers.
%%
%% Current implementation: local disk under
%%   ~/ErlUsers/[Project,Programmer]/
%%
%% The user is identified by the PPN stored in the process dictionary under
%% the key `erlbasic_ppn'.  If that key is absent (e.g. tests or the TCP
%% fallback) the directory "default" is used.
%%
%% Public API (backend-agnostic):
%%
%%   read_program(FileName)     -> {ok, Bin} | {error, Reason}
%%   write_program(FileName, Bin) -> ok | {error, Reason}
%%   list_programs()            -> {ok, [Name]} | {error, Reason}
%%   delete_program(FileName)   -> ok | {error, Reason}
%%   user_dir()                 -> string()   (for display only)

-module(erlbasic_storage).

-export([read_program/1,
         write_program/2,
         list_programs/0,
         list_programs_with_info/0,
         delete_program/1,
         check_quota_for_size/2,
         check_quota_for_growth/2,
         resolve_existing_program_key/1,
         program_key_for_write/1,
         resolve_existing_program_path/1,
         program_path_for_write/1,
         user_dir/0,
         user_ppn_string/0,
         ensure_user_dir/0,
         startup_status/0]).

-define(S3_STARTUP_PROBE_PREFIX, "__erlbasic_startup_probe__").

%% ===================================================================
%% Public API
%% ===================================================================

%% @doc Read a program file from the user's storage area.
-spec read_program(FileName :: string()) -> {ok, binary()} | {error, term()}.
read_program(FileName) ->
    case erlbasic_filestore:validate_name(FileName) of
        {error, _} = Err -> Err;
        ok ->
    case find_existing_program_key(FileName) of
        {ok, Key} ->
            apply(backend(), read, [Key]);
        {error, enoent} ->
            {error, enoent};
        {error, Reason} ->
            {error, Reason}
    end
    end.

%% @doc Write (create or overwrite) a program file in the user's storage area.
-spec write_program(FileName :: string(), Content :: binary() | iolist()) ->
        ok | {error, term()}.
write_program(FileName, Content) ->
    case erlbasic_filestore:validate_name(FileName) of
        {error, _} = Err -> Err;
        ok ->
    case program_key_for_write(FileName) of
        {ok, Key} ->
            ContentBin = iolist_to_binary(Content),
            case check_quota_for_size(Key, byte_size(ContentBin)) of
                ok ->
                    apply(backend(), write, [Key, ContentBin]);
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end
    end.

%% @doc Check whether writing a file to TargetSize bytes would exceed quota.
-spec check_quota_for_size(Key :: string(), TargetSize :: non_neg_integer()) ->
        ok | {error, quota_exceeded | term()}.
check_quota_for_size(Key, TargetSize) when is_integer(TargetSize), TargetSize >= 0 ->
    case project_limit_bytes() of
        unlimited ->
            ok;
        LimitBytes when is_integer(LimitBytes), LimitBytes >= 0 ->
            case list_programs_with_info() of
                {ok, Infos} ->
                    TotalBytes = lists:sum([Size || {_Name, Size, _MTime} <- Infos]),
                    OldSize = existing_size_for_key(Key, Infos),
                    Projected = TotalBytes - OldSize + TargetSize,
                    case Projected =< LimitBytes of
                        true -> ok;
                        false -> {error, quota_exceeded}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end
    end;
check_quota_for_size(_Key, _TargetSize) ->
    {error, quota_exceeded}.

%% @doc Check whether growing a file by GrowthBytes would exceed quota.
-spec check_quota_for_growth(Key :: string(), GrowthBytes :: non_neg_integer()) ->
        ok | {error, quota_exceeded | term()}.
check_quota_for_growth(Key, GrowthBytes) when is_integer(GrowthBytes), GrowthBytes >= 0 ->
    check_quota_for_size(Key, current_size(Key) + GrowthBytes);
check_quota_for_growth(_Key, _GrowthBytes) ->
    {error, quota_exceeded}.

%% @doc List the names of all program files in the user's storage area.
-spec list_programs() -> {ok, [string()]} | {error, term()}.
list_programs() ->
    case list_programs_with_info() of
        {ok, Infos} ->
            {ok, [Name || {Name, _Size, _MTime} <- Infos]};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc List program files with metadata (name, size, mtime).
-spec list_programs_with_info() -> {ok, [{string(), integer(), integer()}]} | {error, term()}.
list_programs_with_info() ->
    apply(backend(), list, [user_prefix()]).

%% @doc Delete a program file from the user's storage area.
-spec delete_program(FileName :: string()) -> ok | {error, term()}.
delete_program(FileName) ->
    case erlbasic_filestore:validate_name(FileName) of
        {error, _} = Err -> Err;
        ok ->
    case find_existing_program_key(FileName) of
        {ok, Key} ->
            apply(backend(), delete, [Key]);
        {error, enoent} ->
            {error, enoent};
        {error, Reason} ->
            {error, Reason}
    end
    end.

resolve_existing_program_key(FileName) ->
    find_existing_program_key(FileName).

program_key_for_write(FileName) ->
    case find_existing_program_key(FileName) of
        {ok, Key} ->
            {ok, Key};
        {error, enoent} ->
            {ok, user_key(FileName)};
        {error, Reason} ->
            {error, Reason}
    end.

find_existing_program_key(FileName) ->
    case direct_existing_program_key(FileName) of
        {ok, _} = Ok ->
            Ok;
        {error, enoent} ->
            find_existing_program_key_by_listing(FileName);
        {error, Reason} ->
            {error, Reason}
    end.

direct_existing_program_key(FileName) ->
    DirectKeys = [user_key(Name) || Name <- direct_name_candidates(FileName)],
    case first_existing_key(DirectKeys) of
        undefined -> {error, enoent};
        Key -> {ok, Key}
    end.

find_existing_program_key_by_listing(FileName) ->
    case list_programs_with_info() of
        {ok, Infos} ->
            Names = [Name || {Name, _Size, _MTime} <- Infos],
            case pick_case_insensitive_name(FileName, Names) of
                undefined -> {error, enoent};
                ExistingName -> {ok, user_key(ExistingName)}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

resolve_existing_program_path(FileName) ->
    resolve_existing_program_key(FileName).

program_path_for_write(FileName) ->
    program_key_for_write(FileName).

%% @doc Return the current user's storage location string.
%%      Intended for display purposes only; do not build keys from this.
-spec user_dir() -> string().
user_dir() ->
    case backend() of
        erlbasic_storage_local ->
            erlbasic_storage_local:user_dir(user_prefix());
        _ ->
            user_prefix()
    end.

%% @doc Return the user's PPN as a formatted string "[P,N]".
-spec user_ppn_string() -> string().
user_ppn_string() ->
    case erlang:get(erlbasic_ppn) of
        {P, N} ->
            "[" ++ integer_to_list(P) ++ "," ++ integer_to_list(N) ++ "]";
        _ ->
            "[1,2]"
    end.

%% @doc Ensure the user's storage directory exists, creating it if needed.
-spec ensure_user_dir() -> {ok, string()} | {error, term()}.
ensure_user_dir() ->
    case backend() of
        erlbasic_storage_local ->
            erlbasic_storage_local:ensure_prefix(user_prefix());
        _ ->
            {ok, user_dir()}
    end.

startup_status() ->
    case application:get_env(erlbasic, storage_backend, local) of
        s3 ->
            startup_status_s3(storage_s3_module());
        Backend ->
            {Backend, skipped}
    end.

%% ===================================================================
%% Internal helpers
%% ===================================================================

backend() ->
    case application:get_env(erlbasic, storage_backend, local) of
        local -> erlbasic_storage_local;
        s3 -> storage_s3_module();
        Module when is_atom(Module) -> Module
    end.

storage_s3_module() ->
    case application:get_env(erlbasic, storage_s3_module) of
        {ok, Module} when is_atom(Module) -> Module;
        _ -> erlbasic_storage_s3
    end.

startup_status_s3(Module) ->
    case run_s3_startup_probe(Module) of
        {ok, _Entries} ->
            {s3, ok, Module};
        {error, Reason} ->
            case maybe_create_missing_s3_bucket(Module, Reason) of
                ok ->
                    case run_s3_startup_probe(Module) of
                        {ok, _RetryEntries} ->
                            {s3, ok, Module};
                        {error, RetryReason} ->
                            {s3, {error, RetryReason}, Module}
                    end;
                {error, _} ->
                    {s3, {error, Reason}, Module};
                skip ->
                    {s3, {error, Reason}, Module}
            end
    end.

run_s3_startup_probe(Module) ->
    try apply(Module, list, [?S3_STARTUP_PROBE_PREFIX]) of
        {ok, _Entries} = Ok ->
            Ok;
        {error, _Reason} = Err ->
            Err;
        Other ->
            {error, {unexpected_response, Other}}
    catch
        Class:Reason ->
            {error, {Class, Reason}}
    end.

maybe_create_missing_s3_bucket(Module, Reason) ->
    case is_missing_s3_bucket_reason(Reason) andalso module_supports_ensure_bucket(Module) of
        true ->
            apply(Module, ensure_bucket, []);
        false ->
            skip
    end.

module_supports_ensure_bucket(Module) ->
    case code:ensure_loaded(Module) of
        {module, Module} -> erlang:function_exported(Module, ensure_bucket, 0);
        _ -> false
    end.

is_missing_s3_bucket_reason(Reason) ->
    ReasonText = string:to_lower(lists:flatten(io_lib:format("~0p", [Reason]))),
    string:str(ReasonText, "nosuchbucket") > 0 orelse
        string:str(ReasonText, "bucket does not exist") > 0.

user_prefix() ->
    user_subdir().

user_key(Name) ->
    user_prefix() ++ "/" ++ Name.

%% Per-user subdirectory derived from the PPN stored in the process dict.
%% Format: "P_N"  (e.g. PPN {1,1} → "1_1"),  or "default" if unknown.
user_subdir() ->
    case erlang:get(erlbasic_ppn) of
        {P, N} ->
            integer_to_list(P) ++ "_" ++ integer_to_list(N);
        _ ->
            "default"
    end.

project_limit_bytes() ->
    case erlang:get(erlbasic_ppn) of
        {P, _N} when P =:= 0; P =:= 1 ->
            unlimited;
        {P, N} ->
            Blocks = erlbasic_limits:get_effective_limit_blocks(P, N),
            blocks_to_bytes(Blocks);
        _ ->
            blocks_to_bytes(erlbasic_limits:default_limit_blocks())
    end.

blocks_to_bytes(unlimited) ->
    unlimited;
blocks_to_bytes(Blocks) when is_integer(Blocks), Blocks >= 0 ->
    Blocks * 1024;
blocks_to_bytes(_Other) ->
    erlbasic_limits:default_limit_blocks() * 1024.

current_size(Key) ->
    case list_programs_with_info() of
        {ok, Infos} ->
            existing_size_for_key(Key, Infos);
        {error, _Reason} ->
            0
    end.

existing_size_for_key(Key, Infos) ->
    case key_in_user_prefix(Key, user_prefix()) of
        true ->
            Name = key_name(Key),
            case lists:keyfind(Name, 1, Infos) of
                {Name, Size, _MTime} -> Size;
                false -> 0
            end;
        false ->
            0
    end.

key_in_user_prefix(Key, Prefix) ->
    Key =:= Prefix orelse lists:prefix(Prefix ++ "/", Key).

key_name(Key) ->
    hd(lists:reverse(string:split(Key, "/", all))).

pick_case_insensitive_name(FileName, Names) ->
    case lists:member(FileName, Names) of
        true ->
            FileName;
        false ->
            FoldedTarget = filename_key(FileName),
            Matches = lists:sort([Name || Name <- Names, filename_key(Name) =:= FoldedTarget]),
            case Matches of
                [Match | _] -> Match;
                [] -> undefined
            end
    end.

filename_key(Name) ->
    string:to_upper(Name).

first_existing_key([Key | Rest]) ->
    case apply(backend(), key_exists, [Key]) of
        true -> Key;
        false -> first_existing_key(Rest)
    end;
first_existing_key([]) ->
    undefined.

direct_name_candidates(FileName) ->
    Base = filename:rootname(FileName),
    Ext = filename:extension(FileName),
    lists:reverse(
        lists:foldl(
            fun(Name, Acc) ->
                case lists:member(Name, Acc) of
                    true -> Acc;
                    false -> [Name | Acc]
                end
            end,
            [],
            case Ext of
                [] ->
                    [FileName,
                     string:to_lower(FileName),
                     string:to_upper(FileName)];
                _ ->
                    [FileName,
                     Base ++ string:to_lower(Ext),
                     Base ++ string:to_upper(Ext),
                     string:to_lower(Base) ++ string:to_lower(Ext),
                     string:to_lower(Base) ++ string:to_upper(Ext),
                     string:to_upper(Base) ++ string:to_lower(Ext),
                     string:to_upper(Base) ++ string:to_upper(Ext),
                     string:to_lower(FileName),
                     string:to_upper(FileName)]
            end)).
