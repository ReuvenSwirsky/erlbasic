-module(erlbasic_parser).

-export([parse_statement/1, should_split_top_level_sequence/1, split_statements/1]).

-define(VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*[\\$%]?)").
-define(VAR_BASE_PATTERN, "([A-Za-z][A-Za-z0-9_]*[\\$%]?)").
-define(LOOP_VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*%?)").

parse_statement(Command) ->
    Trimmed = string:trim(Command),
    parse_print_statement(Trimmed).

parse_print_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PRINT\\s+(.+)$", [{capture, [1], list}]) of
        {match, [Expr]} ->
            {print, Expr};
        nomatch ->
            case re:run(Trimmed, "^\\?\\s*(.+)$", [{capture, [1], list}]) of
                {match, [Expr]} ->
                    {print, Expr};
                nomatch ->
                    parse_input_statement(Trimmed)
            end
    end.

parse_input_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^INPUT\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetText]} ->
            case parse_assignment_target(TargetText) of
                {ok, Target} -> {input, Target};
                error -> unknown
            end;
        nomatch ->
            parse_let_statement(Trimmed)
    end.

parse_let_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LET\\s+(.+?)\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [TargetText, Expr]} ->
            case parse_assignment_target(TargetText) of
                {ok, Target} -> {'let', Target, Expr};
                error -> unknown
            end;
        nomatch ->
            parse_dim_statement(Trimmed)
    end.

parse_dim_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^DIM\\s+(.+)$", [{capture, [1], list}]) of
        {match, [DeclText]} ->
            case parse_dim_decls(DeclText) of
                {ok, Decls} -> {dim, Decls};
                error -> unknown
            end;
        nomatch ->
            parse_def_fn_statement(Trimmed)
    end.

parse_dim_decls(Text) ->
    parse_dim_decls(split_commas_top_level(Text), []).

parse_dim_decls([], Acc) ->
    case Acc of
        [] -> error;
        _ -> {ok, lists:reverse(Acc)}
    end;
parse_dim_decls([Part | Rest], Acc) ->
    case parse_dim_decl(Part) of
        {ok, Decl} -> parse_dim_decls(Rest, [Decl | Acc]);
        error -> error
    end.

parse_dim_decl(Text) ->
    Trimmed = string:trim(Text),
    case re:run(Trimmed, "^" ++ ?VAR_BASE_PATTERN ++ "\\s*\\((.*)\\)$", [{capture, [1, 2], list}]) of
        {match, [Var, DimText]} ->
            case parse_index_exprs(DimText) of
                {ok, Dims} when length(Dims) =:= 1; length(Dims) =:= 2; length(Dims) =:= 3 ->
                    {ok, {string:to_upper(Var), Dims}};
                _ ->
                    error
            end;
        nomatch ->
            error
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
            parse_data_or_read_statement(Trimmed)
    end.

parse_data_or_read_statement(Trimmed) ->
    case parse_read_statement(Trimmed) of
        nomatch ->
            parse_data_statement(Trimmed);
        Result ->
            Result
    end.

parse_read_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^READ\\s+(.+)$", [{capture, [1], list}]) of
        {match, [VarText]} ->
            case parse_read_vars(VarText) of
                {ok, Vars} -> {read_data, Vars};
                error -> unknown
            end;
        nomatch ->
            nomatch
    end.

parse_read_vars(Text) ->
    Parts = split_commas_top_level(Text),
    parse_read_vars(Parts, []).

parse_read_vars([], Acc) ->
    case Acc of
        [] -> error;
        _ -> {ok, lists:reverse(Acc)}
    end;
parse_read_vars([Part | Rest], Acc) ->
    case parse_assignment_target(Part) of
        {ok, Target} ->
            parse_read_vars(Rest, [Target | Acc]);
        error ->
            error
    end.

parse_data_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^DATA(?:\\s+(.*))?$", [{capture, all_but_first, list}]) of
        {match, []} ->
            {data, []};
        {match, [DataText]} ->
            {data, normalize_data_items(split_commas_top_level(DataText))};
        nomatch ->
            parse_keyword_statement(Trimmed)
    end.

split_commas_top_level(Text) ->
    split_commas_top_level(Text, [], [], false, 0).

split_commas_top_level([], CurrentRev, PartsRev, _InString, _Depth) ->
    lists:reverse([lists:reverse(CurrentRev) | PartsRev]);
split_commas_top_level([$" | Rest], CurrentRev, PartsRev, InString, Depth) ->
    split_commas_top_level(Rest, [$" | CurrentRev], PartsRev, not InString, Depth);
split_commas_top_level([$( | Rest], CurrentRev, PartsRev, false, Depth) ->
    split_commas_top_level(Rest, [$( | CurrentRev], PartsRev, false, Depth + 1);
split_commas_top_level([$) | Rest], CurrentRev, PartsRev, false, Depth) when Depth > 0 ->
    split_commas_top_level(Rest, [$) | CurrentRev], PartsRev, false, Depth - 1);
split_commas_top_level([$, | Rest], CurrentRev, PartsRev, false, 0) ->
    split_commas_top_level(Rest, [], [lists:reverse(CurrentRev) | PartsRev], false, 0);
split_commas_top_level([Ch | Rest], CurrentRev, PartsRev, InString, Depth) ->
    split_commas_top_level(Rest, [Ch | CurrentRev], PartsRev, InString, Depth).

parse_assignment_target(Text) ->
    Trimmed = string:trim(Text),
    case re:run(Trimmed, "^" ++ ?VAR_BASE_PATTERN ++ "(?:\\((.*)\\))?$", [{capture, all_but_first, list}]) of
        {match, [Var]} ->
            {ok, {var_target, string:to_upper(Var)}};
        {match, [Var, IndexText]} ->
            case parse_index_exprs(IndexText) of
                {ok, IndexExprs} when length(IndexExprs) =:= 1; length(IndexExprs) =:= 2; length(IndexExprs) =:= 3 ->
                    {ok, {array_target, string:to_upper(Var), IndexExprs}};
                _ ->
                    error
            end;
        nomatch ->
            error
    end.

parse_index_exprs(Text) ->
    Parts = split_commas_top_level(Text),
    parse_non_empty_parts(Parts, []).

parse_non_empty_parts([], Acc) ->
    case Acc of
        [] -> error;
        _ -> {ok, lists:reverse(Acc)}
    end;
parse_non_empty_parts([Part | Rest], Acc) ->
    Trimmed = string:trim(Part),
    case Trimmed of
        "" -> error;
        _ -> parse_non_empty_parts(Rest, [Trimmed | Acc])
    end.

normalize_data_items(Parts) ->
    [normalize_data_item(Part) || Part <- Parts].

normalize_data_item(Part) ->
    Trimmed = string:trim(Part),
    case unquote_data_item(Trimmed) of
        {ok, Value} -> Value;
        error -> Trimmed
    end.

unquote_data_item([$" | Rest]) ->
    case lists:reverse(Rest) of
        [$" | MiddleRev] ->
            {ok, lists:reverse(MiddleRev)};
        _ ->
            error
    end;
unquote_data_item(_Other) ->
    error.

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
