[group('run')]
run args="":
  cargo run --all-features --locked -- {{ args }}
