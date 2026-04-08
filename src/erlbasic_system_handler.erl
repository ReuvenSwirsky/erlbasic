-module(erlbasic_system_handler).
-export([init/2]).

-include_lib("kernel/include/file.hrl").

init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    dispatch(Method, Path, Req, State).

dispatch(<<"GET">>, P, Req, State)
        when P =:= <<"/a/system">>; P =:= <<"/a/system/">> ->
    serve_html(Req, State);

dispatch(<<"GET">>, <<"/a/system/stats">>, Req, State) ->
    with_auth(fun() ->
        Stats = system_stats(),
        reply_json(200, map_to_json(Stats), Req, State)
    end, Req, State);

dispatch(_, _, Req, State) ->
    reply(404, <<"Not Found">>, Req, State).

with_auth(Fun, Req, State) ->
    case check_auth(Req) of
        {ok, _P, _N} -> Fun();
        unauthorized -> reply_unauthorized(Req, State)
    end.

check_auth(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        <<"Basic ", Encoded/binary>> ->
            try
                Decoded = base64:decode(Encoded),
                [UserBin, PassBin] = binary:split(Decoded, <<":">>),
                {ok, P, N} = parse_ppn_bin(UserBin),
                case erlbasic_accounts:authenticate(P, N, PassBin) of
                    {ok, _} ->
                        case erlbasic_accounts:is_privileged(P, N) of
                            true -> {ok, P, N};
                            false -> unauthorized
                        end;
                    _ ->
                        unauthorized
                end
            catch
                _:_ -> unauthorized
            end;
        _ ->
            unauthorized
    end.

parse_ppn_bin(Bin) ->
    case binary:split(Bin, <<",">>) of
        [PBin, NBin] ->
            P = binary_to_integer(string:trim(PBin)),
            N = binary_to_integer(string:trim(NBin)),
            {ok, P, N};
        _ ->
            error(bad_ppn)
    end.

serve_html(Req, State) ->
    PrivDir = code:priv_dir(erlbasic),
    Path = filename:join([PrivDir, "www", "system.html"]),
    case file:read_file(Path) of
        {ok, Body} ->
            Req2 = cowboy_req:reply(200,
                #{<<"content-type">> => <<"text/html; charset=utf-8">>},
                Body, Req),
            {ok, Req2, State};
        {error, Reason} ->
            Body = iolist_to_binary(io_lib:format("Cannot read system.html: ~p", [Reason])),
            Req2 = cowboy_req:reply(500, #{}, Body, Req),
            {ok, Req2, State}
    end.

system_stats() ->
    WdStats = watchdog_stats(),
    MemoryList = erlang:memory(),
    MemoryMap = maps:from_list(MemoryList),
    AccountsCount = case erlbasic_accounts:list_accounts() of
        {ok, Accounts} -> length(Accounts);
        _ -> 0
    end,

    {StorageBytes, StorageFiles, StorageDirs} = storage_usage(),

    #{
        node => atom_to_binary(node(), utf8),
        otp_release => list_to_binary(erlang:system_info(otp_release)),
        process_count => erlang:system_info(process_count),
        process_limit => erlang:system_info(process_limit),
        schedulers => erlang:system_info(schedulers),
        schedulers_online => erlang:system_info(schedulers_online),
        run_queue => erlang:statistics(run_queue),

        users_total => AccountsCount,
        users_logged_in => maps:get(active_users, WdStats, 0),
        sessions_active => maps:get(active_sessions, WdStats, 0),

        session_memory_bytes => maps:get(session_memory_bytes, WdStats, 0),
        memory_total_bytes => maps:get(total, MemoryMap, 0),
        memory_processes_bytes => maps:get(processes, MemoryMap, 0),
        memory_system_bytes => maps:get(system, MemoryMap, 0),
        memory_binary_bytes => maps:get(binary, MemoryMap, 0),
        memory_ets_bytes => maps:get(ets, MemoryMap, 0),

        storage_total_bytes => StorageBytes,
        storage_files => StorageFiles,
        storage_user_dirs => StorageDirs,
        default_storage_limit_blocks => erlbasic_limits:default_limit_blocks(),
        default_memory_limit_kb => erlbasic_limits:default_memory_limit_kb()
    }.

watchdog_stats() ->
    try erlbasic_mem_watchdog:get_stats() of
        Stats when is_map(Stats) -> Stats;
        _ -> #{}
    catch
        _:_ -> #{}
    end.

storage_usage() ->
    Root = erl_users_root(),
    case file:list_dir(Root) of
        {ok, Entries} ->
            lists:foldl(
                fun(Name, {BytesAcc, FilesAcc, DirAcc}) ->
                    Path = filename:join(Root, Name),
                    case file:read_file_info(Path) of
                        {ok, #file_info{type = directory}} ->
                            {DirBytes, DirFiles} = dir_usage(Path),
                            {BytesAcc + DirBytes, FilesAcc + DirFiles, DirAcc + 1};
                        {ok, #file_info{type = regular, size = Size}} ->
                            {BytesAcc + Size, FilesAcc + 1, DirAcc};
                        _ ->
                            {BytesAcc, FilesAcc, DirAcc}
                    end
                end,
                {0, 0, 0},
                Entries);
        _ ->
            {0, 0, 0}
    end.

dir_usage(Dir) ->
    case file:list_dir(Dir) of
        {ok, Entries} ->
            lists:foldl(
                fun(Name, {BytesAcc, FilesAcc}) ->
                    Path = filename:join(Dir, Name),
                    case file:read_file_info(Path) of
                        {ok, #file_info{type = regular, size = Size}} ->
                            {BytesAcc + Size, FilesAcc + 1};
                        {ok, #file_info{type = directory}} ->
                            {NestedBytes, NestedFiles} = dir_usage(Path),
                            {BytesAcc + NestedBytes, FilesAcc + NestedFiles};
                        _ ->
                            {BytesAcc, FilesAcc}
                    end
                end,
                {0, 0},
                Entries);
        _ ->
            {0, 0}
    end.

erl_users_root() ->
    filename:join(home_dir(), "ErlUsers").

home_dir() ->
    case os:getenv("HOME") of
        false ->
            case os:getenv("USERPROFILE") of
                false -> ".";
                Path  -> Path
            end;
        Path -> Path
    end.

map_to_json(Map) when is_map(Map) ->
    Pairs = maps:to_list(Map),
    Encoded = lists:map(fun({Key, Value}) ->
        K = atom_to_binary(Key, utf8),
        [<<"\"">>, K, <<"\":">>, json_value(Value)]
    end, Pairs),
    iolist_to_binary([<<"{">>, lists:join(<<",">>, Encoded), <<"}">>]).

json_value(V) when is_integer(V) ->
    integer_to_binary(V);
json_value(V) when is_float(V) ->
    iolist_to_binary(io_lib:format("~p", [V]));
json_value(V) when is_atom(V) ->
    [<<"\"">>, atom_to_binary(V, utf8), <<"\"">>];
json_value(V) when is_binary(V) ->
    [<<"\"">>, escape_json(binary_to_list(V)), <<"\"">>];
json_value(V) when is_list(V) ->
    [<<"\"">>, escape_json(V), <<"\"">>];
json_value(V) ->
    [<<"\"">>, escape_json(lists:flatten(io_lib:format("~p", [V]))), <<"\"">>].

escape_json(Str) ->
    lists:flatmap(fun
        ($") -> [$\\, $"];
        ($\\) -> [$\\, $\\];
        (C) when C < 32 -> io_lib:format("\\u~4.16.0B", [C]);
        (C) -> [C]
    end, Str).

reply(Code, Body, Req, State) ->
    {ok, cowboy_req:reply(Code, #{}, Body, Req), State}.

reply_json(Code, Body, Req, State) ->
    Req2 = cowboy_req:reply(Code,
        #{<<"content-type">> => <<"application/json">>},
        Body, Req),
    {ok, Req2, State}.

reply_unauthorized(Req, State) ->
    Req2 = cowboy_req:reply(401,
        #{<<"content-type">> => <<"application/json">>},
        <<"{\"error\":\"unauthorized\"}">>, Req),
    {ok, Req2, State}.
