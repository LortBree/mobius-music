use std::{
    env,
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
};

use offline_player_audio_core::{pcm_ring_buffer, PcmRingConfig};
use offline_player_decoder::stream_to_pcm_i32_controlled_at_rate;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = env::args();

    let _program = args.next();

    let path = args
        .next()
        .ok_or("usage: resample <path-to-audio-file> <output-rate>")?;

    let output_rate: u32 = args
        .next()
        .ok_or("usage: resample <path-to-audio-file> <output-rate>")?
        .parse()
        .map_err(|_| "output rate must be a positive integer")?;

    if output_rate == 0 {
        return Err("output rate must be greater than zero".into());
    }

    let path = Path::new(&path);

    let config = PcmRingConfig::new(384_000);

    let (mut producer, mut consumer) = pcm_ring_buffer(config);

    let cancel = Arc::new(AtomicBool::new(false));
    let paused = Arc::new(AtomicBool::new(false));

    let producer_cancel = Arc::clone(&cancel);
    let producer_paused = Arc::clone(&paused);
    let producer_path = path.to_path_buf();

    let producer_thread = thread::spawn(move || {
        stream_to_pcm_i32_controlled_at_rate(
            &producer_path,
            &mut producer,
            &producer_cancel,
            &producer_paused,
            Some(output_rate),
        )
    });

    let mut consumed_samples = 0u64;

    loop {
        match consumer.try_pop() {
            Ok(_sample) => {
                consumed_samples += 1;
            }

            Err(offline_player_audio_core::PcmRingError::Empty) => {
                if producer_thread.is_finished() && consumer.is_empty() {
                    break;
                }

                thread::yield_now();
            }

            Err(err) => {
                cancel.store(true, Ordering::Release);

                return Err(format!("consumer error: {err}").into());
            }
        }
    }

    let stats = producer_thread
        .join()
        .map_err(|_| "decoder thread panicked")??;

    let source_rate = stats.sample_rate;

    println!("File           : {}", path.display());
    println!("Source rate    : {} Hz", source_rate);
    println!("Output rate    : {} Hz", output_rate);
    println!("Channels       : {}", stats.channels);
    println!("Decoded frames : {}", stats.decoded_frames);
    println!("Pushed samples : {}", stats.pushed_samples);
    println!("Pushed frames  : {}", stats.pushed_frames());
    println!("Consumed       : {} samples", consumed_samples);

    let transfer_ok = consumed_samples == stats.pushed_samples;

    println!("Transfer OK    : {}", transfer_ok);

    if source_rate == output_rate {
        println!("Resampling     : not required (native rate)");
    } else {
        println!("Resampling     : {} Hz -> {} Hz", source_rate, output_rate);

        let expected_frames =
            ((stats.decoded_frames as u128 * output_rate as u128) / source_rate as u128) as u64;

        let actual_frames = stats.pushed_frames();

        println!("Expected frames: ~{}", expected_frames);
        println!("Actual frames  : {}", actual_frames);

        let difference = actual_frames.abs_diff(expected_frames);

        println!("Frame diff     : {}", difference);

        if difference > 1 {
            return Err(format!(
                "unexpected resampled frame count: expected ~{}, got {}",
                expected_frames, actual_frames
            )
            .into());
        }
    }

    if !transfer_ok {
        return Err("PCM transfer mismatch".into());
    }

    println!();
    println!("RESAMPLE TEST  : PASS");

    Ok(())
}
