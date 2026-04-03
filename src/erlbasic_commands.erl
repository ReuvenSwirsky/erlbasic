-module(erlbasic_commands).

-include_lib("kernel/include/file.hrl").

-include("erlbasic_state.hrl").

-export([parse_program_line/1,
         parse_list_command/1, filter_program_by_range/3, format_program/1,
         parse_delete_command/1, delete_lines_by_range/3,
         parse_file_command/1,
         handle_dir_command/1, handle_save_command/2, handle_load_command/2,
         handle_scratch_command/2,
         parse_renum_command/1, renumber_program/3,
         parse_bin_as_program/1, serialize_program/1]).

parse_program_line("") ->
    immediate;
parse_program_line(Line) ->
    case re:run(Line, "^(\\d+)\\s*(.*)$", [{capture, [1, 2], list}]) of
        {match, [LineNum, Code]} ->
            {program_line, list_to_integer(LineNum), string:trim(Code)};
        nomatch ->
            immediate
    end.

parse_list_command(Command) ->
    Trimmed = string:trim(Command),
    case Trimmed of
        "LIST" ->
            {list, all};
        _ ->
            %% LIST 10      -> list line 10
            %% LIST 10-50   -> list lines 10 through 50
            %% LIST -50     -> list from start to line 50
            %% LIST 50-     -> list from line 50 to end
            case re:run(Trimmed, "^LIST\\s+(\\d+)-(\\d+)$", [{capture, [1, 2], list}]) of
                {match, [StartStr, EndStr]} ->
                    {list, list_to_integer(StartStr), list_to_integer(EndStr)};
                nomatch ->
                    case re:run(Trimmed, "^LIST\\s+-(\\d+)$", [{capture, [1], list}]) of
                        {match, [EndStr]} ->
                            {list, 0, list_to_integer(EndStr)};
                        nomatch ->
                            case re:run(Trimmed, "^LIST\\s+(\\d+)-$", [{capture, [1], list}]) of
                                {match, [StartStr]} ->
                                    {list, list_to_integer(StartStr), infinity};
                                nomatch ->
                                    case re:run(Trimmed, "^LIST\\s+(\\d+)$", [{capture, [1], list}]) of
                                        {match, [LineStr]} ->
                                            Line = list_to_integer(LineStr),
                                            {list, Line, Line};
                                        nomatch ->
                                            nomatch
                                    end
                            end
                    end
            end
    end.

filter_program_by_range(Program, StartLine, EndLine) ->
    [{LineNum, Code} || {LineNum, Code} <- Program,
                        LineNum >= StartLine,
                        EndLine =:= infinity orelse LineNum =< EndLine].

parse_delete_command(Command) ->
    Trimmed = string:trim(Command),
    %% DELETE 10      -> delete line 10
    %% DELETE 10-50   -> delete lines 10 through 50
    %% DELETE -50     -> delete from start to line 50
    %% DELETE 50-     -> delete from line 50 to end
    case re:run(Trimmed, "^DELETE\\s+(\\d+)-(\\d+)$", [{capture, [1, 2], list}]) of
        {match, [StartStr, EndStr]} ->
            {delete, list_to_integer(StartStr), list_to_integer(EndStr)};
        nomatch ->
            case re:run(Trimmed, "^DELETE\\s+-(\\d+)$", [{capture, [1], list}]) of
                {match, [EndStr]} ->
                    {delete, 0, list_to_integer(EndStr)};
                nomatch ->
                    case re:run(Trimmed, "^DELETE\\s+(\\d+)-$", [{capture, [1], list}]) of
                        {match, [StartStr]} ->
                            {delete, list_to_integer(StartStr), infinity};
                        nomatch ->
                            case re:run(Trimmed, "^DELETE\\s+(\\d+)$", [{capture, [1], list}]) of
                                {match, [LineStr]} ->
                                    Line = list_to_integer(LineStr),
                                    {delete, Line, Line};
                                nomatch ->
                                    nomatch
                            end
                    end
            end
    end.

delete_lines_by_range(Program, StartLine, EndLine) ->
    [{LineNum, Code} || {LineNum, Code} <- Program,
                        LineNum < StartLine orelse (EndLine =/= infinity andalso LineNum > EndLine)].

parse_file_command(Command) ->
    Trimmed = string:trim(Command),
    case re:run(Trimmed, "(?i)^SAVE\\s+(.+)$", [{capture, [1], list}]) of
        {match, [Name]} ->
            {save, string:trim(Name)};
        nomatch ->
            case re:run(Trimmed, "(?i)^LOAD\\s+(.+)$", [{capture, [1], list}]) of
                {match, [Name]} ->
                    {load, string:trim(Name)};
                nomatch ->
                    case re:run(Trimmed, "(?i)^SCRATCH\\s+(.+)$", [{capture, [1], list}]) of
                        {match, [Name]} ->
                            {scratch, string:trim(Name)};
                        nomatch ->
                            nomatch
                    end
            end
    end.

handle_dir_command(State) ->
    case erlbasic_storage:list_programs_with_info() of
        {ok, UserFiles} ->
            case list_example_files_with_info() of
                {ok, ExampleFiles} ->
                    Output = format_dir_listing(UserFiles, ExampleFiles),
                    {State, Output};
                {error, _} ->
                    {State, ["?FILE ERROR\r\n"]}
            end;
        {error, _} ->
            {State, ["?FILE ERROR\r\n"]}
    end.

format_dir_listing([], []) ->
    PPN = erlbasic_storage:user_ppn_string(),
    ["DIR ", PPN, "\r\n",
     "Name             .Ext  Size Prot   Date       SY:", PPN, "\r\n\r\n",
     "Total of 0 blocks in 0 files in SY:", PPN, "\r\n"];
format_dir_listing(UserFiles, ExampleFiles) ->
    PPN = erlbasic_storage:user_ppn_string(),
    AllFiles = UserFiles ++ ExampleFiles,
    TotalFiles = length(AllFiles),
    TotalBlocks = lists:sum([blocks_from_bytes(Size) || {_, Size, _} <- AllFiles]),
    Header = ["DIR ", PPN, "\r\n",
              "Name             .Ext  Size Prot   Date       SY:", PPN, "\r\n\r\n"],
    FileLines = [format_file_entry(Name, Size, MTime) || {Name, Size, MTime} <- AllFiles],
    Footer = ["\r\nTotal of ", integer_to_list(TotalBlocks), " blocks in ",
              integer_to_list(TotalFiles), " files in SY:", PPN, "\r\n"],
    Header ++ FileLines ++ Footer.

format_file_entry(FileName, Size, MTime) ->
    {Name, Ext} = split_filename(FileName),
    NamePart = string:pad(Name, 16, trailing),
    ExtPart = string:pad(Ext, 5, trailing),
    Blocks = blocks_from_bytes(Size),
    SizePart = string:pad(integer_to_list(Blocks), 4, leading) ++ "P",
    ProtPart = "< 40>",
    DatePart = format_date(MTime),
    [NamePart, " ", ExtPart, " ", SizePart, " ", ProtPart, " ", DatePart, "\r\n"].

split_filename(FileName) ->
    case string:split(FileName, ".", trailing) of
        [Name, Ext] -> {Name, "." ++ Ext};
        [Name]      -> {Name, "    "}
    end.

blocks_from_bytes(Bytes) ->
    %% RSTS/E uses 512-byte blocks
    (Bytes + 511) div 512.

format_date(UnixTime) ->
    %% Convert Unix timestamp to datetime
    DateTime = calendar:gregorian_seconds_to_datetime(UnixTime + 62167219200),
    {{Year, Month, Day}, _} = DateTime,
    MonthName = lists:nth(Month, ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]),
    DayStr = string:pad(integer_to_list(Day), 2, leading, $0),
    YearStr = string:pad(integer_to_list(Year rem 100), 2, leading, $0),
    DayStr ++ "-" ++ MonthName ++ "-" ++ YearStr.

handle_save_command(State, RawName) ->
    case normalize_program_filename(RawName) of
        {ok, FileName} ->
            %% Check if base name (without extension) is too long
            BaseName = filename:basename(FileName, filename:extension(FileName)),
            case length(BaseName) > 16 of
                true ->
                    {State, ["?FILE NAME TOO LONG\r\n"]};
                false ->
                    Content = serialize_program(State#state.prog),
                    case erlbasic_storage:write_program(FileName, Content) of
                        ok           -> {State, ["Saved " ++ FileName ++ "\r\n"]};
                        {error, _}   -> {State, ["?FILE ERROR\r\n"]}
                    end
            end;
        {error, _} ->
            {State, ["?FILE ERROR\r\n"]}
    end.

handle_load_command(State, RawName) ->
    case normalize_program_filename(RawName) of
        {ok, FileName} ->
            case load_program_file(FileName) of
                {ok, Program} ->
                    {State#state{prog = Program, data_items = [], data_index = 1, continue_ctx = undefined}, ["OK\r\n"]};
                {syntax_error, LineNumber, PartialProgram} when is_integer(LineNumber) ->
                    %% Load the partial program so user can LIST and see the error
                    NewState = State#state{prog = PartialProgram, data_items = [], data_index = 1, continue_ctx = undefined},
                    {NewState, [erlbasic_eval:format_runtime_error(syntax_error, LineNumber)]};
                {syntax_error, LineNumber} when is_integer(LineNumber) ->
                    {State, [erlbasic_eval:format_runtime_error(syntax_error, LineNumber)]};
                syntax_error ->
                    {State, ["?SYNTAX ERROR\r\n"]};
                {error, program_not_found} ->
                    {State, [erlbasic_eval:format_runtime_error(program_not_found)]};
                {error, _} ->
                    {State, ["?FILE ERROR\r\n"]}
            end;
        {error, _} ->
            {State, ["?FILE ERROR\r\n"]}
    end.

handle_scratch_command(State, RawName) ->
    case normalize_program_filename(RawName) of
        {ok, FileName} ->
            case erlbasic_storage:delete_program(FileName) of
                ok             -> {State, ["Deleted " ++ FileName ++ "\r\n"]};
                {error, enoent} -> {State, [erlbasic_eval:format_runtime_error(program_not_found)]};
                {error, _}     -> {State, ["?FILE ERROR\r\n"]}
            end;
        {error, _} ->
            {State, ["?FILE ERROR\r\n"]}
    end.

load_program_file(FileName) ->
    %% 1. Try the shared examples directory first.
    ExamplePath = filename:join(examples_program_dir(), FileName),
    case read_program_file(ExamplePath) of
        {ok, _} = Ok                         -> Ok;
        {syntax_error, _, _} = E             -> E;
        {syntax_error, _} = E                -> E;
        syntax_error                         -> syntax_error;
        {error, enoent} ->
            %% 2. Fall back to the user's own storage area.
            case erlbasic_storage:read_program(FileName) of
                {ok, Bin} ->
                    parse_bin_as_program(Bin);
                {error, enoent} ->
                    {error, program_not_found};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

read_program_file(Path) ->
    case file:read_file(Path) of
        {ok, Bin} -> parse_bin_as_program(Bin);
        {error, Reason} -> {error, Reason}
    end.

parse_bin_as_program(Bin) ->
    case parse_program_text(binary_to_list(Bin)) of
        {ok, Program} ->
            {ok, Program};
        {error, {syntax_error, LineNumber, PartialProgram}} when is_integer(LineNumber) ->
            {syntax_error, LineNumber, PartialProgram};
        {error, {syntax_error, LineNumber}} when is_integer(LineNumber) ->
            {syntax_error, LineNumber};
        error ->
            syntax_error
    end.

serialize_program(Program) ->
    Lines = [integer_to_list(LineNumber) ++ " " ++ Code || {LineNumber, Code} <- Program],
    string:join(Lines, "\n") ++ "\n".

parse_program_text(Text) ->
    Lines = [string:trim(Line) || Line <- string:split(Text, "\n", all)],
    parse_program_lines(Lines, []).

parse_program_lines([], Acc) ->
    {ok, lists:keysort(1, Acc)};
parse_program_lines(["" | Rest], Acc) ->
    parse_program_lines(Rest, Acc);
parse_program_lines([Line | Rest], Acc) ->
    case parse_program_line(Line) of
        {program_line, Num, Code} ->
            case erlbasic_parser:validate_program_line(Code) of
                ok ->
                    parse_program_lines(Rest, [{Num, Code} | lists:keydelete(Num, 1, Acc)]);
                {error, _Reason} ->
                    %% Keep parse_program_text API stable; report line as syntax_error.
                    PartialProgram = lists:keysort(1, [{Num, Code} | lists:keydelete(Num, 1, Acc)]),
                    {error, {syntax_error, Num, PartialProgram}};
                error ->
                    %% Include the bad line in the partial program so it can be listed
                    PartialProgram = lists:keysort(1, [{Num, Code} | lists:keydelete(Num, 1, Acc)]),
                    {error, {syntax_error, Num, PartialProgram}}
            end;
        immediate ->
            error
    end.

%% ---- File-system helpers (examples dir and utilities) ----
%% Per-user file I/O is handled by erlbasic_storage.  Only shared
%% example files are accessed directly here.

list_regular_files(Dir) ->
    case file:list_dir(Dir) of
        {ok, Names} ->
            {ok, lists:sort([N || N <- Names, is_regular_file(Dir, N)])};
        {error, Reason} ->
            {error, Reason}
    end.

is_regular_file(Dir, Name) ->
    Path = filename:join(Dir, Name),
    case file:read_file_info(Path) of
        {ok, #file_info{type = regular}} -> true;
        _ -> false
    end.

list_files_with_info(Dir) ->
    case file:list_dir(Dir) of
        {ok, Names} ->
            Infos = lists:filtermap(fun(N) -> get_file_info(Dir, N) end, Names),
            {ok, lists:sort(Infos)};
        {error, Reason} ->
            {error, Reason}
    end.

get_file_info(Dir, Name) ->
    Path = filename:join(Dir, Name),
    case file:read_file_info(Path) of
        {ok, #file_info{type = regular, size = Size, mtime = MTime}} ->
            %% Convert mtime to Unix timestamp
            UnixTime = calendar:datetime_to_gregorian_seconds(MTime) - 62167219200,
            {true, {Name, Size, UnixTime}};
        _ ->
            false
    end.

normalize_program_filename(RawName) ->
    Name0 = string:trim(RawName),
    Name = keep_safe_chars(Name0),
    case Name of
        "" ->
            {error, invalid_filename};
        _ ->
            case filename:extension(Name) of
                "" -> {ok, Name ++ ".bas"};
                _ -> {ok, Name}
            end
    end.

keep_safe_chars(Text) ->
    Safe = [Ch || Ch <- Text,
        (Ch >= $A andalso Ch =< $Z) orelse
        (Ch >= $a andalso Ch =< $z) orelse
        (Ch >= $0 andalso Ch =< $9) orelse
        Ch =:= $_ orelse Ch =:= $- orelse Ch =:= $.],
    case Safe of
        [] -> "";
        _ -> Safe
    end.

list_example_files() ->
    Dir = examples_program_dir(),
    case file:list_dir(Dir) of
        {ok, _} ->
            list_regular_files(Dir);
        {error, enoent} ->
            {ok, []};
        {error, Reason} ->
            {error, Reason}
    end.

list_example_files_with_info() ->
    Dir = examples_program_dir(),
    case file:list_dir(Dir) of
        {ok, _} ->
            list_files_with_info(Dir);
        {error, enoent} ->
            {ok, []};
        {error, Reason} ->
            {error, Reason}
    end.

examples_program_dir() ->
    filename:join(repo_root_dir(), "examples").

repo_root_dir() ->
    BeamPath = code:which(?MODULE),
    case BeamPath of
        non_existing ->
            filename:absname(".");
        _ ->
            BeamDir = filename:dirname(BeamPath),
            find_repo_root(BeamDir)
    end.

find_repo_root(Dir) ->
    ConfigPath = filename:join(Dir, "rebar.config"),
    case filelib:is_regular(ConfigPath) of
        true ->
            Dir;
        false ->
            Parent = filename:dirname(Dir),
            case Parent =:= Dir of
                true -> filename:absname(".");
                false -> find_repo_root(Parent)
            end
    end.

parse_renum_command(Command) ->
    Trimmed = string:trim(Command),
    case re:run(Trimmed, "(?i)^RENUM(?:\\s+(\\d+)(?:\\s*,\\s*(\\d+))?)?$", [{capture, all_but_first, list}]) of
        {match, []} ->
            {ok, 10, 10};
        {match, [StartText]} ->
            parse_renum_single_arg(StartText);
        {match, [StartText, IncText]} ->
            parse_renum_two_args(StartText, IncText);
        nomatch ->
            error
    end.

parse_renum_single_arg(StartText) ->
    case parse_positive_int(StartText) of
        {ok, StartLine} ->
            {ok, StartLine, 10};
        error ->
            error
    end.

parse_renum_two_args(StartText, IncText) ->
    case {parse_positive_int(StartText), parse_positive_int(IncText)} of
        {{ok, StartLine}, {ok, Increment}} ->
            {ok, StartLine, Increment};
        _ ->
            error
    end.

parse_positive_int(Text) ->
    case string:to_integer(Text) of
        {Value, ""} when Value > 0 ->
            {ok, Value};
        _ ->
            error
    end.

renumber_program([], _StartLine, _Increment) ->
    [];
renumber_program(Program, StartLine, Increment) ->
    LineMap = build_line_map(Program, StartLine, Increment),
    [{maps:get(OldLine, LineMap), rewrite_line_refs(Code, LineMap)} || {OldLine, Code} <- Program].

build_line_map(Program, StartLine, Increment) ->
    build_line_map(Program, StartLine, Increment, 0, #{}).

build_line_map([], _StartLine, _Increment, _Index, Acc) ->
    Acc;
build_line_map([{OldLine, _Code} | Rest], StartLine, Increment, Index, Acc) ->
    NewLine = StartLine + (Index * Increment),
    build_line_map(Rest, StartLine, Increment, Index + 1, maps:put(OldLine, NewLine, Acc)).

rewrite_line_refs(Code, LineMap) ->
    case erlbasic_parser:should_split_top_level_sequence(Code) of
        true ->
            join_statements([rewrite_line_refs(Stmt, LineMap) || Stmt <- erlbasic_parser:split_statements(Code)]);
        false ->
            rewrite_single_statement_line_refs(Code, LineMap)
    end.

rewrite_single_statement_line_refs(Code, LineMap) ->
    case erlbasic_parser:parse_statement(Code) of
        {goto, LineExpr} ->
            "GOTO " ++ renumber_line_expr(LineExpr, LineMap);
        {gosub, LineExpr} ->
            "GOSUB " ++ renumber_line_expr(LineExpr, LineMap);
        {if_then_else, CondExpr, ThenStmt, undefined} ->
            "IF " ++ string:trim(CondExpr) ++ " THEN " ++ rewrite_line_refs(ThenStmt, LineMap);
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            "IF " ++ string:trim(CondExpr) ++ " THEN " ++ rewrite_line_refs(ThenStmt, LineMap) ++
                " ELSE " ++ rewrite_line_refs(ElseStmt, LineMap);
        _ ->
            Code
    end.

renumber_line_expr(LineExpr, LineMap) ->
    Trimmed = string:trim(LineExpr),
    case string:to_integer(Trimmed) of
        {OldLine, ""} ->
            case maps:find(OldLine, LineMap) of
                {ok, NewLine} -> integer_to_list(NewLine);
                error -> Trimmed
            end;
        _ ->
            Trimmed
    end.

join_statements([]) ->
    "";
join_statements([One]) ->
    One;
join_statements(Parts) ->
    string:join(Parts, ": ").

format_program(Program) ->
    [integer_to_list(LineNumber) ++ " " ++ normalize_keywords_for_list(Code) ++ "\r\n" || {LineNumber, Code} <- Program].

normalize_keywords_for_list(Code) ->
    lists:flatten(normalize_keywords_for_list(Code, [], false, [])).

normalize_keywords_for_list([], CurrentRev, _InString, AccRev) ->
    lists:reverse([flush_word(CurrentRev) | AccRev]);
normalize_keywords_for_list([$" | Rest], CurrentRev, false, AccRev) ->
    NextAccRev = [$" | [flush_word(CurrentRev) | AccRev]],
    normalize_keywords_for_list(Rest, [], true, NextAccRev);
normalize_keywords_for_list([$" | Rest], CurrentRev, true, AccRev) ->
    NextAccRev = [$" | [lists:reverse(CurrentRev) | AccRev]],
    normalize_keywords_for_list(Rest, [], false, NextAccRev);
normalize_keywords_for_list([Ch | Rest], CurrentRev, true, AccRev) ->
    normalize_keywords_for_list(Rest, [Ch | CurrentRev], true, AccRev);
normalize_keywords_for_list([Ch | Rest], CurrentRev, false, AccRev) when
    (Ch >= $A andalso Ch =< $Z) orelse
    (Ch >= $a andalso Ch =< $z) orelse
    (Ch >= $0 andalso Ch =< $9) orelse
    Ch =:= $_ orelse Ch =:= $$ orelse Ch =:= $% ->
    normalize_keywords_for_list(Rest, [Ch | CurrentRev], false, AccRev);
normalize_keywords_for_list([Ch | Rest], CurrentRev, false, AccRev) ->
    NextAccRev = [Ch | [flush_word(CurrentRev) | AccRev]],
    normalize_keywords_for_list(Rest, [], false, NextAccRev).

flush_word([]) ->
    [];
flush_word(CurrentRev) ->
    Word = lists:reverse(CurrentRev),
    case erlbasic_keywords:is_list_keyword(Word) of
        true -> string:to_upper(Word);
        false -> Word
    end.
