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
         user_dir/0,
         user_ppn_string/0,
         ensure_user_dir/0]).

%% ===================================================================
%% Public API
%% ===================================================================

%% @doc Read a program file from the user's storage area.
-spec read_program(FileName :: string()) -> {ok, binary()} | {error, term()}.
read_program(FileName) ->
    case ensure_user_dir() of
        {ok, Dir} ->
            file:read_file(filename:join(Dir, FileName));
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Write (create or overwrite) a program file in the user's storage area.
-spec write_program(FileName :: string(), Content :: binary() | iolist()) ->
        ok | {error, term()}.
write_program(FileName, Content) ->
    case ensure_user_dir() of
        {ok, Dir} ->
            Path = filename:join(Dir, FileName),
            ContentBin = iolist_to_binary(Content),
            case check_quota_for_size(Path, byte_size(ContentBin)) of
                ok ->
                    file:write_file(Path, ContentBin);
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Check whether writing a file to TargetSize bytes would exceed quota.
-spec check_quota_for_size(Path :: string(), TargetSize :: non_neg_integer()) ->
        ok | {error, quota_exceeded | term()}.
check_quota_for_size(Path, TargetSize) when is_integer(TargetSize), TargetSize >= 0 ->
    case ensure_user_dir() of
        {ok, Dir} ->
            case project_limit_bytes() of
                unlimited ->
                    ok;
                LimitBytes when is_integer(LimitBytes), LimitBytes >= 0 ->
                    case total_usage_bytes(Dir) of
                        {ok, TotalBytes} ->
                            OldSize =
                                case path_in_user_dir(Path, Dir) of
                                    true -> file_size(Path);
                                    false -> 0
                                end,
                            Projected = TotalBytes - OldSize + TargetSize,
                            case Projected =< LimitBytes of
                                true -> ok;
                                false -> {error, quota_exceeded}
                            end;
                        {error, Reason} ->
                            {error, Reason}
                    end
            end;
        {error, Reason} ->
            {error, Reason}
    end;
check_quota_for_size(_Path, _TargetSize) ->
    {error, quota_exceeded}.

%% @doc Check whether growing a file by GrowthBytes would exceed quota.
-spec check_quota_for_growth(Path :: string(), GrowthBytes :: non_neg_integer()) ->
        ok | {error, quota_exceeded | term()}.
check_quota_for_growth(Path, GrowthBytes) when is_integer(GrowthBytes), GrowthBytes >= 0 ->
    CurrentSize = file_size(Path),
    check_quota_for_size(Path, CurrentSize + GrowthBytes);
check_quota_for_growth(_Path, _GrowthBytes) ->
    {error, quota_exceeded}.

%% @doc List the names of all program files in the user's storage area.
-spec list_programs() -> {ok, [string()]} | {error, term()}.
list_programs() ->
    case ensure_user_dir() of
        {ok, Dir} ->
            list_regular_files(Dir);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc List program files with metadata (name, size, mtime).
-spec list_programs_with_info() -> {ok, [{string(), integer(), integer()}]} | {error, term()}.
list_programs_with_info() ->
    case ensure_user_dir() of
        {ok, Dir} ->
            list_files_with_info(Dir);
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Delete a program file from the user's storage area.
-spec delete_program(FileName :: string()) -> ok | {error, term()}.
delete_program(FileName) ->
    case ensure_user_dir() of
        {ok, Dir} ->
            file:delete(filename:join(Dir, FileName));
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Return the filesystem path of the current user's storage directory.
%%      Intended for display purposes only; do not build paths from this.
-spec user_dir() -> string().
user_dir() ->
    filename:join(erl_users_root(), user_subdir()).

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
    Dir = user_dir(),
    case filelib:ensure_dir(filename:join(Dir, ".keep")) of
        ok    -> {ok, Dir};
        Error -> Error
    end.

%% ===================================================================
%% Internal – local disk backend
%% ===================================================================

%% Root of all per-user storage: ~/ErlUsers/
erl_users_root() ->
    filename:join(home_dir(), "ErlUsers").

%% Per-user subdirectory derived from the PPN stored in the process dict.
%% Format: "P_N"  (e.g. PPN {1,1} → "1_1"),  or "default" if unknown.
user_subdir() ->
    case erlang:get(erlbasic_ppn) of
        {P, N} ->
            integer_to_list(P) ++ "_" ++ integer_to_list(N);
        _ ->
            "default"
    end.

home_dir() ->
    case os:getenv("HOME") of
        false ->
            case os:getenv("USERPROFILE") of
                false -> ".";
                Path  -> Path
            end;
        Path -> Path
    end.

-include_lib("kernel/include/file.hrl").

list_regular_files(Dir) ->
    case file:list_dir(Dir) of
        {ok, Names} ->
            {ok, lists:sort([N || N <- Names, is_regular_file(Dir, N)])};
        {error, Reason} ->
            {error, Reason}
    end.

is_regular_file(Dir, Name) ->
    case file:read_file_info(filename:join(Dir, Name)) of
        {ok, #file_info{type = regular}} -> true;
        _ -> false
    end.

list_files_with_info(Dir) ->
    case file:list_dir(Dir) of
        {ok, Names} ->
            Infos = lists:filtermap(fun(N) -> get_file_info(Dir, N) end, Names),
            {ok, lists:sort(Infos)};
        {error, Reason} ->
            {error, Reason}
    end.

get_file_info(Dir, Name) ->
    Path = filename:join(Dir, Name),
    case file:read_file_info(Path) of
        {ok, #file_info{type = regular, size = Size, mtime = MTime}} ->
            %% Convert mtime to Unix timestamp
            UnixTime = calendar:datetime_to_gregorian_seconds(MTime) - 62167219200,
            {true, {Name, Size, UnixTime}};
        _ ->
            false
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

total_usage_bytes(Dir) ->
    case list_files_with_info(Dir) of
        {ok, Infos} ->
            {ok, lists:sum([Size || {_Name, Size, _MTime} <- Infos])};
        {error, Reason} ->
            {error, Reason}
    end.

file_size(Path) ->
    case file:read_file_info(Path) of
        {ok, #file_info{type = regular, size = Size}} -> Size;
        _ -> 0
    end.

path_in_user_dir(Path, UserDir) ->
    AbsPath = filename:absname(Path),
    AbsDir = filename:absname(UserDir),
    Prefix = AbsDir ++ [$/],
    lists:prefix(Prefix, AbsPath) orelse AbsPath =:= AbsDir.
