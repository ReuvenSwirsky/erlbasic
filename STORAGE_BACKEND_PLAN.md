# Storage Backend Plan: Local vs S3

Add a pluggable storage backend so either local disk or AWS S3 can be used
for user BASIC program directories and cached asset storage, controlled by a
single `sys.config` setting.

---

## Affected areas

| Area | Module | Current impl |
|---|---|---|
| User BASIC programs | `erlbasic_storage.erl` | Local disk `~/ErlUsers/<P_N>/` |
| BASIC file I/O channels (OPEN/PRINT#/INPUT#) | `erlbasic_filestore.erl` | Local disk via `open_local/*` |
| Homepage render cache | `erlbasic_homepage_handler.erl` | `.home_cache` binary file in user dir |

---

## Step 1 — Behavior module: `erlbasic_storage_backend.erl`

- [ ] Create `src/erlbasic_storage_backend.erl` defining a behavior
- [ ] Callback `read(Key :: string()) -> {ok, binary()} | {error, term()}`
- [ ] Callback `write(Key :: string(), Bin :: binary()) -> ok | {error, term()}`
- [ ] Callback `list(Prefix :: string()) -> {ok, [{Name, Size, MTime}]} | {error, term()}`
- [ ] Callback `delete(Key :: string()) -> ok | {error, term()}`
- [ ] Callback `key_exists(Key :: string()) -> boolean()`

> `Key` is always a `/`-separated path relative to the storage root,
> e.g. `"1_2/GAME.BAS"` or `"1_2/.home_cache"`.

---

## Step 2 — Local backend: `erlbasic_storage_local.erl`

Extract existing file ops from `erlbasic_storage.erl` into a dedicated module implementing the behavior above. No behavior change — purely a refactor.

- [ ] `read/1` → `file:read_file(Root ++ Key)`
- [ ] `write/2` → `filelib:ensure_dir` + `file:write_file/2`
- [ ] `list/1` → existing `list_files_with_info` logic
- [ ] `delete/1` → `file:delete/1`
- [ ] `key_exists/1` → `filelib:is_regular/1`
- [ ] Root path read from `application:get_env(erlbasic, storage_local_root)`, falling back to `~/ErlUsers/`

---

## Step 3 — S3 backend: `erlbasic_storage_s3.erl`

- [ ] Add `erlcloud` to `rebar.config` as a dependency
- [ ] Create `src/erlbasic_storage_s3.erl` implementing the behavior
- [ ] `read/1` → `erlcloud_s3:get_object(Bucket, Prefix ++ Key)` → body binary
- [ ] `write/2` → `erlcloud_s3:put_object(Bucket, Prefix ++ Key, Bin)`
- [ ] `list/1` → `erlcloud_s3:list_objects/2` with `{prefix, ...}`, parse result into `[{Name, Size, MTime}]`
- [ ] `delete/1` → `erlcloud_s3:delete_object/2`
- [ ] `key_exists/1` → `erlcloud_s3:get_object_metadata`, treat 404 as `false`
- [ ] Read bucket, prefix, region from `application:get_env(erlbasic, storage_s3_*)`
- [ ] Support standard AWS env vars (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`) for credentials / IAM instance role

---

## Step 4 — Dispatch layer in `erlbasic_storage.erl`

- [ ] Add private `backend/0` helper:
  ```erlang
  backend() ->
      case application:get_env(erlbasic, storage_backend, local) of
          local -> erlbasic_storage_local;
          s3    -> erlbasic_storage_s3
      end.
  ```
- [ ] Replace direct `file:read_file/write_file/list_dir/delete` calls in public API with `backend():read(Key)`, etc.
- [ ] Quota accounting remains in `erlbasic_storage.erl` (sizes come from `list/1` result)

---

## Step 5 — BASIC file I/O channels: `erlbasic_filestore.erl`

S3 is object storage with no file handle, so use a temp-file round-trip strategy. `erlbasic_fileio.erl` is **not** changed — it only ever sees an `io` device.

- [ ] **INPUT mode**: download object to local temp file on `open/3`; delete temp on `close`
- [ ] **OUTPUT mode**: write to local temp file; upload to S3 on `close`, then delete temp
- [ ] **APPEND mode**: download existing object to temp (if it exists), open in append mode; upload and delete on `close`
- [ ] **RANDOM mode**: download to temp on `open`; upload and delete on `close` (temp file preserves seek semantics)
- [ ] Store temp file path in the channel entry map so `close_entry` can clean up

---

## Step 6 — Homepage render cache: `erlbasic_homepage_handler.erl`

The `.home_cache` blob is derived output, not authoritative data. Keep it **always local** to avoid S3 latency on every page request.

- [ ] Read cache dir from `application:get_env(erlbasic, homepage_cache_dir)`, defaulting to system temp dir
- [ ] Key cache files as `<cache_dir>/<P>_<N>/.home_cache`
- [ ] Do **not** route cache reads/writes through the storage backend
- [ ] No change to TTL / `detect_dynamic` logic

---

## Step 7 — Configuration

- [ ] Add new keys to `sys.config` (commented-out examples):
  ```erlang
  %% Storage backend: 'local' (default) or 's3'
  {storage_backend, local},

  %% Local backend root (overrides ~/ErlUsers/)
  %% {storage_local_root, "/data/erlbasic/users"},

  %% S3 backend (only used when storage_backend = s3)
  %% {storage_s3_bucket, "my-erlbasic-bucket"},
  %% {storage_s3_prefix, "users/"},
  %% {storage_s3_region, "us-east-1"},

  %% Homepage cache directory (always local, defaults to os:get_env("TMPDIR"))
  %% {homepage_cache_dir, "/var/cache/erlbasic"},
  ```
- [ ] Update `credentials-EXAMPLE` with the corresponding AWS credential env vars

---

## Step 8 — Test coverage

- [ ] Create `src/erlbasic_storage_mem.erl` — ETS-backed in-memory backend (test-only) implementing the behavior
- [ ] Update existing eunit tests in `eunit_tests/erlbasic_eunit_tests.erl` to inject the mem backend instead of hitting the filesystem
- [ ] Add opt-in S3 smoke test (guard with `AWS_SMOKE_TESTS=1` env var check) that exercises the S3 backend against a real or LocalStack bucket

---

## Implementation order

1. Step 1 — behavior module
2. Steps 2 + 4 — local refactor + dispatch (smoke tests stay green throughout)
3. Step 7 — update `sys.config` and `credentials-EXAMPLE`
4. Step 3 — S3 backend + `erlcloud` dep
5. Step 5 — filestore temp-file strategy
6. Step 6 — cache dir config
7. Step 8 — test coverage
