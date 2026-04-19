-module(erlbasic_keywords).

-export([
    expr_keywords/0,
    list_keywords/0,
    reserved_only_keywords/0,
    builtin_function_keywords/0,
    is_expr_keyword/1,
    is_list_keyword/1,
    is_builtin_function_keyword/1,
    is_reserved_variable_name/1,
    is_user_fn_name/1
]).

expr_keywords() ->
    builtin_function_keywords() ++ [
        "MOD", "AND", "OR", "NOT", "XOR"
    ].

builtin_function_keywords() ->
    [
        "ABS", "ACOS", "ASIN", "ATAN", "ATN", "ATAN2", "COS", "DEG", "EXP", "FIX", "INT", "LN", "LOG",
        "PI", "POW", "RAD", "RND", "SGN", "SIN", "SQR", "SQRT", "TAN", "FLOOR", "CEIL", "VAL", "POS", "EOF", "LOF", "SEEK",
        "LEFT$", "RIGHT$", "MID$", "LEN", "INSTR", "ASC", "CHR$", "STR$", "SPACE$", "STRING$", "DATE$", "TIME$", "TERM$",
        "TIMER", "FREE", "MEM_USED", "PLAY",
        "CDBL", "CINT", "CSNG", "TYPEOF"
    ].

list_keywords() ->
    [
        "PRINT", "USING", "LET", "INPUT", "LINE", "DEF", "IF", "THEN", "ELSE", "ELSEIF", "FOR", "TO", "STEP", "NEXT", "CLS", "COLOR", "LOCATE",
        "GOTO", "GOSUB", "RETURN", "END", "STOP", "DATA", "READ", "DIM", "MOD", "REM", "GET", "GETKEY", "GETCHAR", "SLEEP", "SOUND", "TIMER", "CHAIN",
        "OPEN", "CLOSE", "WRITE", "FIELD", "PUT", "AS", "APPEND", "RANDOM", "OUTPUT", "SPRITE",
        "TRON", "TROFF", "FLUSH", "BUFFER", "PGET"
    ].

reserved_only_keywords() ->
    [
        "HGR", "HGR2", "TEXT", "PSET", "LINETO", "RECT", "CIRCLE", "ON", "ERROR", "RESUME", "FN"
    ].

%% Keywords recognized while tokenizing/evaluating expressions.
is_expr_keyword(Word) ->
    Upper = string:to_upper(Word),
    lists:member(Upper, expr_keywords()).

%% Keywords normalized to uppercase in LIST output.
is_list_keyword(Word) ->
    Upper = string:to_upper(Word),
    lists:member(Upper, list_keywords()).

is_builtin_function_keyword(Word) ->
    Upper = string:to_upper(Word),
    lists:member(Upper, builtin_function_keywords()).

%% Reserved variable names are the union of expression keywords, LIST keywords,
%% and parser/evaluator keywords that are otherwise context-specific.
is_reserved_variable_name(Name) ->
    UpperFull = string:to_upper(Name),
    UpperBase = string:to_upper(strip_var_sigil(Name)),
    is_expr_keyword(UpperFull) orelse
    is_expr_keyword(UpperBase) orelse
    is_list_keyword(UpperFull) orelse
    is_list_keyword(UpperBase) orelse
    is_reserved_only_keyword(UpperFull) orelse
    is_reserved_only_keyword(UpperBase).

is_reserved_only_keyword(Upper) ->
    lists:member(Upper, reserved_only_keywords()).

is_user_fn_name([$F, $N | Rest]) when Rest =/= [] ->
    lists:all(fun(C) ->
        (C >= $A andalso C =< $Z) orelse
        (C >= $0 andalso C =< $9) orelse
        C =:= $_ orelse
        C =:= $% orelse
        C =:= $& orelse
        C =:= $#
    end, Rest);
is_user_fn_name(_) ->
    false.

strip_var_sigil([]) ->
    [];
strip_var_sigil(Name) ->
    Last = lists:last(Name),
    case Last of
        $$ -> lists:sublist(Name, length(Name) - 1);
        $% -> lists:sublist(Name, length(Name) - 1);
        $& -> lists:sublist(Name, length(Name) - 1);
        $# -> lists:sublist(Name, length(Name) - 1);
        _ -> Name
    end.