-module(erlbasic_mem_watchdog).
-behaviour(gen_server).

-export([start_link/0, register_session/2, unregister_session/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% How often to poll registered processes (milliseconds).
-define(CHECK_INTERVAL_MS, 500).

%% ===================================================================
%% Public API
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Register a connection process for memory watchdog supervision.
%% LimitBytes must be a positive integer, or the atom 'unlimited'.
%% Calling this again for the same Pid updates the limit.
register_session(Pid, unlimited) when is_pid(Pid) ->
    %% Unlimited accounts need no monitoring; remove any existing entry.
    gen_server:cast(?MODULE, {unregister, Pid});
register_session(Pid, LimitBytes) when is_pid(Pid), is_integer(LimitBytes), LimitBytes > 0 ->
    gen_server:cast(?MODULE, {register, Pid, LimitBytes}).

%% Remove a connection process from watchdog supervision.
unregister_session(Pid) when is_pid(Pid) ->
    gen_server:cast(?MODULE, {unregister, Pid}).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    erlang:send_after(?CHECK_INTERVAL_MS, self(), check),
    {ok, #{}}.

handle_cast({register, Pid, LimitBytes}, Sessions) ->
    %% Demonitor any existing entry for this Pid before replacing it.
    Sessions1 = case maps:find(Pid, Sessions) of
        {ok, {_, OldRef}} ->
            erlang:demonitor(OldRef, [flush]),
            maps:remove(Pid, Sessions);
        error ->
            Sessions
    end,
    Ref = erlang:monitor(process, Pid),
    {noreply, Sessions1#{Pid => {LimitBytes, Ref}}};

handle_cast({unregister, Pid}, Sessions) ->
    case maps:find(Pid, Sessions) of
        {ok, {_, Ref}} ->
            erlang:demonitor(Ref, [flush]),
            {noreply, maps:remove(Pid, Sessions)};
        error ->
            {noreply, Sessions}
    end;

handle_cast(_Msg, Sessions) ->
    {noreply, Sessions}.

handle_info(check, Sessions) ->
    maps:foreach(fun(Pid, {LimitBytes, _Ref}) ->
        case process_info(Pid, memory) of
            {memory, Mem} when Mem > LimitBytes ->
                Pid ! memory_limit_exceeded;
            _ ->
                ok
        end
    end, Sessions),
    erlang:send_after(?CHECK_INTERVAL_MS, self(), check),
    {noreply, Sessions};

handle_info({'DOWN', _Ref, process, Pid, _Reason}, Sessions) ->
    {noreply, maps:remove(Pid, Sessions)};

handle_info(_Msg, Sessions) ->
    {noreply, Sessions}.

handle_call(_Req, _From, Sessions) ->
    {reply, ok, Sessions}.

terminate(_Reason, Sessions) ->
    maps:foreach(fun(_Pid, {_, Ref}) ->
        erlang:demonitor(Ref, [flush])
    end, Sessions).
