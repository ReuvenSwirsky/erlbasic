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
         create_account/5,
         authenticate/3,
         list_accounts/0,
         find_by_username/1,
         delete_account/2,
         change_password/3,
         is_privileged/2,
         parse_credentials/1]).

-record(account, {
    ppn,       %% {Project :: 0..254, Programmer :: 0..254}  - primary key
    salt,      %% binary() - random 16-byte PBKDF2 salt
    hash,      %% binary() - 32-byte PBKDF2-SHA256 derived key
    name,      %% binary() - display name
    username   %% binary() - optional login/display username (max 16 chars)
}).

-define(MAX_USERNAME_LEN, 16).

-define(PBKDF2_ITERS, 100000).
-define(PBKDF2_LEN,   32).       %% 256-bit key
-define(TABLE,        account).

%% ===================================================================
%% Public API
%% ===================================================================

%% @doc Open (or create) the DETS accounts table and load credentials from
%% the .credentials file.  See load_credentials/0 for the full semantics.
init() ->
    DataDir = data_dir(),
    ok = filelib:ensure_dir(filename:join([DataDir, "x"])),
    File = filename:join(DataDir, "accounts.dets"),
    {ok, _} = dets:open_file(?TABLE, [{file, File}, {type, set}, {keypos, 2}]),
    ok = migrate_accounts_schema(),
    load_credentials().

%% @doc Create (or overwrite) an account.  Password is uppercased before hashing.
create_account(Project, Programmer, Password, Name) ->
    create_account(Project, Programmer, Password, Name, <<>>).

%% @doc Create (or overwrite) an account with username metadata.
create_account(Project, Programmer, Password, Name, Username) ->
    UsernameBin = normalize_username(Username),
    case validate_username_for_create(Project, Programmer, UsernameBin) of
        ok ->
            {Salt, Hash} = hash_password(upcase_bin(Password)),
            Rec = #account{
                ppn  = {Project, Programmer},
                salt = Salt,
                hash = Hash,
                name = to_bin(Name),
                username = UsernameBin
            },
            dets:insert(?TABLE, Rec);
        {error, _} = Err ->
            Err
    end.

%% @doc Authenticate a user.  Password is uppercased before comparison.
%%      Returns {ok, Name} or {error, bad_credentials}.
authenticate(Project, Programmer, Password) ->
    PwBin = upcase_bin(Password),
    case dets:lookup(?TABLE, {Project, Programmer}) of
        [RawRec] ->
            #account{salt = Salt, hash = Hash, name = Name} = normalize_account(RawRec),
            case verify_password(PwBin, Salt, Hash) of
                true  -> {ok, Name};
                false -> {error, bad_credentials}
            end;
        [] ->
            {error, bad_credentials};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Return a sorted list of {PPN, Name, Username} tuples.
list_accounts() ->
    Result = dets:foldl(
        fun(RawRec, Acc) ->
            #account{ppn = PPN, name = Name, username = Username} = normalize_account(RawRec),
            [{PPN, Name, Username} | Acc]
        end,
        [],
        ?TABLE),
    case Result of
        {error, Reason} -> {error, Reason};
        List            -> {ok, lists:sort(List)}
    end.

%% @doc Find an account by username (case-insensitive).
%%      Returns {ok, {Project, Programmer, Name, Username}} or {error, not_found}.
find_by_username(Username) ->
    Norm = username_key(normalize_username(Username)),
    case Norm of
        <<>> ->
            {error, not_found};
        _ ->
            Result = dets:foldl(
                fun(RawRec, Acc) ->
                    case Acc of
                        {ok, _} ->
                            Acc;
                        not_found ->
                            #account{ppn = {P, N}, name = Name, username = StoredUsername} = normalize_account(RawRec),
                            case username_key(StoredUsername) of
                                Norm -> {ok, {P, N, Name, StoredUsername}};
                                _ -> not_found
                            end
                    end
                end,
                not_found,
                ?TABLE),
            case Result of
                {ok, _} = Ok -> Ok;
                not_found -> {error, not_found};
                {error, Reason} -> {error, Reason}
            end
    end.

%% @doc Delete the account identified by [Project, Programmer].
delete_account(Project, Programmer) ->
    dets:delete(?TABLE, {Project, Programmer}).

%% @doc Replace the password for an existing account.
change_password(Project, Programmer, NewPassword) ->
    case dets:lookup(?TABLE, {Project, Programmer}) of
        [RawRec] ->
            {Salt, Hash} = hash_password(upcase_bin(NewPassword)),
            Rec = normalize_account(RawRec),
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

%% @doc Read the .credentials file and upsert accounts from it.
%%
%%   File missing        → print error to stderr and halt the VM (exit code 1).
%%   File empty/comments → call seed_default_accounts/0.
%%   File has entries    → upsert each entry; accounts not listed are left intact.
%%
%% File format (one entry per line):
%%   [Project,Programmer] PASSWORD[, Display Name[, extra fields...]]
%%
%% Lines starting with '#' or '%' are comments; blank lines are ignored.
%% Passwords are uppercased before hashing (RSTS/E convention).
load_credentials() ->
    Path = credentials_path(),
    case file:read_file(Path) of
        {error, enoent} ->
            io:format(standard_error,
                "~n** ERROR: Credentials file not found: ~s~n"
                "** Create a .credentials file with entries like:~n"
                "**   [0,1] SYSTEM~n"
                "**   [1,1] SYSTEM, System Manager~n~n", [Path]),
            erlang:halt(1);
        {ok, Bin} ->
            Entries = parse_credentials(binary_to_list(Bin)),
            case Entries of
                [] ->
                    seed_default_accounts();
                _ ->
                    lists:foreach(fun({P, N, Pw, Name}) ->
                        ok = create_account(P, N, Pw, Name)
                    end, Entries)
            end
    end.

credentials_path() ->
    case application:get_env(erlbasic, credentials_file) of
        {ok, P}   -> P;
        undefined -> ".credentials"
    end.

%% Parse all valid account entries from credentials file text.
%% Returns [{Project, Programmer, Password, Name}].
parse_credentials(Text) ->
    Lines = string:split(Text, "\n", all),
    lists:filtermap(fun parse_credential_line/1, Lines).

%% Expected format: [P,N] PASSWORD[, Name[, extra...]]
parse_credential_line(Line) ->
    Trimmed = string:trim(Line),
    case Trimmed of
        ""       -> false;
        [$# | _] -> false;
        [$% | _] -> false;
        _ ->
            case re:run(Trimmed, "^\\[(\\d+),(\\d+)\\]\\s+([^\\s,]+)(.*)",
                        [{capture, [1, 2, 3, 4], list}]) of
                {match, [PStr, NStr, Pw, Rest]} ->
                    P    = list_to_integer(PStr),
                    N    = list_to_integer(NStr),
                    Name = parse_name_from_rest(Rest, P, N),
                    {true, {P, N, Pw, Name}};
                nomatch ->
                    io:format(standard_error,
                        "** WARNING: ignoring malformed .credentials line: ~s~n",
                        [Trimmed]),
                    false
            end
    end.

%% Extract display name from the optional tail after the password token.
%% Rest is everything after the password on the line (may be empty or ", Name, ...").
parse_name_from_rest(Rest, P, N) ->
    case string:trim(Rest) of
        [$, | AfterComma] ->
            %% Strip the leading comma then take the first comma-delimited field
            AllFields = string:trim(AfterComma),
            FirstField = hd(string:split(AllFields, ",")),
            case string:trim(FirstField) of
                "" -> lists:flatten(io_lib:format("Account [~w,~w]", [P, N]));
                Name -> Name
            end;
        "" ->
            lists:flatten(io_lib:format("Account [~w,~w]", [P, N]));
        Other ->
            %% No comma delimiter — treat the whole tail as the name
            string:trim(Other)
    end.

seed_default_accounts() ->
    %% [0,1] - system account  |  [1,1] - first admin
    ok = create_account(0, 1, <<"SYSTEM">>, <<"System Account">>, <<"">>),
    ok = create_account(1, 1, <<"SYSTEM">>, <<"System Manager">>, <<"">>).

migrate_accounts_schema() ->
    Result = dets:foldl(
        fun(RawRec, Count) ->
            case RawRec of
                #account{} ->
                    Count;
                {account, PPN, Salt, Hash, Name} ->
                    NewRec = #account{ppn = PPN, salt = Salt, hash = Hash, name = Name, username = <<>>},
                    ok = dets:insert(?TABLE, NewRec),
                    Count + 1;
                _ ->
                    Count
            end
        end,
        0,
        ?TABLE),
    case Result of
        {error, Reason} -> {error, Reason};
        _ -> ok
    end.

normalize_account(#account{} = Rec) ->
    Rec;
normalize_account({account, PPN, Salt, Hash, Name}) ->
    #account{ppn = PPN, salt = Salt, hash = Hash, name = Name, username = <<>>}.

normalize_username(Username) ->
    UsernameBin = to_bin(Username),
    Trimmed = list_to_binary(string:trim(binary_to_list(UsernameBin))),
    case byte_size(Trimmed) =< ?MAX_USERNAME_LEN of
        true -> Trimmed;
        false -> binary:part(Trimmed, 0, ?MAX_USERNAME_LEN)
    end.

validate_username_for_create(_Project, _Programmer, <<>>) ->
    ok;
validate_username_for_create(Project, Programmer, UsernameBin) ->
    case is_reserved_username(UsernameBin) of
        true ->
            {error, reserved_username};
        false ->
            case find_by_username(UsernameBin) of
                {ok, {Project, Programmer, _Name, _Stored}} -> ok;
                {ok, _Other} -> {error, username_taken};
                {error, not_found} -> ok;
                {error, Reason} -> {error, Reason}
            end
    end.

username_key(Bin) when is_binary(Bin) ->
    list_to_binary(string:to_lower(binary_to_list(Bin))).

is_reserved_username(UsernameBin) ->
    Key = username_key(UsernameBin),
    case Key of
        <<>> -> false;
        _ ->
            Tokens = [
                <<"admin">>, <<"administrator">>, <<"sysadmin">>, <<"system">>,
                <<"sysop">>, <<"operator">>, <<"root">>, <<"superuser">>,
                <<"supervisor">>, <<"owner">>, <<"service">>
            ],
            lists:any(fun(Token) -> binary:match(Key, Token) =/= nomatch end, Tokens)
    end.

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