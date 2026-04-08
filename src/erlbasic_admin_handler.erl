%% @doc Cowboy HTTP handler for the ErlBASIC admin web interface.
%%
%% Routes (all under /a/admin/...):
%%   GET  /a/admin[/]                   – serve admin.html
%%   GET  /a/admin/accounts             – serve account admin page
%%   GET  /a/admin/storage              – serve storage quota admin page
%%   GET  /a/admin/memory               – serve memory quota admin page
%%   GET  /a/admin/users                – JSON list of accounts  [auth required]
%%   POST /a/admin/users                – create account         [auth required]
%%   DELETE /a/admin/users/:p/:n        – delete account         [auth required]
%%   PUT  /a/admin/users/:p/:n          – change password        [auth required]
%%   GET  /a/admin/limits/projects      – JSON project limits    [auth required]
%%   PUT  /a/admin/limits/projects/:p   – set project limit      [auth required]
%%   DELETE /a/admin/limits/projects/:p – clear project limit    [auth required]
%%   GET  /a/admin/limits/users         – JSON user overrides    [auth required]
%%   PUT  /a/admin/limits/users/:p/:n   – set user override      [auth required]
%%   DELETE /a/admin/limits/users/:p/:n – clear user override    [auth required]
%%   GET  /a/admin/memory-limits/projects      – JSON project memory limits [auth required]
%%   PUT  /a/admin/memory-limits/projects/:p   – set project memory limit   [auth required]
%%   DELETE /a/admin/memory-limits/projects/:p – clear project memory limit [auth required]
%%   GET  /a/admin/memory-limits/users         – JSON user memory overrides  [auth required]
%%   PUT  /a/admin/memory-limits/users/:p/:n   – set user memory override    [auth required]
%%   DELETE /a/admin/memory-limits/users/:p/:n – clear user memory override  [auth required]
%%
%% Authentication uses HTTP Basic Auth.  The username field must be the PPN in
%% "Project,Programmer" notation (e.g. "1,1") and the password is the account
%% password.  Only privileged accounts (project 0 or 1) may access the API.
-module(erlbasic_admin_handler).

-export([init/2]).

init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path   = cowboy_req:path(Req0),
    dispatch(Method, Path, Req0, State).

%% ===================================================================
%% Routing
%% ===================================================================

dispatch(<<"GET">>, P, Req, State)
        when P =:= <<"/a/admin">>; P =:= <<"/a/admin/">>; P =:= <<"/a/admin/accounts">>; P =:= <<"/a/admin/accounts/">> ->
    serve_html(accounts, Req, State);

dispatch(<<"GET">>, P, Req, State)
        when P =:= <<"/a/admin/storage">>; P =:= <<"/a/admin/storage/">> ->
    serve_html(storage, Req, State);

dispatch(<<"GET">>, P, Req, State)
        when P =:= <<"/a/admin/memory">>; P =:= <<"/a/admin/memory/">> ->
    serve_html(memory, Req, State);

dispatch(Method, <<"/a/admin/users">>, Req, State) ->
    with_auth(Method, [], Req, State);

dispatch(Method, <<"/a/admin/users/", Rest/binary>>, Req, State) ->
    Parts = binary:split(Rest, <<"/">>, [global]),
    with_auth(Method, Parts, Req, State);

dispatch(Method, <<"/a/admin/limits/projects">>, Req, State) ->
    with_limits_auth(Method, {projects, []}, Req, State);

dispatch(Method, <<"/a/admin/limits/projects/", Rest/binary>>, Req, State) ->
    Parts = binary:split(Rest, <<"/">>, [global]),
    with_limits_auth(Method, {projects, Parts}, Req, State);

dispatch(Method, <<"/a/admin/limits/users">>, Req, State) ->
    with_limits_auth(Method, {users, []}, Req, State);

dispatch(Method, <<"/a/admin/limits/users/", Rest/binary>>, Req, State) ->
    Parts = binary:split(Rest, <<"/">>, [global]),
    with_limits_auth(Method, {users, Parts}, Req, State);

dispatch(Method, <<"/a/admin/memory-limits/projects">>, Req, State) ->
    with_limits_auth(Method, {memory_projects, []}, Req, State);

dispatch(Method, <<"/a/admin/memory-limits/projects/", Rest/binary>>, Req, State) ->
    Parts = binary:split(Rest, <<"/">>, [global]),
    with_limits_auth(Method, {memory_projects, Parts}, Req, State);

dispatch(Method, <<"/a/admin/memory-limits/users">>, Req, State) ->
    with_limits_auth(Method, {memory_users, []}, Req, State);

dispatch(Method, <<"/a/admin/memory-limits/users/", Rest/binary>>, Req, State) ->
    Parts = binary:split(Rest, <<"/">>, [global]),
    with_limits_auth(Method, {memory_users, Parts}, Req, State);

dispatch(_, _, Req, State) ->
    reply(404, <<"Not Found">>, Req, State).

%% ===================================================================
%% Auth gate
%% ===================================================================

with_auth(Method, Parts, Req, State) ->
    case check_auth(Req) of
        {ok, _P, _N} -> handle_api(Method, Parts, Req, State);
        unauthorized  -> reply_unauthorized(Req, State)
    end.

with_limits_auth(Method, Parts, Req, State) ->
    case check_auth(Req) of
        {ok, _P, _N} -> handle_limits_api(Method, Parts, Req, State);
        unauthorized  -> reply_unauthorized(Req, State)
    end.

check_auth(Req) ->
    case cowboy_req:header(<<"authorization">>, Req) of
        <<"Basic ", Encoded/binary>> ->
            try
                Decoded   = base64:decode(Encoded),
                %% Split on first ":" only – password itself may contain ":"
                [UserBin, PassBin] = binary:split(Decoded, <<":">>),
                {ok, P, N}         = parse_ppn_bin(UserBin),
                case erlbasic_accounts:authenticate(P, N, PassBin) of
                    {ok, _} ->
                        case erlbasic_accounts:is_privileged(P, N) of
                            true  -> {ok, P, N};
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

%% ===================================================================
%% API handlers
%% ===================================================================

%% GET /a/admin/users  – list all accounts as JSON
handle_api(<<"GET">>, [], Req, State) ->
    case erlbasic_accounts:list_accounts() of
        {ok, Accounts} ->
            Json = accounts_to_json(Accounts),
            Req2 = cowboy_req:reply(200,
                #{<<"content-type">> => <<"application/json">>},
                Json, Req),
            {ok, Req2, State};
        {error, _} ->
            reply(500, <<"Server Error">>, Req, State)
    end;

%% POST /a/admin/users  – create account (URL-encoded body)
handle_api(<<"POST">>, [], Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_urlencoded_body(Req0),
    PBin = proplists:get_value(<<"project">>,    Body, <<>>),
    NBin = proplists:get_value(<<"programmer">>, Body, <<>>),
    Pw   = proplists:get_value(<<"password">>,   Body, <<>>),
    Name = proplists:get_value(<<"name">>,        Body, <<>>),
    Username = proplists:get_value(<<"username">>, Body, <<>>),
    case {safe_int(PBin), safe_int(NBin), Pw} of
        {{ok, P}, {ok, N}, Pw} when byte_size(Pw) > 0 ->
            validate_ppn_range(P, N, fun() ->
                validate_username(Username, fun(ValidUsername) ->
                    case erlbasic_accounts:create_account(P, N, Pw, Name, ValidUsername) of
                        ok ->
                            reply_json(201, <<"{\"status\":\"created\"}">>, Req, State);
                        {error, username_too_short} ->
                            reply_json(400,
                                <<"{\"error\":\"username must be at least 2 characters\"}">>,
                                Req, State);
                        {error, reserved_username} ->
                            reply_json(400,
                                <<"{\"error\":\"username is reserved\"}">>,
                                Req, State);
                        {error, username_taken} ->
                            reply_json(400,
                                <<"{\"error\":\"username is already in use\"}">>,
                                Req, State);
                        {error, Reason} ->
                            ErrMsg = iolist_to_binary(
                                io_lib:format("{\"error\":\"~p\"}", [Reason])),
                            reply_json(500, ErrMsg, Req, State)
                    end
                end, Req, State)
            end, Req, State);
        _ ->
            reply_json(400,
                <<"{\"error\":\"project, programmer and password are required\"}">>,
                Req, State)
    end;

%% DELETE /a/admin/users/:p/:n  – delete account
handle_api(<<"DELETE">>, [PBin, NBin], Req, State) ->
    case {safe_int(PBin), safe_int(NBin)} of
        {{ok, P}, {ok, N}} ->
            case erlbasic_accounts:delete_account(P, N) of
                ok ->
                    reply_json(200, <<"{\"status\":\"deleted\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(
                        io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply(400, <<"Bad Request">>, Req, State)
    end;

%% PUT /a/admin/users/:p/:n  – change password (URL-encoded body)
handle_api(<<"PUT">>, [PBin, NBin], Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_urlencoded_body(Req0),
    Pw = proplists:get_value(<<"password">>, Body, <<>>),
    case {safe_int(PBin), safe_int(NBin), Pw} of
        {{ok, P}, {ok, N}, Pw} when byte_size(Pw) > 0 ->
            case erlbasic_accounts:change_password(P, N, Pw) of
                ok ->
                    reply_json(200, <<"{\"status\":\"updated\"}">>, Req, State);
                {error, not_found} ->
                    reply_json(404, <<"{\"error\":\"account not found\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(
                        io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply(400, <<"password is required">>, Req, State)
    end;

handle_api(_, _, Req, State) ->
    reply(405, <<"Method Not Allowed">>, Req, State).

%% ===================================================================
%% Limits API handlers
%% ===================================================================

handle_limits_api(<<"GET">>, {projects, []}, Req, State) ->
    case erlbasic_limits:list_project_limits() of
        {ok, Limits} ->
            Json = project_limits_to_json(Limits),
            reply_json(200, Json, Req, State);
        {error, _} ->
            reply(500, <<"Server Error">>, Req, State)
    end;

handle_limits_api(<<"PUT">>, {projects, [PBin]}, Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_urlencoded_body(Req0),
    LimitBin = proplists:get_value(<<"limit_blocks">>, Body, <<>>),
    case {safe_int(PBin), safe_int(LimitBin)} of
        {{ok, P}, {ok, Blocks}} when P >= 2, P =< 255, Blocks > 0 ->
            case erlbasic_limits:set_project_limit_blocks(P, Blocks) of
                ok -> reply_json(200, <<"{\"status\":\"updated\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply_json(400,
                <<"{\"error\":\"project must be 2..255 and limit_blocks must be > 0\"}">>,
                Req, State)
    end;

handle_limits_api(<<"DELETE">>, {projects, [PBin]}, Req, State) ->
    case safe_int(PBin) of
        {ok, P} when P >= 2, P =< 255 ->
            case erlbasic_limits:clear_project_limit(P) of
                ok -> reply_json(200, <<"{\"status\":\"cleared\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply_json(400,
                <<"{\"error\":\"project must be 2..255\"}">>,
                Req, State)
    end;

handle_limits_api(<<"GET">>, {users, []}, Req, State) ->
    case erlbasic_limits:list_user_overrides() of
        {ok, Overrides} ->
            Json = user_overrides_to_json(Overrides),
            reply_json(200, Json, Req, State);
        {error, _} ->
            reply(500, <<"Server Error">>, Req, State)
    end;

handle_limits_api(<<"PUT">>, {users, [PBin, NBin]}, Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_urlencoded_body(Req0),
    LimitBin = proplists:get_value(<<"limit_blocks">>, Body, <<>>),
    case {safe_int(PBin), safe_int(NBin), safe_int(LimitBin)} of
        {{ok, P}, {ok, N}, {ok, Blocks}}
                when P >= 2, P =< 255, N >= 0, N =< 255, Blocks > 0 ->
            case erlbasic_limits:set_user_limit_blocks(P, N, Blocks) of
                ok -> reply_json(200, <<"{\"status\":\"updated\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply_json(400,
                <<"{\"error\":\"project must be 2..255, programmer 0..255, and limit_blocks > 0\"}">>,
                Req, State)
    end;

handle_limits_api(<<"DELETE">>, {users, [PBin, NBin]}, Req, State) ->
    case {safe_int(PBin), safe_int(NBin)} of
        {{ok, P}, {ok, N}} when P >= 2, P =< 255, N >= 0, N =< 255 ->
            case erlbasic_limits:clear_user_limit(P, N) of
                ok -> reply_json(200, <<"{\"status\":\"cleared\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply_json(400,
                <<"{\"error\":\"project must be 2..255 and programmer 0..255\"}">>,
                Req, State)
    end;

handle_limits_api(<<"GET">>, {memory_projects, []}, Req, State) ->
    case erlbasic_limits:list_memory_project_limits() of
        {ok, Limits} ->
            Json = memory_project_limits_to_json(Limits),
            reply_json(200, Json, Req, State);
        {error, _} ->
            reply(500, <<"Server Error">>, Req, State)
    end;

handle_limits_api(<<"PUT">>, {memory_projects, [PBin]}, Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_urlencoded_body(Req0),
    LimitBin = proplists:get_value(<<"limit_kb">>, Body, <<>>),
    case {safe_int(PBin), safe_int(LimitBin)} of
        {{ok, P}, {ok, KB}} when P >= 2, P =< 255, KB > 0 ->
            case erlbasic_limits:set_memory_project_limit_kb(P, KB) of
                ok -> reply_json(200, <<"{\"status\":\"updated\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply_json(400,
                <<"{\"error\":\"project must be 2..255 and limit_kb must be > 0\"}">>,
                Req, State)
    end;

handle_limits_api(<<"DELETE">>, {memory_projects, [PBin]}, Req, State) ->
    case safe_int(PBin) of
        {ok, P} when P >= 2, P =< 255 ->
            case erlbasic_limits:clear_memory_project_limit(P) of
                ok -> reply_json(200, <<"{\"status\":\"cleared\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply_json(400,
                <<"{\"error\":\"project must be 2..255\"}">>,
                Req, State)
    end;

handle_limits_api(<<"GET">>, {memory_users, []}, Req, State) ->
    case erlbasic_limits:list_memory_user_overrides() of
        {ok, Overrides} ->
            Json = memory_user_overrides_to_json(Overrides),
            reply_json(200, Json, Req, State);
        {error, _} ->
            reply(500, <<"Server Error">>, Req, State)
    end;

handle_limits_api(<<"PUT">>, {memory_users, [PBin, NBin]}, Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_urlencoded_body(Req0),
    LimitBin = proplists:get_value(<<"limit_kb">>, Body, <<>>),
    case {safe_int(PBin), safe_int(NBin), safe_int(LimitBin)} of
        {{ok, P}, {ok, N}, {ok, KB}}
                when P >= 2, P =< 255, N >= 0, N =< 255, KB > 0 ->
            case erlbasic_limits:set_memory_user_limit_kb(P, N, KB) of
                ok -> reply_json(200, <<"{\"status\":\"updated\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply_json(400,
                <<"{\"error\":\"project must be 2..255, programmer 0..255, and limit_kb > 0\"}">>,
                Req, State)
    end;

handle_limits_api(<<"DELETE">>, {memory_users, [PBin, NBin]}, Req, State) ->
    case {safe_int(PBin), safe_int(NBin)} of
        {{ok, P}, {ok, N}} when P >= 2, P =< 255, N >= 0, N =< 255 ->
            case erlbasic_limits:clear_memory_user_limit(P, N) of
                ok -> reply_json(200, <<"{\"status\":\"cleared\"}">>, Req, State);
                {error, Reason} ->
                    ErrMsg = iolist_to_binary(io_lib:format("{\"error\":\"~p\"}", [Reason])),
                    reply_json(500, ErrMsg, Req, State)
            end;
        _ ->
            reply_json(400,
                <<"{\"error\":\"project must be 2..255 and programmer 0..255\"}">>,
                Req, State)
    end;

handle_limits_api(_, _, Req, State) ->
    reply(405, <<"Method Not Allowed">>, Req, State).

%% ===================================================================
%% HTML serving
%% ===================================================================

serve_html(Page, Req, State) ->
    PrivDir = code:priv_dir(erlbasic),
    FileName =
        case Page of
            accounts -> "admin_accounts.html";
            storage -> "admin_storage.html";
            memory -> "admin_memory.html"
        end,
    Path    = filename:join([PrivDir, "www", FileName]),
    case file:read_file(Path) of
        {ok, Body} ->
            Req2 = cowboy_req:reply(200,
                #{<<"content-type">> => <<"text/html; charset=utf-8">>},
                Body, Req),
            {ok, Req2, State};
        {error, Reason} ->
            Body = iolist_to_binary(
                io_lib:format("Cannot read admin.html: ~p", [Reason])),
            Req2 = cowboy_req:reply(500, #{}, Body, Req),
            {ok, Req2, State}
    end.

%% ===================================================================
%% Helpers
%% ===================================================================

safe_int(Bin) when is_binary(Bin) ->
    try {ok, binary_to_integer(string:trim(Bin))}
    catch _:_ -> error
    end;
safe_int(_) -> error.

validate_ppn_range(P, N, Fun, _Req, _State)
        when P >= 0, P =< 254, N >= 0, N =< 254 ->
    Fun();
validate_ppn_range(_, _, _, Req, State) ->
    reply_json(400,
        <<"{\"error\":\"project and programmer must be 0..254\"}">>,
        Req, State).

validate_username(UsernameBin, Fun, Req, State) ->
    Trimmed = string:trim(UsernameBin),
    case Trimmed of
        <<>> ->
            Fun(Trimmed);
        _ when byte_size(Trimmed) < 2 ->
            reply_json(400,
                <<"{\"error\":\"username must be at least 2 characters\"}">>,
                Req, State);
        _ when byte_size(Trimmed) =< 16 ->
            Fun(Trimmed);
        _ ->
            reply_json(400,
                <<"{\"error\":\"username must be 16 characters or fewer\"}">>,
                Req, State)
    end.

accounts_to_json(Accounts) ->
    Items = lists:map(fun({{P, N}, Name, Username}) ->
        iolist_to_binary(io_lib:format(
            "{\"project\":~w,\"programmer\":~w,\"name\":\"~s\",\"username\":\"~s\"}",
            [P, N, escape_json(binary_to_list(Name)), escape_json(binary_to_list(Username))]))
    end, Accounts),
    iolist_to_binary(["[", lists:join(",", Items), "]"]).

project_limits_to_json(Limits) ->
    Items = lists:map(fun({P, Blocks}) ->
        iolist_to_binary(io_lib:format(
            "{\"project\":~w,\"limit_blocks\":~w,\"effective_blocks\":~w,\"unlimited\":false}",
            [P, Blocks, Blocks]))
    end, Limits),
    iolist_to_binary(["[", lists:join(",", Items), "]"]).

user_overrides_to_json(Overrides) ->
    Items = lists:map(fun({{P, N}, Blocks}) ->
        iolist_to_binary(io_lib:format(
            "{\"project\":~w,\"programmer\":~w,\"limit_blocks\":~w}",
            [P, N, Blocks]))
    end, Overrides),
    iolist_to_binary(["[", lists:join(",", Items), "]"]).

memory_project_limits_to_json(Limits) ->
    Items = lists:map(fun({P, KB}) ->
        iolist_to_binary(io_lib:format(
            "{\"project\":~w,\"limit_kb\":~w,\"effective_kb\":~w,\"unlimited\":false}",
            [P, KB, KB]))
    end, Limits),
    iolist_to_binary(["[", lists:join(",", Items), "]"]).

memory_user_overrides_to_json(Overrides) ->
    Items = lists:map(fun({{P, N}, KB}) ->
        iolist_to_binary(io_lib:format(
            "{\"project\":~w,\"programmer\":~w,\"limit_kb\":~w}",
            [P, N, KB]))
    end, Overrides),
    iolist_to_binary(["[", lists:join(",", Items), "]"]).

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
