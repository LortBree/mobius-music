use std::{env, process, thread, time::Duration};

use offline_player_app_core::{PlaybackController, PlaybackState};

fn require_state(controller: &PlaybackController, expected: PlaybackState, label: &str) {
    let actual = controller.state();

    println!("{label}: state={actual:?}");

    if actual != expected {
        eprintln!("FAIL: expected {:?}, got {:?}", expected, actual);

        process::exit(1);
    }
}

fn main() {
    let path = match env::args().nth(1) {
        Some(path) => path,
        None => {
            eprintln!("usage: playback_lifecycle <audio-file>");

            process::exit(2);
        }
    };

    println!("=== PLAYBACK LIFECYCLE + SEEK TEST ===");
    println!("File: {path}");

    let mut controller = PlaybackController::new();

    //
    // Idle
    //
    require_state(&controller, PlaybackState::Idle, "Initial");

    //
    // Load
    //
    controller.load(&path).unwrap_or_else(|err| {
        eprintln!("load failed: {err}");

        process::exit(1);
    });

    require_state(&controller, PlaybackState::Loaded, "After load");

    let info = controller
        .media_info()
        .expect("media info must exist")
        .clone();

    println!("Format      : {:?}", info.format);

    println!("Total frames: {:?}", info.total_frames);

    println!("Duration    : {:?}", info.duration_seconds());

    println!("Position after load: {:?}", controller.current_frame());

    //
    // Play
    //
    controller.play().unwrap_or_else(|err| {
        eprintln!("play failed: {err}");

        process::exit(1);
    });

    require_state(&controller, PlaybackState::Playing, "After play");

    thread::sleep(Duration::from_secs(1));

    let frame_before_seek = controller.current_frame().expect("position must exist");

    println!("Position after 1s: frame={frame_before_seek}");

    //
    // Basic 1-second clock sanity.
    //
    // current_frame() is expressed in SOURCE frames.
    // Therefore a 96 kHz source should advance by roughly
    // 96,000 frames per second, while a 44.1 kHz source
    // should advance by roughly 44,100 frames per second.
    //
    let sample_rate = info.format.sample_rate as u64;

    let expected_frames_after_one_second = sample_rate;
    let tolerance = sample_rate / 10; // ±10%

    let min_expected_frame = expected_frames_after_one_second.saturating_sub(tolerance);
    let max_expected_frame = expected_frames_after_one_second + tolerance;

    println!(
        "Expected ~{} source frames after 1s (range {}..={})",
        expected_frames_after_one_second, min_expected_frame, max_expected_frame
    );

    if !(min_expected_frame..=max_expected_frame).contains(&frame_before_seek) {
        eprintln!(
            "FAIL: unexpected frame after 1s: \
            expected roughly {} frames, got {}",
            expected_frames_after_one_second, frame_before_seek
        );

        process::exit(1);
    }

    println!("Initial playback clock OK.");

    //
    // Seek while Playing -> 20 seconds
    //
    let sample_rate = info.format.sample_rate as u64;

    let seek_20s = 20 * sample_rate;

    println!("Seek Playing -> 20s ({seek_20s} frames)");

    controller.seek_to_frame(seek_20s).unwrap_or_else(|err| {
        eprintln!("seek while playing failed: {err}");

        process::exit(1);
    });

    require_state(
        &controller,
        PlaybackState::Playing,
        "After seek while playing",
    );

    let frame_after_seek = controller.current_frame().expect("position must exist");

    println!(
        "Position immediately after seek: \
         {frame_after_seek}"
    );

    let seek_delta = frame_after_seek.abs_diff(seek_20s);

    if seek_delta > 2_000 {
        eprintln!(
            "FAIL: seek target mismatch: \
             target={}, actual={}, delta={}",
            seek_20s, frame_after_seek, seek_delta
        );

        process::exit(1);
    }

    thread::sleep(Duration::from_secs(1));

    let frame_after_seek_wait = controller.current_frame().expect("position must exist");

    println!(
        "Position 1s after 20s seek: \
         {frame_after_seek_wait}"
    );

    if frame_after_seek_wait <= seek_20s {
        eprintln!("FAIL: playback clock did not advance");

        process::exit(1);
    }

    println!("Playing seek + clock advance OK.");

    //
    // Pause
    //
    controller.pause().unwrap_or_else(|err| {
        eprintln!("pause failed: {err}");

        process::exit(1);
    });

    require_state(&controller, PlaybackState::Paused, "After pause");

    let paused_frame = controller
        .current_frame()
        .expect("paused position must exist");

    println!("Paused at frame={paused_frame}");

    thread::sleep(Duration::from_secs(2));

    let frame_after_pause = controller
        .current_frame()
        .expect("paused position must exist");

    println!(
        "Frame after 2s paused: \
         {frame_after_pause}"
    );

    if frame_after_pause != paused_frame {
        eprintln!(
            "FAIL: pause clock moved: \
             before={}, after={}",
            paused_frame, frame_after_pause
        );

        process::exit(1);
    }

    println!("Pause clock freeze OK.");

    //
    // Seek while Paused -> 50 seconds
    //
    let seek_50s = 50 * sample_rate;

    println!("Seek Paused -> 50s ({seek_50s} frames)");

    controller.seek_to_frame(seek_50s).unwrap_or_else(|err| {
        eprintln!("seek while paused failed: {err}");

        process::exit(1);
    });

    require_state(
        &controller,
        PlaybackState::Paused,
        "After seek while paused",
    );

    let paused_seek_frame = controller.current_frame().expect("position must exist");

    println!(
        "Position after paused seek: \
         {paused_seek_frame}"
    );

    let paused_seek_delta = paused_seek_frame.abs_diff(seek_50s);

    if paused_seek_delta > 2_000 {
        eprintln!(
            "FAIL: paused seek target mismatch: \
             target={}, actual={}, delta={}",
            seek_50s, paused_seek_frame, paused_seek_delta
        );

        process::exit(1);
    }

    thread::sleep(Duration::from_secs(2));

    let paused_seek_after_wait = controller.current_frame().expect("position must exist");

    if paused_seek_after_wait != paused_seek_frame {
        eprintln!(
            "FAIL: paused seek clock moved: \
             before={}, after={}",
            paused_seek_frame, paused_seek_after_wait
        );

        process::exit(1);
    }

    println!("Paused seek + clock freeze OK.");

    //
    // Resume
    //
    controller.play().unwrap_or_else(|err| {
        eprintln!("resume failed: {err}");

        process::exit(1);
    });

    require_state(&controller, PlaybackState::Playing, "After resume");

    thread::sleep(Duration::from_secs(1));

    let resumed_frame = controller.current_frame().expect("position must exist");

    println!(
        "Position 1s after resume: \
         {resumed_frame}"
    );

    if resumed_frame <= seek_50s {
        eprintln!(
            "FAIL: resume did not continue \
             from 50s seek target"
        );

        process::exit(1);
    }

    println!("Resume from paused seek OK.");

    //
    // Stop
    //
    controller.stop().unwrap_or_else(|err| {
        eprintln!("stop failed: {err}");

        process::exit(1);
    });

    require_state(&controller, PlaybackState::Stopped, "After stop");

    println!("Position after stop: {:?}", controller.current_frame());

    if controller.current_frame().is_some() {
        eprintln!("FAIL: position should be None after stop");

        process::exit(1);
    }

    println!("\nPlayback lifecycle + seek test passed.");
}
