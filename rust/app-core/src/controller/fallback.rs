use std::sync::Arc;

use offline_player_audio_core::SharedEqualizerGains;

use crate::{
    PlaybackError, PlaybackOutputMode, PlaybackState, SignalPathSnapshot,
};

pub struct PlaybackController {
    state: PlaybackState,
    volume: f32,
    bit_perfect_mode: bool,
    volume_normalization: bool,
    track_gain_db: Option<f32>,
    equalizer_gains: Arc<SharedEqualizerGains>,
}

impl PlaybackController {
    pub fn new() -> Self {
        Self {
            state: PlaybackState::Idle,
            volume: 1.0,
            bit_perfect_mode: true,
            volume_normalization: false,
            track_gain_db: None,
            equalizer_gains: Arc::new(SharedEqualizerGains::default()),
        }
    }

    pub fn state(&self) -> PlaybackState {
        self.state
    }

    pub fn output_mode(&self) -> PlaybackOutputMode {
        PlaybackOutputMode::Auto
    }

    pub fn effective_output_rate(&self) -> Option<u32> {
        None
    }

    pub fn set_output_mode(&mut self, _mode: PlaybackOutputMode) {}

    pub fn volume(&self) -> f32 {
        self.volume
    }

    pub fn set_volume(&mut self, volume: f32) {
        self.volume = volume.clamp(0.0, 1.0);
    }

    pub fn hardware_volume(&self) -> f32 {
        1.0
    }

    pub fn set_hardware_volume(&mut self, _volume: f32) {}

    pub fn is_bit_perfect_mode(&self) -> bool {
        self.bit_perfect_mode
    }

    pub fn set_bit_perfect_mode(&mut self, enabled: bool) {
        self.bit_perfect_mode = enabled;
    }

    pub fn volume_normalization(&self) -> bool {
        self.volume_normalization
    }

    pub fn set_volume_normalization(&mut self, enabled: bool) {
        self.volume_normalization = enabled;
    }

    pub fn track_gain_db(&self) -> Option<f32> {
        self.track_gain_db
    }

    pub fn switch_output_route(&mut self) -> Result<(), PlaybackError> {
        Ok(())
    }

    pub fn equalizer_gains(&self) -> [f32; 10] {
        self.equalizer_gains.get()
    }

    pub fn set_equalizer_gains(&mut self, gains_db: [f32; 10]) {
        self.equalizer_gains.set(gains_db);
    }

    pub fn signal_path(&self) -> Option<SignalPathSnapshot> {
        None
    }
}

impl Default for PlaybackController {
    fn default() -> Self {
        Self::new()
    }
}
