# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`remotefs-rs-fuse` mounts any [`remotefs`](https://github.com/remotefs-rs/remotefs-rs) `RemoteFs`
implementation (SFTP/SCP, FTP, AWS S3, SMB, WebDAV, Kube, in-memory, ...) as a local filesystem, via
FUSE on Linux/macOS and Dokany on Windows. Two crates in one Cargo workspace:

- `remotefs-fuse` — the library (`Mount`, `MountOption`, `Driver`).
- `fusibile` — a CLI binary (package `fusibile`, crate dir `crates/fusibile`) that wires a chosen
  remotefs backend into `remotefs-fuse`.

## Build / lint / test

```sh
just build "--all-features"
just fmt_check
just lint "-- -D warnings"
just test "--no-fail-fast"                                  # workspace and documentation tests
just test "--features integration-tests --no-fail-fast"     # + integration tests (real mount/unmount)
```

Run a single test: `just test "-p remotefs-fuse <test_name>"`.

Run the complete local quality gate with `just check`.

Platform notes (mirrors `.github/workflows/ci.yml`):

- **Linux**: needs `fuse3`/`libfuse3-dev` (`sudo apt install fuse3 libfuse3-dev`) and
  `echo 'user_allow_other' | sudo tee -a /etc/fuse.conf` for integration tests. Runs with
  `--features integration-tests`.
- **macOS**: needs `macfuse` (`brew install macfuse`). CI builds/tests with
  `--no-default-features` (no integration-tests feature — actual mounting isn't exercised in CI).
- **Windows**: needs `dokany` (`choco install dokany`). CI runs `just build "--all-features"` then
  the full test suite (integration tests included, no separate feature gate needed there).

`fusibile` pulls in one crate per backend behind a feature flag (`aws-s3`, `ftp`, `kube`,
`smb`, `ssh`, `webdav`), all on by default; use `--no-default-features --features <subset>` to trim.

## Architecture

### Unix vs. Windows split

Nearly everything under `crates/remotefs-fuse/src/driver/` and `mount.rs` is `#[cfg(unix)]` /
`#[cfg(windows)]` gated, implementing the _same_ public API (`Mount`, `Driver<T>`) against two
unrelated backend crates:

- **Unix** (`driver/unix.rs` + `driver/unix/{inode,file_handle}.rs`): implements `fuser::Filesystem`
  for `Driver<T>`. Owns an `InodeDb` (path <-> inode mapping, since FUSE addresses everything by
  inode) and a `FileHandlersDb` (open file handle -> local tempfile mirroring remote content).
  `remote: T` is held directly (fuser callbacks run on one thread).
- **Windows** (`driver/windows.rs` + `driver/windows/{entry,security}.rs`): implements
  `dokan::FileSystemHandler` for `Driver<T>`. `remote: T` is wrapped in `Arc<Mutex<T>>` because
  Dokany calls back from multiple threads. File handles are tracked in a `DashMap` keyed by wide
  string path instead of an inode table (Dokany identifies files by path, not inode).

When changing driver behavior, the fix usually needs to be made **twice** — once per platform file —
since they don't share an implementation, only the same conceptual FS operations.

### Mount lifecycle

`Mount::mount(remote, mountpoint, options)` builds a `Driver<T>` and, per platform, either opens a
`fuser::Session` (Unix) or converts `MountOption`s to Dokany options and defers actual mounting to
`Mount::run()` (Windows — `dokan::FileSystemMounter::mount()`). `Mount::run()` blocks the calling
thread running the FS event loop. `Mount::unmounter()` returns an `Unmount` handle that can be moved
into a signal handler (see `ctrlc` usage in both the crate docs example and
`crates/fusibile/src/main.rs`) to unmount from another thread/signal context.

On Windows the "mountpoint" is conventionally a drive letter (e.g. `Z`), not a filesystem path.

`MountOption` (`mount/option.rs`) is a cross-platform enum; conversions exist both to `fuser`'s
option type (`TryFrom<&MountOption>`, Unix) and to Dokany's option flags
(`MountOption::into_dokan_options`, Windows) — not every variant is meaningful on every platform.

### UID/GID override

`MountOption::Uid`/`Gid`/`DefaultMode` let the caller force ownership/mode on mounted entries. This
exists because the local user's UID often won't match the UID owning files on the remote backend
(e.g. logging into SFTP as a different user than the local user), which otherwise blocks local
access to files the remote credentials are actually entitled to.

### CLI (`fusibile`)

`src/cli.rs` defines the `argh`-based arg parser and a `CliArgs::remote()` that dispatches to one of
`src/cli/{aws_s3,ftp,kube,memory,smb,ssh,webdav}.rs` based on the chosen subcommand/feature, each
building the corresponding `remotefs-*` backend. `remotefs_wrapper.rs` adapts backends whose
`RemoteFs` methods are async (SMB, WebDAV) to the sync `RemoteFs` trait `remotefs-fuse` expects, via
a single-threaded `tokio` runtime (`tokio = { features = ["rt"] }`) driven with `block_on`.

### Tests

`crates/remotefs-fuse/tests/integration_tests.rs` gates real mount/unmount integration tests behind the
`integration-tests` feature (`tests/driver`, `tests/fuse` on Unix, `tests/dokany` on Windows) — these
actually mount a filesystem, so they need the platform FUSE/Dokany service installed and (on Linux)
`user_allow_other` enabled. Driver unit tests live alongside the implementation in
`driver/unix/test.rs` and `driver/windows/test.rs`.

## Conventions

- `rustfmt.toml`: `group_imports = "StdExternalCrate"`, `imports_granularity = "Module"`.
- Workspace-level metadata (`authors`, `edition`, `license`, `repository`, `version`, ...) lives in
  the root `Cargo.toml` under `[workspace.package]` and is inherited via `{ workspace = true }` in
  each member's `Cargo.toml`.
