# Offline Player

Offline, local-first music player. Phase 1 targets macOS Ventura.

## Current milestone

M0/M1.1 repository bootstrap and FLAC probe skeleton.

## Architecture

Flutter UI -> C ABI/Dart FFI -> Rust App Core -> Rust Audio Core -> macOS CoreAudio.

Primary decoder: Symphonia. Reference decoder for validation: libFLAC (test-only).

## Status

Repository skeleton is prepared, but this environment does not currently include `rustc`/`cargo`, so the workspace has not been compiled here.
