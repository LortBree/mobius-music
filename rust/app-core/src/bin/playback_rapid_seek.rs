use std::{env, process, thread, time::Duration};

use offline_player_app_core::{PlaybackController, PlaybackState};

const SEEK_POINTS_SECONDS: &[u64] = &[5, 20, 50, 1, 40, 10, 30, 2, 45, 15, 0, 35];

const PAUSE_AFTER_EVERY_SEEK: bool = false;

fn main() {
    println!("=== RAPID SEEK STRESS TEST ===");

    let path = match env::args().nth(1) {
        Some(value) => value,

        None => {
            eprintln!("usage: playback_rapid_seek <audio-file>");

            process::exit(2);
        }
    };

    println!("File: {path}");

    let mut controller = PlaybackController::with_ring_capacity(262_144);

    controller.load(&path).unwrap_or_else(|err| {
        eprintln!("FAIL: initial load failed: {err}");

        process::exit(1);
    });

    let (sample_rate, total_frames, duration_seconds) = {
        let info = controller.media_info().unwrap_or_else(|| {
            eprintln!("FAIL: media info unavailable");

            process::exit(1);
        });

        (
            info.format.sample_rate as u64,
            info.total_frames.unwrap_or(0),
            info.duration_seconds().unwrap_or(0.0),
        )
    };

    if sample_rate == 0 {
        eprintln!("FAIL: source sample rate is zero");

        process::exit(1);
    }

    if total_frames == 0 {
        eprintln!("FAIL: total frame count is zero");

        process::exit(1);
    }

    println!("Sample rate : {} Hz", sample_rate);

    println!("Total frames: {}", total_frames);

    println!("Duration    : {:.3} s", duration_seconds);

    controller.play().unwrap_or_else(|err| {
        eprintln!("FAIL: initial play failed: {err}");

        process::exit(1);
    });

    if controller.state() != PlaybackState::Playing {
        eprintln!("FAIL: initial state is not Playing");

        process::exit(1);
    }

    println!("\nPlayback started.");

    let before = controller.telemetry();

    println!("Initial telemetry present: {}", before.is_some());

    //
    // Small warm-up. This makes the first seek happen after the
    // decoder/output pipeline has actually started.
    //
    thread::sleep(Duration::from_millis(300));

    let mut expected_underrun = controller
        .telemetry()
        .map(|telemetry| telemetry.underrun_samples)
        .unwrap_or(0);

    for (index, seconds) in SEEK_POINTS_SECONDS.iter().enumerate() {
        let requested_frame = seconds.saturating_mul(sample_rate);

        let target_frame = requested_frame.min(total_frames.saturating_sub(1));

        println!("\n--- SEEK {}/{} ---", index + 1, SEEK_POINTS_SECONDS.len());

        println!(
            "Requested: {:.3}s -> frame {}",
            *seconds as f64, target_frame
        );

        controller
            .seek_to_frame(target_frame)
            .unwrap_or_else(|err| {
                eprintln!("FAIL: seek {} failed: {err}", index + 1);

                process::exit(1);
            });

        if controller.state() != PlaybackState::Playing {
            eprintln!(
                "FAIL: seek {} did not preserve Playing state: {:?}",
                index + 1,
                controller.state()
            );

            process::exit(1);
        }

        let actual_frame = controller.current_frame().unwrap_or(0);

        println!("Actual frame: {}", actual_frame);

        if actual_frame != target_frame {
            eprintln!(
                "FAIL: seek {} landed at {}, expected {}",
                index + 1,
                actual_frame,
                target_frame
            );

            process::exit(1);
        }

        println!("PASS: exact seek position.");

        if PAUSE_AFTER_EVERY_SEEK {
            controller.pause().unwrap_or_else(|err| {
                eprintln!("FAIL: pause after seek failed: {err}");

                process::exit(1);
            });

            controller.play().unwrap_or_else(|err| {
                eprintln!("FAIL: resume after seek failed: {err}");

                process::exit(1);
            });
        }

        //
        // Give the newly-created decoder/output pair a tiny window
        // to start consuming PCM before the next seek.
        //
        thread::sleep(Duration::from_millis(100));

        let telemetry = match controller.telemetry() {
            Some(value) => value,

            None => {
                eprintln!("FAIL: telemetry unavailable after seek {}", index + 1);

                process::exit(1);
            }
        };

        println!(
            "Telemetry: callbacks={} requested={} consumed={} underrun={}",
            telemetry.callback_count,
            telemetry.requested_samples,
            telemetry.consumed_samples,
            telemetry.underrun_samples
        );

        if telemetry.callback_count == 0 {
            eprintln!("FAIL: no CoreAudio callback after seek {}", index + 1);

            process::exit(1);
        }

        if telemetry.consumed_samples == 0 {
            eprintln!("FAIL: no PCM consumed after seek {}", index + 1);

            process::exit(1);
        }

        //
        // Underrun counter is cumulative. It must never decrease.
        //
        if telemetry.underrun_samples < expected_underrun {
            eprintln!(
                "FAIL: underrun counter decreased: {} -> {}",
                expected_underrun, telemetry.underrun_samples
            );

            process::exit(1);
        }

        expected_underrun = telemetry.underrun_samples;
    }

    println!("\n--- POST-SEEK PLAYBACK ---");

    let frame_before_wait = controller.current_frame().unwrap_or(0);

    thread::sleep(Duration::from_millis(500));

    let frame_after_wait = controller.current_frame().unwrap_or(0);

    println!("Frame before wait: {}", frame_before_wait);

    println!("Frame after 500ms: {}", frame_after_wait);

    if frame_after_wait <= frame_before_wait {
        eprintln!("FAIL: playback did not continue after rapid seeks.");

        process::exit(1);
    }

    println!("PASS: playback continued after rapid seeks.");

    let final_telemetry = match controller.telemetry() {
        Some(value) => value,

        None => {
            eprintln!("FAIL: final telemetry unavailable");

            process::exit(1);
        }
    };

    println!("\n--- FINAL TELEMETRY ---");

    println!("State             : {:?}", controller.state());

    println!("Final frame       : {}", frame_after_wait);

    println!(
        "Final position    : {:.3}s",
        frame_after_wait as f64 / sample_rate as f64
    );

    println!("Callbacks         : {}", final_telemetry.callback_count);

    println!("Requested samples : {}", final_telemetry.requested_samples);

    println!("Consumed samples  : {}", final_telemetry.consumed_samples);

    println!("Underrun samples  : {}", final_telemetry.underrun_samples);

    if controller.state() != PlaybackState::Playing {
        eprintln!("FAIL: controller did not remain Playing.");

        process::exit(1);
    }

    if final_telemetry.callback_count == 0 {
        eprintln!("FAIL: CoreAudio callback count is zero.");

        process::exit(1);
    }

    if final_telemetry.consumed_samples == 0 {
        eprintln!("FAIL: no PCM was consumed.");

        process::exit(1);
    }

    //
    // For this stress test, we want zero newly accumulated underruns.
    //
    if final_telemetry.underrun_samples != expected_underrun {
        eprintln!("FAIL: unexpected underrun count change during final playback.");

        process::exit(1);
    }

    println!("PASS: no additional underrun after final seek.");

    controller.stop().unwrap_or_else(|err| {
        eprintln!("FAIL: final stop failed: {err}");

        process::exit(1);
    });

    if controller.state() != PlaybackState::Stopped {
        eprintln!("FAIL: final state is not Stopped.");

        process::exit(1);
    }

    println!("PASS: final stop clean.");

    println!("\nRapid seek stress test passed.");
}
