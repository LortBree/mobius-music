#![cfg_attr(not(test), allow(dead_code))]

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

pub use output_policy::{OutputPlan, OutputPolicy, OutputPolicyError};
pub use playback_queue::{PlaybackQueue, PlaybackQueueError, QueuePosition};

use std::{
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, RwLock,
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

use offline_player_audio_core::{pcm_ring_buffer, PcmRingConfig};

use thiserror::Error;

#[cfg(target_os = "macos")]
use offline_player_decoder::{
    probe, stream_to_pcm_i32_controlled_at_rate_with_equalizer,
    stream_to_pcm_i32_from_frame_at_rate_with_equalizer, AudioFormat, MediaInfo, SampleFormat,
    StreamError, StreamStats,
};

#[cfg(target_os = "macos")]
use offline_player_platform_macos::{
    default_output_device, output_format, output_virtual_format, set_nominal_sample_rate,
    supported_virtual_sample_rates, MacAudioError, PcmOutput, PlaybackTelemetry,
};

#[cfg(target_os = "macos")]
const OUTPUT_RATE_SETTLE_TIMEOUT: Duration = Duration::from_millis(1500);

#[cfg(target_os = "macos")]
const OUTPUT_RATE_POLL_INTERVAL: Duration = Duration::from_millis(25);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackState {
    Idle,
    Loaded,
    Playing,
    Paused,
    Stopped,
}

#[cfg(target_os = "macos")]
#[derive(Debug, Error)]
pub enum PlaybackError {
    #[error("no track is loaded")]
    NotLoaded,

    #[error("invalid playback state: {0:?}")]
    InvalidState(PlaybackState),

    #[error("media probe failed: {0}")]
    Probe(String),

    #[error("decoder error: {0}")]
    Decoder(String),

    #[error("decoder worker failed: {0}")]
    DecoderWorkerError(String),

    #[error("decoder worker panicked")]
    DecoderWorkerPanic,

    #[error("decoder worker could not be started")]
    DecoderWorkerStart,

    #[error("CoreAudio error: {0}")]
    CoreAudio(String),

    #[error("output policy error: {0}")]
    OutputPolicy(String),

    #[error("unsupported source format: {0}")]
    UnsupportedSourceFormat(&'static str),

    #[error("invalid seek target: {0}")]
    InvalidSeekTarget(u64),
}

#[cfg(target_os = "macos")]
impl From<MacAudioError> for PlaybackError {
    fn from(value: MacAudioError) -> Self {
        Self::CoreAudio(value.to_string())
    }
}

#[cfg(target_os = "macos")]
impl From<OutputPolicyError> for PlaybackError {
    fn from(value: OutputPolicyError) -> Self {
        Self::OutputPolicy(value.to_string())
    }
}

#[cfg(target_os = "macos")]
#[derive(Debug)]
struct DecoderWorkerResult {
    result: Result<StreamStats, StreamError>,
}

#[cfg(target_os = "macos")]
struct Session {
    path: PathBuf,
    media_info: MediaInfo,

    cancel: Arc<AtomicBool>,
    paused: Arc<AtomicBool>,

    decoder_thread: Option<JoinHandle<DecoderWorkerResult>>,

    output: PcmOutput,

    running: bool,

    //
    // PcmOutput telemetry starts from zero for each new
    // output instance. This bridges it to the logical track frame.
    //
    position_base_frame: u64,
    output_sample_rate: u32,
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

#[cfg(target_os = "macos")]
pub struct PlaybackController {
    state: PlaybackState,
    session: Option<Session>,
    ring_capacity_samples: usize,
    output_mode: PlaybackOutputMode,
    volume: f32,
    equalizer_gains: Arc<RwLock<[f32; 10]>>,
}

#[cfg(not(target_os = "macos"))]
pub struct PlaybackController {
    state: PlaybackState,
    volume: f32,
    equalizer_gains: Arc<RwLock<[f32; 10]>>,
}

#[cfg(target_os = "macos")]
impl PlaybackController {
    const DEFAULT_RING_CAPACITY_SAMPLES: usize = 262_144;

    pub fn new() -> Self {
        Self {
            state: PlaybackState::Idle,
            session: None,
            ring_capacity_samples: Self::DEFAULT_RING_CAPACITY_SAMPLES,
            output_mode: PlaybackOutputMode::Auto,
            volume: 1.0,
            equalizer_gains: Arc::new(RwLock::new([0.0; 10])),
        }
    }

    pub fn with_ring_capacity(ring_capacity_samples: usize) -> Self {
        assert!(ring_capacity_samples > 0, "ring capacity must be > 0");

        Self {
            state: PlaybackState::Idle,
            session: None,
            ring_capacity_samples,
            output_mode: PlaybackOutputMode::Auto,
            volume: 1.0,
            equalizer_gains: Arc::new(RwLock::new([0.0; 10])),
        }
    }

    pub fn state(&self) -> PlaybackState {
        self.state
    }

    pub fn output_mode(&self) -> PlaybackOutputMode {
        self.output_mode
    }

    pub fn set_output_mode(&mut self, mode: PlaybackOutputMode) {
        self.output_mode = mode;
    }

    pub fn volume(&self) -> f32 {
        self.volume
    }

    pub fn set_volume(&mut self, volume: f32) {
        self.volume = volume.clamp(0.0, 1.0);
        if let Some(session) = self.session.as_ref() {
            session.output.set_volume(self.volume);
        }
    }

    pub fn equalizer_gains(&self) -> [f32; 10] {
        *self
            .equalizer_gains
            .read()
            .unwrap_or_else(|error| error.into_inner())
    }

    pub fn set_equalizer_gains(&mut self, gains_db: [f32; 10]) {
        let mut gains = self
            .equalizer_gains
            .write()
            .unwrap_or_else(|error| error.into_inner());
        *gains = gains_db.map(|gain| {
            if gain.is_finite() {
                gain.clamp(-12.0, 12.0)
            } else {
                0.0
            }
        });
    }

    pub fn loaded_path(&self) -> Option<&Path> {
        self.session.as_ref().map(|session| session.path.as_path())
    }

    pub fn media_info(&self) -> Option<&MediaInfo> {
        self.session.as_ref().map(|session| &session.media_info)
    }

    pub fn total_frames(&self) -> Option<u64> {
        self.session
            .as_ref()
            .and_then(|session| session.media_info.total_frames)
    }

    pub fn duration_seconds(&self) -> Option<f64> {
        self.session
            .as_ref()
            .and_then(|session| session.media_info.duration_seconds())
    }

    pub fn current_frame(&self) -> Option<u64> {
        let session = self.session.as_ref()?;

        let channels = session.media_info.format.channels as u64;

        if channels == 0 {
            return Some(session.position_base_frame);
        }

        let telemetry = session.output.telemetry();

        let progressed_output_frames = telemetry.requested_samples / channels;

        let progressed_source_frames = if session.output_sample_rate == 0 {
            0
        } else {
            ((progressed_output_frames as u128)
                .saturating_mul(session.media_info.format.sample_rate as u128)
                / session.output_sample_rate as u128) as u64
        };

        let position = session
            .position_base_frame
            .saturating_add(progressed_source_frames);

        Some(match session.media_info.total_frames {
            Some(total) => position.min(total),
            None => position,
        })
    }

    pub fn current_seconds(&self) -> Option<f64> {
        let frame = self.current_frame()?;

        let sample_rate = self.session.as_ref()?.media_info.format.sample_rate;

        if sample_rate == 0 {
            return None;
        }

        Some(frame as f64 / sample_rate as f64)
    }

    pub fn telemetry(&self) -> Option<PlaybackTelemetry> {
        self.session
            .as_ref()
            .map(|session| session.output.telemetry())
    }

    pub fn load(&mut self, path: impl AsRef<Path>) -> Result<(), PlaybackError> {
        let path = path.as_ref().to_path_buf();

        self.stop_internal()?;

        let media_info = probe(&path).map_err(|err| PlaybackError::Probe(err.to_string()))?;

        let (source_sample_rate, source_channels, source_bits) = source_format(&media_info)?;

        let device_id = default_output_device()?;

        let supported_rates = supported_virtual_sample_rates(device_id)?;

        let plan = self
            .output_mode
            .plan(source_sample_rate, &supported_rates)?;

        let output_sample_rate = match plan {
            OutputPlan::Native { sample_rate } => sample_rate,
            OutputPlan::Resample {
                output_sample_rate, ..
            } => output_sample_rate,
        };

        //
        // Change the device nominal rate only while playback is stopped.
        // When the source rate is unsupported, the decoder worker resamples
        // before the realtime ring buffer so CoreAudio still receives a
        // native output stream.
        //
        Self::configure_output_rate(device_id, output_sample_rate)?;

        let ring_config = PcmRingConfig::new(self.ring_capacity_samples);

        let (mut producer, consumer) = pcm_ring_buffer(ring_config);

        let output = PcmOutput::open(
            device_id,
            consumer,
            output_sample_rate,
            source_channels,
            source_bits,
        )?;
        output.set_volume(self.volume);

        let cancel = Arc::new(AtomicBool::new(false));

        //
        // Loaded state starts paused.
        //
        let paused = Arc::new(AtomicBool::new(true));

        let worker_cancel = Arc::clone(&cancel);

        let worker_paused = Arc::clone(&paused);

        let worker_path = path.clone();
        let worker_equalizer_gains = Arc::clone(&self.equalizer_gains);

        let decoder_thread = thread::Builder::new()
            .name("offline-player-decoder".to_string())
            .spawn(move || {
                let result = stream_to_pcm_i32_controlled_at_rate_with_equalizer(
                    &worker_path,
                    &mut producer,
                    &worker_cancel,
                    &worker_paused,
                    Some(output_sample_rate),
                    worker_equalizer_gains,
                );

                DecoderWorkerResult { result }
            })
            .map_err(|_| PlaybackError::DecoderWorkerStart)?;

        self.session = Some(Session {
            path,
            media_info,
            cancel,
            paused,
            decoder_thread: Some(decoder_thread),
            output,
            running: false,
            position_base_frame: 0,
            output_sample_rate,
        });

        self.state = PlaybackState::Loaded;

        Ok(())
    }

    pub fn play(&mut self) -> Result<(), PlaybackError> {
        let session = self.session.as_mut().ok_or(PlaybackError::NotLoaded)?;

        match self.state {
            PlaybackState::Loaded | PlaybackState::Paused | PlaybackState::Stopped => {}

            PlaybackState::Playing => {
                return Ok(());
            }

            PlaybackState::Idle => {
                return Err(PlaybackError::InvalidState(self.state));
            }
        }

        session.paused.store(false, Ordering::Release);

        session.output.start()?;

        session.running = true;

        self.state = PlaybackState::Playing;

        Ok(())
    }

    fn configure_output_rate(device_id: u32, target_sample_rate: u32) -> Result<(), PlaybackError> {
        let mut virtual_rate = output_virtual_format(device_id)?.sample_rate;
        let mut physical_rate = output_format(device_id)?.sample_rate;
        if virtual_rate == target_sample_rate && physical_rate == target_sample_rate {
            return Ok(());
        }

        set_nominal_sample_rate(device_id, target_sample_rate as f64)?;

        let deadline = Instant::now() + OUTPUT_RATE_SETTLE_TIMEOUT;

        while Instant::now() < deadline {
            if virtual_rate == target_sample_rate && physical_rate == target_sample_rate {
                return Ok(());
            }

            thread::sleep(OUTPUT_RATE_POLL_INTERVAL);
            virtual_rate = output_virtual_format(device_id)?.sample_rate;
            physical_rate = output_format(device_id)?.sample_rate;
        }

        Err(PlaybackError::CoreAudio(format!(
            "output device did not settle at {target_sample_rate} Hz (virtual {virtual_rate} Hz, physical {physical_rate} Hz)"
        )))
    }

    pub fn pause(&mut self) -> Result<(), PlaybackError> {
        let session = self.session.as_mut().ok_or(PlaybackError::NotLoaded)?;

        if self.state != PlaybackState::Playing {
            return Err(PlaybackError::InvalidState(self.state));
        }

        if session.running {
            session.output.stop()?;
            session.running = false;
        }

        session.paused.store(true, Ordering::Release);

        self.state = PlaybackState::Paused;

        Ok(())
    }

    pub fn stop(&mut self) -> Result<(), PlaybackError> {
        self.stop_internal()
    }

    pub fn seek_to_frame(&mut self, requested_frame: u64) -> Result<(), PlaybackError> {
        let session = self.session.as_ref().ok_or(PlaybackError::NotLoaded)?;

        let target_frame = match session.media_info.total_frames {
            Some(total_frames) => {
                if requested_frame > total_frames {
                    return Err(PlaybackError::InvalidSeekTarget(requested_frame));
                }

                requested_frame
            }

            None => requested_frame,
        };

        let was_playing = self.state == PlaybackState::Playing;

        let was_paused = self.state == PlaybackState::Paused;

        let path = session.path.clone();

        let media_info = session.media_info.clone();

        //
        // The immutable borrow ends naturally before the teardown.
        //
        // drop(session);

        self.stop_output_and_decoder()?;

        let device_id = default_output_device()?;

        let supported_rates = supported_virtual_sample_rates(device_id)?;

        let (source_sample_rate, source_channels, source_bits) = source_format(&media_info)?;

        let plan = self
            .output_mode
            .plan(source_sample_rate, &supported_rates)?;

        let output_sample_rate = match plan {
            OutputPlan::Native { sample_rate } => sample_rate,
            OutputPlan::Resample {
                output_sample_rate, ..
            } => output_sample_rate,
        };

        //
        // Playback is stopped here, so changing the device rate is safe.
        //
        Self::configure_output_rate(device_id, output_sample_rate)?;

        let ring_config = PcmRingConfig::new(self.ring_capacity_samples);

        let (mut producer, consumer) = pcm_ring_buffer(ring_config);

        let output = PcmOutput::open(
            device_id,
            consumer,
            output_sample_rate,
            source_channels,
            source_bits,
        )?;
        output.set_volume(self.volume);

        let cancel = Arc::new(AtomicBool::new(false));

        //
        // Playing resumes immediately.
        // Paused and Loaded remain stopped.
        //
        let paused = Arc::new(AtomicBool::new(!was_playing));

        let worker_cancel = Arc::clone(&cancel);

        let worker_paused = Arc::clone(&paused);

        let worker_path = path.clone();
        let worker_equalizer_gains = Arc::clone(&self.equalizer_gains);

        let decoder_thread = thread::Builder::new()
            .name("offline-player-decoder".to_string())
            .spawn(move || {
                let result = stream_to_pcm_i32_from_frame_at_rate_with_equalizer(
                    &worker_path,
                    target_frame,
                    &mut producer,
                    &worker_cancel,
                    &worker_paused,
                    Some(output_sample_rate),
                    worker_equalizer_gains,
                )
                .map(|(_actual_start_frame, stats)| stats);

                DecoderWorkerResult { result }
            })
            .map_err(|_| PlaybackError::DecoderWorkerStart)?;

        self.session = Some(Session {
            path,
            media_info,
            cancel,
            paused,
            decoder_thread: Some(decoder_thread),
            output,
            running: false,
            position_base_frame: target_frame,
            output_sample_rate,
        });

        if was_playing {
            let session = self.session.as_mut().expect("session was just installed");

            session.paused.store(false, Ordering::Release);

            session.output.start()?;
            session.running = true;

            self.state = PlaybackState::Playing;
        } else if was_paused {
            self.state = PlaybackState::Paused;
        } else {
            self.state = PlaybackState::Loaded;
        }

        Ok(())
    }

    fn stop_output_and_decoder(&mut self) -> Result<(), PlaybackError> {
        let Some(session) = self.session.as_mut() else {
            self.state = PlaybackState::Stopped;

            return Ok(());
        };

        //
        // Stop CoreAudio first. This guarantees the realtime
        // callback stops consuming the old ring before teardown.
        //
        if session.running {
            session.output.stop()?;
            session.running = false;
        }

        //
        // Cancel decoder and wake it if it was paused.
        //
        session.cancel.store(true, Ordering::Release);

        session.paused.store(false, Ordering::Release);

        //
        // Join only from the non-realtime control thread.
        //
        if let Some(handle) = session.decoder_thread.take() {
            let worker = handle
                .join()
                .map_err(|_| PlaybackError::DecoderWorkerPanic)?;

            match worker.result {
                Ok(_stats) => {}

                Err(StreamError::Cancelled) => {}

                Err(err) => {
                    return Err(PlaybackError::DecoderWorkerError(err.to_string()));
                }
            }
        }

        Ok(())
    }

    fn stop_internal(&mut self) -> Result<(), PlaybackError> {
        let result = self.stop_output_and_decoder();

        self.session = None;

        self.state = PlaybackState::Stopped;

        result
    }
}

#[cfg(target_os = "macos")]
fn source_format(media_info: &MediaInfo) -> Result<(u32, u32, u32), PlaybackError> {
    let AudioFormat {
        sample_rate,
        channels,
        sample_format,
    } = media_info.format;

    if sample_rate == 0 {
        return Err(PlaybackError::UnsupportedSourceFormat(
            "sample rate is zero",
        ));
    }

    if channels == 0 {
        return Err(PlaybackError::UnsupportedSourceFormat(
            "channel count is zero",
        ));
    }

    let source_bits = match sample_format {
        SampleFormat::SignedInt(bits) => {
            if bits == 0 {
                return Err(PlaybackError::UnsupportedSourceFormat(
                    "integer bit depth is zero",
                ));
            }

            bits as u32
        }

        SampleFormat::Float(_) => {
            return Err(PlaybackError::UnsupportedSourceFormat(
                "floating-point source PCM is not enabled yet",
            ));
        }
    };

    Ok((sample_rate, channels, source_bits))
}

#[cfg(not(target_os = "macos"))]
impl PlaybackController {
    pub fn new() -> Self {
        Self {
            state: PlaybackState::Idle,
            volume: 1.0,
            equalizer_gains: Arc::new(RwLock::new([0.0; 10])),
        }
    }

    pub fn state(&self) -> PlaybackState {
        self.state
    }

    pub fn volume(&self) -> f32 {
        self.volume
    }

    pub fn set_volume(&mut self, volume: f32) {
        self.volume = volume.clamp(0.0, 1.0);
    }

    pub fn equalizer_gains(&self) -> [f32; 10] {
        *self
            .equalizer_gains
            .read()
            .unwrap_or_else(|error| error.into_inner())
    }

    pub fn set_equalizer_gains(&mut self, gains_db: [f32; 10]) {
        let mut gains = self
            .equalizer_gains
            .write()
            .unwrap_or_else(|error| error.into_inner());
        *gains = gains_db.map(|gain| {
            if gain.is_finite() {
                gain.clamp(-12.0, 12.0)
            } else {
                0.0
            }
        });
    }
}

#[cfg(target_os = "macos")]
impl Drop for PlaybackController {
    fn drop(&mut self) {
        let _ = self.stop_internal();
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
}
