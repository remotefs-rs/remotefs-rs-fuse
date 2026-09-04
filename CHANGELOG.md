# Changelog

All notable changes to this project are documented in this file.

## 0.2.0

Released on 2026-09-04

### Breaking changes

- **fusibile:** rename `remotefs-fuse-cli` to `fusibile` (#6)

> the CLI package has changed from `remotefs-fuse-cli` to `fusibile`

### Added

- add Google Cloud Storage client (#5)
- Breaking: **fusibile:** rename `remotefs-fuse-cli` to `fusibile` (#6)
- **remotefs-fuse:** add optional libfuse feature and ship LICENSE in published crates
- **fusibile:** add smb-vendored feature and keep it out of --all-features
- **release:** add tested version bump script
- **release:** add static musl build scripts with vendored samba and libfuse3
- **install:** add POSIX install script with homebrew and release download paths
- **install:** add windows install script with dokany detection

### Changed

- **fusibile:** migrate CLI argument parsing from argh to clap (#7)

> clap gives typo suggestions, colored output, and a broader ecosystem
> than argh. Also replace the manual log-level string match with
> log::LevelFilter, parsed directly by clap.

### Fixed

- webdav arguments are passed in wrong order (#4)
- fix data-loss, collision, and credential-leak bugs found in review (#8)

> - chore: update fundings
> - fix(remotefs-fuse): fix data-loss, collision, and unbounded-allocation bugs in the drivers
>
> * write() on Unix and write_file() on Windows called remote.create()
>   (create-or-truncate) on every single write, so any file written via
>   more than one write call ended up containing only the last chunk.
>   Writes are now staged per open handle and only persisted once, on
>   flush/release (Unix) or flush_file_buffers/cleanup (Windows).
> * Unix file handle numbers could collide: a freed handle was reused via
>   handles.len(), which could still equal a currently open handle's
>   number after further opens/closes, silently aliasing two open files
>   under one fh.
> * Unix inodes were derived from a path hash with no collision handling,
>   letting two unrelated paths alias onto the same inode. Inode
>   allocation is now a real bidirectional path<->inode table.
> * Reads at a caller-supplied offset (Unix and Windows) allocated a
>   zero-filled buffer sized directly from that offset, letting a
>   misbehaving remote trigger a multi-terabyte allocation; offsets are
>   now skipped by discarding bytes through a fixed-size copy instead.
>   The same issue in readlink's buffer, sized from the remote-reported
>   symlink length, is now capped to PATH_MAX.
>   the target's declared length is now capped to PATH_MAX.
> * Windows alternate-stream reads underflowed (and panicked) when the
>   read offset was past the stream's current length; this is now a
>   normal short/empty read like a regular file.
> * Windows delete_file() panicked on a poisoned stat lock instead of
>   returning an error like every other call site in the file.
> * EntryNameRef's unsafe pointer cast relied on layout equivalence with
>   U16Str without `#[repr(transparent)]`; the struct is now marked as
>   such and the cast documents its safety requirement.
>
> - fix(fusibile): stop leaking credentials via Debug and panicking on unmount failure
>
> * Passwords, access keys, and secret tokens taken as CLI args were
>   exposed by the derived Debug impl on each backend's Args struct,
>   which risks leaking them into logs. Debug is now hand-written to
>   redact those fields.
> * The Ctrl-C handler called umount.unmount().expect(...), so a
>   recoverable unmount failure (e.g. EBUSY) crashed the whole process
>   instead of just logging the error.
>
> - style(remotefs-fuse): enable core compiler lints and clean up doc/lint attributes
>
> * Add a workspace [lints.rust] table with the compiler lints from the
>   Microsoft Rust guidelines' M-STATIC-VERIFICATION (missing Debug
>   impls, redundant imports/lifetimes, unsafe fn hygiene, etc.), and
>   wire both crates into it.
> * Mount and Unmount now derive Debug (Driver already needed it to make
>   that possible), per M-PUBLIC-DEBUG.
> * Replace #[allow] lint overrides with #[expect(..., reason = "...")],
>   scoped to the specific items that actually need them instead of a
>   blanket allow across the whole DriverInner impl block.
> * Fix MountOption::Gid's doc comment, copy-pasted from Uid: it said the
>   option treats files as owned by a given user, but it sets the group.
> * Document remotefs-fuse's feature flags in a table, and stop teaching
>   the panicking unmount pattern in the crate's own doc example.
>
> - fix: fix CI failures from the previous commits
>
> * windows.rs: skip_bytes referenced the bare Read trait name, which
>   only compiles with an unaliased `use std::io::Read`; the crate
>   imports it as `Read as _` (methods only), so the Windows build
>   failed outright. Use the fully qualified `std::io::Read` instead.
> * Drop trivial_numeric_casts from the workspace lints: several mode_t
>   casts in the Unix driver are only trivial on Linux (mode_t is a
>   narrower type on macOS/BSD), so the lint can't be satisfied on every
>   target without per-cast, per-platform attributes.
> * fusibile: the #[expect(clippy::large_enum_variant)] on RemoteFsWrapper
>   was unfulfilled when built with zero or one backend feature (no size
>   disparity to flag with a single variant), which is exactly the
>   --no-default-features CI configuration. Use #[allow] instead, since
>   whether this lint fires depends on which backend features are enabled.

- **release:** drop smb-vendored from the intel macOS build

> pavao-src's vendored Samba build fails to link on macos-15-intel runners
> with undefined libintl symbols building tdb. Confirmed by a real dry run
> of the release workflow. Ship that target without SMB instead.

- **ssh:** change argument for ssh from `config-file` to `ssh-config`.
- **release:** cross-compile x86_64-apple-darwin from macos-latest instead of macos-15-intel

> Matches termscp's actual working release workflow: macos-15-intel is a
> deprecated, poorly maintained image (broken homebrew taps in the dry run
> log) and was never the right fix, only dropping smb-vendored was.

- **driver:** log per-syscall FUSE/Dokany handlers at debug instead of info

> These fire on every filesystem operation (read, write, getattr,
> lookup, readdir, ...), flooding logs at the default info level.
> Lifecycle events (mount, unmount, connect, disconnect) stay at info.

- **release:** allow pkg-config cross-compilation for the macOS build

> fuser links macFUSE via pkg-config unconditionally on macOS (unrelated to
> smb-vendored). Cross-compiling x86_64-apple-darwin from an arm64 runner
> made the pkg-config crate refuse to probe it at all, since host and target
> triples differ. Confirmed by a real dry run of the release workflow.

### Build

- bump remotefs-aws-s3 to 0.4
- bump remotefs-ftp 0.4
- bump fuser to 0.18 and nix to 0.31
- bump remotefs-smb to 0.5
- bump remotefs-ssh to 0.9
- bump widestring and serial test
- add remotefs-smb windows compatibility

## 0.1.0

Released on 2024-12-19

### Added

- CLI tool
- wip
- wip
- file handlers and read
- file handlers by pid
- implemented fuse
- memory fs in cli tool
- unix is kinda working
- new mount
- gid and uid mount options
- default mode option
- windows base; use Generic instead of Boxes
- working on windows
- working on windows driver
- dokany impl

### Fixed

- initial commit
- readme
- workspace with -cli
- wip
- ci
- ci
- macos
- fmt
- test mount
- fmt
- macos ci
- tests
- test
- ci
- setup tests
- setup fuse
- test check access
- use nix
- ci
- macos
- ci
- ci
- test
- min rust version
- integration tests
- windows build
- macos build
- macos build
- macos build
- windows build
- windows build
- set mount option on mount
- don't expose Driver
- generic remoteFs
- volume name as unix only
- import
- linux
- docs
- test
- linux
- windows recursion issue
- should list only direct children
- linux build
- fuser 0.15
- integration tests for windows
- don't run the integration tests on CI
- tests
- cargo toml
- gran coglioni
- umount
- lint
