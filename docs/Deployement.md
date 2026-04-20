# Deployment Plan

This document outlines the recommended deployment shape for ErlBASIC, starting with a local Linux VM rehearsal and then moving to a public Linux host such as Hetzner.

The immediate goal is not clustered or multi-node deployment. The target is a single Linux VM running one ErlBASIC node, with production-like process management, reverse proxying, TLS, logging, and persistent storage.

## Goals

- Rehearse deployment on a Linux VM before using a public host.
- Match the final server shape as closely as practical.
- Run ErlBASIC as a managed Linux service rather than from an interactive shell.
- Put nginx in front of ErlBASIC for HTTP/HTTPS and WebSocket proxying.
- Keep deployment-specific settings in `.sys.override.config`.
- Enable bounded rotating file logs for post-deployment debugging.
- Preserve user data across restarts.

## Recommended Deployment Shape

The recommended production-style layout is:

- Ubuntu Linux VM
- Dedicated `erlbasic` service user
- ErlBASIC built with `rebar3 release`
- ErlBASIC listening on internal or high ports
- nginx listening on ports `80` and `443`
- TLS terminated by nginx
- Certbot handling certificate issuance and renewal
- Application configuration stored in `.sys.override.config`
- Rotating application logs enabled through the ErlBASIC app env

This keeps the public edge simple and aligns with the existing HTTPS and Certbot documentation while avoiding direct exposure of the Erlang node on privileged ports.

## Why Start With a Linux VM

A Linux VM is the best local rehearsal because it exercises:

- Linux package installation
- filesystem layout and permissions
- systemd service management
- nginx reverse proxy behavior
- restart behavior after reboot
- log file paths and rotation
- production-style config separation

WSL2 is useful for an earlier Linux compatibility check, but a real Linux VM is better for validating service startup, reverse proxying, and operational behavior.

## Scope for the First Deployment Rehearsal

The first Linux VM rehearsal should prove all of the following:

1. ErlBASIC builds on Linux.
2. ErlBASIC starts cleanly from a release build.
3. nginx can proxy HTTP and WebSocket traffic to ErlBASIC.
4. TCP BASIC access still works on the configured port.
5. User accounts and saved programs persist across restart.
6. Rotating file logs are created and bounded correctly.
7. The service comes back after a reboot.

The first rehearsal does not need to prove clustered deployment, public DNS, or final Let's Encrypt issuance.

## Local VM Plan

Use an Ubuntu VM that is as close as possible to the eventual Hetzner image. For example, Ubuntu 24.04 LTS.

Recommended VM resources for rehearsal:

- 2 vCPU
- 4 GB RAM
- 20 GB disk

Install these packages:

```bash
sudo apt update
sudo apt install -y git build-essential openssl nginx certbot curl
```

Install Erlang/OTP and `rebar3` using your preferred source, but keep the version aligned with the version used during development.

## Application Layout

Use a layout similar to this on Linux:

```text
/opt/erlbasic/
  repo-or-release-files
  log/
  priv/
  .sys.override.config
```

Run the application under a dedicated service account:

```bash
sudo useradd --system --create-home --home-dir /opt/erlbasic erlbasic
```

Adjust ownership so the service account can read the application files and write any required runtime directories such as logs and local storage roots.

## Build Strategy

For deployment rehearsal, prefer a release build over `rebar3 shell`.

Build with:

```bash
rebar3 release
```

That is a better production match than the Windows-oriented development flow in `run.ps1`, which currently starts an interactive shell.

## Configuration Strategy

Keep deployment-specific values in `.sys.override.config`, which is already supported by the application at startup.

Typical deployment overrides will include:

- `http_port`
- `enable_https`
- `https_port` if ErlBASIC terminates TLS directly
- `storage_backend`
- `storage_s3_config_file` if using S3
- local storage root settings if using filesystem storage
- `log_file_enabled`
- `log_file_path`
- log rotation settings

Example starting point for a VM behind nginx:

```erlang
[
    {erlbasic, [
        {http_port, 8081},
        {enable_https, false},
        {log_file_enabled, true},
        {log_file_path, "log/erlbasic.log"},
        {log_file_level, notice},
        {log_file_max_no_bytes, 10485760},
        {log_file_max_no_files, 5},
        {log_file_compress_on_rotate, true}
    ]}
].
```

## Reverse Proxy Plan

For the Linux VM rehearsal and likely for Hetzner production, use nginx in front of ErlBASIC.

Benefits:

- standard handling for ports `80` and `443`
- easier TLS management
- clearer separation between application and public edge
- easier future hardening

nginx should proxy:

- normal HTTP requests to ErlBASIC's HTTP listener
- WebSocket upgrade requests to the same backend

The exact nginx config can be added later as checked-in deployment artifacts.

## TLS Plan

For the local Linux VM rehearsal:

- use HTTP only at first, or
- use a self-signed certificate at the nginx layer

For public deployment on Hetzner:

- use Certbot and Let's Encrypt
- terminate TLS at nginx
- keep ErlBASIC on an internal or high port

The detailed certificate workflow is already documented in:

- `CERTBOT_DEPLOYMENT.md`
- `HTTPS_QUICKSTART.md`

This document is the deployment plan; those documents remain the certificate-specific reference.

## Storage Decision

Choose one of these early and test the same mode in the Linux VM that you intend to use in production.

### Option 1: Filesystem Storage

Use local disk if:

- a single node is acceptable
- VM-level backup is acceptable
- you want the simplest initial deployment

Requirements:

- persistent directory owned by the service account
- backup plan
- restore test

### Option 2: S3 Storage

Use S3 if:

- you want storage independent of the VM lifecycle
- you want easier backup and migration later

Requirements:

- private S3 config file
- bucket and credentials configured correctly
- rehearsal in the VM using the same S3 path you plan to use later

Do not test only filesystem mode locally and assume S3 deployment will behave the same.

## Logging Plan

Enable the rotating file logger in the VM rehearsal.

This should verify:

- the log directory exists and is writable
- logs contain startup and crash information
- log rotation happens at the configured size
- rotated logs remain bounded

The current application logger supports bounded rotating logs via `.sys.override.config`.

## Service Management Plan

The deployment target should run ErlBASIC under `systemd`.

The service should:

- start automatically at boot
- restart on failure
- run as the dedicated `erlbasic` user
- use the deployment config in the application directory

The repo does not yet include a checked-in Linux service unit. Adding one is a natural next step after this planning document.

## Networking Plan

For the local Linux VM rehearsal:

- expose nginx on a host-only, NAT, or LAN-reachable interface
- keep direct ErlBASIC service ports non-public when possible

For Hetzner:

- expose `80` and `443` publicly through nginx
- only expose the raw TCP BASIC port if that is intentional
- otherwise restrict the TCP port with firewall rules

## Validation Checklist

Before moving from the Linux VM to Hetzner, validate all of the following:

1. Fresh install succeeds from scratch.
2. Release build starts successfully.
3. nginx serves the homepage correctly.
4. Browser WebSocket sessions work through nginx.
5. Raw TCP BASIC access works if enabled.
6. User login, SAVE, LOAD, and homepage serving all work.
7. Restarting the service preserves data.
8. Rebooting the VM restores the service automatically.
9. Rotating file logs are written and bounded.
10. If using S3, credentials and bucket access work correctly.

## Proposed Rollout Order

1. Build and run ErlBASIC directly on a Linux VM.
2. Add `.sys.override.config` for deployment-style settings.
3. Verify persistence and logging.
4. Put nginx in front.
5. Verify HTTP and WebSocket access through nginx.
6. Add systemd service management.
7. Reboot-test the VM.
8. Move the same approach to Hetzner.
9. Add public TLS with Certbot.

## Known Gaps

The application is close to deployable in this shape, but these gaps remain:

- no checked-in Linux deployment script
- no checked-in `systemd` unit
- no checked-in nginx site config
- no release-focused Linux run instructions yet

These should be added after the Linux VM rehearsal path is confirmed.

## Next Recommended Artifacts

After this plan, the next most useful additions are:

1. a checked-in `systemd` unit for ErlBASIC
2. a checked-in nginx config for HTTP, HTTPS, and WebSocket proxying
3. a Linux deployment guide with exact commands for package install, release build, and startup
