# Run all unit, integration, and documentation tests.
[group('test')]
test args="":
  cargo test --workspace {{ args }}
  cargo test --workspace --doc {{ args }}

# Generate an LCOV coverage report.
[group('test')]
coverage output="lcov.info" args="":
  cargo llvm-cov --workspace --lcov --output-path {{ output }} {{ args }}
