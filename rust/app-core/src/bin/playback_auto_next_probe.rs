use std::{env, path::PathBuf};

use offline_player_app_core::{
    playback_queue::RepeatMode, playback_service::PlaybackService, PlaybackQueue, PlaybackState,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = env::args()
        .nth(1)
        .map(PathBuf::from)
        .ok_or("usage: playback_auto_next_probe <audio-file>")?;

    if !path.exists() {
        return Err(format!("file does not exist: {}", path.display()).into());
    }

    let parent = path.parent().ok_or("audio file has no parent directory")?;

    let mut service = PlaybackService::open_in_memory()?;

    let report = service.scan_directory(parent)?;

    println!(
        "scanned_assets={} persisted_assets={} tracks={} errors={}",
        report.scanned_assets(),
        report.persisted_assets(),
        service.library().track_count()?,
        report.scan_errors()
    );

    let tracks = service.library().playback_tracks()?;

    let first = tracks
        .iter()
        .find(|track| track.path == path)
        .ok_or_else(|| format!("track not found for {}", path.display()))?;

    let second = tracks
        .iter()
        .find(|track| track.track_id != first.track_id)
        .ok_or("need at least two tracks")?;

    let first_id = first.track_id;
    let second_id = second.track_id;

    println!("first:  id={} path={}", first_id, first.path.display());
    println!("second: id={} path={}", second_id, second.path.display());

    let mut queue = PlaybackQueue::new();

    queue.set_queue(&service, vec![first_id, second_id])?;

    println!();
    println!("========================================");
    println!("TEST 1: AUTO-NEXT / REPEAT OFF");
    println!("========================================");

    queue.set_repeat_mode(RepeatMode::Off);

    let first = queue.select_and_play(&mut service, 0)?;

    assert_eq!(first.track_id, first_id);
    assert_eq!(queue.current_index(), Some(0));
    assert_eq!(service.state(), PlaybackState::Playing);

    println!(
        "playing_first: id={} frame={:?}",
        first.track_id,
        service.current_frame()
    );

    let first_frame_count = first
        .frame_count
        .ok_or("first track has no finite frame_count")?;

    service.seek_to_frame(first_frame_count)?;

    assert!(service.is_at_end());

    println!(
        "first_at_end: local_frame={:?} source_frame={:?}",
        service.current_frame(),
        service.current_source_frame()
    );

    let second = queue
        .advance_if_at_end(&mut service)?
        .ok_or("expected auto-next to second track")?;

    assert_eq!(second.track_id, second_id);
    assert_eq!(queue.current_index(), Some(1));
    assert_eq!(
        service.current_track().map(|track| track.track_id),
        Some(second_id)
    );
    assert_eq!(service.state(), PlaybackState::Playing);
    assert_eq!(service.current_frame(), Some(0));
    assert!(!service.is_at_end());

    println!(
        "auto_next_first_to_second: id={} frame={:?} state={:?}",
        second.track_id,
        service.current_frame(),
        service.state()
    );

    let second_frame_count = second
        .frame_count
        .ok_or("second track has no finite frame_count")?;

    service.seek_to_frame(second_frame_count)?;

    assert!(service.is_at_end());

    println!(
        "second_at_end: local_frame={:?} source_frame={:?}",
        service.current_frame(),
        service.current_source_frame()
    );

    let result = queue.advance_if_at_end(&mut service)?;

    assert!(result.is_none());
    assert_eq!(queue.current_index(), Some(1));
    assert_eq!(service.state(), PlaybackState::Stopped);

    println!("end_of_queue: result=None state={:?}", service.state());

    println!("AUTO-NEXT OFF: PASS");

    println!();
    println!("========================================");
    println!("TEST 2: AUTO-NEXT / REPEAT TRACK");
    println!("========================================");

    queue.set_repeat_mode(RepeatMode::Track);

    let first = queue.select_and_play(&mut service, 0)?;

    assert_eq!(first.track_id, first_id);
    assert_eq!(queue.current_index(), Some(0));
    assert_eq!(service.state(), PlaybackState::Playing);

    let first_frame_count = first
        .frame_count
        .ok_or("first track has no finite frame_count")?;

    service.seek_to_frame(first_frame_count)?;

    assert!(service.is_at_end());

    println!("first_at_end: repeat track");

    let repeated = queue
        .advance_if_at_end(&mut service)?
        .ok_or("expected repeat-track restart")?;

    assert_eq!(repeated.track_id, first_id);
    assert_eq!(queue.current_index(), Some(0));
    assert_eq!(
        service.current_track().map(|track| track.track_id),
        Some(first_id)
    );
    assert_eq!(service.state(), PlaybackState::Playing);
    assert_eq!(service.current_frame(), Some(0));
    assert!(!service.is_at_end());

    println!(
        "repeated_track: id={} frame={:?} state={:?}",
        repeated.track_id,
        service.current_frame(),
        service.state()
    );

    service.stop()?;

    println!("AUTO-NEXT REPEAT TRACK: PASS");

    println!();
    println!("========================================");
    println!("TEST 3: AUTO-NEXT / REPEAT QUEUE");
    println!("========================================");

    queue.set_repeat_mode(RepeatMode::Queue);

    let first = queue.select_and_play(&mut service, 0)?;

    assert_eq!(first.track_id, first_id);
    assert_eq!(queue.current_index(), Some(0));
    assert_eq!(service.state(), PlaybackState::Playing);

    let first_frame_count = first
        .frame_count
        .ok_or("first track has no finite frame_count")?;

    service.seek_to_frame(first_frame_count)?;

    assert!(service.is_at_end());

    let second = queue
        .advance_if_at_end(&mut service)?
        .ok_or("expected repeat-queue advance to second track")?;

    assert_eq!(second.track_id, second_id);
    assert_eq!(queue.current_index(), Some(1));
    assert_eq!(service.state(), PlaybackState::Playing);
    assert_eq!(service.current_frame(), Some(0));
    assert!(!service.is_at_end());

    println!(
        "queue_first_to_second: id={} frame={:?}",
        second.track_id,
        service.current_frame()
    );

    let second_frame_count = second
        .frame_count
        .ok_or("second track has no finite frame_count")?;

    service.seek_to_frame(second_frame_count)?;

    assert!(service.is_at_end());

    let wrapped = queue
        .advance_if_at_end(&mut service)?
        .ok_or("expected repeat-queue wrap to first track")?;

    assert_eq!(wrapped.track_id, first_id);
    assert_eq!(queue.current_index(), Some(0));
    assert_eq!(
        service.current_track().map(|track| track.track_id),
        Some(first_id)
    );
    assert_eq!(service.state(), PlaybackState::Playing);
    assert_eq!(service.current_frame(), Some(0));
    assert!(!service.is_at_end());

    println!(
        "queue_wrap_second_to_first: id={} frame={:?}",
        wrapped.track_id,
        service.current_frame()
    );

    service.stop()?;

    println!("AUTO-NEXT REPEAT QUEUE: PASS");

    println!();
    println!("========================================");
    println!("ALL AUTO-NEXT TESTS: PASS");
    println!("========================================");

    Ok(())
}
