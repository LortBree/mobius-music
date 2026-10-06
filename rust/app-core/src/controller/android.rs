use std::{
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc,
    },
    thread::{self, JoinHandle},
    time::Duration,
};

use offline_player_audio_core::{pcm_ring_buffer, PcmRingConfig, SharedEqualizerGains};
use offline_player_decoder::{
    probe, stream_to_pcm_i32_controlled_at_rate, stream_to_pcm_i32_from_frame_at_rate, AudioFormat,
    MediaInfo, SampleFormat, StreamError, StreamStats,
};
use offline_player_platform_android::{PcmOutput, PlaybackTelemetry};

use crate::{
    should_reopen_after_disconnect, OutputPlan, PlaybackError, PlaybackOutputMode, PlaybackState,
    SignalPathSnapshot, EQUALIZER_ACTIVE_EPSILON_DB, EQUALIZER_BAND_COUNT,
};

struct Session {
    path: PathBuf,
    media_info: MediaInfo,
    track_gain_db: Option<f32>,
    cancel: Arc<AtomicBool>,
    paused: Arc<AtomicBool>,

    decoder_thread: Option<JoinHandle<DecoderWorkerResult>>,

    output: PcmOutput,

    running: bool,

    // PcmOutput telemetry starts from zero for each new output instance; this
    // bridges it to the logical track frame.
    position_base_frame: u64,
    output_sample_rate: u32,

    // Output underrun count at the moment the decoder was first seen to have
    // finished (u64::MAX until then). See `played_output_samples`.
    underrun_at_decoder_end: AtomicU64,

    // Latches true when a disconnect-triggered reopen has already failed for
    // THIS session, so the recovery path backs off instead of loop-reopening
    // on every control call. Cleared only by a fresh load/seek (new Session).
    reopen_failed: bool,
}

#[derive(Debug)]
struct DecoderWorkerResult {
    result: Result<StreamStats, StreamError>,
}

impl Session {
    /// Output samples that actually carried audio for the playback clock.
    ///
    /// Silence the device plays because the decoder fell behind is not
    /// playback and must not advance the clock; silence after the decoder has
    /// finished is the track's tail draining out and must count, or the clock
    /// never reaches the end and auto-advance never fires. Mirrors macOS.
    fn played_output_samples(&self) -> u64 {
        let telemetry = self.output.telemetry();

        let decoder_done = self
            .decoder_thread
            .as_ref()
            .is_none_or(|handle| handle.is_finished());

        let mut stalls = self.underrun_at_decoder_end.load(Ordering::Relaxed);
        if decoder_done && stalls == u64::MAX {
            stalls = telemetry.underrun_samples;
            self.underrun_at_decoder_end
                .store(stalls, Ordering::Relaxed);
        }

        if stalls == u64::MAX {
            telemetry.consumed_samples
        } else {
            telemetry
                .consumed_samples
                .saturating_add(telemetry.underrun_samples.saturating_sub(stalls))
        }
    }
}

pub struct PlaybackController {
    state: PlaybackState,
    session: Option<Session>,
    ring_capacity_samples: usize,
    output_mode: PlaybackOutputMode,
    volume: f32,
    hardware_volume: f32,
    bit_perfect_mode: bool,
    volume_normalization: bool,
    equalizer_gains: Arc<SharedEqualizerGains>,
}

impl PlaybackController {
    const DEFAULT_RING_CAPACITY_SAMPLES: usize = 262_144;

    pub fn new() -> Self {
        Self {
            state: PlaybackState::Idle,
            session: None,
            ring_capacity_samples: Self::DEFAULT_RING_CAPACITY_SAMPLES,
            output_mode: PlaybackOutputMode::Auto,
            volume: 1.0,
            hardware_volume: 0.36, // -20 dB safe level
            bit_perfect_mode: true,
            volume_normalization: false,
            equalizer_gains: Arc::new(SharedEqualizerGains::default()),
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
            hardware_volume: 0.36,
            bit_perfect_mode: true,
            volume_normalization: false,
            equalizer_gains: Arc::new(SharedEqualizerGains::default()),
        }
    }

    pub fn state(&self) -> PlaybackState {
        self.state
    }

    pub fn output_mode(&self) -> PlaybackOutputMode {
        self.output_mode
    }

    /// The sample rate AAudio actually negotiated for the current session, or
    /// `None` when nothing is loaded. On Android this is for display only: it
    /// is NOT a bit-perfect signal, because `AudioFlinger` always owns and may
    /// resample the chain (see the honesty rule). Output is always classified
    /// as standard/internal regardless of whether this equals the source rate.
    pub fn effective_output_rate(&self) -> Option<u32> {
        self.session
            .as_ref()
            .map(|session| session.output_sample_rate)
            .filter(|&rate| rate > 0)
    }

    pub fn set_output_mode(&mut self, mode: PlaybackOutputMode) {
        self.output_mode = mode;
    }

    pub fn volume(&self) -> f32 {
        self.volume
    }

    pub fn set_volume(&mut self, volume: f32) {
        self.service_disconnect().ok();

        self.volume = volume.clamp(0.0, 1.0);
        if let Some(session) = self.session.as_ref() {
            if self.bit_perfect_mode && session.output.is_usb_dac() {
                session.output.set_software_volume(1.0);
                return;
            }
            session.output.set_software_volume(self.effective_volume());
        }
    }

    pub fn set_software_volume(&mut self, volume: f32) {
        self.set_volume(volume);
    }

    pub fn hardware_volume(&self) -> f32 {
        if let Some(session) = self.session.as_ref() {
            session.output.hardware_volume()
        } else {
            self.hardware_volume
        }
    }

    pub fn set_hardware_volume(&mut self, volume: f32) {
        self.hardware_volume = volume.clamp(0.0, 1.0);
        if let Some(session) = self.session.as_ref() {
            session.output.set_hardware_volume(self.hardware_volume);
        }
    }

    pub fn is_bit_perfect_mode(&self) -> bool {
        if let Some(session) = self.session.as_ref() {
            session.output.is_bit_perfect_mode()
        } else {
            self.bit_perfect_mode
        }
    }

    pub fn set_bit_perfect_mode(&mut self, enabled: bool) {
        self.bit_perfect_mode = enabled;
        if let Some(session) = self.session.as_ref() {
            session.output.set_bit_perfect_mode(enabled);
            session.output.set_hardware_volume(self.hardware_volume);
            if enabled {
                session.output.set_software_volume(1.0);
            } else {
                session.output.set_software_volume(self.volume);
            }
        }
    }

    pub fn volume_normalization(&self) -> bool {
        self.volume_normalization
    }

    pub fn set_volume_normalization(&mut self, enabled: bool) {
        self.volume_normalization = enabled;
        if let Some(session) = self.session.as_ref() {
            if self.is_bit_perfect_mode() && session.output.is_usb_dac() {
                session.output.set_software_volume(1.0);
            } else {
                session.output.set_software_volume(self.effective_volume());
            }
        }
    }

    pub fn track_gain_db(&self) -> Option<f32> {
        self.session.as_ref().and_then(|s| s.track_gain_db)
    }

    fn effective_volume(&self) -> f32 {
        if self.volume_normalization && !self.is_bit_perfect_mode() {
            if let Some(gain_db) = self.session.as_ref().and_then(|s| s.track_gain_db) {
                let multiplier = 10.0f32.powf(gain_db / 20.0);
                (self.volume * multiplier).clamp(0.0, 1.0)
            } else {
                self.volume
            }
        } else {
            self.volume
        }
    }

    pub fn switch_output_route(&mut self) -> Result<(), PlaybackError> {
        self.service_disconnect().ok();
        if let Some(session) = self.session.as_ref() {
            let target_frame = self.current_frame().unwrap_or(0);
            let path = session.path.clone();
            let media_info = session.media_info.clone();
            let was_playing = self.state == PlaybackState::Playing;
            let was_paused = self.state == PlaybackState::Paused;
            self.reopen_at_frame(path, media_info, target_frame, was_playing, was_paused)?;
        }
        Ok(())
    }

    pub fn equalizer_gains(&self) -> [f32; 10] {
        self.equalizer_gains.get()
    }

    pub fn set_equalizer_gains(&mut self, gains_db: [f32; 10]) {
        // Lock-free: the output callback picks it up within one callback buffer.
        self.equalizer_gains.set(gains_db);
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

        let progressed_output_frames = session.played_output_samples() / channels;

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

    /// Engine-side signal-path snapshot for the loaded track, or `None` when
    /// nothing is loaded. AAudio float output; `bit_perfect` is ALWAYS `false`
    /// on Android because `AudioFlinger` owns and may resample/mix the route
    /// (the honesty rule), regardless of whether rates happen to match. Route
    /// and device name are left for the host to fill from `mobius/audio_route`.
    pub fn signal_path(&self) -> Option<SignalPathSnapshot> {
        let session = self.session.as_ref()?;

        let source_rate = session.media_info.format.sample_rate;
        let output_rate = session.output_sample_rate;
        let resampling = output_rate != 0 && source_rate != 0 && output_rate != source_rate;

        let gains = self.equalizer_gains.get();
        let equalizer_active = gains
            .iter()
            .any(|gain| gain.abs() > EQUALIZER_ACTIVE_EPSILON_DB);

        let telemetry = session.output.telemetry();
        let output_channels = session.output.channels();

        // Queued source samples -> frames -> ms at the output rate. Source and
        // output run at the same rate on the ring (the decoder resamples to the
        // output rate upstream), so dividing by the output rate is correct.
        let buffer_ms = if output_rate == 0 || output_channels == 0 {
            0
        } else {
            let queued_frames = session.output.queued_source_samples() / output_channels as u64;
            ((queued_frames.saturating_mul(1000)) / output_rate as u64).min(u32::MAX as u64) as u32
        };

        let is_usb_dac = session.output.is_usb_dac();
        let is_bp_mode = session.output.is_bit_perfect_mode();
        let (output_api, bit_perfect, output_is_float, device_name) = if is_usb_dac {
            (
                "Direct UAC2",
                // Bit-perfect requires: Direct UAC2 output, no resampling, no equalizer active,
                // and Bit-Perfect mode enabled!
                !resampling && !equalizer_active && is_bp_mode,
                false,
                "JadeAudio JA11".to_string(),
            )
        } else {
            ("AAudio", false, true, String::new())
        };

        Some(SignalPathSnapshot {
            output_sample_rate: output_rate,
            output_channels,
            output_bits_per_sample: 32,
            output_is_float,
            resampling,
            equalizer_active,
            bit_perfect,
            equalizer_bands: EQUALIZER_BAND_COUNT,
            volume: self.volume,
            buffer_ms,
            underrun_samples: telemetry.underrun_samples,
            callback_count: telemetry.callback_count,
            output_api,
            device_name,
        })
    }

    pub fn load(&mut self, path: impl AsRef<Path>) -> Result<(), PlaybackError> {
        let path = path.as_ref().to_path_buf();

        self.stop_internal()?;

        let media_info = probe(&path).map_err(|err| PlaybackError::Probe(err.to_string()))?;

        let (_source_sample_rate, source_channels, source_bits) = source_format(&media_info)?;

        // Request the source rate; AAudio negotiates and we read back what it
        // actually opened. The decoder resamples to that negotiated rate.
        let requested_rate = media_info.format.sample_rate;

        let ring_config =
            PcmRingConfig::new(self.ring_capacity_for(requested_rate, source_channels));

        let (mut producer, consumer) = pcm_ring_buffer(ring_config);

        let output = PcmOutput::open_with_equalizer(
            consumer,
            requested_rate,
            source_channels,
            source_bits,
            Some(Arc::clone(&self.equalizer_gains)),
        )?;
        output.set_hardware_volume(self.hardware_volume);
        output.set_bit_perfect_mode(self.bit_perfect_mode);
        if self.bit_perfect_mode && output.is_usb_dac() {
            output.set_software_volume(1.0);
        } else {
            output.set_software_volume(self.effective_volume());
        }
        let track_gain_db = offline_player_metadata::read(&path)
            .ok()
            .and_then(|m| m.track_gain_db);
        let output_sample_rate = output.sample_rate();

        let cancel = Arc::new(AtomicBool::new(false));

        // Loaded state starts paused.
        let paused = Arc::new(AtomicBool::new(true));

        let worker_cancel = Arc::clone(&cancel);
        let worker_paused = Arc::clone(&paused);
        let worker_path = path.clone();

        let decoder_thread = thread::Builder::new()
            .name("offline-player-decoder".to_string())
            .spawn(move || {
                let result = stream_to_pcm_i32_controlled_at_rate(
                    &worker_path,
                    &mut producer,
                    &worker_cancel,
                    &worker_paused,
                    Some(output_sample_rate),
                );

                DecoderWorkerResult { result }
            })
            .map_err(|_| PlaybackError::DecoderWorkerStart)?;

        self.session = Some(Session {
            path,
            media_info,
            track_gain_db,
            cancel,
            paused,
            decoder_thread: Some(decoder_thread),
            output,
            running: false,
            position_base_frame: 0,
            underrun_at_decoder_end: AtomicU64::new(u64::MAX),
            output_sample_rate,
            reopen_failed: false,
        });

        self.state = PlaybackState::Loaded;

        Ok(())
    }

    /// Rebuild the AAudio output if the device reported a disconnect (headphones
    /// unplugged, Bluetooth route change) since the last check, preserving the
    /// play/pause state, the current position, volume and EQ.
    ///
    /// Called from every `&mut self` control entry point (`play`, `pause`,
    /// `seek_to_frame`, `set_volume`) — the surfaces the UI's media session and
    /// the user drive — so a disconnect is recovered on the next interaction
    /// without a dedicated poll export and without touching the realtime thread
    /// (the reopen runs on the control thread; the error callback only flips an
    /// atomic flag). If the reopen itself fails, `Session::reopen_failed` latches
    /// so this does not loop-reopen on every call, and the error is surfaced.
    fn service_disconnect(&mut self) -> Result<(), PlaybackError> {
        let (disconnected, has_session, already_failed) = match self.session.as_ref() {
            Some(session) => (
                session.output.is_disconnected(),
                true,
                session.reopen_failed,
            ),
            None => (false, false, false),
        };

        if !should_reopen_after_disconnect(disconnected, has_session, already_failed, self.state) {
            return Ok(());
        }

        // Preserve position + play/pause across the rebuild. `reopen_at_frame`
        // re-wires volume (via `output.set_volume(self.volume)`) and EQ (via the
        // shared `self.equalizer_gains`) exactly like a seek.
        let target_frame = self.current_frame().unwrap_or(0);
        let session = self.session.as_ref().expect("session present");
        let path = session.path.clone();
        let media_info = session.media_info.clone();
        let was_playing = self.state == PlaybackState::Playing;
        let was_paused = self.state == PlaybackState::Paused;

        match self.reopen_at_frame(path, media_info, target_frame, was_playing, was_paused) {
            Ok(()) => Ok(()),
            Err(err) => {
                // Back off: tear down to a clean Stopped state and latch the
                // failure so we do not loop-reopen. Surface the error.
                let _ = self.stop_internal();
                if let Some(session) = self.session.as_mut() {
                    session.reopen_failed = true;
                }
                Err(err)
            }
        }
    }

    pub fn play(&mut self) -> Result<(), PlaybackError> {
        self.service_disconnect()?;

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

    /// Ring size for one session: the configured capacity, grown so it always
    /// holds at least `MIN_RING_SECONDS` of audio at the OUTPUT rate.
    fn ring_capacity_for(&self, output_sample_rate: u32, channels: impl Into<u64>) -> usize {
        const MIN_RING_SECONDS: u64 = 3;
        let needed = output_sample_rate as u64 * channels.into() * MIN_RING_SECONDS;
        self.ring_capacity_samples.max(needed as usize)
    }

    pub fn pause(&mut self) -> Result<(), PlaybackError> {
        self.service_disconnect()?;

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

        // Any failure from here on has already torn down (part of) the old
        // session; drop to a clean Stopped state so the next load works.
        let result = self.reopen_at_frame(path, media_info, target_frame, was_playing, was_paused);
        if result.is_err() {
            let _ = self.stop_internal();
        }
        result
    }

    fn reopen_at_frame(
        &mut self,
        path: PathBuf,
        media_info: MediaInfo,
        target_frame: u64,
        was_playing: bool,
        was_paused: bool,
    ) -> Result<(), PlaybackError> {
        self.stop_output_and_decoder()?;
        self.session = None;

        let (_source_sample_rate, source_channels, source_bits) = source_format(&media_info)?;

        let requested_rate = media_info.format.sample_rate;

        let ring_config =
            PcmRingConfig::new(self.ring_capacity_for(requested_rate, source_channels));

        let (mut producer, consumer) = pcm_ring_buffer(ring_config);

        let output = PcmOutput::open_with_equalizer(
            consumer,
            requested_rate,
            source_channels,
            source_bits,
            Some(Arc::clone(&self.equalizer_gains)),
        )?;
        output.set_hardware_volume(self.hardware_volume);
        output.set_bit_perfect_mode(self.bit_perfect_mode);
        if self.bit_perfect_mode && output.is_usb_dac() {
            output.set_software_volume(1.0);
        } else {
            output.set_software_volume(self.effective_volume());
        }
        let track_gain_db = self.session.as_ref().and_then(|s| s.track_gain_db);
        let output_sample_rate = output.sample_rate();

        let cancel = Arc::new(AtomicBool::new(false));

        // Playing resumes immediately; Paused and Loaded remain stopped.
        let paused = Arc::new(AtomicBool::new(!was_playing));

        let worker_cancel = Arc::clone(&cancel);
        let worker_paused = Arc::clone(&paused);
        let worker_path = path.clone();

        let decoder_thread = thread::Builder::new()
            .name("offline-player-decoder".to_string())
            .spawn(move || {
                let result = stream_to_pcm_i32_from_frame_at_rate(
                    &worker_path,
                    target_frame,
                    &mut producer,
                    &worker_cancel,
                    &worker_paused,
                    Some(output_sample_rate),
                )
                .map(|(_actual_start_frame, stats)| stats);

                DecoderWorkerResult { result }
            })
            .map_err(|_| PlaybackError::DecoderWorkerStart)?;

        self.session = Some(Session {
            path,
            media_info,
            track_gain_db,
            cancel,
            paused,
            decoder_thread: Some(decoder_thread),
            output,
            running: false,
            position_base_frame: target_frame,
            underrun_at_decoder_end: AtomicU64::new(u64::MAX),
            output_sample_rate,
            reopen_failed: false,
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

        // Stop AAudio first so the realtime callback stops consuming the old
        // ring before teardown.
        if session.running {
            session.output.stop()?;
            session.running = false;
        }

        // Cancel the decoder and wake it if it was paused.
        session.cancel.store(true, Ordering::Release);
        session.paused.store(false, Ordering::Release);

        // Join only from the non-realtime control thread.
        if let Some(handle) = session.decoder_thread.take() {
            let worker = handle
                .join()
                .map_err(|_| PlaybackError::DecoderWorkerPanic)?;

            match worker.result {
                Ok(_) | Err(StreamError::Cancelled) => {}
                Err(err) => {
                    eprintln!("[AndroidPlaybackController] Previous decoder worker ended with: {err}");
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

impl Drop for PlaybackController {
    fn drop(&mut self) {
        let _ = self.stop_internal();
    }
}

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
