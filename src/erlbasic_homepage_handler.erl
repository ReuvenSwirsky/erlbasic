-module(erlbasic_homepage_handler).
-export([init/2, init_cache/0, render_home_bas_html/5, validate_home_bas/3]).

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
            case read_home_bas(Project, Programmer) of
                {ok, HomeBas} ->
                    Body = render_home_bas_html(StoredUsername, Name, Project, Programmer, HomeBas),
                    reply_html(Req, State, Body);
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

read_home_bas(Project, Programmer) ->
    with_ppn({Project, Programmer}, fun() ->
        erlbasic_storage:read_program("HOME.BAS")
    end).

render_home_from_bas(Username, Name, Project, Programmer, HomeBas) ->
    UsernameText = escape_html(to_text(Username)),
    NameText = escape_html(to_text(Name)),
    PpnText = io_lib:format("[~w,~w]", [Project, Programmer]),
    CacheFile = homepage_cache_file(Project, Programmer),
    FileHash = crypto:hash(sha256, HomeBas),
    RenderResult = execute_home_bas(CacheFile, FileHash, HomeBas, Project, Programmer),
    SectionsHtml = render_sections_html(RenderResult),
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
        ".home-section pre{margin:0;padding:14px 16px;font-family:'Courier New',Courier,monospace;font-size:14px;line-height:1.35;background:transparent;color:#AAAAAA;white-space:pre}",
        ".home-section-gfx{padding:0;line-height:0}",
        "</style></head><body><div class=\"wrap\"><div class=\"card\">",
        "<h1>", UsernameText, "</h1>",
        "<div class=\"meta\">", NameText, " - ", io_lib:format("~s", [PpnText]), "</div>",
        SectionsHtml,
        "</div></div></body></html>"
    ]).

render_home_bas_html(Username, Name, Project, Programmer, HomeBas) ->
    render_home_from_bas(Username, Name, Project, Programmer, HomeBas).

validate_home_bas(HomeBas, Project, Programmer) ->
    HomeBasBin = iolist_to_binary(HomeBas),
    case run_home_bas(HomeBasBin, Project, Programmer) of
        {ok, Sections} ->
            {ok, length(Sections)};
        {error, Reason} ->
            {error, Reason}
    end.

render_section({text, Html}) ->
    ["<div class=\"home-section\"><pre>", Html, "</pre></div>"];
render_section({gfx, Svg}) ->
    ["<div class=\"home-section home-section-gfx\">", Svg, "</div>"].

render_sections_html({ok, Sections}) ->
    [render_section(S) || S <- Sections];
render_sections_html({error, Reason}) ->
    [render_home_error_section(Reason)].

render_home_error_section(no_home_publish) ->
    render_text_error_section([
        "HOME.BAS did not publish any homepage sections.",
        "Add at least one HOME PUBLISH statement so the homepage has something to render."
    ]);
render_home_error_section(no_sections) ->
    render_text_error_section([
        "HOME.BAS ran, but no homepage sections were captured.",
        "Check that the program reaches HOME PUBLISH and does not stop before it."
    ]);
render_home_error_section(timeout) ->
    render_text_error_section([
        "HOME.BAS rendering timed out.",
        "Homepage rendering must finish within 5 seconds."
    ]);
render_home_error_section({runtime_crash, Reason}) ->
    render_text_error_section([
        "HOME.BAS crashed during homepage rendering.",
        io_lib:format("Reason: ~p", [Reason])
    ]);
render_home_error_section(parse_failed) ->
    render_text_error_section([
        "HOME.BAS could not be parsed for homepage rendering.",
        "Reload or resave the program and check for syntax problems."
    ]);
render_home_error_section(Reason) ->
    render_text_error_section([
        "HOME.BAS could not be rendered.",
        io_lib:format("Reason: ~p", [Reason])
    ]).

render_text_error_section(Lines) ->
    ["<div class=\"home-section\"><pre>",
     escape_html(lists:flatten(string:join([lists:flatten(Line) || Line <- Lines], "\n\n"))),
     "</pre></div>"].

init_cache() ->
    ok.

execute_home_bas(CacheFile, FileHash, HomeBas, Project, Programmer) ->
    case cache_lookup(CacheFile, FileHash) of
        {hit, CachedOutput} ->
            {ok, CachedOutput};
        miss ->
            TTL = detect_dynamic(HomeBas),
            case run_home_bas(HomeBas, Project, Programmer) of
                {ok, Output} ->
                    cache_store(CacheFile, FileHash, Output, TTL),
                    {ok, Output};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

run_home_bas(HomeBas, Project, Programmer) ->
    case erlbasic_commands:parse_bin_as_program(HomeBas) of
        {ok, Program} ->
            State = #state{prog = Program},
            Self = self(),
            Pid = spawn(fun() ->
                erlang:put(erlbasic_ppn, {Project, Programmer}),
                erlang:put(erlbasic_conn_type, home_bas),
                try
                    erlbasic_home_screen:init(),
                    {_RanState, _Output} = erlbasic_runtime:run_program(State),
                    Self ! {bas_sections, erlbasic_home_screen:get_sections()}
                catch
                    Class:Reason ->
                        Self ! {bas_error, {Class, Reason}}
                end
            end),
            receive
                {bas_sections, Sections} ->
                    case Sections of
                        [] ->
                            case has_home_publish(HomeBas) of
                                true -> {error, no_sections};
                                false -> {error, no_home_publish}
                            end;
                        _ ->
                            {ok, Sections}
                    end;
                {bas_error, Reason} ->
                    {error, {runtime_crash, Reason}}
            after 5000 ->
                exit(Pid, kill),
                {error, timeout}
            end;
        _ ->
            {error, parse_failed}
    end.

has_home_publish(HomeBas) ->
    Upper = string:to_upper(binary_to_list(HomeBas)),
    string:find(Upper, "HOME PUBLISH") =/= nomatch.

%% Detect whether HOME.BAS uses dynamic keywords that affect caching.
%% Returns: never (volatile - don't cache), or an integer TTL in seconds,
%%          or the atom 'infinity' (cache until the file changes).
detect_dynamic(HomeBas) ->
    Upper = string:to_upper(binary_to_list(HomeBas)),
    HasVolatile = lists:any(
        fun(Kw) -> string:find(Upper, Kw) =/= nomatch end,
        ["INPUT", "INKEY$", "GETKEY", "RND", "RANDOMIZE"]),
    HasTimed = lists:any(
        fun(Kw) -> string:find(Upper, Kw) =/= nomatch end,
        ["TIME$", "TIMER"]),
    HasDate = string:find(Upper, "DATE$") =/= nomatch,
    if
        HasVolatile -> never;
        HasTimed    -> 30;
        HasDate     -> 3600;
        true        -> infinity
    end.

cache_lookup(CacheFile, FileHash) ->
    case file:read_file(CacheFile) of
        {ok, Bin} ->
            try binary_to_term(Bin, [safe]) of
                {FileHash, CachedAt, TTL, Output} ->
                    case is_cached_sections(Output) of
                        true ->
                            case TTL of
                                infinity ->
                                    {hit, Output};
                                _ ->
                                    Now = erlang:system_time(second),
                                    case Now - CachedAt =< TTL of
                                        true  -> {hit, Output};
                                        false -> miss
                                    end
                            end;
                        false ->
                            %% Legacy cache entries stored plain text output.
                            %% Treat as a miss so we regenerate section tuples.
                            miss
                    end;
                _ ->
                    miss
            catch
                _:_ -> miss
            end;
        _ ->
            miss
    end.

cache_store(_CacheFile, _FileHash, _Output, never) ->
    ok;
cache_store(CacheFile, FileHash, Output, TTL) ->
    Now = erlang:system_time(second),
    Bin = term_to_binary({FileHash, Now, TTL, Output}),
    _ = filelib:ensure_dir(CacheFile),
    _ = file:write_file(CacheFile, Bin),
    ok.

is_cached_sections(Sections) when is_list(Sections) ->
    lists:all(fun
        ({text, Html}) when is_list(Html); is_binary(Html) -> true;
        ({gfx, Svg}) when is_list(Svg); is_binary(Svg) -> true;
        (_) -> false
    end, Sections);
is_cached_sections(_) ->
    false.

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

homepage_cache_file(Project, Programmer) ->
    UserCacheDir = integer_to_list(Project) ++ "_" ++ integer_to_list(Programmer),
    filename:join([homepage_cache_dir(), UserCacheDir, ".home_cache"]).

homepage_cache_dir() ->
    case application:get_env(erlbasic, homepage_cache_dir) of
        {ok, Dir} -> Dir;
        undefined -> temp_dir()
    end.

temp_dir() ->
    case os:getenv("TMPDIR") of
        false ->
            case os:getenv("TMP") of
                false ->
                    case os:getenv("TEMP") of
                        false -> ".";
                        Dir -> Dir
                    end;
                Dir -> Dir
            end;
        Dir -> Dir
    end.

with_ppn(Ppn, Fun) ->
    PrevPpn = erlang:get(erlbasic_ppn),
    erlang:put(erlbasic_ppn, Ppn),
    try
        Fun()
    after
        case PrevPpn of
            undefined -> erlang:erase(erlbasic_ppn);
            _ -> erlang:put(erlbasic_ppn, PrevPpn)
        end
    end.
