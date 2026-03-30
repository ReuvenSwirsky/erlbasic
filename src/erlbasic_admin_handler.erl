%% @doc Cowboy HTTP handler for the ErlBASIC admin web interface.
%%
%% Routes (all under /admin/...):
%%   GET  /admin[/]                   – serve admin.html
%%   GET  /admin/users                – JSON list of accounts  [auth required]
%%   POST /admin/users                – create account         [auth required]
%%   DELETE /admin/users/:p/:n        – delete account         [auth required]
%%   PUT  /admin/users/:p/:n          – change password        [auth required]
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
        when P =:= <<"/admin">>; P =:= <<"/admin/">> ->
    serve_html(Req, State);

dispatch(Method, <<"/admin/users">>, Req, State) ->
    with_auth(Method, [], Req, State);

dispatch(Method, <<"/admin/users/", Rest/binary>>, Req, State) ->
    Parts = binary:split(Rest, <<"/">>, [global]),
    with_auth(Method, Parts, Req, State);

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

%% GET /admin/users  – list all accounts as JSON
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

%% POST /admin/users  – create account (URL-encoded body)
handle_api(<<"POST">>, [], Req0, State) ->
    {ok, Body, Req} = cowboy_req:read_urlencoded_body(Req0),
    PBin = proplists:get_value(<<"project">>,    Body, <<>>),
    NBin = proplists:get_value(<<"programmer">>, Body, <<>>),
    Pw   = proplists:get_value(<<"password">>,   Body, <<>>),
    Name = proplists:get_value(<<"name">>,        Body, <<>>),
    case {safe_int(PBin), safe_int(NBin), Pw} of
        {{ok, P}, {ok, N}, Pw} when byte_size(Pw) > 0 ->
            validate_ppn_range(P, N, fun() ->
                case erlbasic_accounts:create_account(P, N, Pw, Name) of
                    ok ->
                        reply_json(201, <<"{\"status\":\"created\"}">>, Req, State);
                    {error, Reason} ->
                        ErrMsg = iolist_to_binary(
                            io_lib:format("{\"error\":\"~p\"}", [Reason])),
                        reply_json(500, ErrMsg, Req, State)
                end
            end, Req, State);
        _ ->
            reply_json(400,
                <<"{\"error\":\"project, programmer and password are required\"}">>,
                Req, State)
    end;

%% DELETE /admin/users/:p/:n  – delete account
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

%% PUT /admin/users/:p/:n  – change password (URL-encoded body)
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
%% HTML serving
%% ===================================================================

serve_html(Req, State) ->
    PrivDir = code:priv_dir(erlbasic),
    Path    = filename:join([PrivDir, "www", "admin.html"]),
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

accounts_to_json(Accounts) ->
    Items = lists:map(fun({{P, N}, Name}) ->
        iolist_to_binary(io_lib:format(
            "{\"project\":~w,\"programmer\":~w,\"name\":\"~s\"}",
            [P, N, escape_json(binary_to_list(Name))]))
    end, Accounts),
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
