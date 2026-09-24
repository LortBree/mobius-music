use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::Instant,
};

use offline_player_audio_core::{pcm_ring_buffer, PcmRingConfig};
use offline_player_decoder::{probe, stream_to_pcm_i32_from_frame};

fn main() {
    let path = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            eprintln!("usage: cargo run -p offline-player-decoder --bin seek -- <audio-file>");
            std::process::exit(2);
        });

    let info = match probe(&path) {
        Ok(info) => info,
        Err(err) => {
            eprintln!("probe failed: {err}");
            std::process::exit(1);
        }
    };

    let sample_rate = info.format.sample_rate as u64;

    let channels = info.format.channels as u64;

    let total_frames = info.total_frames.unwrap_or(0);

    println!("=== SEEK TEST ===");
    println!("File        : {}", path.display());
    println!(
        "Format      : {} Hz / {} ch / {:?}",
        info.format.sample_rate, info.format.channels, info.format.sample_format
    );
    println!("Total frames: {}", total_frames);

    if sample_rate == 0 || channels == 0 {
        eprintln!("invalid audio format");
        std::process::exit(1);
    }

    let targets_seconds = [0.0f64, 5.0, 20.0, 50.0];

    let mut failures = 0usize;

    for seconds in targets_seconds {
        let target_frame = (seconds * sample_rate as f64).round() as u64;

        if target_frame > total_frames {
            println!(
                "SKIP  {:>6.2}s -> frame {} (past EOF)",
                seconds, target_frame
            );
            continue;
        }

        let ring_config = PcmRingConfig::new(1_048_576);

        let (mut producer, mut consumer) = pcm_ring_buffer(ring_config);

        let cancel = Arc::new(AtomicBool::new(false));

        let paused = Arc::new(AtomicBool::new(false));

        let cancel_consumer = Arc::clone(&cancel);

        let drain_thread = thread::spawn(move || {
            let mut drained = 0u64;

            loop {
                match consumer.try_pop() {
                    Ok(_) => {
                        drained += 1;
                    }

                    Err(_) => {
                        if cancel_consumer.load(Ordering::Acquire) {
                            break;
                        }

                        thread::yield_now();
                    }
                }
            }

            drained
        });

        let started = Instant::now();

        let result =
            stream_to_pcm_i32_from_frame(&path, target_frame, &mut producer, &cancel, &paused);

        cancel.store(true, Ordering::Release);

        let drained = drain_thread.join().expect("drain thread panicked");

        let elapsed = started.elapsed();

        match result {
            Ok((actual_frame, stats)) => {
                let actual_seconds = actual_frame as f64 / sample_rate as f64;

                let delta_frames = actual_frame.abs_diff(target_frame);

                let delta_seconds = delta_frames as f64 / sample_rate as f64;

                println!(
                    "TARGET {:>6.2}s | requested={:<10} actual={:<10} actual_s={:>9.4} delta={:>8.5}s decoded_frames={} pushed_samples={} drained={} elapsed={:.3}s",
                    seconds,
                    target_frame,
                    actual_frame,
                    actual_seconds,
                    delta_seconds,
                    stats.decoded_frames,
                    stats.pushed_samples,
                    drained,
                    elapsed.as_secs_f64(),
                );

                //
                // Accurate seek should land close to the requested
                // frame. We allow 250 ms because container/codec
                // seek granularity can differ by format.
                //
                const MAX_DELTA_SECONDS: f64 = 0.250;

                if delta_seconds > MAX_DELTA_SECONDS {
                    println!(
                        "FAIL  seek delta {:.5}s > {:.3}s",
                        delta_seconds, MAX_DELTA_SECONDS
                    );

                    failures += 1;
                } else {
                    println!("PASS");
                }
            }

            Err(err) => {
                println!("TARGET {:>6.2}s | ERROR: {}", seconds, err);

                failures += 1;
            }
        }

        println!();
    }

    if failures != 0 {
        eprintln!("Seek test failed: {} case(s)", failures);

        std::process::exit(1);
    }

    println!("All decoder seek tests passed.");
}
