-module(erlbasic_mem_watchdog).
-behaviour(gen_server).

-export([start_link/0, register_session/2, unregister_session/1,
         try_register_session/4, get_stats/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% How often to poll registered processes (milliseconds).
-define(CHECK_INTERVAL_MS, 500).

%% Internal state record.
%% sessions:   Pid => {LimitBytes, MonRef, PPN}   (PPN may be 'undefined')
%% ppn_counts: {P,N} => integer()                 (active session count)
-record(wd, {sessions = #{}, ppn_counts = #{}}).

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
    gen_server:cast(?MODULE, {register, Pid, LimitBytes, undefined}).

%% Atomically check the per-PPN session count and register if within the limit.
%% MaxSessions must be a positive integer or the atom 'unlimited'.
%% Returns 'ok' on success or '{error, too_many_sessions}'.
try_register_session(Pid, LimitBytes, PPN, MaxSessions)
        when is_pid(Pid), is_atom(MaxSessions); is_pid(Pid), is_integer(MaxSessions) ->
    gen_server:call(?MODULE, {try_register, Pid, LimitBytes, PPN, MaxSessions}).

%% Return current watchdog session statistics.
get_stats() ->
    gen_server:call(?MODULE, get_stats).

%% Remove a connection process from watchdog supervision.
unregister_session(Pid) when is_pid(Pid) ->
    gen_server:cast(?MODULE, {unregister, Pid}).

%% ===================================================================
%% gen_server callbacks
%% ===================================================================

init([]) ->
    erlang:send_after(?CHECK_INTERVAL_MS, self(), check),
    {ok, #wd{}}.

handle_call({try_register, Pid, LimitBytes, PPN, MaxSessions}, _From,
            #wd{sessions = Sessions, ppn_counts = Counts} = State) ->
    %% Clean up any stale entries for this PPN from dead processes
    Counts1 = clean_stale_ppn_count(PPN, Sessions, Counts),
    CurrentCount = maps:get(PPN, Counts1, 0),
    Over = case MaxSessions of
        unlimited -> false;
        Max when is_integer(Max) -> CurrentCount >= Max
    end,
    case Over of
        true ->
            {reply, {error, too_many_sessions}, State};
        false ->
            %% Demonitor any existing entry for this Pid.
            {Sessions3, Counts3} = do_unregister(Pid, Sessions, Counts1),
            Ref = erlang:monitor(process, Pid),
            Sessions4 = Sessions3#{Pid => {LimitBytes, Ref, PPN}},
            Counts4 = case PPN of
                undefined -> Counts3;
                _ -> Counts3#{PPN => maps:get(PPN, Counts3, 0) + 1}
            end,
            {reply, ok, State#wd{sessions = Sessions4, ppn_counts = Counts4}}
    end;

handle_call(get_stats, _From, #wd{sessions = Sessions, ppn_counts = Counts} = State) ->
    SessionCount = maps:size(Sessions),
    ActiveUsers = maps:size(Counts),
    SessionMemBytes = maps:fold(
        fun(Pid, _Entry, Acc) ->
            case process_info(Pid, memory) of
                {memory, Mem} -> Acc + Mem;
                _ -> Acc
            end
        end,
        0,
        Sessions),
    {reply, #{active_sessions => SessionCount,
              active_users => ActiveUsers,
              session_memory_bytes => SessionMemBytes}, State};

handle_call(_Req, _From, State) ->
    {reply, ok, State}.

handle_cast({register, Pid, LimitBytes, PPN}, #wd{sessions = Sessions, ppn_counts = Counts} = State) ->
    {Sessions1, Counts1} = do_unregister(Pid, Sessions, Counts),
    Ref = erlang:monitor(process, Pid),
    Sessions2 = Sessions1#{Pid => {LimitBytes, Ref, PPN}},
    Counts2 = case PPN of
        undefined -> Counts1;
        _ -> Counts1#{PPN => maps:get(PPN, Counts1, 0) + 1}
    end,
    {noreply, State#wd{sessions = Sessions2, ppn_counts = Counts2}};

handle_cast({unregister, Pid}, #wd{sessions = Sessions, ppn_counts = Counts} = State) ->
    {Sessions1, Counts1} = do_unregister(Pid, Sessions, Counts),
    {noreply, State#wd{sessions = Sessions1, ppn_counts = Counts1}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(check, #wd{sessions = Sessions} = State) ->
    maps:foreach(fun(Pid, {LimitBytes, _Ref, _PPN}) ->
        case process_info(Pid, memory) of
            {memory, Mem} when Mem > LimitBytes ->
                Pid ! memory_limit_exceeded;
            _ ->
                ok
        end
    end, Sessions),
    erlang:send_after(?CHECK_INTERVAL_MS, self(), check),
    {noreply, State};

handle_info({'DOWN', _Ref, process, Pid, _Reason},
            #wd{sessions = Sessions, ppn_counts = Counts} = State) ->
    {Sessions1, Counts1} = do_unregister(Pid, Sessions, Counts),
    {noreply, State#wd{sessions = Sessions1, ppn_counts = Counts1}};

handle_info(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, #wd{sessions = Sessions}) ->
    maps:foreach(fun(_Pid, {_, Ref, _}) ->
        erlang:demonitor(Ref, [flush])
    end, Sessions).

%% ===================================================================
%% Internal helpers
%% ===================================================================

%% Clean up any stale sessions (dead processes) registered for the given PPN.
%% This ensures the ppn_count stays accurate even if DOWN messages are delayed.
clean_stale_ppn_count(undefined, _Sessions, Counts) ->
    Counts;
clean_stale_ppn_count(PPN, Sessions, Counts) ->
    PidList = maps:fold(
        fun(Pid, {_, _, SessionPPN}, Acc) ->
            case SessionPPN =:= PPN of
                true -> [Pid | Acc];
                false -> Acc
            end
        end,
        [],
        Sessions),
    %% Count how many of these Pids are actually still alive
    AliveCount = lists:foldl(
        fun(Pid, Cnt) ->
            case erlang:is_process_alive(Pid) of
                true -> Cnt + 1;
                false -> Cnt
            end
        end,
        0,
        PidList),
    %% If the actual count differs from the stored count, fix it
    StoredCount = maps:get(PPN, Counts, 0),
    case AliveCount =:= StoredCount of
        true -> Counts;
        false ->
            case AliveCount of
                0 -> maps:remove(PPN, Counts);
                _ -> Counts#{PPN => AliveCount}
            end
    end.

do_unregister(Pid, Sessions, Counts) ->
    case maps:find(Pid, Sessions) of
        {ok, {_, Ref, PPN}} ->
            erlang:demonitor(Ref, [flush]),
            Sessions1 = maps:remove(Pid, Sessions),
            Counts1 = case PPN of
                undefined ->
                    Counts;
                _ ->
                    case maps:get(PPN, Counts, 0) of
                        N when N =< 1 -> maps:remove(PPN, Counts);
                        N -> Counts#{PPN => N - 1}
                    end
            end,
            {Sessions1, Counts1};
        error ->
            {Sessions, Counts}
    end.
