use std::{env, process, thread, time::Duration};

use offline_player_app_core::{PlaybackController, PlaybackState};

const LOOPS: usize = 10;

fn assert_state(controller: &PlaybackController, expected: PlaybackState, label: &str) {
    let actual = controller.state();

    if actual != expected {
        eprintln!(
            "FAIL: {label}: expected state {:?}, got {:?}",
            expected, actual
        );

        process::exit(1);
    }

    println!("PASS: {label}: state={:?}", actual);
}

fn current_frame(controller: &PlaybackController, label: &str) -> u64 {
    controller.current_frame().unwrap_or_else(|| {
        eprintln!("FAIL: {label}: playback position unavailable");

        process::exit(1);
    })
}

fn main() {
    println!("=== PLAYBACK LIFECYCLE STRESS TEST ===");

    let path = match env::args().nth(1) {
        Some(value) => value,

        None => {
            eprintln!("usage: playback_lifecycle_stress <audio-file>");

            process::exit(2);
        }
    };

    println!("File: {path}");

    let mut controller = PlaybackController::with_ring_capacity(262_144);

    //
    // ---------------------------------------------------------------
    // Initial load
    // ---------------------------------------------------------------
    //
    controller.load(&path).unwrap_or_else(|err| {
        eprintln!("FAIL: initial load failed: {err}");

        process::exit(1);
    });

    assert_state(&controller, PlaybackState::Loaded, "initial load");

    let total_frames = controller.total_frames().unwrap_or_else(|| {
        eprintln!("FAIL: total frame count unavailable");

        process::exit(1);
    });

    let sample_rate = controller
        .media_info()
        .map(|info| info.format.sample_rate)
        .unwrap_or(0);

    if sample_rate == 0 {
        eprintln!("FAIL: sample rate unavailable");

        process::exit(1);
    }

    println!("Total frames : {}", total_frames);

    println!("Sample rate  : {} Hz", sample_rate);

    //
    // ---------------------------------------------------------------
    // Repeated lifecycle cycles
    // ---------------------------------------------------------------
    //
    for iteration in 0..LOOPS {
        println!("\n--- LOOP {}/{} ---", iteration + 1, LOOPS);

        //
        // PLAY
        //
        controller.play().unwrap_or_else(|err| {
            eprintln!("FAIL: loop {} play failed: {err}", iteration + 1);

            process::exit(1);
        });

        assert_state(&controller, PlaybackState::Playing, "play");

        thread::sleep(Duration::from_millis(300));

        let play_frame = current_frame(&controller, "after play");

        println!("Position after play: {}", play_frame);

        if play_frame == 0 {
            eprintln!("FAIL: playback did not advance");

            process::exit(1);
        }

        //
        // PAUSE
        //
        controller.pause().unwrap_or_else(|err| {
            eprintln!("FAIL: loop {} pause failed: {err}", iteration + 1);

            process::exit(1);
        });

        assert_state(&controller, PlaybackState::Paused, "pause");

        let paused_frame = current_frame(&controller, "after pause");

        thread::sleep(Duration::from_millis(300));

        let paused_frame_after_wait = current_frame(&controller, "paused wait");

        if paused_frame_after_wait != paused_frame {
            eprintln!(
                "FAIL: paused clock moved: {} -> {}",
                paused_frame, paused_frame_after_wait
            );

            process::exit(1);
        }

        println!("PASS: pause froze frame at {}", paused_frame);

        //
        // RESUME
        //
        controller.play().unwrap_or_else(|err| {
            eprintln!("FAIL: loop {} resume failed: {err}", iteration + 1);

            process::exit(1);
        });

        assert_state(&controller, PlaybackState::Playing, "resume");

        thread::sleep(Duration::from_millis(300));

        let resume_frame = current_frame(&controller, "after resume");

        if resume_frame <= paused_frame {
            eprintln!(
                "FAIL: playback did not resume: {} -> {}",
                paused_frame, resume_frame
            );

            process::exit(1);
        }

        println!("PASS: resume advanced frame to {}", resume_frame);

        //
        // SEEK WHILE PLAYING
        //
        let seek_target = match iteration % 3 {
            0 => 0,

            1 => total_frames / 4,

            _ => total_frames / 2,
        };

        println!(
            "Seeking while playing -> frame {} ({:.3}s)",
            seek_target,
            seek_target as f64 / sample_rate as f64
        );

        controller.seek_to_frame(seek_target).unwrap_or_else(|err| {
            eprintln!("FAIL: loop {} playing seek failed: {err}", iteration + 1);

            process::exit(1);
        });

        assert_state(&controller, PlaybackState::Playing, "playing seek");

        let after_seek = current_frame(&controller, "after playing seek");

        if after_seek != seek_target {
            eprintln!(
                "FAIL: playing seek landed at {}, expected {}",
                after_seek, seek_target
            );

            process::exit(1);
        }

        println!("PASS: playing seek landed exactly at frame {}", after_seek);

        //
        // PAUSE AGAIN
        //
        controller.pause().unwrap_or_else(|err| {
            eprintln!("FAIL: loop {} second pause failed: {err}", iteration + 1);

            process::exit(1);
        });

        assert_state(&controller, PlaybackState::Paused, "second pause");

        let pause_seek_target = if total_frames > sample_rate as u64 {
            total_frames.saturating_sub(sample_rate as u64)
        } else {
            0
        };

        println!("Seeking while paused -> frame {}", pause_seek_target);

        controller
            .seek_to_frame(pause_seek_target)
            .unwrap_or_else(|err| {
                eprintln!("FAIL: loop {} paused seek failed: {err}", iteration + 1);

                process::exit(1);
            });

        assert_state(&controller, PlaybackState::Paused, "paused seek");

        let paused_seek_frame = current_frame(&controller, "after paused seek");

        if paused_seek_frame != pause_seek_target {
            eprintln!(
                "FAIL: paused seek landed at {}, expected {}",
                paused_seek_frame, pause_seek_target
            );

            process::exit(1);
        }

        println!(
            "PASS: paused seek landed exactly at frame {}",
            paused_seek_frame
        );

        //
        // RESUME AFTER PAUSED SEEK
        //
        controller.play().unwrap_or_else(|err| {
            eprintln!(
                "FAIL: loop {} resume-after-seek failed: {err}",
                iteration + 1
            );

            process::exit(1);
        });

        assert_state(
            &controller,
            PlaybackState::Playing,
            "resume after paused seek",
        );

        thread::sleep(Duration::from_millis(300));

        let after_resume_seek = current_frame(&controller, "resume after paused seek position");

        if after_resume_seek <= pause_seek_target && pause_seek_target < total_frames {
            eprintln!(
                "FAIL: playback did not advance after paused seek: {} -> {}",
                pause_seek_target, after_resume_seek
            );

            process::exit(1);
        }

        println!(
            "PASS: resume after paused seek advanced to {}",
            after_resume_seek
        );

        //
        // STOP
        //
        controller.stop().unwrap_or_else(|err| {
            eprintln!("FAIL: loop {} stop failed: {err}", iteration + 1);

            process::exit(1);
        });

        assert_state(&controller, PlaybackState::Stopped, "stop");

        if controller.current_frame().is_some() {
            eprintln!("FAIL: stopped controller still reports a playback frame");

            process::exit(1);
        }

        println!("PASS: stopped controller released playback position");

        //
        // -----------------------------------------------------------
        // LOAD AGAIN
        // -----------------------------------------------------------
        //
        controller.load(&path).unwrap_or_else(|err| {
            eprintln!("FAIL: loop {} reload failed: {err}", iteration + 1);

            process::exit(1);
        });

        assert_state(&controller, PlaybackState::Loaded, "reload after stop");

        let reloaded_frame = current_frame(&controller, "after reload");

        if reloaded_frame != 0 {
            eprintln!(
                "FAIL: reload started at frame {}, expected 0",
                reloaded_frame
            );

            process::exit(1);
        }

        println!("PASS: reload reset position to frame 0");
    }

    //
    // ---------------------------------------------------------------
    // FINAL CLEAN STOP
    // ---------------------------------------------------------------
    //
    controller.stop().unwrap_or_else(|err| {
        eprintln!("FAIL: final stop failed: {err}");

        process::exit(1);
    });

    assert_state(&controller, PlaybackState::Stopped, "final stop");

    println!("\nAll {} playback lifecycle stress loops passed.", LOOPS);
}
