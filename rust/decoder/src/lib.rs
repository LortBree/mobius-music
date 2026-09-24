use std::{
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, RwLock,
    },
    thread,
};

use offline_player_audio_core::{
    EqualizerSettings, GraphicEqualizer, LinearResampler, PcmProducer, PcmRingError, ResamplerError,
};

use symphonia::core::{
    audio::{Audio, GenericAudioBufferRef},
    codecs::audio::AudioDecoderOptions,
    errors::Error as SymphoniaError,
    formats::{probe::Hint, FormatOptions, SeekMode, SeekTo, TrackType},
    io::MediaSourceStream,
    meta::MetadataOptions,
    units::Timestamp,
};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ProbeError {
    #[error("failed to open file: {0}")]
    Io(#[from] std::io::Error),

    #[error("unsupported or unrecognized media: {0}")]
    Symphonia(#[from] SymphoniaError),

    #[error("no audio track found")]
    NoAudioTrack,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SampleFormat {
    SignedInt(u16),
    Float(u16),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AudioFormat {
    pub sample_rate: u32,
    pub channels: u32,
    pub sample_format: SampleFormat,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaInfo {
    pub path: PathBuf,
    pub codec: String,
    pub format: AudioFormat,
    pub total_frames: Option<u64>,
}

impl MediaInfo {
    /// Presentation-layer convenience only.
    ///
    /// Internal playback positioning remains frame-based.
    pub fn duration_seconds(&self) -> Option<f64> {
        self.total_frames
            .zip((self.format.sample_rate > 0).then_some(self.format.sample_rate))
            .map(|(frames, rate)| frames as f64 / rate as f64)
    }
}

pub fn probe(path: &Path) -> Result<MediaInfo, ProbeError> {
    let file = std::fs::File::open(path)?;

    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();

    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe().probe(
        &hint,
        mss,
        FormatOptions::default(),
        MetadataOptions::default(),
    )?;

    let track = probed
        .default_track(TrackType::Audio)
        .ok_or(ProbeError::NoAudioTrack)?;

    let params = track
        .codec_params
        .as_ref()
        .and_then(|params| params.audio())
        .ok_or(ProbeError::NoAudioTrack)?;

    let sample_rate = params.sample_rate.unwrap_or(0);

    let channels = params
        .channels
        .as_ref()
        .map(|channels| channels.count() as u32)
        .unwrap_or(0);

    let codec = format!("{:?}", params.codec);

    let total_frames = track.num_frames;

    let sample_format = match params.bits_per_sample {
        Some(bits) => SampleFormat::SignedInt(bits as u16),
        None => SampleFormat::SignedInt(0),
    };

    Ok(MediaInfo {
        path: path.to_path_buf(),
        codec,
        format: AudioFormat {
            sample_rate,
            channels,
            sample_format,
        },
        total_frames,
    })
}

#[derive(Debug, Error)]
pub enum StreamError {
    #[error("failed to open file: {0}")]
    Io(#[from] std::io::Error),

    #[error("unsupported or unrecognized media: {0}")]
    Symphonia(#[from] SymphoniaError),

    #[error("no audio track found")]
    NoAudioTrack,

    #[error("missing sample rate")]
    MissingSampleRate,

    #[error("missing channel configuration")]
    MissingChannels,

    #[error("decoder creation failed: {0}")]
    DecoderCreation(String),

    #[error("decode error: {0}")]
    Decode(String),

    #[error("decoder reset required")]
    ResetRequired,

    #[error("unsupported PCM format for i32 streaming: {0}")]
    UnsupportedPcmFormat(&'static str),

    #[error("invalid output sample rate")]
    InvalidOutputSampleRate,

    #[error("resampler error: {0}")]
    Resampler(ResamplerError),

    #[error("seek timestamp overflow for frame {0}")]
    SeekTimestampOverflow(u64),

    #[error("seek returned a negative timestamp: {0}")]
    NegativeSeekTimestamp(i64),

    #[error("seek target {0} is past the end of the stream")]
    SeekPastEnd(u64),

    #[error("decoder streaming cancelled")]
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StreamStats {
    pub sample_rate: u32,
    pub channels: usize,
    pub decoded_frames: u64,
    pub pushed_samples: u64,
}

impl StreamStats {
    pub fn pushed_frames(&self) -> u64 {
        if self.channels == 0 {
            return 0;
        }

        self.pushed_samples / self.channels as u64
    }
}

/// Decode the complete file and push interleaved integer PCM into
/// the supplied SPSC producer.
pub fn stream_to_pcm_i32(
    path: &Path,
    producer: &mut PcmProducer,
) -> Result<StreamStats, StreamError> {
    let cancel = Arc::new(AtomicBool::new(false));
    let paused = Arc::new(AtomicBool::new(false));

    stream_to_pcm_i32_controlled(path, producer, &cancel, &paused)
}

/// Controlled full-file decode.
///
/// The decoder checks `cancel` and `paused` between output
/// operations. The realtime consumer is never called from here.
pub fn stream_to_pcm_i32_controlled(
    path: &Path,
    producer: &mut PcmProducer,
    cancel: &AtomicBool,
    paused: &AtomicBool,
) -> Result<StreamStats, StreamError> {
    stream_to_pcm_i32_controlled_at_rate(path, producer, cancel, paused, None)
}

/// Controlled full-file decode with an optional output sample rate.
///
/// When `target_sample_rate` differs from the source rate, resampling happens
/// on the decoder worker before PCM enters the realtime ring buffer.
pub fn stream_to_pcm_i32_controlled_at_rate(
    path: &Path,
    producer: &mut PcmProducer,
    cancel: &AtomicBool,
    paused: &AtomicBool,
    target_sample_rate: Option<u32>,
) -> Result<StreamStats, StreamError> {
    let (_actual_start_frame, stats) = stream_internal(
        path,
        producer,
        cancel,
        paused,
        None,
        target_sample_rate,
        None,
    )?;

    Ok(stats)
}

pub fn stream_to_pcm_i32_controlled_at_rate_with_equalizer(
    path: &Path,
    producer: &mut PcmProducer,
    cancel: &AtomicBool,
    paused: &AtomicBool,
    target_sample_rate: Option<u32>,
    gains_db: Arc<RwLock<[f32; 10]>>,
) -> Result<StreamStats, StreamError> {
    let (_actual_start_frame, stats) = stream_internal(
        path,
        producer,
        cancel,
        paused,
        None,
        target_sample_rate,
        Some(gains_db),
    )?;
    Ok(stats)
}

/// Decode from a requested frame.
///
/// Symphonia performs the coarse seek. The decoder then discards
/// samples inside the first decoded buffer until the exact requested
/// frame is reached.
///
/// Returns:
/// - actual_start_frame: the timestamp/frame where Symphonia landed
/// - StreamStats: decode/push statistics after the seek
pub fn stream_to_pcm_i32_from_frame(
    path: &Path,
    target_frame: u64,
    producer: &mut PcmProducer,
    cancel: &AtomicBool,
    paused: &AtomicBool,
) -> Result<(u64, StreamStats), StreamError> {
    stream_to_pcm_i32_from_frame_at_rate(path, target_frame, producer, cancel, paused, None)
}

/// Decode from a requested source frame with an optional output sample rate.
pub fn stream_to_pcm_i32_from_frame_at_rate(
    path: &Path,
    target_frame: u64,
    producer: &mut PcmProducer,
    cancel: &AtomicBool,
    paused: &AtomicBool,
    target_sample_rate: Option<u32>,
) -> Result<(u64, StreamStats), StreamError> {
    stream_internal(
        path,
        producer,
        cancel,
        paused,
        Some(target_frame),
        target_sample_rate,
        None,
    )
}

pub fn stream_to_pcm_i32_from_frame_at_rate_with_equalizer(
    path: &Path,
    target_frame: u64,
    producer: &mut PcmProducer,
    cancel: &AtomicBool,
    paused: &AtomicBool,
    target_sample_rate: Option<u32>,
    gains_db: Arc<RwLock<[f32; 10]>>,
) -> Result<(u64, StreamStats), StreamError> {
    stream_internal(
        path,
        producer,
        cancel,
        paused,
        Some(target_frame),
        target_sample_rate,
        Some(gains_db),
    )
}

fn stream_internal(
    path: &Path,
    producer: &mut PcmProducer,
    cancel: &AtomicBool,
    paused: &AtomicBool,
    seek_frame: Option<u64>,
    target_sample_rate: Option<u32>,
    equalizer_gains: Option<Arc<RwLock<[f32; 10]>>>,
) -> Result<(u64, StreamStats), StreamError> {
    if cancel.load(Ordering::Acquire) {
        return Err(StreamError::Cancelled);
    }

    let file = std::fs::File::open(path)?;

    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();

    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let mut format = symphonia::default::get_probe().probe(
        &hint,
        mss,
        FormatOptions::default(),
        MetadataOptions::default(),
    )?;

    let track = format
        .default_track(TrackType::Audio)
        .ok_or(StreamError::NoAudioTrack)?;

    let track_id = track.id;

    //
    // Clone codec params before performing a mutable seek.
    //
    let audio_params = track
        .codec_params
        .as_ref()
        .and_then(|params| params.audio())
        .ok_or(StreamError::NoAudioTrack)?
        .clone();

    let sample_rate = audio_params
        .sample_rate
        .ok_or(StreamError::MissingSampleRate)?;

    let channels = audio_params
        .channels
        .as_ref()
        .ok_or(StreamError::MissingChannels)?
        .count();

    if channels == 0 {
        return Err(StreamError::MissingChannels);
    }

    let source_bits = audio_params.bits_per_sample.unwrap_or(32) as u32;

    let output_sample_rate = target_sample_rate.unwrap_or(sample_rate);

    if output_sample_rate == 0 {
        return Err(StreamError::InvalidOutputSampleRate);
    }

    let mut resampler = if output_sample_rate != sample_rate {
        Some(
            LinearResampler::new(sample_rate, output_sample_rate, channels)
                .map_err(StreamError::Resampler)?,
        )
    } else {
        None
    };
    let mut equalizer = equalizer_gains
        .as_ref()
        .map(|_| GraphicEqualizer::new(output_sample_rate, channels, source_bits));

    let decoder_options = AudioDecoderOptions::default().gapless(true).verify(true);

    let mut decoder = symphonia::default::get_codecs()
        .make_audio_decoder(&audio_params, &decoder_options)
        .map_err(|err| StreamError::DecoderCreation(err.to_string()))?;

    let actual_start_frame;

    if let Some(target_frame) = seek_frame {
        //
        // Validate against container metadata when available.
        //
        if let Some(total_frames) = track.num_frames {
            if target_frame > total_frames {
                return Err(StreamError::SeekPastEnd(target_frame));
            }

            //
            // Seeking exactly to EOF does not require asking Symphonia
            // to seek/decode. There are no PCM frames to produce.
            //
            if target_frame == total_frames {
                return Ok((
                    total_frames,
                    StreamStats {
                        sample_rate,
                        channels,
                        decoded_frames: 0,
                        pushed_samples: 0,
                    },
                ));
            }
        }

        let target_ts_value = i64::try_from(target_frame)
            .map_err(|_| StreamError::SeekTimestampOverflow(target_frame))?;

        let target_ts = Timestamp::new(target_ts_value);

        let seeked_to = format
            .seek(
                SeekMode::Accurate,
                SeekTo::Timestamp {
                    ts: target_ts,
                    track_id,
                },
            )
            .map_err(StreamError::Symphonia)?;

        let actual_ts = seeked_to.actual_ts;
        let actual_value = actual_ts.get();

        if actual_value < 0 {
            return Err(StreamError::NegativeSeekTimestamp(actual_value));
        }

        actual_start_frame = actual_value as u64;

        //
        // Seeking invalidates decoder state.
        //
        decoder.reset();
    } else {
        actual_start_frame = 0;
    }

    let mut stream_frame = actual_start_frame;

    let mut decoded_frames = 0u64;
    let mut pushed_samples = 0u64;

    loop {
        if cancel.load(Ordering::Acquire) {
            return Err(StreamError::Cancelled);
        }

        wait_while_paused(cancel, paused)?;

        let packet = match format.next_packet() {
            Ok(Some(packet)) => packet,

            Ok(None) => break,

            Err(SymphoniaError::ResetRequired) => {
                return Err(StreamError::ResetRequired);
            }

            Err(SymphoniaError::IoError(err))
                if err.kind() == std::io::ErrorKind::UnexpectedEof =>
            {
                break;
            }

            Err(SymphoniaError::IoError(err)) => {
                return Err(StreamError::Io(err));
            }

            Err(err) => {
                return Err(StreamError::Symphonia(err));
            }
        };

        if packet.track_id != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(buffer) => buffer,

            Err(SymphoniaError::DecodeError(err)) => {
                return Err(StreamError::Decode(err.to_string()));
            }

            Err(SymphoniaError::IoError(err)) => {
                return Err(StreamError::Io(err));
            }

            Err(SymphoniaError::ResetRequired) => {
                return Err(StreamError::ResetRequired);
            }

            Err(err) => {
                eprintln!("DECODER decode() error variant: {:?}", err);
                return Err(StreamError::Symphonia(err));
            }
        };

        let buffer_frames = decoded.frames() as u64;

        decoded_frames = decoded_frames.saturating_add(buffer_frames);

        //
        // Seek alignment:
        //
        // Symphonia can land before the exact requested frame.
        // We discard only the prefix necessary to reach target.
        //
        // IMPORTANT:
        // stream_frame advances by the ENTIRE decoded buffer,
        // not only by the discarded prefix.
        //
        let mut source_samples = Vec::with_capacity(decoded.frames() * channels);
        decode_buffer_to_i32(decoded, source_bits, &mut source_samples)?;

        let samples_to_skip = if let Some(target_frame) = seek_frame {
            if stream_frame < target_frame {
                let frames_to_skip = (target_frame - stream_frame).min(buffer_frames);
                frames_to_skip.saturating_mul(channels as u64) as usize
            } else {
                0
            }
        } else {
            0
        };

        let samples_to_skip = samples_to_skip.min(source_samples.len());
        if samples_to_skip > 0 {
            source_samples.copy_within(samples_to_skip.., 0);
            source_samples.truncate(source_samples.len() - samples_to_skip);
        }

        if let Some(resampler) = resampler.as_mut() {
            let mut output_samples = Vec::with_capacity(
                ((source_samples.len() / channels) as f64 * output_sample_rate as f64
                    / sample_rate as f64)
                    .ceil() as usize
                    * channels,
            );

            resampler
                .process(&source_samples, &mut output_samples)
                .map_err(StreamError::Resampler)?;

            if let (Some(equalizer), Some(gains)) = (equalizer.as_mut(), equalizer_gains.as_ref()) {
                let gains_db = *gains.read().unwrap_or_else(|error| error.into_inner());
                equalizer.process(&mut output_samples, EqualizerSettings { gains_db });
            }

            pushed_samples += push_samples_controlled(producer, &output_samples, cancel, paused)?;
        } else if let (Some(equalizer), Some(gains)) =
            (equalizer.as_mut(), equalizer_gains.as_ref())
        {
            let mut output_samples = source_samples;
            let gains_db = *gains.read().unwrap_or_else(|error| error.into_inner());
            equalizer.process(&mut output_samples, EqualizerSettings { gains_db });
            pushed_samples += push_samples_controlled(producer, &output_samples, cancel, paused)?;
        } else {
            pushed_samples += push_samples_controlled(producer, &source_samples, cancel, paused)?;
        }

        stream_frame = stream_frame.saturating_add(buffer_frames);
    }

    if let Some(resampler) = resampler.as_mut() {
        let mut output_samples = Vec::new();
        resampler
            .flush(&mut output_samples)
            .map_err(StreamError::Resampler)?;

        if let (Some(equalizer), Some(gains)) = (equalizer.as_mut(), equalizer_gains.as_ref()) {
            let gains_db = *gains.read().unwrap_or_else(|error| error.into_inner());
            equalizer.process(&mut output_samples, EqualizerSettings { gains_db });
        }

        pushed_samples += push_samples_controlled(producer, &output_samples, cancel, paused)?;
    }

    //
    // Symphonia 0.6.1 returns FinalizeResult directly.
    //
    let _finalize_result = decoder.finalize();

    Ok((
        actual_start_frame,
        StreamStats {
            sample_rate,
            channels,
            decoded_frames,
            pushed_samples,
        },
    ))
}

fn wait_while_paused(cancel: &AtomicBool, paused: &AtomicBool) -> Result<(), StreamError> {
    while paused.load(Ordering::Acquire) {
        if cancel.load(Ordering::Acquire) {
            return Err(StreamError::Cancelled);
        }

        thread::yield_now();
    }

    if cancel.load(Ordering::Acquire) {
        return Err(StreamError::Cancelled);
    }

    Ok(())
}

fn decode_buffer_to_i32(
    buffer: GenericAudioBufferRef<'_>,
    source_bits: u32,
    out: &mut Vec<i32>,
) -> Result<(), StreamError> {
    macro_rules! extend_iter {
        ($iter:expr) => {{
            out.extend($iter);
        }};
    }

    match buffer {
        GenericAudioBufferRef::S8(buf) => {
            extend_iter!(buf.iter_interleaved().map(|sample| sample as i32));
        }

        GenericAudioBufferRef::S16(buf) => {
            extend_iter!(buf.iter_interleaved().map(|sample| sample as i32));
        }

        GenericAudioBufferRef::S24(buf) => {
            extend_iter!(buf.iter_interleaved().map(|sample| sample.inner()));
        }

        GenericAudioBufferRef::S32(buf) => {
            let shift = 32u32.saturating_sub(source_bits);

            extend_iter!(buf.iter_interleaved().map(|sample| {
                if shift == 0 {
                    sample
                } else {
                    sample >> shift
                }
            }));
        }

        GenericAudioBufferRef::U8(buf) => {
            extend_iter!(buf.iter_interleaved().map(|sample| sample as i32));
        }

        GenericAudioBufferRef::U16(buf) => {
            extend_iter!(buf.iter_interleaved().map(|sample| sample as i32));
        }

        GenericAudioBufferRef::U24(buf) => {
            extend_iter!(buf.iter_interleaved().map(|sample| sample.inner() as i32));
        }

        GenericAudioBufferRef::U32(buf) => {
            extend_iter!(buf.iter_interleaved().map(|sample| sample as i32));
        }

        GenericAudioBufferRef::F32(_) => {
            return Err(StreamError::UnsupportedPcmFormat("f32"));
        }

        GenericAudioBufferRef::F64(_) => {
            return Err(StreamError::UnsupportedPcmFormat("f64"));
        }
    }

    Ok(())
}

fn push_samples_controlled(
    producer: &mut PcmProducer,
    samples: &[i32],
    cancel: &AtomicBool,
    paused: &AtomicBool,
) -> Result<u64, StreamError> {
    let mut pushed = 0u64;

    for &sample in samples {
        wait_while_paused(cancel, paused)?;
        push_sample(producer, sample, cancel)?;
        pushed += 1;
    }

    Ok(pushed)
}

/// Push one integer PCM sample.
///
/// The producer side may yield while the SPSC ring is full.
/// The realtime consumer never blocks here.
#[inline]
fn push_sample(
    producer: &mut PcmProducer,
    sample: i32,
    cancel: &AtomicBool,
) -> Result<(), StreamError> {
    loop {
        if cancel.load(Ordering::Acquire) {
            return Err(StreamError::Cancelled);
        }

        match producer.try_push(sample) {
            Ok(()) => return Ok(()),

            Err(PcmRingError::Full) => {
                thread::yield_now();
            }

            Err(PcmRingError::Empty) => {
                unreachable!("producer cannot report Empty");
            }

            Err(PcmRingError::InvalidLength) => {
                unreachable!(
                    "single-sample push cannot \
                     have invalid length"
                );
            }
        }
    }
}
