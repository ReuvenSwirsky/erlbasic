# Storage Backend Plan: Local Disk or S3

Goal: configurable storage for user BASIC program files so development/testing
can run on local disk and deployment can run on S3, selected by config.

The non-secret selector lives in `sys.config`; S3 connection details and
credentials live in a private `.s3.config` secrets file.

---

## Status snapshot

### Done

- [x] Backend behavior exists (`src/erlbasic_storage_backend.erl`)
- [x] Local backend exists (`src/erlbasic_storage_local.erl`)
- [x] `erlbasic_storage` dispatches by `{storage_backend, ...}` and supports
      `local | s3 | ModuleAtom`
- [x] `sys.config` already has `storage_backend`, `storage_local_root`,
      `storage_s3_config_file`, and `homepage_cache_dir` comments/examples
- [x] Private S3 config loader exists (`src/erlbasic_s3_config.erl`) and is
      loaded on app start (`erlbasic_app:start/2`)
- [x] `.s3.config` is ignored, and `s3.config-EXAMPLE` exists
- [x] EUnit tests cover private S3 config loading behavior

### Not done

- [x] End-to-end S3 smoke tests (opt-in via `AWS_SMOKE_TESTS=1`)

---

## Configuration contract (source of truth)

### `sys.config` (non-secret)

Required/optional keys under `erlbasic` app env:

- `{storage_backend, local | s3}`
- `{storage_local_root, "/path"}` (optional; local backend only)
- `{storage_s3_config_file, ".s3.config"}` (optional; default `.s3.config`)
- `{homepage_cache_dir, "/path"}` (optional; always local)

### `.s3.config` (secret file, never committed)

Private file contains S3 connection details used when `storage_backend = s3`:

- `{storage_s3_endpoint, "https://..."}`
- `{storage_s3_bucket, "bucket-name"}`
- `{storage_s3_prefix, "users/"}`
- `{storage_s3_region, "us-east-1"}`
- `{storage_s3_access_key_id, "..."}`
- `{storage_s3_secret_access_key, "..."}`

The checked-in `s3.config-EXAMPLE` shows this exact schema.

---

## Remaining implementation plan

### Phase 1 - S3 backend module

- [x] Add S3 client dependency to `rebar.config`
- [x] Create `src/erlbasic_storage_s3.erl` implementing
      `erlbasic_storage_backend` callbacks
- [x] Resolve config from app env loaded by `erlbasic_s3_config:load/0`
- [x] Implement object key mapping as `Prefix ++ Key`
- [x] Normalize list results to `[{Name, Size, UnixMTime}]`
- [x] Map not-found to `enoent`/`false` consistently with local backend

Acceptance:

- `erlbasic_storage:read_program/write_program/list_programs/delete_program`
  work unchanged with `{storage_backend, s3}`.

### Phase 2 - File channel strategy (`OPEN`/`INPUT #`/`PRINT #`)

Current `erlbasic_filestore` uses `erlbasic_storage_local:key_to_path/1`
directly, which bypasses backend selection.

- [x] Keep local path fast path for `storage_backend = local`
- [x] Add S3 temp-file strategy for channel modes:
- [x] INPUT: download object to temp file before `file:open`
- [x] OUTPUT: write temp file, upload on close
- [x] APPEND: pre-download if object exists, append, upload on close
- [x] RANDOM: pre-download/create temp, random read/write, upload on close
- [x] Track temp metadata in channel entry so close cleanup is reliable

Acceptance:

- Existing BASIC file I/O semantics remain unchanged for local backend.
- S3 backend supports channel operations without modifying BASIC syntax/runtime.

### Phase 3 - Test matrix

- [ ] Unit tests for S3 backend key mapping and error normalization
- [x] Unit tests for filestore temp-file lifecycle and cleanup on failures
- [x] Opt-in integration smoke test against real S3/MinIO/LocalStack,
      guarded by env var (for example `AWS_SMOKE_TESTS=1`)

Acceptance:

- Default CI/test flow passes without cloud credentials.
- Opt-in S3 test validates real object round-trip behavior.

---

## Deployment and dev examples

### Local development/testing

`sys.config`:

```erlang
{storage_backend, local},
```

Optional:

```erlang
{storage_local_root, "/tmp/erlbasic-users"},
```

### Deployment on S3

`sys.config`:

```erlang
{storage_backend, s3},
{storage_s3_config_file, ".s3.config"},
```

`.s3.config` (private):

```erlang
[
  {storage_s3_endpoint, "https://s3.example.internal"},
  {storage_s3_bucket, "erlbasic-private-bucket"},
  {storage_s3_prefix, "users/"},
  {storage_s3_region, "us-east-1"},
  {storage_s3_access_key_id, "REPLACE_ME"},
  {storage_s3_secret_access_key, "REPLACE_ME"}
].
```

---

## Sequence to execute next

1. Add focused unit tests for S3 backend key mapping and error normalization.
