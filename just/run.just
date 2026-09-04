[group('run')]
run args="":
  cargo run --features {{ all_features }} --locked -p fusibile -- {{ args }}
