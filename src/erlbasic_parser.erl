-module(erlbasic_parser).

-export([parse_statement/1, should_split_top_level_sequence/1, split_statements/1, validate_program_line/1]).

-define(VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*[\\$%&]?)").
-define(VAR_BASE_PATTERN, "([A-Za-z][A-Za-z0-9_]*[\\$%&]?)").
-define(LOOP_VAR_PATTERN, "([A-Za-z][A-Za-z0-9_]*[%&]?)").

parse_statement(Command) ->
    Trimmed = string:trim(Command),
    case re:run(Trimmed, "(?i)^REM(\\s|$)", [{capture, none}]) of
        match  -> {remark};
        nomatch -> parse_print_statement(Trimmed)
    end.

validate_program_line(Command) ->
    Trimmed = string:trim(Command),
    case has_balanced_quotes(Trimmed) of
        false ->
            error;
        true ->
            validate_statement_sequence(Trimmed)
    end.

parse_print_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PRINT\\s+USING\\s+(.+)$", [{capture, [1], list}]) of
        {match, [UsingText]} ->
            case parse_print_using_items(UsingText) of
                {ok, FormatExpr, Items, EndWithNewline} -> {print_using, FormatExpr, Items, EndWithNewline};
                error -> unknown
            end;
        nomatch ->
            parse_print_or_qmark_statement(Trimmed)
    end.

parse_print_or_qmark_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PRINT(?:\\s+(.*))?$", [{capture, all_but_first, list}]) of
        {match, []} ->
            {print, [], true};
        {match, [ItemsText]} ->
            case parse_print_items(ItemsText) of
                {ok, Items, EndWithNewline} -> {print, Items, EndWithNewline};
                error -> unknown
            end;
        nomatch ->
            case re:run(Trimmed, "^\\?\\s*(.*)$", [{capture, [1], list}]) of
                {match, [ItemsText]} ->
                    case parse_print_items(ItemsText) of
                        {ok, Items, EndWithNewline} -> {print, Items, EndWithNewline};
                        error -> unknown
                    end;
                nomatch ->
                    parse_input_statement(Trimmed)
            end
    end.

parse_print_using_items(Text) ->
    case parse_print_items(Text) of
        {ok, [], _EndWithNewline} ->
            error;
        {ok, [{FormatExpr, _FmtSep} | Rest], EndWithNewline} ->
            {ok, FormatExpr, Rest, EndWithNewline};
        error ->
            error
    end.

parse_print_items(Text) ->
    parse_print_items(Text, [], [], false, 0).

parse_print_items([], CurrentRev, PartsRev, _InString, _Depth) ->
    FinalExpr = string:trim(lists:reverse(CurrentRev)),
    case {FinalExpr, PartsRev} of
        {"", []} ->
            {ok, [], true};
        {"", [{_Expr, semicolon} | _]} ->
            {ok, lists:reverse(PartsRev), false};
        {"", _} ->
            error;
        {_Expr, _} ->
            {ok, lists:reverse([{FinalExpr, none} | PartsRev]), true}
    end;
parse_print_items([$" | Rest], CurrentRev, PartsRev, InString, Depth) ->
    parse_print_items(Rest, [$" | CurrentRev], PartsRev, not InString, Depth);
parse_print_items([$( | Rest], CurrentRev, PartsRev, false, Depth) ->
    parse_print_items(Rest, [$( | CurrentRev], PartsRev, false, Depth + 1);
parse_print_items([$) | Rest], CurrentRev, PartsRev, false, Depth) when Depth > 0 ->
    parse_print_items(Rest, [$) | CurrentRev], PartsRev, false, Depth - 1);
parse_print_items([$, | Rest], CurrentRev, PartsRev, false, 0) ->
    push_print_part(Rest, CurrentRev, PartsRev, comma);
parse_print_items([$; | Rest], CurrentRev, PartsRev, false, 0) ->
    push_print_part(Rest, CurrentRev, PartsRev, semicolon);
parse_print_items([Ch | Rest], CurrentRev, PartsRev, InString, Depth) ->
    parse_print_items(Rest, [Ch | CurrentRev], PartsRev, InString, Depth).

push_print_part(Rest, CurrentRev, PartsRev, Sep) ->
    Expr = string:trim(lists:reverse(CurrentRev)),
    case Expr of
        "" ->
            error;
        _ ->
            parse_print_items(Rest, [], [{Expr, Sep} | PartsRev], false, 0)
    end.

parse_input_statement(Trimmed) ->
    %% INPUT LINE must be checked before plain INPUT to avoid prefix ambiguity.
    case re:run(Trimmed, "(?i)^INPUT\\s+LINE\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {input_line, Target};
                error -> unknown
            end;
        nomatch ->
            case re:run(Trimmed, "(?i)^INPUT\\s+(.+)$", [{capture, [1], list}]) of
                {match, [TargetsText]} ->
                    case parse_input_target_list(split_commas_top_level(TargetsText), []) of
                        {ok, Targets} -> {input, Targets};
                        error -> unknown
                    end;
                nomatch ->
                    parse_get_statement(Trimmed)
            end
    end.

%% GETKEY must be matched before GET to avoid prefix collision.
parse_get_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^GETKEY\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetText]} ->
            case parse_assignment_target(string:trim(TargetText)) of
                {ok, Target} -> {getkey, Target};
                error -> unknown
            end;
        nomatch ->
            case re:run(Trimmed, "(?i)^GET\\s+(.+)$", [{capture, [1], list}]) of
                {match, [TargetText]} ->
                    case parse_assignment_target(string:trim(TargetText)) of
                        {ok, Target} -> {get, Target};
                        error -> unknown
                    end;
                nomatch ->
                    parse_let_statement(Trimmed)
            end
    end.

parse_input_target_list([], []) ->
    error;
parse_input_target_list([], Acc) ->
    {ok, lists:reverse(Acc)};
parse_input_target_list([Part | Rest], Acc) ->
    case parse_assignment_target(string:trim(Part)) of
        {ok, Target} -> parse_input_target_list(Rest, [Target | Acc]);
        error -> error
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
            parse_error_handler_statement(Trimmed)
    end.

parse_error_handler_statement(Trimmed) ->
    %% Check for ON ERROR GOTO
    case re:run(Trimmed, "(?i)^ON\\s+ERROR\\s+GOTO\\s+(.+)$", [{capture, [1], list}]) of
        {match, [TargetExpr]} ->
            {on_error_goto, string:trim(TargetExpr)};
        nomatch ->
            parse_resume_statement(Trimmed)
    end.

parse_resume_statement(Trimmed) ->
    %% Check for RESUME variants
    case re:run(Trimmed, "(?i)^RESUME\\s+NEXT$", [{capture, none}]) of
        match ->
            {resume_next};
        nomatch ->
            case re:run(Trimmed, "(?i)^RESUME\\s+(.+)$", [{capture, [1], list}]) of
                {match, [LineExpr]} ->
                    case string:trim(LineExpr) of
                        "0" -> {resume};  % RESUME 0 is same as RESUME
                        Other -> {resume_line, Other}
                    end;
                nomatch ->
                    case re:run(Trimmed, "(?i)^RESUME$", [{capture, none}]) of
                        match ->
                            {resume};
                        nomatch ->
                            parse_jump_statement(Trimmed)
                    end
            end
    end.

parse_jump_statement(Trimmed) ->
    %% Check for ON...GOSUB / ON...GOTO first (computed jump)
    case re:run(Trimmed, "(?i)^ON\\s+(.+?)\\s+GOSUB\\s+(.+)$", [{capture, [1,2], list}]) of
        {match, [Expr, Targets]} ->
            TargetList = parse_comma_separated_list(Targets),
            {on_gosub, Expr, TargetList};
        nomatch ->
            case re:run(Trimmed, "(?i)^ON\\s+(.+?)\\s+GOTO\\s+(.+)$", [{capture, [1,2], list}]) of
                {match, [Expr, Targets]} ->
                    TargetList = parse_comma_separated_list(Targets),
                    {on_goto, Expr, TargetList};
                nomatch ->
                    parse_simple_jump_statement(Trimmed)
            end
    end.

parse_simple_jump_statement(Trimmed) ->
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

parse_comma_separated_list(Str) ->
    Parts = string:split(string:trim(Str), ",", all),
    [string:trim(P) || P <- Parts].

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
            parse_locate_statement(Trimmed)
    end.

parse_locate_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LOCATE\\s+(.+?)\\s*,\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [RowExpr, ColExpr]} ->
            {locate, RowExpr, ColExpr};
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
        "CLS" -> {cls};
        "HGR" -> {hgr};
        "TEXT" -> {text};
        "RETURN" -> {'return'};
        "END" -> {'end'};
        _ -> parse_pset_statement(Trimmed)
    end.

parse_pset_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^PSET\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+)$", [{capture, [1, 2, 3], list}]) of
        {match, [XExpr, YExpr, ColorExpr]} -> {pset, XExpr, YExpr, ColorExpr};
        nomatch -> parse_line_statement(Trimmed)
    end.

parse_line_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LINE\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*-\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+)$", 
                [{capture, [1, 2, 3, 4, 5], list}]) of
        {match, [X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr]} -> 
            {line, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr};
        nomatch -> parse_lineto_statement(Trimmed)
    end.

parse_lineto_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^LINETO\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+)$", 
                [{capture, [1, 2, 3], list}]) of
        {match, [XExpr, YExpr, ColorExpr]} -> 
            {lineto, XExpr, YExpr, ColorExpr};
        nomatch -> parse_rect_statement(Trimmed)
    end.

parse_rect_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^RECT\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*-\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+)$", 
                [{capture, [1, 2, 3, 4, 5], list}]) of
        {match, [X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr]} -> 
            {rect, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr};
        nomatch -> parse_circle_statement(Trimmed)
    end.

parse_circle_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^CIRCLE\\s*\\(\\s*(.+?)\\s*,\\s*(.+?)\\s*\\)\\s*,\\s*(.+?)\\s*,\\s*(.+)$", 
                [{capture, [1, 2, 3, 4], list}]) of
        {match, [XExpr, YExpr, RadiusExpr, ColorExpr]} -> 
            {circle, XExpr, YExpr, RadiusExpr, ColorExpr};
        nomatch -> parse_sleep_statement(Trimmed)
    end.

parse_sleep_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^SLEEP\\s+(.+)$", [{capture, [1], list}]) of
        {match, [Expr]} -> {sleep, Expr};
        nomatch         -> parse_color_statement(Trimmed)
    end.

parse_color_statement(Trimmed) ->
    case re:run(Trimmed, "(?i)^COLOR\\s+(.+?)(?:\\s*,\\s*(.+))?$", [{capture, all_but_first, list}]) of
        {match, [FgExpr]} ->
            {color, FgExpr, undefined};
        {match, [FgExpr, BgExpr]} ->
            {color, FgExpr, BgExpr};
        nomatch ->
            parse_implicit_let_statement(Trimmed)
    end.

parse_implicit_let_statement(Trimmed) ->
    case re:run(Trimmed, "^(.+?)\\s*=\\s*(.+)$", [{capture, [1, 2], list}]) of
        {match, [TargetText, Expr]} ->
            case parse_assignment_target(TargetText) of
                {ok, Target} -> {'let', Target, Expr};
                error -> unknown
            end;
        nomatch ->
            unknown
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
    case re:run(Part, "(?i)^REM(\\s|$)", [{capture, none}]) of
        match   -> lists:reverse(add_part(Part, PartsRev));
        nomatch -> split_statements(Rest, [], add_part(Part, PartsRev), false)
    end;
split_statements([Ch | Rest], CurrentRev, PartsRev, InString) ->
    split_statements(Rest, [Ch | CurrentRev], PartsRev, InString).

add_part("", PartsRev) ->
    PartsRev;
add_part(Part, PartsRev) ->
    [Part | PartsRev].

validate_statement_sequence("") ->
    ok;
validate_statement_sequence(Command) ->
    Statements =
        case should_split_top_level_sequence(Command) of
            true -> split_statements(Command);
            false -> [string:trim(Command)]
        end,
    validate_statements(Statements).

validate_statements([]) ->
    ok;
validate_statements([Stmt | Rest]) ->
    case validate_statement(Stmt) of
        ok -> validate_statements(Rest);
        error -> error
    end.

validate_statement(Stmt) ->
    case parse_statement(Stmt) of
        {print, Items, _EndWithNewline} ->
            validate_print_items(Items);
        {print_using, FormatExpr, Items, _EndWithNewline} ->
            case validate_expr_syntax(FormatExpr) of
                ok -> validate_print_items(Items);
                error -> error
            end;
        {input, Targets} ->
            validate_input_targets(Targets);
        {input_line, Target} ->
            validate_target_syntax(Target);
        {get, Target} ->
            validate_target_syntax(Target);
        {getkey, Target} ->
            validate_target_syntax(Target);
        {'let', Target, Expr} ->
            case validate_target_syntax(Target) of
                ok -> validate_expr_syntax(Expr);
                error -> error
            end;
        {dim, Decls} ->
            validate_dim_decls(Decls);
        {def_fn, _FnName, _ArgVar, Expr} ->
            validate_expr_syntax(Expr);
        {if_then_else, CondExpr, ThenStmt, ElseStmt} ->
            case validate_condition_syntax(CondExpr) of
                ok ->
                    case validate_statement_sequence(ThenStmt) of
                        ok -> validate_optional_statement_sequence(ElseStmt);
                        error -> error
                    end;
                error ->
                    error
            end;
        {goto, LineExpr} ->
            validate_expr_syntax(LineExpr);
        {gosub, LineExpr} ->
            validate_expr_syntax(LineExpr);
        {on_goto, Expr, Targets} ->
            case validate_expr_syntax(Expr) of
                ok -> validate_line_targets(Targets);
                error -> error
            end;
        {on_gosub, Expr, Targets} ->
            case validate_expr_syntax(Expr) of
                ok -> validate_line_targets(Targets);
                error -> error
            end;
        {on_error_goto, TargetExpr} ->
            validate_expr_syntax(TargetExpr);
        {resume} ->
            ok;
        {resume_next} ->
            ok;
        {resume_line, LineExpr} ->
            validate_expr_syntax(LineExpr);
        {for_loop, _Var, StartExpr, EndExpr, undefined} ->
            validate_expr_pair(StartExpr, EndExpr);
        {for_loop, _Var, StartExpr, EndExpr, StepExpr} ->
            case validate_expr_pair(StartExpr, EndExpr) of
                ok -> validate_expr_syntax(StepExpr);
                error -> error
            end;
        {next_loop, _MaybeVar} ->
            ok;
        {locate, RowExpr, ColExpr} ->
            validate_expr_pair(RowExpr, ColExpr);
        {data, _Items} ->
            ok;
        {read_data, Targets} ->
            validate_targets(Targets);
        {'return'} ->
            ok;
        {cls} ->
            ok;
        {hgr} ->
            ok;
        {text} ->
            ok;
        {pset, XExpr, YExpr, ColorExpr} ->
            case validate_expr_pair(XExpr, YExpr) of
                ok -> validate_expr_syntax(ColorExpr);
                error -> error
            end;
        {line, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr} ->
            case validate_expr_pair(X1Expr, Y1Expr) of
                ok ->
                    case validate_expr_pair(X2Expr, Y2Expr) of
                        ok -> validate_expr_syntax(ColorExpr);
                        error -> error
                    end;
                error -> error
            end;
        {circle, XExpr, YExpr, RadiusExpr, ColorExpr} ->
            case validate_expr_pair(XExpr, YExpr) of
                ok ->
                    case validate_expr_syntax(RadiusExpr) of
                        ok -> validate_expr_syntax(ColorExpr);
                        error -> error
                    end;
                error -> error
            end;
        {sleep, Expr} ->
            validate_expr_syntax(Expr);
        {color, FgExpr, undefined} ->
            validate_expr_syntax(FgExpr);
        {color, FgExpr, BgExpr} ->
            validate_expr_pair(FgExpr, BgExpr);
        {remark} ->
            ok;
        {'end'} ->
            ok;
        unknown ->
            error
    end.

validate_optional_statement_sequence(undefined) ->
    ok;
validate_optional_statement_sequence(Stmt) ->
    validate_statement_sequence(Stmt).

validate_expr_pair(LeftExpr, RightExpr) ->
    case validate_expr_syntax(LeftExpr) of
        ok -> validate_expr_syntax(RightExpr);
        error -> error
    end.

validate_targets([]) ->
    ok;
validate_targets([Target | Rest]) ->
    case validate_target_syntax(Target) of
        ok -> validate_targets(Rest);
        error -> error
    end.

validate_dim_decls([]) ->
    ok;
validate_dim_decls([{_Name, DimExprs} | Rest]) ->
    case validate_exprs(DimExprs) of
        ok -> validate_dim_decls(Rest);
        error -> error
    end.

validate_input_targets([]) ->
    error;                              %% no targets at all: parse error
validate_input_targets(Targets) ->
    validate_input_targets_all(Targets).

validate_input_targets_all([]) -> ok;
validate_input_targets_all([Target | Rest]) ->
    case validate_target_syntax(Target) of
        ok    -> validate_input_targets_all(Rest);
        error -> error
    end.

validate_target_syntax({var_target, _Var}) ->
    ok;
validate_target_syntax({array_target, _Var, IndexExprs}) ->
    validate_exprs(IndexExprs).

validate_exprs([]) ->
    ok;
validate_exprs([Expr | Rest]) ->
    case validate_expr_syntax(Expr) of
        ok -> validate_exprs(Rest);
        error -> error
    end.

validate_expr_syntax(Expr) ->
    case erlbasic_eval:eval_expr_result(Expr, #{}, #{}) of
        {error, syntax_error, _} -> error;
        _ -> ok
    end.

validate_print_items([]) ->
    ok;
validate_print_items([{Expr, _Sep} | Rest]) ->
    case validate_expr_syntax(Expr) of
        ok -> validate_print_items(Rest);
        error -> error
    end.

validate_condition_syntax(CondExpr) ->
    case erlbasic_eval:eval_condition_result(CondExpr, #{}, #{}) of
        {error, syntax_error} -> error;
        _ -> ok
    end.

validate_line_targets([]) ->
    ok;
validate_line_targets([Target | Rest]) ->
    case validate_expr_syntax(Target) of
        ok -> validate_line_targets(Rest);
        error -> error
    end.

has_balanced_quotes(Text) ->
    has_balanced_quotes(Text, false).

has_balanced_quotes([], InString) ->
    not InString;
has_balanced_quotes([$" | Rest], InString) ->
    has_balanced_quotes(Rest, not InString);
has_balanced_quotes([_Ch | Rest], InString) ->
    has_balanced_quotes(Rest, InString).
