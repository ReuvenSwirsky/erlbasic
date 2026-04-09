-module(erlbasic_mml).

-export([parse/1]).

%% Parse a Microsoft BASIC Music Macro Language string.
%%
%% Returns {ok, Notes, FinalMode}  where
%%   Notes    = [{FreqHz, PlayMs, TotalMs}]   (FreqHz = 0 means rest)
%%   FinalMode = unchanged | background | foreground
%%
%% Supported MML:
%%   O<n>              set octave (0-6)
%%   < | >             decrease / increase octave
%%   L<n>[.]           set default note length (1=whole .. 64)
%%   T<n>              set tempo in BPM (32-255, default 120)
%%   A-G[#+-][n][.]    play named note at given or default length
%%   N<n>[.]           play note by number (0=rest, 1-84)
%%   P<n>[.] | R<n>[.] rest for given or default length
%%   MN / ML / MS       articulation: normal / legato / staccato
%%   MB / MF            background / foreground (sets FinalMode)

-record(st, {
    octave = 4,
    tempo  = 120,
    len    = 4,
    dot    = false,     %% whether the current default length is dotted
    style  = normal,    %% normal | legato | staccato
    mode   = unchanged  %% unchanged | background | foreground
}).

parse(MmlStr) when is_list(MmlStr) ->
    Upper = string:to_upper(string:trim(MmlStr)),
    parse_tokens(Upper, #st{}, []);
parse(MmlStr) when is_binary(MmlStr) ->
    parse(binary_to_list(MmlStr)).

%% -----------------------------------------------------------------------
%% Token loop
%% -----------------------------------------------------------------------

parse_tokens([], St, Acc) ->
    {ok, lists:reverse(Acc), St#st.mode};

parse_tokens([$  | Rest], St, Acc) -> parse_tokens(Rest, St, Acc);
parse_tokens([$\t | Rest], St, Acc) -> parse_tokens(Rest, St, Acc);

%% Octave
parse_tokens([$O | Rest], St, Acc) ->
    case scan_int(Rest) of
        {ok, N, Tail} -> parse_tokens(Tail, St#st{octave = clamp(N, 0, 6)}, Acc);
        error         -> {error, syntax_error}
    end;
parse_tokens([$< | Rest], St, Acc) ->
    parse_tokens(Rest, St#st{octave = max(0, St#st.octave - 1)}, Acc);
parse_tokens([$> | Rest], St, Acc) ->
    parse_tokens(Rest, St#st{octave = min(6, St#st.octave + 1)}, Acc);

%% Default note length
parse_tokens([$L | Rest], St, Acc) ->
    case scan_int(Rest) of
        {ok, N, Tail} when N >= 1, N =< 64 ->
            {Dot, Tail2} = scan_dot(Tail),
            parse_tokens(Tail2, St#st{len = N, dot = Dot}, Acc);
        _ ->
            {error, syntax_error}
    end;

%% Tempo
parse_tokens([$T | Rest], St, Acc) ->
    case scan_int(Rest) of
        {ok, N, Tail} when N >= 32, N =< 255 ->
            parse_tokens(Tail, St#st{tempo = N}, Acc);
        _ ->
            {error, syntax_error}
    end;

%% Note by number: N0=rest, N1..N84=MIDI 24..107
parse_tokens([$N | Rest], St, Acc) ->
    case scan_int(Rest) of
        {ok, 0, Tail} ->
            {Dot, Tail2} = scan_dot(Tail),
            parse_tokens(Tail2, St, [rest_note(St#st.len, Dot, St) | Acc]);
        {ok, N, Tail} when N >= 1, N =< 84 ->
            {Dot, Tail2} = scan_dot(Tail),
            Note = named_note(23 + N, St#st.len, Dot, St),
            parse_tokens(Tail2, St, [Note | Acc]);
        _ ->
            {error, syntax_error}
    end;

%% Rest (P or R)
parse_tokens([$P | Rest], St, Acc) -> parse_rest(Rest, St, Acc);
parse_tokens([$R | Rest], St, Acc) -> parse_rest(Rest, St, Acc);

%% Mode / articulation (M prefix)
parse_tokens([$M | Rest], St, Acc) ->
    case Rest of
        [$B | T] -> parse_tokens(T, St#st{mode  = background}, Acc);
        [$F | T] -> parse_tokens(T, St#st{mode  = foreground}, Acc);
        [$N | T] -> parse_tokens(T, St#st{style = normal},     Acc);
        [$L | T] -> parse_tokens(T, St#st{style = legato},     Acc);
        [$S | T] -> parse_tokens(T, St#st{style = staccato},   Acc);
        _        -> {error, syntax_error}
    end;

%% Named note A-G
parse_tokens([Ch | Rest], St, Acc) when Ch >= $A, Ch =< $G ->
    {Acc2, Rest2, St2} = parse_named_note(Ch, Rest, St, Acc),
    parse_tokens(Rest2, St2, Acc2);

%% Skip unrecognised characters (lenient)
parse_tokens([_ | Rest], St, Acc) ->
    parse_tokens(Rest, St, Acc).

%% -----------------------------------------------------------------------
%% Rest helper
%% -----------------------------------------------------------------------

parse_rest(Rest, St, Acc) ->
    case scan_int(Rest) of
        {ok, N, Tail} when N >= 1, N =< 64 ->
            {Dot, Tail2} = scan_dot(Tail),
            parse_tokens(Tail2, St, [rest_note(N, Dot, St) | Acc]);
        _ ->
            {Dot, Rest2} = scan_dot(Rest),
            parse_tokens(Rest2, St, [rest_note(St#st.len, Dot, St) | Acc])
    end.

%% -----------------------------------------------------------------------
%% Named note helper (A-G with optional accidental, length, dot)
%% -----------------------------------------------------------------------

parse_named_note(Ch, Rest, St, Acc) ->
    {AccType, Rest2} = case Rest of
        [$# | T] -> {sharp, T};
        [$+ | T] -> {sharp, T};
        [$- | T] -> {flat,  T};
        _        -> {none,  Rest}
    end,
    {Len, Rest3} = case scan_int(Rest2) of
        {ok, N, T2} when N >= 1, N =< 64 -> {N, T2};
        _                                 -> {St#st.len, Rest2}
    end,
    {Dot, Rest4} = scan_dot(Rest3),
    Midi = note_midi(Ch, AccType, St#st.octave),
    Note = named_note(Midi, Len, Dot, St),
    {[Note | Acc], Rest4, St}.

%% -----------------------------------------------------------------------
%% Low-level numeric helpers
%% -----------------------------------------------------------------------

scan_dot([$. | Rest]) -> {true, Rest};
scan_dot(Rest)        -> {false, Rest}.

scan_int(Str) -> scan_int(Str, []).

scan_int([Ch | Rest], Acc) when Ch >= $0, Ch =< $9 ->
    scan_int(Rest, [Ch | Acc]);
scan_int(_Rest, []) ->
    error;
scan_int(Rest, Acc) ->
    {ok, list_to_integer(lists:reverse(Acc)), Rest}.

%% -----------------------------------------------------------------------
%% Music theory helpers
%% -----------------------------------------------------------------------

note_midi(Ch, AccType, Octave) ->
    Base = case Ch of
        $C -> 0; $D -> 2; $E -> 4; $F -> 5;
        $G -> 7; $A -> 9; $B -> 11
    end,
    Adj = case AccType of
        sharp -> 1; flat -> -1; none -> 0
    end,
    12 * (Octave + 1) + Base + Adj.

midi_to_hz(Midi) ->
    round(440.0 * math:pow(2.0, (Midi - 69) / 12.0)).

%% Duration in ms for a note of length Len (1=whole .. 64) at Tempo BPM.
dur_ms(Len, Dot, Tempo) ->
    Base = (60000.0 / Tempo) * (4.0 / Len),
    Raw  = case Dot of true -> Base * 1.5; false -> Base end,
    max(1, round(Raw)).

named_note(Midi, Len, Dot, St) ->
    Total = dur_ms(Len, Dot, St#st.tempo),
    Play  = articulate(Total, St#st.style),
    {midi_to_hz(Midi), Play, Total}.

rest_note(Len, Dot, St) ->
    Total = dur_ms(Len, Dot, St#st.tempo),
    {0, 0, Total}.

articulate(Total, normal)   -> max(1, round(Total * 7 / 8));
articulate(Total, legato)   -> Total;
articulate(Total, staccato) -> max(1, round(Total * 3 / 4)).

clamp(V, Min, _)   when V < Min -> Min;
clamp(V, _, Max)   when V > Max -> Max;
clamp(V, _, _)                  -> V.
