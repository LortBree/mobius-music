use std::path::PathBuf;

use offline_player_app_core::library_service::LibraryService;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = PathBuf::from(std::env::var_os("HOME").ok_or("HOME is not set")?)
        .join("Downloads")
        .join("Music");

    println!("Scanning: {}", root.display());

    if !root.exists() {
        return Err(format!("music directory does not exist: {}", root.display()).into());
    }

    let mut service = LibraryService::open_in_memory()?;
    let report = service.scan_directory(&root)?;

    println!();
    println!("=== SCAN REPORT ===");
    println!("root             : {}", report.root.display());
    println!("scanned assets   : {}", report.scanned_assets());
    println!("ignored files    : {}", report.ignored_files());
    println!("scan errors      : {}", report.scan_errors());
    println!("persisted assets : {}", report.persisted_assets());

    if report.has_scan_errors() {
        println!();
        println!("=== SCAN ERRORS ===");
        println!(
            "LibraryScanReport only exposes the error count publicly: {}",
            report.scan_errors()
        );
    }

    let track_count = service.track_count()?;

    println!();
    println!("=== LIBRARY ===");
    println!("assets  : {}", service.asset_count()?);
    println!("tracks  : {track_count}");
    println!("artists : {}", service.artist_count()?);
    println!("albums  : {}", service.album_count()?);

    println!();
    println!("=== PLAYBACK TRACK MAPPING ===");

    for track_id in 1..=track_count {
        let Some(track) = service.playback_track(track_id)? else {
            println!();
            println!("Track #{track_id}");
            println!("  lookup         : NOT FOUND");
            continue;
        };

        let title = service
            .track_title(track_id)?
            .unwrap_or_else(|| "<untitled>".to_string());

        println!();
        println!("Track #{track_id}");
        println!("  title          : {title}");
        println!("  asset_id       : {}", track.asset_id);
        println!("  path           : {}", track.path.display());
        println!("  sample_rate    : {} Hz", track.sample_rate);
        println!("  channels       : {}", track.channels);
        println!("  bits_per_sample: {}", track.bits_per_sample);
        println!("  start_frame    : {}", track.start_frame);

        match track.frame_count {
            Some(frame_count) => {
                println!("  frame_count    : {frame_count}");
                println!(
                    "  duration       : {:.3}s",
                    frame_count as f64 / track.sample_rate as f64
                );
            }
            None => {
                println!("  frame_count    : <open ended>");
                println!("  duration       : <open ended>");
            }
        }
    }

    println!();
    println!("probe passed");

    Ok(())
}
