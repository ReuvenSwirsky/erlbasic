-module(erlbasic_web_listener).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Type) ->
    case should_start(Type) of
        {start, StartArg} ->
            gen_server:start_link(?MODULE, StartArg, []);
        ignore ->
            ignore
    end.

init(http) ->
    HttpPort = application:get_env(erlbasic, http_port, 8081),
    {ok, _} = cowboy:start_clear(erlbasic_http,
        [{port, HttpPort}, {nodelay, true}],
        protocol_opts()),
    logger:notice("event=listener_started listener=http port=~p", [HttpPort]),
    {ok, #{listener => erlbasic_http}};
init({https, HttpsPort, TlsOpts}) ->
    {ok, _} = cowboy:start_tls(erlbasic_https,
        TlsOpts,
        protocol_opts()),
    logger:notice("event=listener_started listener=https port=~p certfile=~ts keyfile=~ts", [
        HttpsPort,
        proplists:get_value(certfile, TlsOpts),
        proplists:get_value(keyfile, TlsOpts)
    ]),
    {ok, #{listener => erlbasic_https}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #{listener := ListenerName}) ->
    catch cowboy:stop_listener(ListenerName),
    ok;
terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

should_start(http) ->
    {start, http};
should_start(https) ->
    HttpsPort = application:get_env(erlbasic, https_port, 8443),
    CertFile = application:get_env(erlbasic, certfile, "priv/ssl/cert.pem"),
    KeyFile = application:get_env(erlbasic, keyfile, "priv/ssl/key.pem"),
    case {filelib:is_file(CertFile), filelib:is_file(KeyFile)} of
        {true, true} ->
            BaseTlsOpts = [
                {port, HttpsPort},
                {certfile, CertFile},
                {keyfile, KeyFile},
                {nodelay, true}
            ],
            TlsOpts = maybe_add_cacert(BaseTlsOpts),
            {start, {https, HttpsPort, TlsOpts}};
        {false, _} ->
            logger:error("event=listener_failed listener=https reason=certfile_not_found certfile=~ts", [CertFile]),
            logger:warning("event=https_disabled reason=certfile_not_found hint=generate_certs.ps1"),
            ignore;
        {_, false} ->
            logger:error("event=listener_failed listener=https reason=keyfile_not_found keyfile=~ts", [KeyFile]),
            logger:warning("event=https_disabled reason=keyfile_not_found hint=generate_certs.ps1"),
            ignore
    end.

maybe_add_cacert(BaseTlsOpts) ->
    case application:get_env(erlbasic, cacertfile, undefined) of
        undefined ->
            BaseTlsOpts;
        CaCertFile when is_list(CaCertFile) ->
            case filelib:is_file(CaCertFile) of
                true ->
                    BaseTlsOpts ++ [{cacertfile, CaCertFile}];
                false ->
                    logger:warning("event=https_cacert_missing cacertfile=~ts", [CaCertFile]),
                    BaseTlsOpts
            end;
        _ ->
            BaseTlsOpts
    end.

protocol_opts() ->
    #{env => #{dispatch => dispatch()}}.

dispatch() ->
    cowboy_router:compile([
        {'_', [
            {"/ws", erlbasic_ws_handler, []},
            {"/a/admin", erlbasic_admin_handler, []},
            {"/a/admin/[...]", erlbasic_admin_handler, []},
            {"/a/system", erlbasic_system_handler, []},
            {"/a/system/[...]", erlbasic_system_handler, []},
            {"/:username", erlbasic_homepage_handler, []},
            {"/:username/", erlbasic_homepage_handler, []},
            {'_', erlbasic_http_handler, []}
        ]}
    ]).