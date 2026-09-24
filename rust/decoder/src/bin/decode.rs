use std::{env, fs::File, io, path::Path};

use hex::encode as hex_encode;
use sha2::{Digest, Sha256};

use symphonia::core::{
    audio::{Audio, GenericAudioBufferRef},
    codecs::audio::AudioDecoderOptions,
    errors::Error as SymphoniaError,
    formats::{probe::Hint, FormatOptions, TrackType},
    io::MediaSourceStream,
    meta::MetadataOptions,
};

use symphonia::default::{get_codecs, get_probe};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = env::args()
        .nth(1)
        .ok_or("usage: decode <path-to-audio-file>")?;

    decode_file(Path::new(&path))
}

fn decode_file(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let file = File::open(path)?;
    let file_size = file.metadata()?.len();

    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();

    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let mut format = get_probe().probe(
        &hint,
        mss,
        FormatOptions::default(),
        MetadataOptions::default(),
    )?;

    let track = format
        .default_track(TrackType::Audio)
        .ok_or("no default audio track")?;

    let track_id = track.id;
    let expected_frames = track.num_frames;

    let audio_params = track
        .codec_params
        .as_ref()
        .and_then(|params| params.audio())
        .ok_or("track has no audio codec parameters")?;

    let sample_rate = audio_params.sample_rate.ok_or("missing sample rate")?;

    let channels = audio_params
        .channels
        .as_ref()
        .ok_or("missing channel configuration")?
        .count();

    let bits_per_sample = audio_params.bits_per_sample.unwrap_or(0);

    // Symphonia's AudioDecoderOptions is non-exhaustive.
    // Use the builder methods instead of struct literal initialization.
    let decoder_options = AudioDecoderOptions::default().gapless(true).verify(true);

    let mut decoder = get_codecs().make_audio_decoder(audio_params, &decoder_options)?;

    let mut decoded_frames: u64 = 0;
    let mut decoded_samples: u64 = 0;

    let mut min_sample = i32::MAX;
    let mut max_sample = i32::MIN;

    let mut hasher = Sha256::new();

    loop {
        let packet = match format.next_packet() {
            Ok(Some(packet)) => packet,

            Ok(None) => break,

            Err(SymphoniaError::ResetRequired) => {
                return Err("decoder reset required".into());
            }

            Err(SymphoniaError::IoError(err)) if err.kind() == io::ErrorKind::UnexpectedEof => {
                break;
            }

            Err(SymphoniaError::IoError(err)) => {
                return Err(Box::new(err));
            }

            Err(err) => {
                return Err(Box::new(err));
            }
        };

        if packet.track_id != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(buffer) => buffer,

            Err(SymphoniaError::DecodeError(err)) => {
                return Err(format!("decode error: {err}").into());
            }

            Err(SymphoniaError::IoError(err)) => {
                return Err(Box::new(err));
            }

            Err(SymphoniaError::ResetRequired) => {
                return Err("decoder reset required".into());
            }

            Err(err) => {
                return Err(Box::new(err));
            }
        };

        update_stats(
            decoded,
            &mut decoded_frames,
            &mut decoded_samples,
            &mut min_sample,
            &mut max_sample,
            &mut hasher,
        );
    }

    let finalize_result = decoder.finalize();

    let digest = hasher.finalize();

    let frame_count_ok = expected_frames
        .map(|expected| expected == decoded_frames)
        .unwrap_or(false);

    let duration_seconds = decoded_frames as f64 / sample_rate as f64;

    println!("File            : {}", path.display());
    println!("File size       : {} bytes", file_size);
    println!("Sample rate     : {} Hz", sample_rate);
    println!("Channels        : {}", channels);
    println!("Bit depth       : {} bit", bits_per_sample);
    println!("Expected frames : {:?}", expected_frames);
    println!("Decoded frames  : {}", decoded_frames);
    println!("Decoded samples : {}", decoded_samples);
    println!("Frame count OK  : {}", frame_count_ok);
    println!("PCM min (i32)   : {}", min_sample);
    println!("PCM max (i32)   : {}", max_sample);
    println!("Duration        : {:.6} s", duration_seconds);
    println!("PCM SHA-256     : {}", hex_encode(digest));
    println!("Finalize        : {:?}", finalize_result);

    Ok(())
}

fn update_stats(
    buffer: GenericAudioBufferRef<'_>,
    decoded_frames: &mut u64,
    decoded_samples: &mut u64,
    min_sample: &mut i32,
    max_sample: &mut i32,
    hasher: &mut Sha256,
) {
    *decoded_frames += buffer.frames() as u64;

    *decoded_samples += (buffer.frames() * buffer.spec().channels().count()) as u64;

    match buffer {
        GenericAudioBufferRef::S8(buf) => {
            for sample in buf.iter_interleaved() {
                let value = sample as i32;

                update_integer_sample(value, min_sample, max_sample, hasher);
            }
        }

        GenericAudioBufferRef::S16(buf) => {
            for sample in buf.iter_interleaved() {
                let value = sample as i32;

                update_integer_sample(value, min_sample, max_sample, hasher);
            }
        }

        GenericAudioBufferRef::S24(buf) => {
            for sample in buf.iter_interleaved() {
                let value = sample.inner();

                update_integer_sample(value, min_sample, max_sample, hasher);
            }
        }

        GenericAudioBufferRef::S32(buf) => {
            for sample in buf.iter_interleaved() {
                update_integer_sample(sample, min_sample, max_sample, hasher);
            }
        }

        GenericAudioBufferRef::U8(buf) => {
            for sample in buf.iter_interleaved() {
                let value = sample as i32;

                update_integer_sample(value, min_sample, max_sample, hasher);
            }
        }

        GenericAudioBufferRef::U16(buf) => {
            for sample in buf.iter_interleaved() {
                let value = sample as i32;

                update_integer_sample(value, min_sample, max_sample, hasher);
            }
        }

        GenericAudioBufferRef::U24(buf) => {
            for sample in buf.iter_interleaved() {
                let value = sample.inner() as i32;

                update_integer_sample(value, min_sample, max_sample, hasher);
            }
        }

        GenericAudioBufferRef::U32(buf) => {
            for sample in buf.iter_interleaved() {
                let value = sample as i32;

                update_integer_sample(value, min_sample, max_sample, hasher);
            }
        }

        GenericAudioBufferRef::F32(buf) => {
            for sample in buf.iter_interleaved() {
                hasher.update(sample.to_bits().to_le_bytes());
            }
        }

        GenericAudioBufferRef::F64(buf) => {
            for sample in buf.iter_interleaved() {
                hasher.update(sample.to_bits().to_le_bytes());
            }
        }
    }
}

fn update_integer_sample(
    value: i32,
    min_sample: &mut i32,
    max_sample: &mut i32,
    hasher: &mut Sha256,
) {
    *min_sample = (*min_sample).min(value);
    *max_sample = (*max_sample).max(value);

    hasher.update(value.to_le_bytes());
}
