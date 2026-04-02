-module(erlbasic_sup).
-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    ok = start_cowboy(),
    Listener = #{
        id => erlbasic_listener,
        start => {erlbasic_listener, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [erlbasic_listener]
    },
    {ok, {{one_for_one, 5, 10}, [Listener]}}.

start_cowboy() ->
    HttpPort = application:get_env(erlbasic, http_port, 8081),
    EnableHttps = application:get_env(erlbasic, enable_https, false),
    
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/ws", erlbasic_ws_handler, []},
            {"/admin", erlbasic_admin_handler, []},
            {"/admin/[...]", erlbasic_admin_handler, []},
            {'_', erlbasic_http_handler, []}
        ]}
    ]),
    
    %% Start HTTP listener
    {ok, _} = cowboy:start_clear(erlbasic_http,
        [{port, HttpPort}],
        #{env => #{dispatch => Dispatch}}
    ),
    io:format("erlbasic HTTP server listening on port ~p~n", [HttpPort]),
    
    %% Optionally start HTTPS listener
    case EnableHttps of
        true ->
            start_https_listener(Dispatch);
        false ->
            ok
    end.

start_https_listener(Dispatch) ->
    HttpsPort = application:get_env(erlbasic, https_port, 8443),
    CertFile = application:get_env(erlbasic, certfile, "priv/ssl/cert.pem"),
    KeyFile = application:get_env(erlbasic, keyfile, "priv/ssl/key.pem"),
    
    %% Check if certificate files exist
    case {filelib:is_file(CertFile), filelib:is_file(KeyFile)} of
        {true, true} ->
            BaseTlsOpts = [
                {port, HttpsPort},
                {certfile, CertFile},
                {keyfile, KeyFile}
            ],
            
            %% Add CA cert file if specified
            TlsOpts = case application:get_env(erlbasic, cacertfile, undefined) of
                undefined -> 
                    BaseTlsOpts;
                CaCertFile when is_list(CaCertFile) ->
                    case filelib:is_file(CaCertFile) of
                        true -> 
                            BaseTlsOpts ++ [{cacertfile, CaCertFile}];
                        false ->
                            io:format("Warning: CA cert file ~s not found~n", [CaCertFile]),
                            BaseTlsOpts
                    end;
                _ -> 
                    BaseTlsOpts
            end,
            
            {ok, _} = cowboy:start_tls(erlbasic_https,
                TlsOpts,
                #{env => #{dispatch => Dispatch}}
            ),
            io:format("erlbasic HTTPS server listening on port ~p~n", [HttpsPort]),
            io:format("  Using cert: ~s~n", [CertFile]),
            io:format("  Using key:  ~s~n", [KeyFile]),
            ok;
        {false, _} ->
            io:format("Error: Certificate file not found: ~s~n", [CertFile]),
            io:format("HTTPS server not started. Generate certificates with: pwsh generate_certs.ps1~n"),
            ok;
        {_, false} ->
            io:format("Error: Key file not found: ~s~n", [KeyFile]),
            io:format("HTTPS server not started. Generate certificates with: pwsh generate_certs.ps1~n"),
            ok
    end.