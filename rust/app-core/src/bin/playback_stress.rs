use std::{
    env, process, thread,
    time::{Duration, Instant},
};

use offline_player_app_core::{PlaybackController, PlaybackState};

const TEST_DURATION_SECS: u64 = 15;
const TELEMETRY_INTERVAL_MS: u64 = 500;

macro_rules! require_telemetry {
    ($controller:expr) => {{
        match $controller.telemetry() {
            Some(value) => value,

            None => {
                eprintln!("FAIL: playback telemetry unavailable.");

                process::exit(1);
            }
        }
    }};
}

fn main() {
    println!("=== REAL PLAYBACK PIPELINE STRESS TEST ===");

    let path = match env::args().nth(1) {
        Some(value) => value,

        None => {
            eprintln!("usage: playback_stress <audio-file>");

            process::exit(2);
        }
    };

    println!("File: {path}");

    println!("Test duration: {} seconds", TEST_DURATION_SECS);

    let mut controller = PlaybackController::with_ring_capacity(262_144);

    println!("Initial state: {:?}", controller.state());

    controller.load(&path).unwrap_or_else(|err| {
        eprintln!("FAIL: load failed: {err}");

        process::exit(1);
    });

    //
    // Copy everything needed from MediaInfo into owned/scalar values.
    // This releases the immutable borrow of `controller` before
    // calling any mutable method such as `play()`.
    //
    let (source_format, codec, total_frames, duration_seconds) = {
        let info = controller.media_info().unwrap_or_else(|| {
            eprintln!("FAIL: media info unavailable after load");

            process::exit(1);
        });

        (
            info.format,
            info.codec.clone(),
            info.total_frames,
            info.duration_seconds(),
        )
    };

    println!("Loaded state : {:?}", controller.state());

    println!("Format       : {:?}", source_format);

    println!("Codec        : {}", codec);

    println!("Total frames : {:?}", total_frames);

    println!("Duration     : {:?} s", duration_seconds);

    controller.play().unwrap_or_else(|err| {
        eprintln!("FAIL: play failed: {err}");

        process::exit(1);
    });

    if controller.state() != PlaybackState::Playing {
        eprintln!("FAIL: controller did not enter Playing state");

        process::exit(1);
    }

    println!("State after play: {:?}", controller.state());

    let started = Instant::now();

    let mut previous = require_telemetry!(&controller);

    let sample_rate = source_format.sample_rate as u64;

    if sample_rate == 0 {
        eprintln!("FAIL: source sample rate is zero");

        process::exit(1);
    }

    while started.elapsed() < Duration::from_secs(TEST_DURATION_SECS) {
        thread::sleep(Duration::from_millis(TELEMETRY_INTERVAL_MS));

        let elapsed = started.elapsed().as_secs_f64();

        let telemetry = require_telemetry!(&controller);

        let current_frame = controller.current_frame().unwrap_or(0);

        let expected_frames = (elapsed * sample_rate as f64) as u64;

        let frame_delta = if current_frame >= expected_frames {
            current_frame.saturating_sub(expected_frames)
        } else {
            expected_frames.saturating_sub(current_frame)
        };

        let delta_requested = telemetry
            .requested_samples
            .saturating_sub(previous.requested_samples);

        let delta_consumed = telemetry
            .consumed_samples
            .saturating_sub(previous.consumed_samples);

        let delta_underrun = telemetry
            .underrun_samples
            .saturating_sub(previous.underrun_samples);

        println!(
            "[{:>5.1}s] frame={:<9} expected≈{:<9} delta={} callbacks={} req={} cons={} underrun={} | interval req={} cons={} underrun={}",
            elapsed,
            current_frame,
            expected_frames,
            frame_delta,
            telemetry.callback_count,
            telemetry.requested_samples,
            telemetry.consumed_samples,
            telemetry.underrun_samples,
            delta_requested,
            delta_consumed,
            delta_underrun,
        );

        if controller.state() != PlaybackState::Playing {
            eprintln!(
                "FAIL: playback left Playing state unexpectedly: {:?}",
                controller.state()
            );

            process::exit(1);
        }

        previous = telemetry;
    }

    println!("\n--- FINAL TELEMETRY ---");

    let final_telemetry = require_telemetry!(&controller);

    let final_frame = controller.current_frame().unwrap_or(0);

    let final_seconds = controller.current_seconds().unwrap_or(0.0);

    println!("State             : {:?}", controller.state());

    println!("Final frame       : {}", final_frame);

    println!("Final position    : {:.3} s", final_seconds);

    println!("Callbacks         : {}", final_telemetry.callback_count);

    println!("Requested samples : {}", final_telemetry.requested_samples);

    println!("Consumed samples  : {}", final_telemetry.consumed_samples);

    println!("Underrun samples  : {}", final_telemetry.underrun_samples);

    if final_telemetry.callback_count == 0 {
        eprintln!("FAIL: CoreAudio callback never ran.");

        process::exit(1);
    }

    if final_telemetry.requested_samples == 0 {
        eprintln!("FAIL: CoreAudio never requested samples.");

        process::exit(1);
    }

    if final_telemetry.consumed_samples == 0 {
        eprintln!("FAIL: real decoder PCM never reached CoreAudio.");

        process::exit(1);
    }

    if final_frame < sample_rate {
        eprintln!(
            "FAIL: playback advanced less than one second: {} frames",
            final_frame
        );

        process::exit(1);
    }

    if final_telemetry.underrun_samples != 0 {
        eprintln!(
            "FAIL: real pipeline experienced {} underrun samples.",
            final_telemetry.underrun_samples
        );

        eprintln!("This means decoder supply did not maintain a continuous PCM stream.");

        process::exit(1);
    }

    println!("PASS: controller remained in Playing state.");

    println!("PASS: real decoder PCM reached CoreAudio.");

    println!("PASS: playback clock advanced.");

    println!(
        "PASS: zero underruns during {} second stress run.",
        TEST_DURATION_SECS
    );

    controller.stop().unwrap_or_else(|err| {
        eprintln!("FAIL: stop failed: {err}");

        process::exit(1);
    });

    println!("Final stopped state: {:?}", controller.state());

    println!("\nReal playback pipeline stress test passed.");
}
