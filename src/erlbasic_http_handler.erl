-module(erlbasic_http_handler).
-export([init/2]).

init(Req, State) ->
    PrivDir = code:priv_dir(erlbasic),
    Path = filename:join([PrivDir, "www", "index.html"]),
    case file:read_file(Path) of
        {ok, Body} ->
            Req2 = cowboy_req:reply(200,
                #{<<"content-type">> => <<"text/html; charset=utf-8">>},
                Body, Req),
            {ok, Req2, State};
        {error, Reason} ->
            Body = iolist_to_binary(io_lib:format("Cannot read index.html: ~p", [Reason])),
            Req2 = cowboy_req:reply(500, #{}, Body, Req),
            {ok, Req2, State}
    end.
