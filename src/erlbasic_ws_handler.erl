-module(erlbasic_ws_handler).
-behaviour(cowboy_websocket).

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2, terminate/3]).

%% Called by Cowboy when the HTTP request arrives; upgrade to WebSocket.
init(Req, State) ->
    {cowboy_websocket, Req, State, #{idle_timeout => infinity}}.

%% Called once the WebSocket handshake is complete.
websocket_init(_State) ->
    %% Start a fresh interpreter session, telling it to send output to this process.
    {ok, Pid} = erlbasic_conn:start_ws(self()),
    {ok, #{conn => Pid}}.

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
    {reply, {text, list_to_binary(Text)}, State};
websocket_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _Req, _State) ->
    ok.
