%% @doc RSTS/E-style user account management backed by DETS.
%%
%% Accounts are identified by a PPN (Project-Programmer Number) pair,
%% e.g. {1, 1} = [1,1] in RSTS notation.
%%
%% Privilege rules (mirrors RSTS/E):
%%   Project 0 - system accounts ([0,1] is the root-equivalent)
%%   Project 1 - privileged accounts (all are admins)
%%   Project 2-254 - ordinary user accounts
%%
%% Passwords are uppercased before hashing (RSTS/E convention) and stored
%% with PBKDF2-SHA256 (100 000 iterations / 32-byte key).
-module(erlbasic_accounts).

-export([init/0,
         create_account/4,
         authenticate/3,
         list_accounts/0,
         delete_account/2,
         change_password/3,
         is_privileged/2]).

-record(account, {
    ppn,    %% {Project :: 0..254, Programmer :: 0..254}  - primary key
    salt,   %% binary() - random 16-byte PBKDF2 salt
    hash,   %% binary() - 32-byte PBKDF2-SHA256 derived key
    name    %% binary() - display name
}).

-define(PBKDF2_ITERS, 100000).
-define(PBKDF2_LEN,   32).       %% 256-bit key
-define(TABLE,        account).

%% ===================================================================
%% Public API
%% ===================================================================

%% @doc Open (or create) the DETS accounts table and seed defaults.
init() ->
    DataDir = data_dir(),
    ok = filelib:ensure_dir(filename:join([DataDir, "x"])),
    File = filename:join(DataDir, "accounts.dets"),
    {ok, _} = dets:open_file(?TABLE, [{file, File}, {type, set}, {keypos, 2}]),
    case dets:info(?TABLE, size) of
        0 -> seed_default_accounts();
        _ -> ok
    end.

%% @doc Create (or overwrite) an account.  Password is uppercased before hashing.
create_account(Project, Programmer, Password, Name) ->
    {Salt, Hash} = hash_password(upcase_bin(Password)),
    Rec = #account{
        ppn  = {Project, Programmer},
        salt = Salt,
        hash = Hash,
        name = to_bin(Name)
    },
    dets:insert(?TABLE, Rec).

%% @doc Authenticate a user.  Password is uppercased before comparison.
%%      Returns {ok, Name} or {error, bad_credentials}.
authenticate(Project, Programmer, Password) ->
    PwBin = upcase_bin(Password),
    case dets:lookup(?TABLE, {Project, Programmer}) of
        [#account{salt = Salt, hash = Hash, name = Name}] ->
            case verify_password(PwBin, Salt, Hash) of
                true  -> {ok, Name};
                false -> {error, bad_credentials}
            end;
        [] ->
            {error, bad_credentials};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Return a sorted list of {PPN, Name} tuples.
list_accounts() ->
    Result = dets:foldl(
        fun(#account{ppn = PPN, name = Name}, Acc) -> [{PPN, Name} | Acc] end,
        [],
        ?TABLE),
    case Result of
        {error, Reason} -> {error, Reason};
        List            -> {ok, lists:sort(List)}
    end.

%% @doc Delete the account identified by [Project, Programmer].
delete_account(Project, Programmer) ->
    dets:delete(?TABLE, {Project, Programmer}).

%% @doc Replace the password for an existing account.
change_password(Project, Programmer, NewPassword) ->
    case dets:lookup(?TABLE, {Project, Programmer}) of
        [Rec] ->
            {Salt, Hash} = hash_password(upcase_bin(NewPassword)),
            dets:insert(?TABLE, Rec#account{salt = Salt, hash = Hash});
        [] ->
            {error, not_found};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc True when the account has system-level privileges (project 0 or 1).
is_privileged(Project, _Programmer) ->
    Project =:= 0 orelse Project =:= 1.

%% ===================================================================
%% Internal helpers
%% ===================================================================

data_dir() ->
    case application:get_env(erlbasic, accounts_dir) of
        {ok, D}   -> D;
        undefined -> filename:join([code:priv_dir(erlbasic), "accounts"])
    end.

seed_default_accounts() ->
    %% [0,1] - system account  |  [1,1] - first admin
    ok = create_account(0, 1, <<"SYSTEM">>, <<"System Account">>),
    ok = create_account(1, 1, <<"SYSTEM">>, <<"System Manager">>).

hash_password(PwBin) ->
    Salt = crypto:strong_rand_bytes(16),
    Hash = crypto:pbkdf2_hmac(sha256, PwBin, Salt, ?PBKDF2_ITERS, ?PBKDF2_LEN),
    {Salt, Hash}.

%% Constant-time comparison - prevents timing-based password oracle attacks.
verify_password(PwBin, Salt, StoredHash) ->
    Hash = crypto:pbkdf2_hmac(sha256, PwBin, Salt, ?PBKDF2_ITERS, ?PBKDF2_LEN),
    byte_size(Hash) =:= byte_size(StoredHash) andalso
        0 =:= lists:foldl(
            fun({A, B}, Acc) -> Acc bor (A bxor B) end,
            0,
            lists:zip(binary_to_list(Hash), binary_to_list(StoredHash))).

upcase_bin(X) when is_binary(X) -> list_to_binary(string:to_upper(binary_to_list(X)));
upcase_bin(X) when is_list(X)   -> list_to_binary(string:to_upper(X)).

to_bin(X) when is_binary(X) -> X;
to_bin(X) when is_list(X)   -> list_to_binary(X).