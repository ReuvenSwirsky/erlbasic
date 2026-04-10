-module(erlbasic_graphics).

-export([execute_stmt/2]).

-include("erlbasic_state.hrl").

execute_stmt({cls}, State) ->
    {State, erlbasic_runtime:cls_output()};
execute_stmt({hgr}, State) ->
    case erlang:get(erlbasic_conn_type) of
        websocket ->
            {State#state{graphics_mode = hgr, graphics_pen = undefined, sprites = #{}, sprite_active_collisions = []},
             erlbasic_runtime:hgr_output() ++ ["\x02GFX:SPRCLR"]};
        _ ->
            {State, [erlbasic_eval:format_runtime_error(graphics_not_supported_on_tty)]}
    end;
execute_stmt({hgr2}, State) ->
    case erlang:get(erlbasic_conn_type) of
        websocket ->
            {State#state{graphics_mode = hgr2, graphics_pen = undefined, sprites = #{}, sprite_active_collisions = []},
             erlbasic_runtime:hgr2_output() ++ ["\x02GFX:SPRCLR"]};
        _ ->
            {State, [erlbasic_eval:format_runtime_error(graphics_not_supported_on_tty)]}
    end;
execute_stmt({text}, State) ->
    case erlang:get(erlbasic_conn_type) of
        websocket ->
            {State#state{graphics_mode = false, graphics_pen = undefined, sprites = #{}, sprite_active_collisions = []},
             erlbasic_runtime:text_output() ++ ["\x02GFX:SPRCLR"]};
        _ ->
            {State, [erlbasic_eval:format_runtime_error(graphics_not_supported_on_tty)]}
    end;
execute_stmt({pset, XExpr, YExpr, ColorExpr}, State) ->
    case State#state.graphics_mode of
        false ->
            {State, [erlbasic_eval:format_runtime_error(no_graphics_mode)]};
        _ ->
            case erlbasic_runtime:eval_pset(XExpr, YExpr, ColorExpr, State#state.vars, State#state.funcs) of
                {ok, Vars1, Output} ->
                    {State#state{vars = Vars1}, Output};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end
    end;
execute_stmt({line, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr}, State) ->
    case State#state.graphics_mode of
        false ->
            {State, [erlbasic_eval:format_runtime_error(no_graphics_mode)]};
        _ ->
            case erlbasic_runtime:eval_line(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, State#state.vars, State#state.funcs) of
                {ok, Vars1, Output, X2, Y2} ->
                    {State#state{vars = Vars1, graphics_pen = {X2, Y2}}, Output};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end
    end;
execute_stmt({lineto, XExpr, YExpr, ColorExpr}, State) ->
    case State#state.graphics_mode of
        false ->
            {State, [erlbasic_eval:format_runtime_error(no_graphics_mode)]};
        _ ->
            case State#state.graphics_pen of
                {X1, Y1} ->
                    case erlbasic_runtime:eval_lineto(XExpr, YExpr, ColorExpr, X1, Y1, State#state.vars, State#state.funcs) of
                        {ok, Vars1, Output, X2, Y2} ->
                            {State#state{vars = Vars1, graphics_pen = {X2, Y2}}, Output};
                        {error, Reason, Vars1} ->
                            {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
                    end;
                undefined ->
                    {State, [erlbasic_eval:format_runtime_error(no_previous_line)]}
            end
    end;
execute_stmt({rect, X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr}, State) ->
    case State#state.graphics_mode of
        false ->
            {State, [erlbasic_eval:format_runtime_error(no_graphics_mode)]};
        _ ->
            case erlbasic_runtime:eval_rect(X1Expr, Y1Expr, X2Expr, Y2Expr, ColorExpr, State#state.vars, State#state.funcs) of
                {ok, Vars1, Output} ->
                    {State#state{vars = Vars1}, Output};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end
    end;
execute_stmt({circle, XExpr, YExpr, RadiusExpr, ColorExpr}, State) ->
    case State#state.graphics_mode of
        false ->
            {State, [erlbasic_eval:format_runtime_error(no_graphics_mode)]};
        _ ->
            case erlbasic_runtime:eval_circle(XExpr, YExpr, RadiusExpr, ColorExpr, State#state.vars, State#state.funcs) of
                {ok, Vars1, Output} ->
                    {State#state{vars = Vars1}, Output};
                {error, Reason, Vars1} ->
                    {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
            end
    end;
execute_stmt({locate, RowExpr, ColExpr}, State) ->
    case erlbasic_runtime:eval_locate(RowExpr, ColExpr, State#state.vars, State#state.funcs) of
        {ok, Vars1, Output} ->
            {State#state{vars = Vars1}, Output};
        {error, Reason, Vars1} ->
            {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
    end;
execute_stmt({color, FgExpr, BgExpr}, State) ->
    case erlbasic_runtime:eval_color(FgExpr, BgExpr, State#state.vars, State#state.funcs) of
        {ok, Vars1, Output} ->
            {State#state{vars = Vars1}, Output};
        {error, Reason, Vars1} ->
            {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
    end;
execute_stmt({sound, VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr}, State) ->
    case erlbasic_runtime:eval_sound(VoiceExpr, PitchExpr, DistortionExpr, VolumeExpr, State#state.vars, State#state.funcs) of
        {ok, Vars1, Output} ->
            {State#state{vars = Vars1}, Output};
        {error, Reason, Vars1} ->
            {State#state{vars = Vars1}, [erlbasic_eval:format_runtime_error(Reason)]}
    end.
