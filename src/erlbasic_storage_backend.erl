-module(erlbasic_storage_backend).

-export_type([list_entry/0]).

-type list_entry() :: {string(), non_neg_integer(), integer()}.

-callback read(Key :: string()) -> {ok, binary()} | {error, term()}.
-callback write(Key :: string(), Bin :: binary()) -> ok | {error, term()}.
-callback list(Prefix :: string()) -> {ok, [list_entry()]} | {error, term()}.
-callback delete(Key :: string()) -> ok | {error, term()}.
-callback key_exists(Key :: string()) -> boolean().