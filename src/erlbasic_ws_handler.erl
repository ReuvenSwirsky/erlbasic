-module(erlbasic_ws_handler).
-behaviour(cowboy_websocket).

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2, terminate/3]).

%% Called by Cowboy when the HTTP request arrives; upgrade to WebSocket.
init(Req, State) ->
    BaseOpts = #{idle_timeout => infinity},
    DefaultDeflateOpts = #{server_context_takeover => no_takeover},
    WsOpts = case State of
        #{compress := false} ->
            BaseOpts;
        #{compress := true} = Map ->
            case maps:get(deflate_opts, Map, undefined) of
                undefined -> BaseOpts#{compress => true, deflate_opts => DefaultDeflateOpts};
                DeflateOpts -> BaseOpts#{compress => true, deflate_opts => DeflateOpts}
            end;
        _ -> BaseOpts#{compress => true, deflate_opts => DefaultDeflateOpts}
    end,
    {cowboy_websocket, Req, State, WsOpts}.

%% Called once the WebSocket handshake is complete.
websocket_init(_State) ->
    %% Start a fresh interpreter session, telling it to send output to this process.
    {ok, Pid} = erlbasic_conn:start_ws(self()),
    MonitorRef = erlang:monitor(process, Pid),
    {ok, #{conn => Pid, monitor => MonitorRef}}.

%% Data arriving from the browser (keyboard input).
websocket_handle({text, <<3>>}, State = #{conn := Pid}) ->
    %% Ctrl-C (ASCII 3)
    Pid ! interrupt,
    {ok, State};
websocket_handle({text, Data}, State = #{conn := Pid}) ->
    erlbasic_conn:send_input(Pid, binary_to_list(Data)),
    {ok, State};
websocket_handle(_Frame, State) ->
    {ok, State}.

%% Messages from the interpreter process (output to send to browser).
websocket_info({output, Text}, State) ->
    %% WebSocket text frames must be valid UTF-8. Convert iodata/chars safely.
    Utf8 = unicode:characters_to_binary(Text),
    {reply, {text, Utf8}, State};
websocket_info({'DOWN', _MonRef, process, Pid, Reason}, State = #{conn := Pid}) ->
    %% A normal/shutdown DOWN is expected for QUIT/BYE/session teardown.
    case Reason of
        normal ->
            {stop, State};
        shutdown ->
            {stop, State};
        {shutdown, _} ->
            {stop, State};
        _ ->
            error_logger:error_msg("===== WebSocket interpreter process ~p CRASHED =====~nReason: ~p~n", [Pid, Reason]),
            ErrorMsg = io_lib:format("\r\n?SYSTEM ERROR: Interpreter crashed - ~p\r\n", [Reason]),
            Utf8 = unicode:characters_to_binary(ErrorMsg),
            {reply, {text, Utf8}, State}
    end;
websocket_info(close, State) ->
    {stop, State};
websocket_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _Req, _State) ->
    ok.
