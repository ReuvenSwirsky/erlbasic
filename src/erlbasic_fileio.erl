-module(erlbasic_fileio).

-export([
    open_file/6,
    close_file/2,
    print_file/7,
    write_file/6,
    input_file/6,
    line_input_file/6,
    field_file/5,
    put_record/5,
    get_record/6,
    eof/1,
    lof/1,
    seek/1
]).

-include("erlbasic_state.hrl").
-include_lib("kernel/include/file.hrl").

open_file(Path, Mode, ChannelValue, RecLenValue, Vars, State) ->
    case normalize_channel(ChannelValue) of
        {ok, Channel} ->
            OpenFiles = State#state.open_files,
            case maps:is_key(Channel, OpenFiles) of
                true ->
                    {error, illegal_function_call, Vars};
                false ->
                    case normalize_path(Path) of
                        {ok, FilePath} ->
                            case open_with_mode(FilePath, Mode, RecLenValue) of
                                {ok, Entry} ->
                                    NextFiles = maps:put(Channel, Entry, OpenFiles),
                                    {ok, Vars, State#state{open_files = NextFiles}};
                                {error, Reason} ->
                                    {error, Reason, Vars}
                            end;
                        error ->
                            {error, type_mismatch, Vars}
                    end
            end;
        error ->
            {error, illegal_function_call, Vars}
    end.

close_file(all, State) ->
    maps:foreach(
        fun(_Channel, Entry) ->
            close_entry(Entry)
        end,
        State#state.open_files),
    {ok, State#state{open_files = #{}}};
close_file(ChannelValues, State) when is_list(ChannelValues) ->
    close_file_channels(ChannelValues, State#state.open_files, State);
close_file(_Other, State) ->
    {error, illegal_function_call, State}.

print_file(ChannelValue, Items, EndWithNewline, Vars, Funcs, State, PrintCol) ->
    case get_open_file(ChannelValue, State) of
        {ok, _Channel, Entry} ->
            case allow_write_mode(Entry) of
                false ->
                    {error, illegal_function_call, Vars, State, PrintCol};
                true ->
                    case erlbasic_runtime:render_print_items(Items, Vars, Funcs, PrintCol) of
                        {ok, Vars1, Text, _NextCol} ->
                            Out =
                                case EndWithNewline of
                                    true -> Text ++ "\r\n";
                                    false -> Text
                                end,
                            case io:put_chars(maps:get(io, Entry), Out) of
                                ok ->
                                    {ok, Vars1, State, PrintCol};
                                _ ->
                                    {error, illegal_function_call, Vars1, State, PrintCol}
                            end;
                        {error, Reason, Vars1} ->
                            {error, Reason, Vars1, State, PrintCol}
                    end
            end;
        error ->
            {error, illegal_function_call, Vars, State, PrintCol};
        {error, Reason} ->
            {error, Reason, Vars, State, PrintCol}
    end.

write_file(ChannelValue, Exprs, Vars, Funcs, State, _PrintCol) ->
    case get_open_file(ChannelValue, State) of
        {ok, _Channel, Entry} ->
            case allow_write_mode(Entry) of
                false ->
                    {error, illegal_function_call, Vars, State};
                true ->
                    case eval_write_values(Exprs, Vars, Funcs, []) of
                        {ok, Values, Vars1} ->
                            Line = build_write_line(Values) ++ "\r\n",
                            case io:put_chars(maps:get(io, Entry), Line) of
                                ok -> {ok, Vars1, State};
                                _ -> {error, illegal_function_call, Vars1, State}
                            end;
                        {error, Reason, Vars1} ->
                            {error, Reason, Vars1, State}
                    end
            end;
        error ->
            {error, illegal_function_call, Vars, State};
        {error, Reason} ->
            {error, Reason, Vars, State}
    end.

input_file(ChannelValue, Targets, Vars, Funcs, State, _PrintCol) ->
    case get_open_file(ChannelValue, State) of
        {ok, Channel, Entry} ->
            case maps:get(mode, Entry) of
                input ->
                    Io = maps:get(io, Entry),
                    case io:get_line(Io, "") of
                        eof ->
                            {error, out_of_data, Vars, put_eof(Channel, true, State)};
                        Line ->
                            Parts = split_input_fields(strip_newline(Line)),
                            case assign_input_targets(Targets, Parts, Vars, Funcs) of
                                {ok, Vars1} ->
                                    {ok, Vars1, put_eof(Channel, false, State)};
                                {error, Reason, Vars1} ->
                                    {error, Reason, Vars1, put_eof(Channel, false, State)}
                            end
                    end;
                _ ->
                    {error, illegal_function_call, Vars, State}
            end;
        error ->
            {error, illegal_function_call, Vars, State};
        {error, Reason} ->
            {error, Reason, Vars, State}
    end.

line_input_file(ChannelValue, Target, Vars, Funcs, State, _PrintCol) ->
    case get_open_file(ChannelValue, State) of
        {ok, Channel, Entry} ->
            case maps:get(mode, Entry) of
                input ->
                    Io = maps:get(io, Entry),
                    case io:get_line(Io, "") of
                        eof ->
                            {error, out_of_data, Vars, put_eof(Channel, true, State)};
                        Line ->
                            case erlbasic_eval:assign_target(Target, strip_newline(Line), Vars, Funcs) of
                                {ok, Vars1} ->
                                    {ok, Vars1, put_eof(Channel, false, State)};
                                {error, Reason} ->
                                    {error, Reason, Vars, put_eof(Channel, false, State)}
                            end
                    end;
                _ ->
                    {error, illegal_function_call, Vars, State}
            end;
        error ->
            {error, illegal_function_call, Vars, State};
        {error, Reason} ->
            {error, Reason, Vars, State}
    end.

field_file(ChannelValue, Specs, Vars, Funcs, State) ->
    case get_open_file(ChannelValue, State) of
        {ok, Channel, Entry} ->
            case maps:get(mode, Entry) of
                random ->
                    case eval_field_specs(Specs, Vars, Funcs, []) of
                        {ok, FieldDefs, Vars1} ->
                            RecLen = maps:get(rec_len, Entry),
                            TotalLen = lists:sum([Len || {_Var, Len} <- FieldDefs]),
                            case TotalLen =< RecLen of
                                true ->
                                    Entry1 = maps:put(fields, FieldDefs, Entry),
                                    NextFiles = maps:put(Channel, Entry1, State#state.open_files),
                                    {ok, Vars1, State#state{open_files = NextFiles}};
                                false ->
                                    {error, illegal_function_call, Vars1}
                            end;
                        {error, Reason, Vars1} ->
                            {error, Reason, Vars1}
                    end;
                _ ->
                    {error, illegal_function_call, Vars}
            end;
        error ->
            {error, illegal_function_call, Vars};
        {error, Reason} ->
            {error, Reason, Vars}
    end.

put_record(ChannelValue, RecordValue, Vars, _Funcs, State) ->
    case get_open_file(ChannelValue, State) of
        {ok, _Channel, Entry} ->
            case maps:get(mode, Entry) of
                random ->
                    case normalize_record_no(RecordValue) of
                        {ok, RecNo} ->
                            Fields = maps:get(fields, Entry, []),
                            case Fields of
                                [] ->
                                    {error, illegal_function_call, Vars};
                                _ ->
                                    RecLen = maps:get(rec_len, Entry),
                                    Offset = (RecNo - 1) * RecLen,
                                    Record = build_record_binary(Fields, Vars, RecLen),
                                    case file:pwrite(maps:get(io, Entry), Offset, Record) of
                                        ok -> {ok, Vars, State};
                                        _ -> {error, illegal_function_call, Vars}
                                    end
                            end;
                        error ->
                            {error, illegal_function_call, Vars}
                    end;
                _ ->
                    {error, illegal_function_call, Vars}
            end;
        error ->
            {error, illegal_function_call, Vars};
        {error, Reason} ->
            {error, Reason, Vars}
    end.

get_record(ChannelValue, RecordValue, Vars, Funcs, State, _PrintCol) ->
    case get_open_file(ChannelValue, State) of
        {ok, _Channel, Entry} ->
            case maps:get(mode, Entry) of
                random ->
                    case normalize_record_no(RecordValue) of
                        {ok, RecNo} ->
                            Fields = maps:get(fields, Entry, []),
                            case Fields of
                                [] ->
                                    {error, illegal_function_call, Vars, State};
                                _ ->
                                    RecLen = maps:get(rec_len, Entry),
                                    Offset = (RecNo - 1) * RecLen,
                                    case file:pread(maps:get(io, Entry), Offset, RecLen) of
                                        eof ->
                                            {error, out_of_data, Vars, State};
                                        {ok, Bin0} ->
                                            Bin = pad_record(Bin0, RecLen),
                                            case assign_record_fields(Fields, Bin, Vars, Funcs) of
                                                {ok, Vars1} -> {ok, Vars1, State};
                                                {error, Reason, Vars1} -> {error, Reason, Vars1, State}
                                            end;
                                        _ ->
                                            {error, illegal_function_call, Vars, State}
                                    end
                            end;
                        error ->
                            {error, illegal_function_call, Vars, State}
                    end;
                _ ->
                    {error, illegal_function_call, Vars, State}
            end;
        error ->
            {error, illegal_function_call, Vars, State};
        {error, Reason} ->
            {error, Reason, Vars, State}
    end.

eof(ChannelValue) ->
    case lookup_builtin_channel(ChannelValue) of
        {ok, Entry} ->
            Value =
                case maps:get(mode, Entry) of
                    input ->
                        case maps:get(eof, Entry, false) of
                            true -> 1;
                            false -> 0
                        end;
                    random -> case file_size_from_entry(Entry) of
                        {ok, Size} ->
                            case file:position(maps:get(io, Entry), cur) of
                                {ok, Pos} when Pos >= Size -> 1;
                                {ok, _} -> 0;
                                _ -> 0
                            end;
                        _ -> 0
                    end;
                    _ -> 0
                end,
            {ok, Value};
        error ->
            {error, illegal_function_call}
    end.

lof(ChannelValue) ->
    case lookup_builtin_channel(ChannelValue) of
        {ok, Entry} ->
            case file_size_from_entry(Entry) of
                {ok, Size} -> {ok, Size};
                _ -> {error, illegal_function_call}
            end;
        error ->
            {error, illegal_function_call}
    end.

seek(ChannelValue) ->
    case lookup_builtin_channel(ChannelValue) of
        {ok, Entry} ->
            case file:position(maps:get(io, Entry), cur) of
                {ok, Pos} -> {ok, Pos + 1};
                _ -> {error, illegal_function_call}
            end;
        error ->
            {error, illegal_function_call}
    end.

close_file_channels([], _OpenFiles, State) ->
    {ok, State};
close_file_channels([ChannelValue | Rest], OpenFiles, State) ->
    case normalize_channel(ChannelValue) of
        {ok, Channel} ->
            case maps:find(Channel, OpenFiles) of
                {ok, Entry} ->
                    close_entry(Entry),
                    NextFiles = maps:remove(Channel, OpenFiles),
                    close_file_channels(Rest, NextFiles, State#state{open_files = NextFiles});
                error ->
                    {error, illegal_function_call, State}
            end;
        error ->
            {error, illegal_function_call, State}
    end.

open_with_mode(Path, "INPUT", _RecLenValue) ->
    case file:open(Path, [read]) of
        {ok, Io} -> {ok, #{mode => input, io => Io, path => Path, eof => false}};
        {error, enoent} -> {error, illegal_function_call};
        _ -> {error, illegal_function_call}
    end;
open_with_mode(Path, "OUTPUT", _RecLenValue) ->
    case file:open(Path, [write]) of
        {ok, Io} -> {ok, #{mode => output, io => Io, path => Path}};
        _ -> {error, illegal_function_call}
    end;
open_with_mode(Path, "APPEND", _RecLenValue) ->
    case file:open(Path, [append]) of
        {ok, Io} -> {ok, #{mode => append, io => Io, path => Path}};
        _ -> {error, illegal_function_call}
    end;
open_with_mode(Path, "RANDOM", RecLenValue) ->
    RecLen =
        case normalize_record_len(RecLenValue) of
            {ok, Len} -> Len;
            error -> 128
        end,
    case file:open(Path, [read, write, binary]) of
        {ok, Io} ->
            {ok, #{mode => random, io => Io, path => Path, rec_len => RecLen, fields => []}};
        {error, enoent} ->
            case file:open(Path, [write, binary]) of
                {ok, Io0} ->
                    ok = file:close(Io0),
                    case file:open(Path, [read, write, binary]) of
                        {ok, Io1} -> {ok, #{mode => random, io => Io1, path => Path, rec_len => RecLen, fields => []}};
                        _ -> {error, illegal_function_call}
                    end;
                _ -> {error, illegal_function_call}
            end;
        _ ->
            {error, illegal_function_call}
    end;
open_with_mode(_Path, _Mode, _RecLenValue) ->
    {error, illegal_function_call}.

get_open_file(ChannelValue, State) ->
    case normalize_channel(ChannelValue) of
        {ok, Channel} ->
            case maps:find(Channel, State#state.open_files) of
                {ok, Entry} -> {ok, Channel, Entry};
                error -> error
            end;
        error ->
            {error, illegal_function_call}
    end.

allow_write_mode(Entry) ->
    Mode = maps:get(mode, Entry),
    Mode =:= output orelse Mode =:= append.

close_entry(Entry) ->
    catch file:close(maps:get(io, Entry)),
    ok.

normalize_channel(Value) when is_integer(Value), Value > 0 ->
    {ok, Value};
normalize_channel(Value) when is_float(Value), Value > 0 ->
    {ok, trunc(Value)};
normalize_channel(Value) when is_list(Value) ->
    case string:to_integer(string:trim(Value)) of
        {Int, ""} when Int > 0 -> {ok, Int};
        _ -> error
    end;
normalize_channel(_Value) ->
    error.

normalize_record_no(Value) ->
    case normalize_channel(Value) of
        {ok, N} -> {ok, N};
        error -> error
    end.

normalize_record_len(undefined) ->
    {ok, 128};
normalize_record_len(Value) when is_integer(Value), Value > 0 ->
    {ok, Value};
normalize_record_len(Value) when is_float(Value), Value > 0 ->
    {ok, trunc(Value)};
normalize_record_len(Value) when is_list(Value) ->
    case string:to_integer(string:trim(Value)) of
        {Int, ""} when Int > 0 -> {ok, Int};
        _ -> error
    end;
normalize_record_len(_Value) ->
    error.

normalize_path(Path) when is_list(Path) ->
    case filename:pathtype(Path) of
        absolute ->
            {ok, Path};
        _ ->
            case erlbasic_storage:ensure_user_dir() of
                {ok, UserDir} ->
                    {ok, filename:join(UserDir, Path)};
                {error, _Reason} ->
                    error
            end
    end;
normalize_path(_Other) ->
    error.

strip_newline(Line) ->
    lists:reverse(strip_newline_rev(lists:reverse(Line))).

strip_newline_rev([$\n | Rest]) ->
    strip_newline_rev(Rest);
strip_newline_rev([$\r | Rest]) ->
    strip_newline_rev(Rest);
strip_newline_rev(Rest) ->
    Rest.

split_input_fields(Text) ->
    split_input_fields(Text, [], [], false).

split_input_fields([], CurrentRev, PartsRev, _InString) ->
    lists:reverse([string:trim(lists:reverse(CurrentRev)) | PartsRev]);
split_input_fields([$" | Rest], CurrentRev, PartsRev, InString) ->
    split_input_fields(Rest, [$" | CurrentRev], PartsRev, not InString);
split_input_fields([$, | Rest], CurrentRev, PartsRev, false) ->
    Part = string:trim(lists:reverse(CurrentRev)),
    split_input_fields(Rest, [], [Part | PartsRev], false);
split_input_fields([Ch | Rest], CurrentRev, PartsRev, InString) ->
    split_input_fields(Rest, [Ch | CurrentRev], PartsRev, InString).

assign_input_targets(Targets, Parts, Vars, Funcs) ->
    case length(Targets) =:= length(Parts) of
        true -> assign_input_targets_1(Targets, Parts, Vars, Funcs);
        false -> {error, type_mismatch, Vars}
    end.

assign_input_targets_1([], [], Vars, _Funcs) ->
    {ok, Vars};
assign_input_targets_1([Target | RestTargets], [Part | RestParts], Vars, Funcs) ->
    case convert_input_field(Target, Part, Vars, Funcs) of
        {ok, Value} ->
            case erlbasic_eval:assign_target(Target, Value, Vars, Funcs) of
                {ok, Vars1} -> assign_input_targets_1(RestTargets, RestParts, Vars1, Funcs);
                {error, Reason} -> {error, Reason, Vars}
            end;
        {error, Reason} ->
            {error, Reason, Vars}
    end.

convert_input_field(Target, RawPart, Vars, Funcs) ->
    case erlbasic_eval:target_is_string(Target) of
        true ->
            {ok, unquote_input(RawPart)};
        false ->
            Part = string:trim(RawPart),
            case Part of
                "" -> {ok, 0};
                _ ->
                    case erlbasic_eval:eval_expr_result(Part, Vars, Funcs) of
                        {ok, Value, _} when is_number(Value) -> {ok, Value};
                        _ -> {error, type_mismatch}
                    end
            end
    end.

unquote_input([$" | Rest]) ->
    case lists:reverse(Rest) of
        [$" | MiddleRev] -> lists:reverse(MiddleRev);
        _ -> [$" | Rest]
    end;
unquote_input(Other) ->
    Other.

eval_write_values([], Vars, _Funcs, Acc) ->
    {ok, lists:reverse(Acc), Vars};
eval_write_values([Expr | Rest], Vars, Funcs, Acc) ->
    case erlbasic_eval:eval_expr_result(Expr, Vars, Funcs) of
        {ok, Value, Vars1} -> eval_write_values(Rest, Vars1, Funcs, [Value | Acc]);
        {error, Reason, Vars1} -> {error, Reason, Vars1}
    end.

build_write_line(Values) ->
    Parts = [format_write_value(V) || V <- Values],
    join_with_comma(Parts).

format_write_value(Value) when is_list(Value) ->
    Escaped = string:replace(Value, "\"", "\"\"", all),
    "\"" ++ Escaped ++ "\"";
format_write_value(Value) ->
    erlbasic_eval:format_print_value(Value).

join_with_comma([]) ->
    "";
join_with_comma([Only]) ->
    Only;
join_with_comma([Head | Rest]) ->
    Head ++ "," ++ join_with_comma(Rest).

eval_field_specs([], Vars, _Funcs, Acc) ->
    {ok, lists:reverse(Acc), Vars};
eval_field_specs([{LenExpr, Var} | Rest], Vars, Funcs, Acc) ->
    case erlbasic_eval:eval_expr_result(LenExpr, Vars, Funcs) of
        {ok, LenValue, Vars1} ->
            case normalize_record_len(LenValue) of
                {ok, Len} ->
                    eval_field_specs(Rest, Vars1, Funcs, [{Var, Len} | Acc]);
                error ->
                    {error, illegal_function_call, Vars1}
            end;
        {error, Reason, Vars1} ->
            {error, Reason, Vars1}
    end.

build_record_binary(Fields, Vars, RecLen) ->
    Segments =
        [
            pad_or_truncate(to_basic_string(maps:get(Var, Vars, "")), Len)
            || {Var, Len} <- Fields
        ],
    Raw = iolist_to_binary(Segments),
    pad_record(Raw, RecLen).

assign_record_fields(Fields, Bin, Vars, Funcs) ->
    assign_record_fields(Fields, Bin, 0, Vars, Funcs).

assign_record_fields([], _Bin, _Offset, Vars, _Funcs) ->
    {ok, Vars};
assign_record_fields([{Var, Len} | Rest], Bin, Offset, Vars, Funcs) ->
    <<_:Offset/binary, Segment:Len/binary, _/binary>> = Bin,
    Value = binary_to_list(Segment),
    case erlbasic_eval:assign_target({var_target, Var}, Value, Vars, Funcs) of
        {ok, Vars1} ->
            assign_record_fields(Rest, Bin, Offset + Len, Vars1, Funcs);
        {error, Reason} ->
            {error, Reason, Vars}
    end.

pad_or_truncate(Str, Len) ->
    case length(Str) of
        N when N > Len -> lists:sublist(Str, Len);
        N when N < Len -> Str ++ lists:duplicate(Len - N, $ );
        _ -> Str
    end.

pad_record(Bin, RecLen) when byte_size(Bin) >= RecLen ->
    binary:part(Bin, 0, RecLen);
pad_record(Bin, RecLen) ->
    Pad = list_to_binary(lists:duplicate(RecLen - byte_size(Bin), $ )),
    <<Bin/binary, Pad/binary>>.

to_basic_string(Value) when is_list(Value) ->
    Value;
to_basic_string(Value) when is_integer(Value); is_float(Value) ->
    erlbasic_eval:format_print_value(Value);
to_basic_string(_Value) ->
    "".

put_eof(Channel, Value, State) ->
    case maps:find(Channel, State#state.open_files) of
        {ok, Entry} ->
            Entry1 = maps:put(eof, Value, Entry),
            NextFiles = maps:put(Channel, Entry1, State#state.open_files),
            State#state{open_files = NextFiles};
        error ->
            State
    end.

lookup_builtin_channel(ChannelValue) ->
    case normalize_channel(ChannelValue) of
        {ok, Channel} ->
            OpenFiles =
                case erlang:get(erlbasic_open_files) of
                    Map when is_map(Map) -> Map;
                    _ -> #{}
                end,
            case maps:find(Channel, OpenFiles) of
                {ok, Entry} -> {ok, Entry};
                error -> error
            end;
        error ->
            error
    end.

file_size_from_entry(Entry) ->
    Path = maps:get(path, Entry),
    case file:read_file_info(Path) of
        {ok, Info} -> {ok, Info#file_info.size};
        _ -> {error, illegal_function_call}
    end.
