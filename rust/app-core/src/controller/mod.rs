//! Platform-specific playback controller implementations.
//!
//! - `macos`: CoreAudio backend with physical rate switching and IOProc callback.
//! - `android`: AAudio backend with pull model and UAC2 driver support.
//! - `fallback`: Headless/stub implementation for other hosts and tests.

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::PlaybackController;

#[cfg(target_os = "android")]
mod android;
#[cfg(target_os = "android")]
pub use android::PlaybackController;

#[cfg(all(not(target_os = "macos"), not(target_os = "android")))]
mod fallback;
#[cfg(all(not(target_os = "macos"), not(target_os = "android")))]
pub use fallback::PlaybackController;
