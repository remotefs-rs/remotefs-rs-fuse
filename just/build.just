# Build every target in debug mode.
[group('build')]
build args="":
  cargo build --all-targets {{ args }}

# Build every target in release mode.
[group('build')]
release args="":
  cargo build --all-targets --release {{ args }}

# Remove Cargo build artifacts.
[group('build')]
[confirm("Are you sure you want to clean the build artifacts?")]
clean:
  cargo clean

# Bump the workspace version everywhere and refresh Cargo.lock.
[group('build')]
bump_version version:
  dist/release/bump_version.sh {{ version }}
  cargo update --workspace

# Run the bump_version.sh test suite.
[group('build')]
test_bump_version:
  dist/release/test_bump_version.sh
