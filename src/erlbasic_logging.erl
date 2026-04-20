-module(erlbasic_logging).

-export([configure/0]).

-define(FILE_HANDLER, erlbasic_file_h).

configure() ->
    case application:get_env(erlbasic, log_file_enabled, false) of
        true ->
            ensure_primary_level(log_file_level()),
            ensure_file_handler();
        _ ->
            ok
    end.

ensure_file_handler() ->
    FilePath = application:get_env(erlbasic, log_file_path, "log/erlbasic.log"),
    ok = filelib:ensure_dir(FilePath),
    case logger:get_handler_config(?FILE_HANDLER) of
        {ok, _} ->
            ok = logger:remove_handler(?FILE_HANDLER);
        _ ->
            ok
    end,
    Config = #{
        level => log_file_level(),
        formatter => {logger_formatter, #{single_line => false, time_designator => $T}},
        config => #{
            type => file,
            file => FilePath,
            max_no_bytes => application:get_env(erlbasic, log_file_max_no_bytes, 10485760),
            max_no_files => application:get_env(erlbasic, log_file_max_no_files, 5),
            compress_on_rotate => application:get_env(erlbasic, log_file_compress_on_rotate, true),
            filesync_repeat_interval => application:get_env(erlbasic, log_file_sync_interval_ms, 5000)
        }
    },
    case logger:add_handler(?FILE_HANDLER, logger_std_h, Config) of
        ok ->
            logger:notice(
                "event=file_logging_enabled path=~ts level=~p max_no_bytes=~p max_no_files=~p compress_on_rotate=~p",
                [
                    FilePath,
                    log_file_level(),
                    application:get_env(erlbasic, log_file_max_no_bytes, 10485760),
                    application:get_env(erlbasic, log_file_max_no_files, 5),
                    application:get_env(erlbasic, log_file_compress_on_rotate, true)
                ]
            );
        {error, {already_exist, ?FILE_HANDLER}} ->
            ok;
        {error, Reason} ->
            logger:error("event=file_logging_enable_failed reason=~p path=~ts", [Reason, FilePath])
    end.

ensure_primary_level(TargetLevel) ->
    Current = maps:get(level, logger:get_primary_config(), notice),
    case more_verbose_level(Current, TargetLevel) of
        Current ->
            ok;
        NewLevel ->
            ok = logger:set_primary_config(level, NewLevel)
    end.

more_verbose_level(LevelA, LevelB) ->
    case level_rank(LevelA) =< level_rank(LevelB) of
        true -> LevelA;
        false -> LevelB
    end.

log_file_level() ->
    application:get_env(erlbasic, log_file_level, notice).

level_rank(debug) -> 0;
level_rank(info) -> 1;
level_rank(notice) -> 2;
level_rank(warning) -> 3;
level_rank(error) -> 4;
level_rank(critical) -> 5;
level_rank(alert) -> 6;
level_rank(emergency) -> 7.