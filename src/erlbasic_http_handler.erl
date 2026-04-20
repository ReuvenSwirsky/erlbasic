-module(erlbasic_http_handler).
-export([init/2]).

init(Req, State) ->
    Path = cowboy_req:path(Req),
    case map_request_to_file(Path) of
        {ok, FilePath, ContentType} ->
            serve_file(Req, State, FilePath, ContentType);
        not_found ->
            Req2 = cowboy_req:reply(404, #{}, <<"Not Found">>, Req),
            {ok, Req2, State}
    end.

map_request_to_file(Path) ->
    PrivDir = code:priv_dir(erlbasic),
    WwwDir = filename:join([PrivDir, "www"]),
    case Path of
        <<"/">> ->
            {ok, filename:join(WwwDir, "home.html"), <<"text/html; charset=utf-8">>};
        <<"/index.html">> ->
            {ok, filename:join(WwwDir, "home.html"), <<"text/html; charset=utf-8">>};
        <<"/s/term">> ->
            {ok, filename:join(WwwDir, "index.html"), <<"text/html; charset=utf-8">>};
        <<"/s/term/">> ->
            {ok, filename:join(WwwDir, "index.html"), <<"text/html; charset=utf-8">>};
        <<"/docs/basic-functions">> ->
            {ok, filename:join([WwwDir, "docs", "basic-functions.html"]), <<"text/html; charset=utf-8">>};
        <<"/docs/basic-functions/">> ->
            {ok, filename:join([WwwDir, "docs", "basic-functions.html"]), <<"text/html; charset=utf-8">>};
        <<"/docs/basic-syntax">> ->
            {ok, filename:join([WwwDir, "docs", "basic-syntax.html"]), <<"text/html; charset=utf-8">>};
        <<"/docs/basic-syntax/">> ->
            {ok, filename:join([WwwDir, "docs", "basic-syntax.html"]), <<"text/html; charset=utf-8">>};
        <<"/docs/", Rest/binary>> ->
            docs_file(WwwDir, Rest);
        <<"/assets/", Rest/binary>> ->
            asset_file(WwwDir, Rest);
        _ ->
            not_found
    end.

docs_file(WwwDir, Rest) ->
    DocName = binary_to_list(Rest),
    case filename:basename(DocName) =:= DocName of
        true ->
            case string:lowercase(filename:extension(DocName)) of
                ".html" ->
                    FullPath = filename:join([WwwDir, "docs", DocName]),
                    {ok, FullPath, <<"text/html; charset=utf-8">>};
                _ ->
                    not_found
            end;
        false ->
            not_found
    end.

asset_file(WwwDir, Rest) ->
    AssetName = binary_to_list(Rest),
    case filename:basename(AssetName) =:= AssetName of
        true ->
            FullPath = filename:join([WwwDir, "assets", AssetName]),
            {ok, FullPath, content_type_for_asset(AssetName)};
        false ->
            not_found
    end.

content_type_for_asset(FileName) ->
    Ext = string:lowercase(filename:extension(FileName)),
    case Ext of
        ".png" -> <<"image/png">>;
        ".jpg" -> <<"image/jpeg">>;
        ".jpeg" -> <<"image/jpeg">>;
        ".gif" -> <<"image/gif">>;
        ".svg" -> <<"image/svg+xml">>;
        ".webp" -> <<"image/webp">>;
        _ -> <<"application/octet-stream">>
    end.

serve_file(Req, State, Path, ContentType) ->
    case file:read_file(Path) of
        {ok, Body} ->
            Req2 = cowboy_req:reply(200,
                #{<<"content-type">> => ContentType},
                Body,
                Req),
            {ok, Req2, State};
        {error, enoent} ->
            Req2 = cowboy_req:reply(404, #{}, <<"Not Found">>, Req),
            {ok, Req2, State};
        {error, Reason} ->
            Body = iolist_to_binary(io_lib:format("Cannot read file: ~p", [Reason])),
            Req2 = cowboy_req:reply(500, #{}, Body, Req),
            {ok, Req2, State}
    end.
