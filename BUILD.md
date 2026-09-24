# Build notes

## Environment requirement

Phase 1 is intended to be built on macOS Ventura with a current Rust toolchain and Flutter SDK.

This workspace was scaffolded in an environment that does not currently provide `rustc`/`cargo`, so compilation was not performed here.

## First checks on macOS

```bash
rustc --version
cargo --version
cargo check --workspace
```

Then probe a real FLAC:

```bash
cargo run -p offline-player-decoder --bin probe -- /path/to/file.flac
```
