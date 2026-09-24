# Mobius

Mobius is an offline-first music player built with Flutter and a Rust audio core. The current desktop app targets macOS and uses CoreAudio for playback.

## Requirements

- macOS with Xcode and its command-line tools
- Flutter SDK (stable channel)
- Rust toolchain with Cargo, installed through [rustup](https://rustup.rs/)
- CocoaPods for Flutter's macOS plugins

Check that the tools are available:

```bash
flutter doctor
rustc --version
cargo --version
pod --version
```

If CocoaPods is not installed, install it with Homebrew:

```bash
brew install cocoapods
```

## Install project dependencies

From the repository root:

```bash
cd app/mobius
flutter pub get
cd ../..
```

`flutter pub get` resolves the Dart packages. The macOS release build also runs CocoaPods integration for the native Flutter plugins.

## Build the Rust FFI library in release mode

From the repository root:

```bash
cargo build -p offline-player-ffi --release
```

The macOS dynamic library is written to:

```text
target/release/liboffline_player_ffi.dylib
```

## Build the macOS app in release mode

```bash
cd app/mobius
flutter build macos --release
```

The app is produced under `app/mobius/build/macos/Build/Products/Release/`. The Xcode release build phase builds the Rust FFI library and embeds it in the app bundle automatically, so running the Rust command separately is useful when you want to build or verify the FFI library first.

## Project structure

- `app/mobius/` — Flutter application and macOS runner
- `rust/audio-core/` — audio DSP primitives, including the equalizer and resampler
- `rust/decoder/` — local audio decoding
- `rust/app-core/` — library, playback, and queue logic
- `rust/platform-macos/` — macOS CoreAudio output backend
- `rust/ffi/` — C ABI consumed by Dart FFI
