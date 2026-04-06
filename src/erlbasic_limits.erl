-module(erlbasic_limits).

-export([
    init/0,
    get_effective_limit_blocks/2,
    get_project_limit_blocks/1,
    set_project_limit_blocks/2,
    clear_project_limit/1,
    list_project_limits/0,
    get_user_limit_blocks/2,
    set_user_limit_blocks/3,
    clear_user_limit/2,
    list_user_overrides/0,
    default_limit_blocks/0,

    get_effective_memory_limit_kb/2,
    get_memory_project_limit_kb/1,
    set_memory_project_limit_kb/2,
    clear_memory_project_limit/1,
    list_memory_project_limits/0,
    get_memory_user_limit_kb/2,
    set_memory_user_limit_kb/3,
    clear_memory_user_limit/2,
    list_memory_user_overrides/0,
    default_memory_limit_kb/0
]).

-define(TABLE, erlbasic_limits).

init() ->
    ensure_open().

get_effective_limit_blocks(P, N) when is_integer(P), is_integer(N) ->
    case P of
        0 -> unlimited;
        1 -> unlimited;
        _ ->
            case get_user_limit_blocks(P, N) of
                {ok, Blocks} -> Blocks;
                not_found ->
                    case get_project_limit_blocks(P) of
                        {ok, Blocks} -> Blocks;
                        not_found -> default_limit_blocks();
                        {error, _} -> default_limit_blocks()
                    end;
                {error, _} -> default_limit_blocks()
            end
    end;
get_effective_limit_blocks(_P, _N) ->
    default_limit_blocks().

get_project_limit_blocks(P) when is_integer(P) ->
    with_table(fun() ->
        case dets:lookup(?TABLE, {project, P}) of
            [{{project, P}, Blocks}] -> {ok, Blocks};
            [] -> not_found;
            {error, Reason} -> {error, Reason}
        end
    end);
get_project_limit_blocks(_P) ->
    {error, badarg}.

set_project_limit_blocks(P, Blocks) when is_integer(P), is_integer(Blocks), Blocks > 0 ->
    with_table(fun() ->
        dets:insert(?TABLE, {{project, P}, Blocks})
    end);
set_project_limit_blocks(_P, _Blocks) ->
    {error, badarg}.

clear_project_limit(P) when is_integer(P) ->
    with_table(fun() ->
        dets:delete(?TABLE, {project, P})
    end);
clear_project_limit(_P) ->
    {error, badarg}.

list_project_limits() ->
    with_table(fun() ->
        Folded = dets:foldl(
            fun({{project, P}, Blocks}, Acc) ->
                    [{P, Blocks} | Acc];
               (_, Acc) ->
                    Acc
            end,
            [],
            ?TABLE),
        case Folded of
            {error, Reason} -> {error, Reason};
            List -> {ok, lists:sort(List)}
        end
    end).

get_user_limit_blocks(P, N) when is_integer(P), is_integer(N) ->
    with_table(fun() ->
        case dets:lookup(?TABLE, {user, P, N}) of
            [{{user, P, N}, Blocks}] -> {ok, Blocks};
            [] -> not_found;
            {error, Reason} -> {error, Reason}
        end
    end);
get_user_limit_blocks(_P, _N) ->
    {error, badarg}.

set_user_limit_blocks(P, N, Blocks)
        when is_integer(P), is_integer(N), is_integer(Blocks), Blocks > 0 ->
    with_table(fun() ->
        dets:insert(?TABLE, {{user, P, N}, Blocks})
    end);
set_user_limit_blocks(_P, _N, _Blocks) ->
    {error, badarg}.

clear_user_limit(P, N) when is_integer(P), is_integer(N) ->
    with_table(fun() ->
        dets:delete(?TABLE, {user, P, N})
    end);
clear_user_limit(_P, _N) ->
    {error, badarg}.

list_user_overrides() ->
    with_table(fun() ->
        Folded = dets:foldl(
            fun({{user, P, N}, Blocks}, Acc) ->
                    [{{P, N}, Blocks} | Acc];
               (_, Acc) ->
                    Acc
            end,
            [],
            ?TABLE),
        case Folded of
            {error, Reason} -> {error, Reason};
            List -> {ok, lists:sort(List)}
        end
    end).

default_limit_blocks() ->
    application:get_env(erlbasic, default_storage_limit_blocks, 256).

get_effective_memory_limit_kb(P, N) when is_integer(P), is_integer(N) ->
    case P of
        0 -> unlimited;
        1 -> unlimited;
        _ ->
            case get_memory_user_limit_kb(P, N) of
                {ok, KB} -> KB;
                not_found ->
                    case get_memory_project_limit_kb(P) of
                        {ok, KB} -> KB;
                        not_found -> default_memory_limit_kb();
                        {error, _} -> default_memory_limit_kb()
                    end;
                {error, _} -> default_memory_limit_kb()
            end
    end;
get_effective_memory_limit_kb(_P, _N) ->
    default_memory_limit_kb().

get_memory_project_limit_kb(P) when is_integer(P) ->
    with_table(fun() ->
        case dets:lookup(?TABLE, {memory_project, P}) of
            [{{memory_project, P}, KB}] -> {ok, KB};
            [] -> not_found;
            {error, Reason} -> {error, Reason}
        end
    end);
get_memory_project_limit_kb(_P) ->
    {error, badarg}.

set_memory_project_limit_kb(P, KB) when is_integer(P), is_integer(KB), KB > 0 ->
    with_table(fun() ->
        dets:insert(?TABLE, {{memory_project, P}, KB})
    end);
set_memory_project_limit_kb(_P, _KB) ->
    {error, badarg}.

clear_memory_project_limit(P) when is_integer(P) ->
    with_table(fun() ->
        dets:delete(?TABLE, {memory_project, P})
    end);
clear_memory_project_limit(_P) ->
    {error, badarg}.

list_memory_project_limits() ->
    with_table(fun() ->
        Folded = dets:foldl(
            fun({{memory_project, P}, KB}, Acc) ->
                    [{P, KB} | Acc];
               (_, Acc) ->
                    Acc
            end,
            [],
            ?TABLE),
        case Folded of
            {error, Reason} -> {error, Reason};
            List -> {ok, lists:sort(List)}
        end
    end).

get_memory_user_limit_kb(P, N) when is_integer(P), is_integer(N) ->
    with_table(fun() ->
        case dets:lookup(?TABLE, {memory_user, P, N}) of
            [{{memory_user, P, N}, KB}] -> {ok, KB};
            [] -> not_found;
            {error, Reason} -> {error, Reason}
        end
    end);
get_memory_user_limit_kb(_P, _N) ->
    {error, badarg}.

set_memory_user_limit_kb(P, N, KB)
        when is_integer(P), is_integer(N), is_integer(KB), KB > 0 ->
    with_table(fun() ->
        dets:insert(?TABLE, {{memory_user, P, N}, KB})
    end);
set_memory_user_limit_kb(_P, _N, _KB) ->
    {error, badarg}.

clear_memory_user_limit(P, N) when is_integer(P), is_integer(N) ->
    with_table(fun() ->
        dets:delete(?TABLE, {memory_user, P, N})
    end);
clear_memory_user_limit(_P, _N) ->
    {error, badarg}.

list_memory_user_overrides() ->
    with_table(fun() ->
        Folded = dets:foldl(
            fun({{memory_user, P, N}, KB}, Acc) ->
                    [{{P, N}, KB} | Acc];
               (_, Acc) ->
                    Acc
            end,
            [],
            ?TABLE),
        case Folded of
            {error, Reason} -> {error, Reason};
            List -> {ok, lists:sort(List)}
        end
    end).

default_memory_limit_kb() ->
    application:get_env(erlbasic, default_memory_limit_kb, 512).

with_table(Fun) ->
    case ensure_open() of
        ok -> Fun();
        {error, Reason} -> {error, Reason}
    end.

ensure_open() ->
    case dets:info(?TABLE, file) of
        undefined ->
            DataDir = data_dir(),
            ok = filelib:ensure_dir(filename:join([DataDir, "x"])),
            File = filename:join(DataDir, "limits.dets"),
            case dets:open_file(?TABLE, [{file, File}, {type, set}]) of
                {ok, _} -> ok;
                {error, {already_started, _}} -> ok;
                {error, Reason} -> {error, Reason}
            end;
        _ ->
            ok
    end.

data_dir() ->
    case application:get_env(erlbasic, accounts_dir) of
        {ok, D} -> D;
        undefined -> filename:join([code:priv_dir(erlbasic), "accounts"])
    end.