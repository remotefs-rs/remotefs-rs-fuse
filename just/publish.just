# Package and publish remotefs-fuse to crates.io.
[group('publish')]
publish_lib args="":
  cargo publish --locked -p remotefs-fuse {{ args }}

# Package and publish remotefs-fuse-cli to crates.io.
[group('publish')]
publish_cli args="":
  cargo publish --locked -p remotefs-fuse-cli {{ args }}

# Publish both crates in dependency order.
[group('publish')]
publish args="":
  cargo publish --locked {{ args }}
