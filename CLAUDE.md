# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`remotefs-rs-fuse` mounts any [`remotefs`](https://github.com/remotefs-rs/remotefs-rs) `RemoteFs`
(or, with the `tokio` feature, `AsyncRemoteFs`) implementation (SFTP/SCP, FTP, AWS S3, SMB, WebDAV,
Kube, in-memory, ...) as a local filesystem, via FUSE on Linux/macOS and Dokany on Windows. Two
crates in one Cargo workspace:

- `remotefs-fuse` — the library (`Mount`, `MountOption`, `Driver`).
- `fusibile` — a CLI binary (package `fusibile`, crate dir `crates/fusibile`) that wires a chosen
  remotefs backend into `remotefs-fuse`.

## Build / lint / test

```sh
just build ""                                               # workspace, default features
just fmt_check
just lint "-- -D warnings"
just test "--no-fail-fast"                                  # workspace and documentation tests
just test "--features integration-tests,remotefs-fuse/tokio --no-fail-fast" # + integration tests
```

Run a single test: `just test "-p remotefs-fuse <test_name>"`.

Run the complete local quality gate with `just check`.

Platform notes (mirrors `.github/workflows/ci.yml`):

- **Linux**: needs `fuse3`/`libfuse3-dev` (`sudo apt install fuse3 libfuse3-dev`) and
  `echo 'user_allow_other' | sudo tee -a /etc/fuse.conf` for integration tests. Runs with
  `--features integration-tests,remotefs-fuse/tokio`.
- **macOS**: needs `macfuse` (`brew install macfuse`). CI builds/tests with
  `--no-default-features --features remotefs-fuse/tokio`.
- **Windows**: needs `dokany` (`choco install dokany`). CI runs with
  `--features remotefs-fuse/tokio`.

`fusibile` pulls in one crate per backend behind a feature flag (`aws-s3`, `ftp`, `kube`,
`smb`, `ssh`, `webdav`), all on by default; use `--no-default-features --features <subset>` to trim.

`smb-vendored` builds Samba from source instead of linking the system `libsmbclient`. It is
excluded from the `all_features` list in the `Justfile` on purpose — it takes over an hour to
compile — and is used only by the release builds.

## Architecture

### Unix vs. Windows split

Nearly everything under `crates/remotefs-fuse/src/driver/` and `mount.rs` is `#[cfg(unix)]` /
`#[cfg(windows)]` gated, implementing the _same_ public API (`Mount`, `Driver<T>`) against two
unrelated backend crates:

- **Unix** (`driver/unix.rs` + `driver/unix/{inode,file_handle,state}.rs`): implements `fuser::Filesystem`
  for `Driver<T>`. Owns an `InodeDb` (path <-> inode mapping, since FUSE addresses everything by
  inode) and a `FileHandlersDb` (open file handle -> local tempfile mirroring remote content).
  `remote: T` is held directly (fuser callbacks run on one thread).
- **Windows** (`driver/windows.rs` + `driver/windows/{entry,security,common}.rs`): implements
  `dokan::FileSystemHandler` for `Driver<T>`. `remote: T` is wrapped in `RwLock<T>` because
  Dokany calls back from multiple threads. File handles are tracked in a `DashMap` keyed by wide
  string path instead of an inode table (Dokany identifies files by path, not inode).

When changing driver behavior, the fix usually needs to be made in the sync body and mirrored in its
async twin, once per platform. The platform state and transfer helpers are shared between the two
implementations.

### Shared transfer helpers

`driver/transfer.rs` holds the platform-neutral transfer logic both drivers call: ranged reads
(`read_at`), staged writes (`PendingWriteState`, `start_pending_write`, `write_to_pending`,
`finalize_pending_write`), `create_empty_file`, `truncate_file` and `append_data`. It picks a
streaming or one-shot path from `RemoteFs::capabilities()` and falls back to buffering when
`create` reports `SizeRequired` or `UnsupportedFeature`. Its unit tests (including a `NoStreamFs`
wrapper that disables streaming) run on every host, so fix transfer behaviour there first and only
then touch the platform drivers.

### Async clients

`AsyncMount` / `AsyncUnmount` (`mount/async.rs`, feature `tokio`) mount an `AsyncRemoteFs` through
native async drivers, never through a blocking adapter. `driver/unix/async.rs` implements
`fuser::Filesystem` by spawning one task per request on the runtime (reply handles are `Send +
'static`); a per-handle `Turnstile` keeps `write`/`flush`/`fsync`/`release` in kernel order.
`driver/windows/async.rs` implements `dokan::FileSystemHandler` with one `Handle::block_on` per
callback around an async body. Both share `transfer/async.rs` and the platform state modules
(`unix/state.rs`, `windows/common.rs`) with the sync drivers. `AsyncMount::mount` connects the
client and `run` disconnects it after the loop returns; the drivers' `init`/`destroy` and
`mounted`/`unmounted` are no-ops.

### Mount lifecycle

`Mount::mount(remote, mountpoint, options)` builds a `Driver<T>` and, per platform, either opens a
`fuser::Session` (Unix) or converts `MountOption`s to Dokany options and defers actual mounting to
`Mount::run()` (Windows — `dokan::FileSystemMounter::mount()`). `Mount::run()` blocks the calling
thread running the FS event loop. `Mount::unmounter()` returns an `Unmount` handle that can be moved
into a signal handler (see the crate docs example) to unmount from another thread/signal context.

On Windows the "mountpoint" is conventionally a drive letter (e.g. `Z`), not a filesystem path.
Windows stores `remote` in an `RwLock<T>`: operations take the read lock, while `connect` and
`disconnect` take the write lock.

`MountOption` (`mount/option.rs`) is a cross-platform enum; conversions exist both to `fuser`'s
option type (`TryFrom<&MountOption>`, Unix) and to Dokany's option flags
(`MountOption::into_dokan_options`, Windows) — not every variant is meaningful on every platform.

### UID/GID override

`MountOption::Uid`/`Gid`/`DefaultMode` let the caller force ownership/mode on mounted entries. This
exists because the local user's UID often won't match the UID owning files on the remote backend
(e.g. logging into SFTP as a different user than the local user), which otherwise blocks local
access to files the remote credentials are actually entitled to.

### CLI (`fusibile`)

`src/cli.rs` defines the `clap`-based arg parser and `CliArgs::remote()`, which returns a
`Box<dyn AsyncRemoteFs>` built by one of
`src/cli/{aws_s3,ftp,gcs,kube,memory,smb,ssh,webdav}.rs`; blocking backends (memory, SMB) are
wrapped in `Unblock`. `main.rs` uses `#[tokio::main]`, mounts through `AsyncMount`, and handles
`SIGINT`/`SIGTERM` with `tokio::signal`.

### Tests

`crates/remotefs-fuse/tests/integration_tests.rs` gates real mount/unmount integration tests behind the
`integration-tests` feature (`tests/driver`, `tests/fuse` on Unix, `tests/dokany` on Windows) — these
actually mount a filesystem, so they need the platform FUSE/Dokany service installed and (on Linux)
`user_allow_other` enabled. The `tokio` feature adds async mount integration tests. Transfer unit
tests live in `driver/transfer.rs` and `driver/transfer/async.rs`; platform-specific tests live
alongside the implementations in `driver/unix/test.rs`, `driver/unix/async/test.rs`,
`driver/unix/async/turnstile.rs`, and `driver/windows/test.rs`.

## Conventions

- `rustfmt.toml`: `group_imports = "StdExternalCrate"`, `imports_granularity = "Module"`.
- Workspace-level metadata (`authors`, `edition`, `license`, `repository`, `version`, ...) lives in
  the root `Cargo.toml` under `[workspace.package]` and is inherited via `{ workspace = true }` in
  each member's `Cargo.toml`.
