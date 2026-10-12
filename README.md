# Mobius

**Mobius** is a modern, offline-first, audiophile-grade music player built with **Flutter** and a high-performance **Rust** audio core. Designed for listeners who care about uncompromised sound quality, clean ergonomics, and complete privacy.

---

## ✨ Features

### 🎧 Bit-Perfect Audio Engine
- **Custom Rust Audio Pipeline**: High-performance audio engine bypassing typical operating system mixer degradation.
- **Direct USB DAC Output**: Hardware stream bypass for USB Audio Class 2 (UAC2) DACs on both desktop and Android, unlocking bit-perfect sample rate switching.
- **Real-Time Signal Path Transparency**: Inspect the exact audio signal chain: source sample rate & bit-depth, DSP processing stages, resampling status, and active hardware route.
- **Audiophile DSP & Normalization**:
  - 10-band graphic equalizer with high-precision biquad filters.
  - Track-gain volume normalization (ReplayGain) with headroom safety.
  - Hardware volume attenuation support.

### 📱 Multiplatform Experience (macOS & Android)
- **macOS Desktop**:
  - Native CoreAudio output backend with low-latency buffering.
  - Keyboard shortcuts, global media keys, and native macOS window styling.
  - Collapsible navigation rail and persistent playback control bar.
- **Android Mobile**:
  - Modern bottom-oriented layout designed for comfortable one-handed reachability.
  - Foreground playback service (`MobiusPlaybackService`) with rich lockscreen controls, Android media session integration, and audio focus handling.
  - AAudio low-latency engine with direct UAC2 bypass support.

### 🎨 Visuals & Thoughtful UX
- **Dynamic Ambient Glow**: GPU-accelerated GLSL shader (`ambient_glow.frag`) that creates subtle, fluid light fields reacting to active themes.
- **Cohesive Theming**: Seamless dark (deep violet / lilac) and light ("Sunrise" / dim stone) modes with zero hardcoded visual artifacts.
- **Interactive Home Hub**:
  - **Jump Back In**: Instantly resume paused sessions or shuffle recent tracks.
  - **Recently Added**: Smooth horizontal rail for newly indexed albums and tracks.
  - **Album Spotlight & Smart Mixes**: Instant 1-tap mixes (*Shuffle All*, *Favorites*) and deep album exploration.
- **Synchronized Lyrics**: Clean, scrolling synchronized `.lrc` lyrics with animated line highlights.
- **Shareable Music Cards**: Generate high-resolution, beautifully styled cards (Minimal, Retro Cassette, Vinyl Record, CD Jewel Case, Modern Poster) to export or share.

### 🔒 100% Offline & Private
- Zero cloud accounts, zero tracking, zero telemetries.
- Fast local SQLite indexer that scans and extracts ID3/Vorbis/FLAC metadata and embedded album artwork locally on your device.

---

## 🏗️ Architecture

Mobius combines the UI flexibility of Flutter with the deterministic performance and memory safety of Rust:

```
mobius-music/
├── app/
│   └── mobius/                  # Flutter application
│       ├── lib/
│       │   ├── app/             # Application shell, routing & themes
│       │   ├── features/        # Home, Library, Sound, Settings, Onboarding
│       │   ├── platform/        # Native bridge (macOS / Android channels)
│       │   └── playback/        # Audio controllers, lyrics, now-playing UI
│       ├── android/             # Android native host & Kotlin playback service
│       └── macos/               # macOS native runner & CoreAudio hooks
└── rust/
    ├── audio-core/              # DSP primitives, EQ filters, volume & resampler
    ├── decoder/                 # Local audio decoders (FLAC, MP3, WAV, ALAC, AAC)
    ├── app-core/                # Playback queue, state machine & library scanner
    ├── platform-macos/          # macOS CoreAudio output backend
    ├── platform-android/        # Android AAudio / Direct USB DAC backend
    └── ffi/                     # C ABI bridge consumed by Dart FFI
```

---

## 🚀 Getting Started

### Prerequisites

1. **Flutter SDK**: Stable channel (`>= 3.24.0`).
2. **Rust Toolchain**: Stable channel (`rustup default stable`).
3. **Platform-specific tools**:
   - **macOS**: Xcode with Command Line Tools and CocoaPods (`brew install cocoapods`).
   - **Android**: Android SDK (API 34+), NDK (`27.0.12077973`), and `cargo-ndk` (`cargo install cargo-ndk`).

Verify your environment:
```bash
flutter doctor
rustc --version
cargo --version
```

---

### Building for macOS

1. **Fetch Flutter dependencies**:
   ```bash
   cd app/mobius
   flutter pub get
   cd ../..
   ```

2. **Build the Rust FFI dynamic library**:
   ```bash
   cargo build -p offline-player-ffi --release
   ```
   The compiled library will be output to `target/release/liboffline_player_ffi.dylib`.

3. **Run or build the macOS application**:
   ```bash
   cd app/mobius
   # For running in debug mode:
   flutter run -d macos

   # For building release app bundle:
   flutter build macos --release
   ```
   The release bundle will be available at `app/mobius/build/macos/Build/Products/Release/mobius.app`.

---

### Building for Android

1. **Add Android Rust target**:
   ```bash
   rustup target add aarch64-linux-android
   ```

2. **Compile the Rust library for Android**:
   ```bash
   cargo ndk -t arm64-v8a -o app/mobius/android/app/src/main/jniLibs build -p offline-player-ffi --release
   ```

3. **Build the Android APK**:
   ```bash
   cd app/mobius
   flutter build apk --release --target-platform android-arm64
   ```
   The release APK will be generated at `app/mobius/build/app/outputs/flutter-apk/app-release.apk`.

---

## 📦 Automated Releases

This repository includes GitHub Actions workflows for automated builds:
- Pushing a version tag (e.g. `v1.0.3`) triggers both:
  - `.github/workflows/android-release.yml` (builds `arm64-v8a` APK)
  - `.github/workflows/macos-release.yml` (builds macOS `arm64` and `x86_64` bundles)
- Release binaries are compiled with optimizations and published directly to GitHub Releases.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
