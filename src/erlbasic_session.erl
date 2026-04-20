-module(erlbasic_session).

-export([
    new/0,
    initial_output/0,
    phase/1,
    awaiting_input/1,
    awaiting_input_nonblocking/1,
    awaiting_input_getkey/1,
    handle_line/3
]).

new() ->
    #{phase => login_prompt, attempts => 0}.

initial_output() ->
    [erlbasic_shell:login_prompt_marker()].

phase(Session) ->
    maps:get(phase, Session).

awaiting_input(#{phase := session, interpreter := InterpMod, interpreter_state := InterpState}) ->
    InterpMod:awaiting_input(InterpState);
awaiting_input(_Session) ->
    false.

awaiting_input_nonblocking(#{phase := session, interpreter := InterpMod, interpreter_state := InterpState}) ->
    InterpMod:awaiting_input_nonblocking(InterpState);
awaiting_input_nonblocking(_Session) ->
    false.

awaiting_input_getkey(#{phase := session, interpreter := InterpMod, interpreter_state := InterpState}) ->
    InterpMod:awaiting_input_getkey(InterpState);
awaiting_input_getkey(_Session) ->
    false.

handle_line(Line, #{phase := login_prompt, attempts := Attempts} = Session, _ExecFun) ->
    case erlbasic_shell:parse_os_command(Line) of
        {login, hello_prompt} ->
            {Session#{phase => login_wait_ppn}, [erlbasic_shell:user_prompt_message()], #{}};
        {login, {hello, P, N}} ->
            {Session#{phase => {login_wait_password, P, N}}, [erlbasic_shell:password_prompt_message()], #{}};
        {login, {hello, P, N, {password, Pw}}} ->
            handle_login_attempt(P, N, Pw, Session, true);
        not_os_command ->
            {PromptSession, PromptOutput, Control} = enter_login_prompt(Session, Attempts + 1),
            {PromptSession, [erlbasic_shell:please_say_hello_message() | PromptOutput], Control};
        _ ->
            {Session, [erlbasic_shell:bye_message()], #{close => true}}
    end;
handle_line(Line, #{phase := login_wait_ppn, attempts := Attempts} = Session, _ExecFun) ->
    case erlbasic_shell:parse_ppn_only(Line) of
        {ok, P, N} ->
            {Session#{phase => {login_wait_password, P, N}}, [erlbasic_shell:password_prompt_message()], #{}};
        error ->
            {PromptSession, PromptOutput, Control} = enter_login_prompt(Session, Attempts + 1),
            {PromptSession, [erlbasic_shell:invalid_ppn_message() | PromptOutput], Control}
    end;
handle_line(Line, #{phase := {login_wait_password, P, N}} = Session, _ExecFun) ->
    handle_login_attempt(P, N, Line, Session, false);
handle_line(Line, #{phase := session} = Session, ExecFun) ->
    handle_session_line(Line, Session, ExecFun).

handle_login_attempt(P, N, Pw, #{attempts := Attempts} = Session, Inline) ->
    case erlbasic_shell:start_session(P, N, Pw) of
        {ok, SessionInfo} ->
            {session_from_login(Session, SessionInfo), maps:get(welcome, SessionInfo) ++ [maps:get(prompt, SessionInfo)], #{login_result => success, inline_login => Inline}};
        {error, too_many_sessions} ->
            {PromptSession, PromptOutput, Control} = enter_login_prompt(Session, Attempts + 1),
            {PromptSession, [erlbasic_shell:too_many_sessions_message() | PromptOutput], Control#{login_result => too_many_sessions, inline_login => Inline}};
        {error, login_failure} ->
            {PromptSession, PromptOutput, Control} = enter_login_prompt(Session, Attempts + 1),
            {PromptSession, [erlbasic_shell:login_failure_message() | PromptOutput], Control#{login_result => login_failure, delay_ms => 2000, inline_login => Inline}}
    end.

session_from_login(Session, SessionInfo) ->
    Session#{
        phase => session,
        ppn => maps:get(ppn, SessionInfo),
        interpreter => maps:get(interpreter, SessionInfo),
        interpreter_state => maps:get(interpreter_state, SessionInfo)
    }.

handle_session_line(Line, #{ppn := {P, N}} = Session, ExecFun) ->
    case awaiting_input(Session) of
        true ->
            run_interpreter(Line, Session, ExecFun);
        false ->
            case erlbasic_shell:parse_os_command(Line) of
                logout ->
                    erlbasic_shell:unregister_current_session(),
                    {PromptSession, PromptOutput, Control} = enter_login_prompt(clear_session(Session), 0),
                    {PromptSession, [erlbasic_shell:logged_off_message(P, N) | PromptOutput], Control};
                quit ->
                    erlbasic_shell:unregister_current_session(),
                    {clear_session(Session), [erlbasic_shell:goodbye_message()], #{close => true}};
                {login, hello_prompt} ->
                    erlbasic_shell:unregister_current_session(),
                    {(clear_session(Session))#{phase := login_prompt, attempts := 0}, [erlbasic_shell:logged_off_message(P, N), erlbasic_shell:login_prompt_marker()], #{}};
                {login, {hello, NP, NN}} ->
                    erlbasic_shell:unregister_current_session(),
                    {(clear_session(Session))#{phase := {login_wait_password, NP, NN}, attempts := 0}, [erlbasic_shell:logged_off_message(P, N), erlbasic_shell:password_prompt_message()], #{}};
                {login, {hello, NP, NN, {password, Pw}}} ->
                    erlbasic_shell:unregister_current_session(),
                    handle_login_attempt(NP, NN, Pw, clear_session(Session), true, erlbasic_shell:logged_off_message(P, N));
                not_os_command ->
                    run_interpreter(Line, Session, ExecFun)
            end
    end.

handle_login_attempt(P, N, Pw, Session, Inline, Prefix) ->
    case handle_login_attempt(P, N, Pw, Session, Inline) of
        {NextSession, Output, Control} ->
            {NextSession, [Prefix | Output], Control}
    end.

run_interpreter(Line, #{interpreter := InterpMod, interpreter_state := InterpState} = Session, ExecFun) ->
    case ExecFun(InterpMod, InterpState, Line) of
        {ok, NextInterpState, Output} ->
            {Session#{interpreter_state => NextInterpState}, Output ++ [InterpMod:next_prompt(NextInterpState)], #{}};
        {close, Output} ->
            erlbasic_shell:unregister_current_session(),
            {Session, Output, #{close => true}};
        {error, Output} ->
            {Session, Output, #{}}
    end.

clear_session(Session) ->
    maps:without([ppn, interpreter, interpreter_state], Session).

enter_login_prompt(Session, Attempts) when Attempts >= 4 ->
    {Session#{phase => stop, attempts => Attempts}, [], #{close => true}};
enter_login_prompt(Session, Attempts) ->
    {Session#{phase => login_prompt, attempts => Attempts}, [erlbasic_shell:login_prompt_marker()], #{}}.