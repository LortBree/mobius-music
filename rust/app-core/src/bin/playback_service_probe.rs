use std::{env, path::PathBuf, thread, time::Duration};

use offline_player_app_core::{playback_service::PlaybackService, PlaybackState};

fn main() {
    let root = env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/Users/bree/Downloads/Music"));

    println!("PlaybackService integration probe");
    println!("Library root: {}", root.display());
    println!();

    assert!(
        root.exists(),
        "library root does not exist: {}",
        root.display()
    );

    assert!(
        root.is_dir(),
        "library root is not a directory: {}",
        root.display()
    );

    let mut service = PlaybackService::open_in_memory().expect("failed to create PlaybackService");

    assert_eq!(service.state(), PlaybackState::Idle);

    println!("=== SCAN ===");

    let report = service.scan_directory(&root).expect("library scan failed");

    println!("scanned assets   : {}", report.scanned_assets());
    println!("ignored files    : {}", report.ignored_files());
    println!("scan errors      : {}", report.scan_errors());
    println!("persisted assets : {}", report.persisted_assets());

    assert!(report.scanned_assets() > 0, "scan produced no audio assets");

    assert_eq!(report.scan_errors(), 0, "library scan reported errors");

    assert_eq!(
        report.scanned_assets(),
        report.persisted_assets(),
        "not every scanned asset was persisted"
    );

    println!();
    println!("=== LIBRARY ===");

    let asset_count = service
        .library()
        .asset_count()
        .expect("failed to query asset count");

    let track_count = service
        .library()
        .track_count()
        .expect("failed to query track count");

    let artist_count = service
        .library()
        .artist_count()
        .expect("failed to query artist count");

    let album_count = service
        .library()
        .album_count()
        .expect("failed to query album count");

    println!("assets  : {}", asset_count);
    println!("tracks  : {}", track_count);
    println!("artists : {}", artist_count);
    println!("albums  : {}", album_count);

    assert!(asset_count > 0, "library contains no assets");
    assert!(track_count > 0, "library contains no tracks");

    println!();
    println!("=== LOAD TRACK 1 ===");

    let track = service.load_track(1).expect("failed to load track 1");

    let sample_rate = track.sample_rate;
    let frame_count = track
        .frame_count
        .expect("track must have finite frame_count");

    println!("track_id         : {}", track.track_id);
    println!("asset_id         : {}", track.asset_id);
    println!("path             : {}", track.path.display());
    println!("sample_rate      : {} Hz", sample_rate);
    println!("channels         : {}", track.channels);
    println!("bits_per_sample  : {}", track.bits_per_sample);
    println!("start_frame      : {}", track.start_frame);
    println!("frame_count      : {}", frame_count);

    println!(
        "duration         : {:.3}s",
        service
            .duration_seconds()
            .expect("track duration unavailable")
    );

    assert_eq!(service.state(), PlaybackState::Loaded);
    assert_eq!(service.current_frame(), Some(0));

    println!("state            : {:?}", service.state());
    println!("current frame    : {:?}", service.current_frame());

    println!();
    println!("=== PLAY ===");

    service.play().expect("play failed");

    assert_eq!(service.state(), PlaybackState::Playing);

    thread::sleep(Duration::from_millis(500));

    let frame_after_play = service
        .current_frame()
        .expect("current frame unavailable while playing");

    let seconds_after_play = service
        .current_seconds()
        .expect("current seconds unavailable while playing");

    println!(
        "position after 500ms: {} frames / {:.3}s",
        frame_after_play, seconds_after_play
    );

    assert!(
        frame_after_play > 0,
        "playback did not advance from frame 0"
    );

    println!();
    println!("=== PAUSE ===");

    service.pause().expect("pause failed");

    assert_eq!(service.state(), PlaybackState::Paused);

    let paused_frame = service
        .current_frame()
        .expect("current frame unavailable after pause");

    thread::sleep(Duration::from_millis(250));

    let frame_after_pause_wait = service
        .current_frame()
        .expect("current frame unavailable while paused");

    println!("paused frame      : {}", paused_frame);
    println!("after 250ms       : {}", frame_after_pause_wait);

    assert_eq!(
        frame_after_pause_wait, paused_frame,
        "paused playback position changed"
    );

    println!();
    println!("=== SEEK ===");

    let target_frame = u64::from(sample_rate)
        .checked_mul(20)
        .expect("20 second target overflow");

    assert!(
        target_frame <= frame_count,
        "20 second seek target exceeds track length"
    );

    service.seek_to_frame(target_frame).expect("seek failed");

    let seeked_frame = service
        .current_frame()
        .expect("current frame unavailable after seek");

    println!("requested local frame: {}", target_frame);
    println!("actual local frame   : {}", seeked_frame);

    println!(
        "actual position      : {:.3}s",
        service
            .current_seconds()
            .expect("current seconds unavailable")
    );

    assert_eq!(
        seeked_frame, target_frame,
        "seek landed on unexpected logical track frame"
    );

    assert_eq!(
        service.state(),
        PlaybackState::Paused,
        "seek while paused should remain paused"
    );

    println!();
    println!("=== RESUME ===");

    service.play().expect("resume failed");

    assert_eq!(service.state(), PlaybackState::Playing);

    let before_resume_wait = service
        .current_frame()
        .expect("current frame unavailable before resume");

    thread::sleep(Duration::from_millis(500));

    let after_resume_wait = service
        .current_frame()
        .expect("current frame unavailable after resume");

    println!("before resume wait: {}", before_resume_wait);
    println!("after resume wait : {}", after_resume_wait);

    assert!(
        after_resume_wait > before_resume_wait,
        "resume did not advance playback"
    );

    println!();
    println!("=== STOP ===");

    service.stop().expect("stop failed");

    assert_eq!(service.state(), PlaybackState::Stopped);

    println!("state             : {:?}", service.state());

    println!();
    println!("playback service integration probe passed");
}
