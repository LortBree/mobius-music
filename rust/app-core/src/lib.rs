#![cfg_attr(not(test), allow(dead_code))]

pub mod controller;
pub mod cue;
pub mod cue_tracks;
pub mod library;
pub mod library_service;
pub mod library_store;
pub mod metadata_model;
pub mod output_policy;
pub mod playback_model;
pub mod playback_queue;
pub mod playback_service;
pub mod scanner;

pub use controller::PlaybackController;
pub use output_policy::{OutputPlan, OutputPolicy, OutputPolicyError};
pub use playback_queue::{PlaybackQueue, PlaybackQueueError, QueuePosition};

#[cfg(target_os = "macos")]
pub use offline_player_platform_macos::PlaybackTelemetry;
#[cfg(target_os = "android")]
pub use offline_player_platform_android::PlaybackTelemetry;

use thiserror::Error;

#[cfg(target_os = "macos")]
use offline_player_platform_macos::MacAudioError;

#[cfg(target_os = "android")]
use offline_player_platform_android::AndroidAudioError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackState {
    Idle,
    Loaded,
    Playing,
    Paused,
    Stopped,
}

/// Immutable snapshot of the engine's output path for the currently loaded
/// track, consumed by the FFI `offline_player_signal_path` export.
///
/// Only engine-side ground truth lives here; the host fills route and device
/// name on Android. `bit_perfect` is the engine's own verdict and is always
/// `false` on Android. All fields are zeroed when nothing is loaded.
#[derive(Debug, Clone, PartialEq)]
pub struct SignalPathSnapshot {
    pub output_sample_rate: u32,
    pub output_channels: u32,
    pub output_bits_per_sample: u32,
    pub output_is_float: bool,
    pub resampling: bool,
    pub equalizer_active: bool,
    pub bit_perfect: bool,
    pub equalizer_bands: u32,
    pub volume: f32,
    pub buffer_ms: u32,
    pub underrun_samples: u64,
    pub callback_count: u64,
    /// Output backend label, e.g. "CoreAudio" / "AAudio". Empty on hosts with
    /// no audio backend compiled in.
    pub output_api: &'static str,
    /// CoreAudio device name when cheaply available, else empty. Android leaves
    /// this empty for the host to fill from `mobius/audio_route`.
    pub device_name: String,
}

/// EQ is "active" only when at least one band departs flat by more than this
/// many dB. Matches the UI contract (`enabled && any |gain| > 0.01 dB`); the
/// engine has no separate enabled flag, so a non-zero gain IS enablement.
#[cfg(any(target_os = "macos", target_os = "android"))]
const EQUALIZER_ACTIVE_EPSILON_DB: f32 = 0.01;

/// Number of graphic-EQ bands the engine exposes.
#[cfg(any(target_os = "macos", target_os = "android"))]
const EQUALIZER_BAND_COUNT: u32 = 10;

/// Decide whether the output stream should be rebuilt after an AAudio
/// disconnect (headphones unplugged, Bluetooth route change).
///
/// Factored out of the `cfg(target_os = "android")` controller so the policy is
/// host-testable. Rebuild only when the device actually reported a disconnect,
/// a track is loaded, and we have not already failed to reopen THIS session
/// (which would otherwise loop-reopen on every poll). Returns `false` for the
/// `Idle` state, where there is nothing to carry over.
pub fn should_reopen_after_disconnect(
    disconnected: bool,
    has_session: bool,
    reopen_already_failed: bool,
    state: PlaybackState,
) -> bool {
    disconnected && has_session && !reopen_already_failed && !matches!(state, PlaybackState::Idle)
}

#[derive(Debug, Error)]
pub enum PlaybackError {
    #[error("no track is loaded")]
    NotLoaded,

    #[error("invalid playback state: {0:?}")]
    InvalidState(PlaybackState),

    #[error("invalid seek target: {0}")]
    InvalidSeekTarget(u64),

    #[error("media probe failed: {0}")]
    #[cfg(any(target_os = "macos", target_os = "android"))]
    Probe(String),

    #[error("decoder error: {0}")]
    #[cfg(any(target_os = "macos", target_os = "android"))]
    Decoder(String),

    #[error("decoder worker failed: {0}")]
    #[cfg(any(target_os = "macos", target_os = "android"))]
    DecoderWorkerError(String),

    #[error("decoder worker panicked")]
    #[cfg(any(target_os = "macos", target_os = "android"))]
    DecoderWorkerPanic,

    #[error("decoder worker could not be started")]
    #[cfg(any(target_os = "macos", target_os = "android"))]
    DecoderWorkerStart,

    #[error("unsupported source format: {0}")]
    #[cfg(any(target_os = "macos", target_os = "android"))]
    UnsupportedSourceFormat(&'static str),

    #[error("output policy error: {0}")]
    #[cfg(any(target_os = "macos", target_os = "android"))]
    OutputPolicy(String),

    #[error("CoreAudio error: {0}")]
    #[cfg(target_os = "macos")]
    CoreAudio(String),

    #[error("AAudio error: {0}")]
    #[cfg(target_os = "android")]
    AndroidAudio(String),
}

#[cfg(target_os = "macos")]
impl From<MacAudioError> for PlaybackError {
    fn from(value: MacAudioError) -> Self {
        Self::CoreAudio(value.to_string())
    }
}

#[cfg(target_os = "android")]
impl From<AndroidAudioError> for PlaybackError {
    fn from(value: AndroidAudioError) -> Self {
        Self::AndroidAudio(value.to_string())
    }
}

#[cfg(any(target_os = "macos", target_os = "android"))]
impl From<OutputPolicyError> for PlaybackError {
    fn from(value: OutputPolicyError) -> Self {
        Self::OutputPolicy(value.to_string())
    }
}


#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackOutputMode {
    Auto,
    Fixed44100,
    Fixed48000,
    Fixed96000,
}

impl PlaybackOutputMode {
    fn plan(
        self,
        source_sample_rate: u32,
        supported_rates: &[u32],
    ) -> Result<OutputPlan, OutputPolicyError> {
        match self {
            Self::Auto => OutputPolicy::Auto.plan(source_sample_rate, supported_rates),
            Self::Fixed44100 => OutputPolicy::Fixed {
                sample_rate: 44_100,
            }
            .plan(source_sample_rate, supported_rates),
            Self::Fixed48000 => OutputPolicy::Fixed {
                sample_rate: 48_000,
            }
            .plan(source_sample_rate, supported_rates),
            Self::Fixed96000 => OutputPolicy::Fixed {
                sample_rate: 96_000,
            }
            .plan(source_sample_rate, supported_rates),
        }
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn initial_state_is_idle() {
        let controller = PlaybackController::new();

        assert_eq!(controller.state(), PlaybackState::Idle);
    }

    #[test]
    fn reopen_decision_requires_a_disconnect() {
        // No disconnect reported -> never reopen, whatever the state.
        for state in [
            PlaybackState::Loaded,
            PlaybackState::Playing,
            PlaybackState::Paused,
            PlaybackState::Stopped,
        ] {
            assert!(!should_reopen_after_disconnect(false, true, false, state));
        }
    }

    #[test]
    fn reopen_decision_reopens_when_disconnected_with_a_session() {
        assert!(should_reopen_after_disconnect(
            true,
            true,
            false,
            PlaybackState::Playing
        ));
        assert!(should_reopen_after_disconnect(
            true,
            true,
            false,
            PlaybackState::Paused
        ));
    }

    #[test]
    fn reopen_decision_backs_off_after_a_failed_reopen() {
        // reopen_already_failed latched -> do not loop-reopen.
        assert!(!should_reopen_after_disconnect(
            true,
            true,
            true,
            PlaybackState::Playing
        ));
    }

    #[test]
    fn reopen_decision_needs_a_session_and_a_non_idle_state() {
        // Disconnected but nothing loaded.
        assert!(!should_reopen_after_disconnect(
            true,
            false,
            false,
            PlaybackState::Idle
        ));
        // Disconnected, has_session claimed, but Idle has nothing to carry over.
        assert!(!should_reopen_after_disconnect(
            true,
            true,
            false,
            PlaybackState::Idle
        ));
    }

    #[test]
    fn volume_normalization_toggles_and_defaults_to_false() {
        let mut controller = PlaybackController::new();
        assert!(!controller.volume_normalization());

        controller.set_volume_normalization(true);
        assert!(controller.volume_normalization());

        controller.set_volume_normalization(false);
        assert!(!controller.volume_normalization());
    }

    #[test]
    fn bit_perfect_mode_bypasses_volume_normalization() {
        let mut controller = PlaybackController::new();
        controller.set_bit_perfect_mode(true);
        controller.set_volume_normalization(true);
        assert!(controller.is_bit_perfect_mode());
        assert!(controller.volume_normalization());

        // Switching to standard mode allows volume normalization
        controller.set_bit_perfect_mode(false);
        assert!(!controller.is_bit_perfect_mode());
    }
}
