-module(erlbasic_homepage_handler).
-export([init/2, init_cache/0]).

-include("erlbasic_state.hrl").

init(Req, State) ->
    case cowboy_req:method(Req) of
        <<"GET">> ->
            serve_homepage(Req, State);
        _ ->
            {ok, cowboy_req:reply(405, #{}, <<"Method Not Allowed">>, Req), State}
    end.

serve_homepage(Req, State) ->
    Username = cowboy_req:binding(username, Req),
    case erlbasic_accounts:find_by_username(Username) of
        {ok, {Project, Programmer, Name, StoredUsername}} ->
            UserDir = user_dir(Project, Programmer),
            _ = filelib:ensure_dir(filename:join(UserDir, ".keep")),
            case read_home_bas(UserDir) of
                {ok, HomeBas, HomeBasPath} ->
                    serve_with_cache(StoredUsername, Name, Project, Programmer,
                                     HomeBas, HomeBasPath, UserDir, Req, State);
                {error, enoent} ->
                    Body = default_homepage(StoredUsername, Name, Project, Programmer),
                    reply_html(Req, State, Body);
                {error, _Reason} ->
                    {ok, cowboy_req:reply(500, #{}, <<"Server Error">>, Req), State}
            end;
        {error, not_found} ->
            {ok, cowboy_req:reply(404, #{}, <<"User not found">>, Req), State};
        {error, _Reason} ->
            {ok, cowboy_req:reply(500, #{}, <<"Server Error">>, Req), State}
    end.

reply_html(Req, State, Body) ->
    Req2 = cowboy_req:reply(200,
        #{<<"content-type">> => <<"text/html; charset=utf-8">>},
        Body,
        Req),
    {ok, Req2, State}.

read_home_bas(UserDir) ->
    Candidates = [
        filename:join(UserDir, "HOME.BAS"),
        filename:join(UserDir, "home.bas")
    ],
    read_first_existing(Candidates).

read_first_existing([]) ->
    {error, enoent};
read_first_existing([Path | Rest]) ->
    case file:read_file(Path) of
        {error, enoent} ->
            read_first_existing(Rest);
        {ok, Bin} ->
            {ok, Bin, Path};
        {error, _} = Err ->
            Err
    end.

user_dir(Project, Programmer) ->
    SubDir = integer_to_list(Project) ++ "_" ++ integer_to_list(Programmer),
    filename:join([erl_users_root(), SubDir]).

render_home_from_bas(Username, Name, Project, Programmer, HomeBas) ->
    UsernameText = escape_html(to_text(Username)),
    NameText = escape_html(to_text(Name)),
    PpnText = io_lib:format("[~w,~w]", [Project, Programmer]),
    Sections = run_home_bas(HomeBas, Project, Programmer),
    SectionsHtml = [render_section(S) || S <- Sections],
    iolist_to_binary([
        "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
        "<title>", UsernameText, " - Homepage</title>",
        "<style>",
        "body{margin:0;font-family:Georgia,\"Times New Roman\",serif;background:linear-gradient(135deg,#f8f4ea,#e3edf7);color:#1f2937}",
        ".wrap{max-width:900px;margin:40px auto;padding:24px}",
        ".card{background:#ffffffdd;border:1px solid #cbd5e1;border-radius:16px;padding:24px;box-shadow:0 10px 30px #64748b33}",
        "h1{margin:0 0 8px 0;font-size:2rem;color:#0f172a}",
        ".meta{color:#334155;margin-bottom:18px}",
        ".home-section{background:#0b1220;border-radius:12px;padding:2px;margin-bottom:16px;overflow:auto}",
        ".home-section pre{margin:0;padding:14px 16px;font-family:'Courier New',Courier,monospace;font-size:14px;",
        "line-height:1.35;background:transparent;color:#AAAAAA;white-space:pre}",
        ".home-section-gfx{padding:0;line-height:0}",
        "</style></head><body><div class=\"wrap\"><div class=\"card\">",
        "<h1>", UsernameText, "</h1>",
        "<div class=\"meta\">", NameText, " - ", io_lib:format("~s", [PpnText]), "</div>",
        SectionsHtml,
        "</div></div></body></html>"
    ]).

render_section({text, Html}) ->
    ["<div class=\"home-section\"><pre>", Html, "</pre></div>"];
render_section({gfx, Svg}) ->
    ["<div class=\"home-section home-section-gfx\">", Svg, "</div>"].

%% init_cache/0 kept for backward compatibility with erlbasic_app.erl.
init_cache() ->
    ok.

serve_with_cache(Username, Name, Project, Programmer, HomeBas, HomeBasPath, UserDir, Req, State) ->
    CacheFile    = filename:join(UserDir, ".home_cache.html"),
    HomeBasMtime = filelib:last_modified(HomeBasPath),
    CacheMtime   = filelib:last_modified(CacheFile),
    UseCache = CacheMtime =/= 0 andalso CacheMtime >= HomeBasMtime,
    case UseCache of
        true ->
            case file:read_file(CacheFile) of
                {ok, CachedBin} ->
                    reply_html(Req, State, CachedBin);
                _ ->
                    render_and_cache(Username, Name, Project, Programmer, HomeBas, CacheFile, Req, State)
            end;
        false ->
            render_and_cache(Username, Name, Project, Programmer, HomeBas, CacheFile, Req, State)
    end.

render_and_cache(Username, Name, Project, Programmer, HomeBas, CacheFile, Req, State) ->
    Body = render_home_from_bas(Username, Name, Project, Programmer, HomeBas),
    _ = file:write_file(CacheFile, Body),
    reply_html(Req, State, Body).

run_home_bas(HomeBas, Project, Programmer) ->
    case erlbasic_commands:parse_bin_as_program(HomeBas) of
        {ok, Program} ->
            State = #state{prog = Program},
            Self = self(),
            Pid = spawn(fun() ->
                erlang:put(erlbasic_ppn, {Project, Programmer}),
                erlang:put(erlbasic_conn_type, home_bas),
                erlbasic_home_screen:init(),
                {_RanState, _Output} = erlbasic_runtime:run_program(State),
                Self ! {bas_sections, erlbasic_home_screen:get_sections()}
            end),
            receive
                {bas_sections, Sections} -> Sections
            after 5000 ->
                exit(Pid, kill),
                []
            end;
        _ ->
            []
    end.

default_homepage(Username, _Name, Project, Programmer) ->
    UsernameText = escape_html(to_text(Username)),
    PpnText = io_lib:format("[~w,~w]", [Project, Programmer]),
    iolist_to_binary([
        "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
        "<title>", UsernameText, " - Homepage</title>",
        "<style>",
        "body{margin:0;font-family:Georgia,\"Times New Roman\",serif;background:radial-gradient(circle at 20% 20%,#fde68a 0,#fef3c7 25%,#e0f2fe 70%,#dbeafe 100%);color:#111827}",
        ".wrap{max-width:860px;margin:48px auto;padding:24px}",
        ".panel{background:#fffffff0;border:1px solid #bfdbfe;border-radius:18px;padding:28px;box-shadow:0 14px 34px #1d4ed81f}",
        "h1{margin:0 0 8px 0;font-size:2.2rem;letter-spacing:.02em}",
        ".sub{color:#1e3a8a;margin-bottom:20px}",
        ".badge{display:inline-block;background:#1d4ed8;color:#fff;border-radius:999px;padding:6px 12px;font-size:.85rem}",
        "ul{margin:16px 0 0 20px;line-height:1.6}",
        "code{background:#e2e8f0;border-radius:6px;padding:2px 6px}",
        "</style></head><body><div class=\"wrap\"><div class=\"panel\">",
        "<span class=\"badge\">ErlBASIC Homepage</span>",
        "<h1>", UsernameText, "</h1>",
        "<div class=\"sub\">", UsernameText, " - ", io_lib:format("~s", [PpnText]), "</div>",
        "<p>No <code>home.bas</code> was found yet. This default homepage is being served.</p>",
        "<ul>",
        "<li>Create a BASIC homepage file named <code>home.bas</code> in your user directory.</li>",
        "<li>Your homepage URL stays <code>/", UsernameText, "</code>.</li>",
        "<li>The system will render BASIC to HTML here as that pipeline evolves.</li>",
        "</ul>",
        "</div></div></body></html>"
    ]).

escape_html(Str) when is_list(Str) ->
    lists:flatmap(fun
        ($&) -> "&amp;";
        ($<) -> "&lt;";
        ($>) -> "&gt;";
        ($\") -> "&quot;";
        (C) -> [C]
    end, Str).

to_text(Bin) when is_binary(Bin) ->
    binary_to_list(Bin);
to_text(List) when is_list(List) ->
    List;
to_text(Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
to_text(Int) when is_integer(Int) ->
    integer_to_list(Int);
to_text(Other) ->
    lists:flatten(io_lib:format("~p", [Other])).

erl_users_root() ->
    filename:join(home_dir(), "ErlUsers").

home_dir() ->
    case os:getenv("HOME") of
        false ->
            case os:getenv("USERPROFILE") of
                false -> ".";
                Path  -> Path
            end;
        Path -> Path
    end.
