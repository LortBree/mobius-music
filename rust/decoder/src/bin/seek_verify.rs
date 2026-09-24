use std::{env, process, thread, time::Duration};

use offline_player_audio_core::{pcm_ring_buffer, PcmRingConfig};

use offline_player_decoder::{probe, stream_to_pcm_i32, stream_to_pcm_i32_from_frame};

const RING_CAPACITY_SAMPLES: usize = 1_048_576;
const VERIFY_FRAMES: u64 = 32;

#[derive(Debug)]
struct CaptureResult {
    samples: Vec<i32>,
    drained_samples: u64,
}

fn drain_sequential_reference(
    path: &std::path::Path,
    channels: usize,
    targets: &[u64],
) -> Result<Vec<Vec<i32>>, Box<dyn std::error::Error>> {
    let ring = PcmRingConfig::new(RING_CAPACITY_SAMPLES);

    let (mut producer, mut consumer) = pcm_ring_buffer(ring);

    let path = path.to_path_buf();

    let worker = thread::Builder::new()
        .name("seek-verify-reference".to_string())
        .spawn(move || stream_to_pcm_i32(&path, &mut producer))?;

    let mut captures = vec![Vec::<i32>::new(); targets.len()];

    let mut global_sample_index = 0u64;

    loop {
        match consumer.try_pop() {
            Ok(sample) => {
                let frame = global_sample_index / channels as u64;

                for (index, target) in targets.iter().enumerate() {
                    if frame >= *target && frame < target.saturating_add(VERIFY_FRAMES) {
                        captures[index].push(sample);
                    }
                }

                global_sample_index = global_sample_index.saturating_add(1);
            }

            Err(_) => {
                if worker.is_finished() {
                    break;
                }

                thread::yield_now();
            }
        }
    }

    //
    // Drain anything that arrived immediately before the worker
    // completed.
    //
    loop {
        match consumer.try_pop() {
            Ok(sample) => {
                let frame = global_sample_index / channels as u64;

                for (index, target) in targets.iter().enumerate() {
                    if frame >= *target && frame < target.saturating_add(VERIFY_FRAMES) {
                        captures[index].push(sample);
                    }
                }

                global_sample_index = global_sample_index.saturating_add(1);
            }

            Err(_) => break,
        }
    }

    let stats = worker
        .join()
        .map_err(|_| "reference decoder thread panicked")??;

    println!(
        "Reference decode: decoded_frames={} pushed_samples={} drained_samples={}",
        stats.decoded_frames, stats.pushed_samples, global_sample_index,
    );

    for (index, target) in targets.iter().enumerate() {
        let expected_samples = VERIFY_FRAMES.saturating_mul(channels as u64) as usize;

        if captures[index].len() != expected_samples {
            return Err(format!(
                "reference capture incomplete at frame {}: expected {} samples, got {}",
                target,
                expected_samples,
                captures[index].len()
            )
            .into());
        }
    }

    Ok(captures)
}

fn drain_seek(
    path: &std::path::Path,
    target_frame: u64,
    expected: &[i32],
    channels: usize,
) -> Result<CaptureResult, Box<dyn std::error::Error>> {
    let ring = PcmRingConfig::new(RING_CAPACITY_SAMPLES);

    let (mut producer, mut consumer) = pcm_ring_buffer(ring);

    let cancel = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));

    let paused = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));

    let worker_cancel = std::sync::Arc::clone(&cancel);

    let worker_paused = std::sync::Arc::clone(&paused);

    let path = path.to_path_buf();

    let worker = thread::Builder::new()
        .name("seek-verify-target".to_string())
        .spawn(move || {
            stream_to_pcm_i32_from_frame(
                &path,
                target_frame,
                &mut producer,
                &worker_cancel,
                &worker_paused,
            )
        })?;

    let mut captured = Vec::<i32>::with_capacity(expected.len());

    let mut drained_samples = 0u64;

    let mut timeout_loops = 0u32;

    while captured.len() < expected.len() {
        match consumer.try_pop() {
            Ok(sample) => {
                captured.push(sample);

                drained_samples = drained_samples.saturating_add(1);

                timeout_loops = 0;
            }

            Err(_) => {
                timeout_loops = timeout_loops.saturating_add(1);

                if worker.is_finished() && consumer.is_empty() && captured.len() < expected.len() {
                    break;
                }

                if timeout_loops > 5_000 {
                    break;
                }

                thread::yield_now();
            }
        }
    }

    //
    // Stop the decoder if we already captured the exact verification
    // window. This keeps the test fast and makes cancellation part of
    // the controlled decoder path.
    //
    if captured.len() >= expected.len() {
        cancel.store(true, std::sync::atomic::Ordering::Release);
    }

    let worker_result = worker.join().map_err(|_| "seek decoder thread panicked")?;

    match worker_result {
        Ok((_actual_start_frame, stats)) => {
            println!(
                "Seek decoder: decoded_frames={} pushed_samples={}",
                stats.decoded_frames, stats.pushed_samples,
            );
        }

        Err(offline_player_decoder::StreamError::Cancelled) => {
            //
            // Expected when the required verification window was
            // captured before the decoder reached EOF.
            //
        }

        Err(err) => {
            return Err(format!("seek decoder failed at target {}: {}", target_frame, err).into());
        }
    }

    if captured.len() != expected.len() {
        return Err(format!(
            "seek capture incomplete at target {}: expected {} samples, got {}",
            target_frame,
            expected.len(),
            captured.len()
        )
        .into());
    }

    //
    // Make sure capture length is frame-aligned.
    //
    if captured.len() % channels != 0 {
        return Err(format!(
            "capture at target {} is not frame-aligned: {} samples / {} channels",
            target_frame,
            captured.len(),
            channels
        )
        .into());
    }

    Ok(CaptureResult {
        samples: captured,
        drained_samples,
    })
}

fn first_mismatch(expected: &[i32], actual: &[i32]) -> Option<usize> {
    expected
        .iter()
        .zip(actual.iter())
        .position(|(left, right)| left != right)
        .or_else(|| {
            if expected.len() != actual.len() {
                Some(expected.len().min(actual.len()))
            } else {
                None
            }
        })
}

fn main() {
    let path = match env::args().nth(1) {
        Some(path) => path,
        None => {
            eprintln!("usage: seek_verify <audio-file>");

            process::exit(2);
        }
    };

    println!("=== BIT-EXACT SEEK VERIFICATION ===");

    println!("File: {path}");

    let path = std::path::Path::new(&path);

    let info = probe(path).unwrap_or_else(|err| {
        eprintln!("probe failed: {err}");

        process::exit(1);
    });

    let sample_rate = info.format.sample_rate;

    let channels = info.format.channels as usize;

    println!("Format      : {:?}", info.format);

    println!("Total frames: {:?}", info.total_frames);

    if sample_rate == 0 || channels == 0 {
        eprintln!("FAIL: invalid source format");

        process::exit(1);
    }

    if info.format.sample_format
        != offline_player_decoder::SampleFormat::SignedInt(match info.format.sample_format {
            offline_player_decoder::SampleFormat::SignedInt(bits) => bits,
            offline_player_decoder::SampleFormat::Float(_) => 0,
        })
    {
        eprintln!("FAIL: this verification binary expects signed integer PCM");

        process::exit(1);
    }

    let total_frames = match info.total_frames {
        Some(value) => value,
        None => {
            eprintln!("FAIL: exact reference verification requires total frame count");

            process::exit(1);
        }
    };

    //
    // Targets deliberately chosen at exact second boundaries.
    //
    let requested_targets = [
        0u64,
        5u64.saturating_mul(sample_rate as u64),
        20u64.saturating_mul(sample_rate as u64),
        50u64.saturating_mul(sample_rate as u64),
    ];

    let targets: Vec<u64> = requested_targets
        .into_iter()
        .filter(|target| target.saturating_add(VERIFY_FRAMES) <= total_frames)
        .collect();

    println!(
        "Verification window: {} frames ({} interleaved samples)",
        VERIFY_FRAMES,
        VERIFY_FRAMES.saturating_mul(channels as u64)
    );

    println!("\n--- BUILDING SEQUENTIAL REFERENCE ---");

    let references = drain_sequential_reference(path, channels, &targets).unwrap_or_else(|err| {
        eprintln!("FAIL: reference decode failed: {err}");

        process::exit(1);
    });

    println!("\n--- VERIFYING SEEK TARGETS ---");

    for (index, target) in targets.iter().enumerate() {
        let target_seconds = *target as f64 / sample_rate as f64;

        println!("\nTARGET {:>6.2}s | frame={}", target_seconds, target,);

        let result =
            drain_seek(path, *target, &references[index], channels).unwrap_or_else(|err| {
                eprintln!("FAIL: seek test failed at target {}: {err}", target);

                process::exit(1);
            });

        let mismatch = first_mismatch(&references[index], &result.samples);

        match mismatch {
            None => {
                println!("PASS: first {} frames are bit-exact", VERIFY_FRAMES);

                println!("      drained_samples={}", result.drained_samples);
            }

            Some(sample_index) => {
                let frame_index = sample_index / channels;

                let channel_index = sample_index % channels;

                println!(
                    "FAIL: mismatch at frame {}, channel {}",
                    frame_index, channel_index
                );

                println!("      expected={}", references[index][sample_index]);

                println!("      actual={}", result.samples[sample_index]);

                let start = sample_index.saturating_sub(4);

                let end = (sample_index + 4).min(references[index].len());

                println!(
                    "      reference window={:?}",
                    &references[index][start..end]
                );

                println!("      seek window={:?}", &result.samples[start..end]);

                process::exit(1);
            }
        }

        //
        // Small pause between targets so the console output remains
        // readable and the worker teardown has time to settle.
        //
        thread::sleep(Duration::from_millis(20));
    }

    println!("\nAll bit-exact seek verification tests passed.");
}
