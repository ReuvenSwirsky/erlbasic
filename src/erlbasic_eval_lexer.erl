-module(erlbasic_eval_lexer).

-export([tokenize_expr/1]).

tokenize_expr(Text) ->
    case erlbasic_eval_lexer_leex:string(Text) of
        {ok, Tokens, _EndLine} ->
            {ok, Tokens};
        {error, _ErrorInfo, _ErrorLine} ->
            error
    end.
