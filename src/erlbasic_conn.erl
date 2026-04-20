-module(erlbasic_conn).

-export([start/1, start_link/1, start_ws/1, start_ws_link/1, send_input/2,
         parse_hello/1, parse_ppn_only/1, parse_os_command/1,
         normalize_char_input/1]).

-export([init_tcp_session/1, init_ws_session/1]).

start(Socket) ->
    erlbasic_tcp_conn:start(Socket).

start_link(Socket) ->
    erlbasic_tcp_conn:start_link(Socket).

init_tcp_session(Socket) ->
    erlbasic_tcp_conn:init(Socket).

start_ws(WsPid) ->
    erlbasic_ws_conn:start(WsPid).

start_ws_link(WsPid) ->
    erlbasic_ws_conn:start_link(WsPid).

init_ws_session(WsPid) ->
    erlbasic_ws_conn:init(WsPid).

send_input(Pid, Line) ->
    erlbasic_ws_conn:send_input(Pid, Line).

parse_hello(RawLine) ->
    erlbasic_shell:parse_hello(RawLine).

parse_ppn_only(Str) ->
    erlbasic_shell:parse_ppn_only(Str).

parse_os_command(Line) ->
    erlbasic_shell:parse_os_command(Line).

normalize_char_input(Bin) ->
    Chars = [C || C <- binary_to_list(Bin), C =/= $\r, C =/= $\n],
    case Chars of
        [Single | _] -> [Single];
        [] -> ""
    end.
