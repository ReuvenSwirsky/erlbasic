-module(erlbasic_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
    ok = erlbasic_config_override:load(),
    ok = erlbasic_logging:configure(),
    ok = erlbasic_s3_config:load(),
    ok = report_storage_startup_status(),
    ok = erlbasic_limits:init(),
    ok = erlbasic_accounts:init(),
    ok = erlbasic_homepage_handler:init_cache(),
    erlbasic_sup:start_link().

stop(_State) ->
    ok.

report_storage_startup_status() ->
    case erlbasic_storage:startup_status() of
        {s3, ok, Module} ->
            io:format(
                "S3 startup check: OK (module=~p bucket=~p prefix=~p)~n",
                [Module, s3_env(storage_s3_bucket), s3_env(storage_s3_prefix)]
            ),
            logger:notice(
                "event=s3_startup_check status=ok module=~p bucket=~p prefix=~p",
                [Module, s3_env(storage_s3_bucket), s3_env(storage_s3_prefix)]
            ),
            ok;
        {s3, {error, Reason}, Module} ->
            io:format(
                "S3 startup check: FAILED (module=~p bucket=~p prefix=~p reason=~0p)~n",
                [Module, s3_env(storage_s3_bucket), s3_env(storage_s3_prefix), Reason]
            ),
            logger:warning(
                "event=s3_startup_check status=failed module=~p bucket=~p prefix=~p reason=~0p",
                [Module, s3_env(storage_s3_bucket), s3_env(storage_s3_prefix), Reason]
            ),
            ok;
        _ ->
            ok
    end.

s3_env(Key) ->
    case application:get_env(erlbasic, Key) of
        {ok, Value} -> Value;
        undefined -> undefined
    end.