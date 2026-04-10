%% erlbasic_home_screen.erl
%% Virtual 80x24 text screen used when executing home.bas for HTML rendering.
%%
%% State is stored in the executing process dictionary so that it survives
%% across the entire run_program call without threading extra parameters
%% through every runtime function.
%%
%% Process-dictionary keys:
%%   home_scr_cells    : #{ {Row, Col} => {Char, FG, BG} }
%%   home_scr_row      : integer 1..?ROWS   (cursor row)
%%   home_scr_col      : integer 1..?COLS   (cursor col)
%%   home_scr_fg       : 0..15              (current foreground index)
%%   home_scr_bg       : 0..15              (current background index)
%%   home_scr_sections : [HtmlBinary]       (most-recent at head)

-module(erlbasic_home_screen).
-export([init/0, write_text/1, set_color/2, locate/2, cls/0, publish/0, get_sections/0]).

-define(COLS, 80).
-define(ROWS, 24).
-define(DEFAULT_FG, 7).   %% light grey
-define(DEFAULT_BG, 0).   %% black

%% CGA/GWBASIC 16-colour palette (index 0-15)
-define(CGA_COLORS, {
    "#000000", "#0000AA", "#00AA00", "#00AAAA",
    "#AA0000", "#AA00AA", "#AA5500", "#AAAAAA",
    "#555555", "#5555FF", "#55FF55", "#55FFFF",
    "#FF5555", "#FF55FF", "#FFFF55", "#FFFFFF"
}).

%%%=========================================================================
%%% Public API
%%%=========================================================================

init() ->
    erlang:put(home_scr_cells,    #{}),
    erlang:put(home_scr_row,      1),
    erlang:put(home_scr_col,      1),
    erlang:put(home_scr_fg,       ?DEFAULT_FG),
    erlang:put(home_scr_bg,       ?DEFAULT_BG),
    erlang:put(home_scr_sections, []).

%% Write a string of characters to the virtual screen at the current cursor.
%% Handles \r\n, \r, and \n line endings.
write_text(Text) ->
    write_chars(Text).

%% Set current foreground and background colour indices.
set_color(Fg, undefined) ->
    erlang:put(home_scr_fg, Fg band 15);
set_color(Fg, Bg) ->
    erlang:put(home_scr_fg, Fg band 15),
    erlang:put(home_scr_bg, Bg band 15).

%% Move cursor to a given row/col (1-based, clamped to screen bounds).
locate(Row, Col) ->
    erlang:put(home_scr_row, max(1, min(Row, ?ROWS))),
    erlang:put(home_scr_col, max(1, min(Col, ?COLS))).

%% Clear the screen, home the cursor, and reset colours to defaults.
cls() ->
    erlang:put(home_scr_cells, #{}),
    erlang:put(home_scr_row,   1),
    erlang:put(home_scr_col,   1),
    erlang:put(home_scr_fg,    ?DEFAULT_FG),
    erlang:put(home_scr_bg,    ?DEFAULT_BG).

%% Snapshot the current screen as an HTML fragment, append to the sections
%% list, then clear the screen ready for the next section.
publish() ->
    Cells    = erlang:get(home_scr_cells),
    Html     = render_screen(Cells),
    Sections = erlang:get(home_scr_sections),
    erlang:put(home_scr_sections, [Html | Sections]),
    cls().

%% Return all published sections in order (first published first).
get_sections() ->
    lists:reverse(erlang:get(home_scr_sections)).

%%%=========================================================================
%%% Internal: cursor & character placement
%%%=========================================================================

write_chars([]) -> ok;
write_chars([$\r, $\n | Rest]) ->
    do_newline(),
    write_chars(Rest);
write_chars([$\r | Rest]) ->
    erlang:put(home_scr_col, 1),
    write_chars(Rest);
write_chars([$\n | Rest]) ->
    do_newline(),
    write_chars(Rest);
write_chars([Ch | Rest]) ->
    do_put_char(Ch),
    do_advance(),
    write_chars(Rest).

do_newline() ->
    Row = erlang:get(home_scr_row),
    if Row < ?ROWS ->
        erlang:put(home_scr_row, Row + 1),
        erlang:put(home_scr_col, 1);
    true ->
        do_scroll_up(),
        erlang:put(home_scr_col, 1)
    end.

do_scroll_up() ->
    Cells = erlang:get(home_scr_cells),
    NewCells = maps:fold(fun({R, C}, V, Acc) ->
        case R > 1 of
            true  -> Acc#{{R - 1, C} => V};
            false -> Acc           %% row 1 scrolls off the top
        end
    end, #{}, Cells),
    erlang:put(home_scr_cells, NewCells).

do_put_char(Ch) ->
    Row   = erlang:get(home_scr_row),
    Col   = erlang:get(home_scr_col),
    Fg    = erlang:get(home_scr_fg),
    Bg    = erlang:get(home_scr_bg),
    Cells = erlang:get(home_scr_cells),
    erlang:put(home_scr_cells, Cells#{{Row, Col} => {Ch, Fg, Bg}}).

do_advance() ->
    Col = erlang:get(home_scr_col),
    if Col >= ?COLS ->
        do_newline();
    true ->
        erlang:put(home_scr_col, Col + 1)
    end.

%%%=========================================================================
%%% Internal: HTML rendering
%%%=========================================================================

%% Render the cell map to an iolist suitable for embedding inside a <pre>.
render_screen(Cells) ->
    MaxRow = case maps:keys(Cells) of
        []   -> 0;
        Keys -> lists:max([R || {R, _} <- Keys])
    end,
    case MaxRow of
        0 -> <<>>;
        _ ->
            Lines = [render_row(R, Cells) || R <- lists:seq(1, MaxRow)],
            iolist_to_binary(Lines)
    end.

render_row(R, Cells) ->
    RowEntries = [{C, V} || {{Row, C}, V} <- maps:to_list(Cells), Row =:= R],
    case RowEntries of
        [] ->
            "\n";
        _ ->
            Sorted = lists:sort(RowEntries),
            MaxCol = element(1, lists:last(Sorted)),
            Full   = fill_row(1, MaxCol, Sorted),
            Spans  = group_spans(Full),
            Trimmed = trim_trailing(Spans),
            [render_span_list(Trimmed), "\n"]
    end.

%% Build a flat list of {Char, FG, BG} for every column 1..MaxCol,
%% filling gaps with default-colour spaces.
fill_row(Col, MaxCol, _) when Col > MaxCol ->
    [];
fill_row(Col, MaxCol, []) ->
    [{$\s, ?DEFAULT_FG, ?DEFAULT_BG} | fill_row(Col + 1, MaxCol, [])];
fill_row(Col, MaxCol, [{Col, {Ch, Fg, Bg}} | Rest]) ->
    [{Ch, Fg, Bg} | fill_row(Col + 1, MaxCol, Rest)];
fill_row(Col, MaxCol, Entries) ->
    [{$\s, ?DEFAULT_FG, ?DEFAULT_BG} | fill_row(Col + 1, MaxCol, Entries)].

%% Merge consecutive cells that share the same FG/BG into a single span.
group_spans([]) -> [];
group_spans([{Ch, Fg, Bg} | Rest]) ->
    group_spans(Rest, Fg, Bg, [Ch], []).

group_spans([], Fg, Bg, ChAcc, SpanAcc) ->
    lists:reverse([{Fg, Bg, lists:reverse(ChAcc)} | SpanAcc]);
group_spans([{Ch, Fg, Bg} | Rest], Fg, Bg, ChAcc, SpanAcc) ->
    group_spans(Rest, Fg, Bg, [Ch | ChAcc], SpanAcc);
group_spans([{Ch, NewFg, NewBg} | Rest], Fg, Bg, ChAcc, SpanAcc) ->
    group_spans(Rest, NewFg, NewBg, [Ch], [{Fg, Bg, lists:reverse(ChAcc)} | SpanAcc]).

%% Strip trailing default-colour spaces from the last span (avoids
%% rendering long runs of invisible whitespace at the end of each line).
trim_trailing([]) ->
    [];
trim_trailing(Spans) ->
    case lists:last(Spans) of
        {?DEFAULT_FG, ?DEFAULT_BG, Chars} ->
            Stripped = lists:reverse(
                           lists:dropwhile(fun(C) -> C =:= $\s end,
                                           lists:reverse(Chars))),
            case Stripped of
                [] ->
                    trim_trailing(lists:droplast(Spans));
                _  ->
                    lists:droplast(Spans) ++ [{?DEFAULT_FG, ?DEFAULT_BG, Stripped}]
            end;
        _ ->
            Spans
    end.

render_span_list(Spans) ->
    [render_one_span(Fg, Bg, Chars) || {Fg, Bg, Chars} <- Spans].

%% Omit explicit CSS when both colours are the defaults (the <pre> CSS
%% already sets those via the outer container).
render_one_span(?DEFAULT_FG, ?DEFAULT_BG, Chars) ->
    esc(Chars);
render_one_span(Fg, ?DEFAULT_BG, Chars) ->
    ["<span style=\"color:", color_hex(Fg), "\">", esc(Chars), "</span>"];
render_one_span(?DEFAULT_FG, Bg, Chars) ->
    ["<span style=\"background:", color_hex(Bg), "\">", esc(Chars), "</span>"];
render_one_span(Fg, Bg, Chars) ->
    ["<span style=\"color:", color_hex(Fg), ";background:", color_hex(Bg), "\">",
     esc(Chars), "</span>"].

color_hex(N) when N >= 0, N =< 15 -> element(N + 1, ?CGA_COLORS);
color_hex(_)                       -> "#AAAAAA".

esc(Chars) ->
    lists:flatmap(fun
        ($&) -> "&amp;";
        ($<) -> "&lt;";
        ($>) -> "&gt;";
        ($") -> "&quot;";
        (C)  -> [C]
    end, Chars).
