use std::{env, path::Path, thread};

use offline_player_audio_core::{pcm_ring_buffer, PcmRingConfig};

use offline_player_decoder::stream_to_pcm_i32;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = env::args()
        .nth(1)
        .ok_or("usage: stream <path-to-audio-file>")?;

    let path = Path::new(&path);

    //
    // 2 seconds of stereo 96 kHz PCM.
    //
    // 96_000 frames * 2 channels * 2 seconds
    // = 384_000 i32 samples.
    //
    let config = PcmRingConfig::new(384_000);

    let (mut producer, mut consumer) = pcm_ring_buffer(config);

    let producer_path = path.to_path_buf();

    let producer_thread = thread::spawn(move || stream_to_pcm_i32(&producer_path, &mut producer));

    //
    // Consume the PCM on this thread.
    //
    // M1.5.2 only verifies that the producer can continuously
    // decode and transfer PCM through the SPSC ring.
    //
    // We intentionally do not send the samples to CoreAudio yet.
    //
    let mut consumed_samples = 0u64;

    loop {
        match consumer.try_pop() {
            Ok(_sample) => {
                consumed_samples += 1;
            }

            Err(offline_player_audio_core::PcmRingError::Empty) => {
                if producer_thread.is_finished() {
                    if consumer.is_empty() {
                        break;
                    }
                }

                thread::yield_now();
            }

            Err(err) => {
                return Err(format!("consumer error: {err}").into());
            }
        }
    }

    let stats = producer_thread
        .join()
        .map_err(|_| "decoder thread panicked")??;

    println!("File           : {}", path.display());

    println!("Sample rate    : {} Hz", stats.sample_rate);

    println!("Channels       : {}", stats.channels);

    println!("Decoded frames : {}", stats.decoded_frames);

    println!("Pushed samples : {}", stats.pushed_samples);

    println!("Pushed frames  : {}", stats.pushed_frames());

    println!("Consumed       : {} samples", consumed_samples);

    println!(
        "Transfer OK    : {}",
        consumed_samples == stats.pushed_samples
    );

    Ok(())
}
