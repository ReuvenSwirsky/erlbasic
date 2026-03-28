-module(erlbasic_parser).

-export([parse_statement/1, should_split_top_level_sequence/1, split_statements/1]).

-define(VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*[\\$%]?)").
-define(LOOP_VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*%?)").

parse_statement(Command) ->
    Trimmed = string:trim(Command),
    parse_print_statement(Trimmed).

parse_print_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PRINT\\s+(.+)$", [{capture, [1], list}]) of
        {match, [Expr]} ->
            {print, Expr};
        nomatch ->
            parse_input_statement(Trimmed)
    end.

parse_input_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^INPUT\\s+" ++ ?VAR_PATTERN ++ "$", [{capture, [1], list}]) of
        {match, [Var]} ->
            {input, string:to_upper(Var)};
        nomatch ->
            parse_let_statement(Trimmed)
    end.

parse_let_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LET\\s+" ++ ?VAR_PATTERN ++ "\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [Var, Expr]} ->
            {'let', string:to_upper(Var), Expr};
        nomatch ->
            parse_def_fn_statement(Trimmed)
    end.

parse_def_fn_statement(Trimmed) ->
    case re:run(
        Trimmed,
        "(?i)^DEF\\s+FN([A-Za-z][A-Za-z0-9_]*)(?:\\s*\\(\\s*" ++ ?VAR_PATTERN ++ "\\s*\\))?\\s*=\\s*(.+)$",
        [{capture, all_but_first, list}]) of
        {match, [FnSuffix, Expr]} ->
            {def_fn, "FN" ++ string:to_upper(FnSuffix), undefined, Expr};
        {match, [FnSuffix, ArgVar, Expr]} ->
            {def_fn, "FN" ++ string:to_upper(FnSuffix), string:to_upper(ArgVar), Expr};
        nomatch ->
            parse_if_statement(Trimmed)
    end.

parse_if_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^IF\\s+(.+?)\\s+THEN\\s+(.+?)(?:\\s+ELSE\\s+(.+))?$", [{capture, all_but_first, list}]) of
        {match, [CondExpr, ThenStmt]} ->
            {if_then_else, CondExpr, ThenStmt, undefined};
        {match, [CondExpr, ThenStmt, ElseStmt]} ->
            {if_then_else, CondExpr, ThenStmt, ElseStmt};
        nomatch ->
            parse_jump_statement(Trimmed)
    end.

parse_jump_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^GOTO\\s+(.+)$", [{capture, [1], list}]) of
        {match, [LineExpr]} ->
            {goto, LineExpr};
        nomatch ->
            case re:run(Trimmed, "(?i)^GOSUB\\s+(.+)$", [{capture, [1], list}]) of
                {match, [LineExpr]} ->
                    {gosub, LineExpr};
                nomatch ->
                    parse_loop_statement(Trimmed)
            end
    end.

parse_loop_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^FOR\\s+" ++ ?LOOP_VAR_PATTERN ++ "\\s*=\\s*(.+)\\s+TO\\s+(.+?)(?:\\s+STEP\\s+(.+))?$", [{capture, all_but_first, list}]) of
        {match, [Var, StartExpr, EndExpr]} ->
            {for_loop, string:to_upper(Var), StartExpr, EndExpr, undefined};
        {match, [Var, StartExpr, EndExpr, StepExpr]} ->
            {for_loop, string:to_upper(Var), StartExpr, EndExpr, StepExpr};
        nomatch ->
            parse_next_statement(Trimmed)
    end.

parse_next_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^NEXT(?:\\s+" ++ ?VAR_PATTERN ++ ")?$", [{capture, all_but_first, list}]) of
        {match, []} ->
            {next_loop, undefined};
        {match, [Var]} ->
            {next_loop, string:to_upper(Var)};
        nomatch ->
            parse_keyword_statement(Trimmed)
    end.

parse_keyword_statement(Trimmed) ->
    case string:to_upper(Trimmed) of
        "RETURN" -> {'return'};
        "END" -> {'end'};
        _ -> unknown
    end.

should_split_top_level_sequence(Command) ->
    Statements = split_statements(Command),
    case length(Statements) > 1 of
        false ->
            false;
        true ->
            Trimmed = string:trim(Command),
            case re:run(Trimmed, "(?i)^IF\\s+", [{capture, none}]) of
                match -> false;
                nomatch -> true
            end
    end.

split_statements(Text) ->
    split_statements(Text, [], [], false).

split_statements([], CurrentRev, PartsRev, _InString) ->
    FinalPart = string:trim(lists:reverse(CurrentRev)),
    lists:reverse(add_part(FinalPart, PartsRev));
split_statements([$" | Rest], CurrentRev, PartsRev, InString) ->
    split_statements(Rest, [$" | CurrentRev], PartsRev, not InString);
split_statements([$: | Rest], CurrentRev, PartsRev, false) ->
    Part = string:trim(lists:reverse(CurrentRev)),
    split_statements(Rest, [], add_part(Part, PartsRev), false);
split_statements([Ch | Rest], CurrentRev, PartsRev, InString) ->
    split_statements(Rest, [Ch | CurrentRev], PartsRev, InString).

add_part("", PartsRev) ->
    PartsRev;
add_part(Part, PartsRev) ->
    [Part | PartsRev].
