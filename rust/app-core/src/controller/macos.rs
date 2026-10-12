use std::{
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc,
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

use offline_player_audio_core::{pcm_ring_buffer, PcmRingConfig, SharedEqualizerGains};
use offline_player_decoder::{
    probe, stream_to_pcm_i32_controlled_at_rate, stream_to_pcm_i32_from_frame_at_rate, AudioFormat,
    MediaInfo, SampleFormat, StreamError, StreamStats,
};
use offline_player_platform_macos::{
    default_output_device, output_format, output_virtual_format, set_nominal_sample_rate,
    supported_virtual_sample_rates, PcmOutput, PlaybackTelemetry,
};

use crate::{
    OutputPlan, PlaybackError, PlaybackOutputMode, PlaybackState,
    SignalPathSnapshot, EQUALIZER_ACTIVE_EPSILON_DB, EQUALIZER_BAND_COUNT,
};

const OUTPUT_RATE_SETTLE_TIMEOUT: Duration = Duration::from_millis(1500);
const OUTPUT_RATE_POLL_INTERVAL: Duration = Duration::from_millis(25);

#[derive(Debug)]
struct DecoderWorkerResult {
    result: Result<StreamStats, StreamError>,
}

struct Session {
    path: PathBuf,
    media_info: MediaInfo,
    track_gain_db: Option<f32>,
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

    //
    // Output underrun count at the moment the decoder was first seen to have
    // finished (u64::MAX until then). See `played_output_samples`.
    //
    underrun_at_decoder_end: AtomicU64,
}

impl Session {
    /// Output samples that actually carried audio for the playback clock.
    ///
    /// Silence the device plays because the decoder fell behind (a stall on
    /// a slow disk, the first few milliseconds after start) is not playback:
    /// counting it made the position run ahead of the audio and could even
    /// reach end-of-track early. Silence after the decoder has finished is
    /// the tail of the track draining out, and it must count, or the clock
    /// never reaches the end and auto-advance never fires.
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

    /// The sample rate the current session actually negotiated with the output
    /// device, or `None` when nothing is loaded. This is the ground truth for
    /// whether playback is bit-perfect (equals the source rate) or resampled.
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
        self.volume = volume.clamp(0.0, 1.0);
        if let Some(session) = self.session.as_ref() {
            session.output.set_volume(self.effective_volume());
        }
    }

    pub fn set_software_volume(&mut self, volume: f32) {
        self.set_volume(volume);
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
        if let Some(session) = self.session.as_ref() {
            session.output.set_volume(self.effective_volume());
        }
    }

    pub fn volume_normalization(&self) -> bool {
        self.volume_normalization
    }

    pub fn set_volume_normalization(&mut self, enabled: bool) {
        self.volume_normalization = enabled;
        if let Some(session) = self.session.as_ref() {
            session.output.set_volume(self.effective_volume());
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
        Ok(())
    }

    pub fn equalizer_gains(&self) -> [f32; 10] {
        self.equalizer_gains.get()
    }

    pub fn set_equalizer_gains(&mut self, gains_db: [f32; 10]) {
        // Lock-free: the output callback picks it up within one I/O buffer.
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

    pub fn telemetry(&self) -> Option<PlaybackTelemetry> {
        self.session
            .as_ref()
            .map(|session| session.output.telemetry())
    }

    /// Engine-side signal-path snapshot for the loaded track, or `None` when
    /// nothing is loaded. CoreAudio float output; `bit_perfect` is reported
    /// conservatively (rate matches source AND no resampling AND EQ inactive
    /// AND volume effectively unity).
    pub fn signal_path(&self) -> Option<SignalPathSnapshot> {
        let session = self.session.as_ref()?;

        let source_rate = session.media_info.format.sample_rate;
        let output_rate = session.output_sample_rate;
        let resampling = output_rate != 0 && source_rate != 0 && output_rate != source_rate;

        let gains = self.equalizer_gains.get();
        let equalizer_active = gains
            .iter()
            .any(|gain| gain.abs() > EQUALIZER_ACTIVE_EPSILON_DB);

        let effective_vol = self.effective_volume();

        // Conservative: any doubt about the chain reports non-bit-perfect.
        let bit_perfect = output_rate != 0
            && source_rate != 0
            && output_rate == source_rate
            && !resampling
            && !equalizer_active
            && effective_vol >= 0.999
            && self.is_bit_perfect_mode();
        let telemetry = session.output.telemetry();

        // macOS opens the output at the source channel count (no channel
        // remix), so output channels == source channels.
        let channels = session.media_info.format.channels;

        Some(SignalPathSnapshot {
            output_sample_rate: output_rate,
            output_channels: channels,
            output_bits_per_sample: 32,
            output_is_float: true,
            resampling,
            equalizer_active,
            bit_perfect,
            equalizer_bands: EQUALIZER_BAND_COUNT,
            volume: self.volume,
            // macOS: ring fill is not surfaced by CoreAudio PcmOutput; reported
            // as 0 rather than guessed. The shipping Android path reports a real
            // value from the AAudio ring consumer.
            buffer_ms: 0,
            underrun_samples: telemetry.underrun_samples,
            callback_count: telemetry.callback_count,
            output_api: "CoreAudio",
            device_name: String::new(),
        })
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

        let ring_config =
            PcmRingConfig::new(self.ring_capacity_for(output_sample_rate, source_channels));

        let (mut producer, consumer) = pcm_ring_buffer(ring_config);

        let output = PcmOutput::open_with_equalizer(
            device_id,
            consumer,
            output_sample_rate,
            source_channels,
            source_bits,
            Some(Arc::clone(&self.equalizer_gains)),
        )?;
        output.set_volume(self.effective_volume());
        let track_gain_db = offline_player_metadata::read(&path)
            .ok()
            .and_then(|m| m.track_gain_db);

        let cancel = Arc::new(AtomicBool::new(false));

        //
        // Loaded state starts paused.
        //
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

    /// Ring size for one session: the configured capacity, grown so it always
    /// holds at least `MIN_RING_SECONDS` of audio at the OUTPUT rate. A fixed
    /// 262,144-sample ring is ~3 s at 44.1 kHz stereo but only ~0.34 s at
    /// 384 kHz, which would leave little margin against decoder stalls.
    fn ring_capacity_for(&self, output_sample_rate: u32, channels: impl Into<u64>) -> usize {
        const MIN_RING_SECONDS: u64 = 2;
        let needed = output_sample_rate as u64 * channels.into() * MIN_RING_SECONDS;
        self.ring_capacity_samples.max(needed as usize)
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
        // Any failure from here on has already torn down (part of) the old
        // session. Leaving it installed would wedge the player: a session
        // whose decoder is gone and whose output is stopped, so every later
        // play/seek acts on a dead stream. Drop to a clean Stopped state
        // instead, from which the next load works normally.
        //
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

        let ring_config =
            PcmRingConfig::new(self.ring_capacity_for(output_sample_rate, source_channels));

        let (mut producer, consumer) = pcm_ring_buffer(ring_config);

        let output = PcmOutput::open_with_equalizer(
            device_id,
            consumer,
            output_sample_rate,
            source_channels,
            source_bits,
            Some(Arc::clone(&self.equalizer_gains)),
        )?;
        output.set_volume(self.effective_volume());
        let track_gain_db = self.session.as_ref().and_then(|s| s.track_gain_db);

        let cancel = Arc::new(AtomicBool::new(false));

        //
        // Playing resumes immediately.
        // Paused and Loaded remain stopped.
        //
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
                Ok(_) | Err(StreamError::Cancelled) => {}
                Err(err) => {
                    eprintln!("[PlaybackController] Previous decoder worker ended with: {err}");
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
