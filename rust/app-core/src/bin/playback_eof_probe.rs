use std::{env, path::PathBuf};

use offline_player_app_core::{playback_service::PlaybackService, PlaybackState};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = env::args()
        .nth(1)
        .map(PathBuf::from)
        .ok_or("usage: playback_eof_probe <audio-file>")?;

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

    let track_id = {
        let tracks = service.library().playback_tracks()?;

        tracks
            .iter()
            .find(|track| track.path == path)
            .map(|track| track.track_id)
            .ok_or_else(|| format!("track not found for {}", path.display()))?
    };

    let track = service.load_track(track_id)?.clone();

    let frame_count = track.frame_count.ok_or("track has no finite frame_count")?;

    println!(
        "track_id={} start_frame={} frame_count={} end_frame={}",
        track.track_id,
        track.start_frame,
        frame_count,
        track.end_frame().ok_or("failed to calculate end frame")?
    );

    assert_eq!(service.state(), PlaybackState::Loaded);

    service.seek_to_frame(frame_count - 1)?;

    println!(
        "before_end: local_frame={:?} source_frame={:?} is_at_end={}",
        service.current_frame(),
        service.current_source_frame(),
        service.is_at_end()
    );

    assert_eq!(service.current_frame(), Some(frame_count - 1));
    assert!(!service.is_at_end());

    service.seek_to_frame(frame_count)?;

    println!(
        "at_end: local_frame={:?} source_frame={:?} is_at_end={}",
        service.current_frame(),
        service.current_source_frame(),
        service.is_at_end()
    );

    assert_eq!(service.current_frame(), Some(frame_count));
    assert!(service.is_at_end());

    println!("EOF boundary: PASS");

    Ok(())
}
