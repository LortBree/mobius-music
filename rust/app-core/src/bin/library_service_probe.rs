use std::{env, path::Path};

use offline_player_app_core::library_service::LibraryService;

#[derive(Debug, Clone, PartialEq, Eq)]
struct Snapshot {
    assets: i64,
    artists: i64,
    albums: i64,
    tracks: i64,
    stored_ids: Vec<(i64, Vec<i64>)>,
}

fn main() {
    let root_arg = env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: library_service_probe <music-directory>");
        std::process::exit(2);
    });

    let root = Path::new(&root_arg);

    println!("LIBRARY SERVICE PROBE");
    println!("=====================");
    println!("{}", root.display());
    println!();

    let mut service = LibraryService::open_in_memory().unwrap_or_else(|error| {
        eprintln!("service open failed: {error}");
        std::process::exit(1);
    });

    println!("PASS 1");
    println!("------");

    let report_1 = service.scan_directory(root).unwrap_or_else(|error| {
        eprintln!("first scan failed: {error}");
        std::process::exit(1);
    });

    print_report(&report_1);

    let snapshot_1 = snapshot(&service, &report_1);

    println!();
    println!("DATABASE AFTER PASS 1");
    println!("--------------------");
    print_snapshot(&snapshot_1);

    println!();
    println!("PASS 2");
    println!("------");

    let report_2 = service.scan_directory(root).unwrap_or_else(|error| {
        eprintln!("second scan failed: {error}");
        std::process::exit(1);
    });

    print_report(&report_2);

    let snapshot_2 = snapshot(&service, &report_2);

    println!();
    println!("DATABASE AFTER PASS 2");
    println!("--------------------");
    print_snapshot(&snapshot_2);

    println!();

    if snapshot_1 != snapshot_2 {
        eprintln!("FAIL: service state changed after rescan");
        std::process::exit(1);
    }

    if report_1.asset_count() != report_1.persisted_count() {
        eprintln!(
            "FAIL: PASS 1 scanned {} assets but persisted {}",
            report_1.asset_count(),
            report_1.persisted_count()
        );
        std::process::exit(1);
    }

    if report_2.asset_count() != report_2.persisted_count() {
        eprintln!(
            "FAIL: PASS 2 scanned {} assets but persisted {}",
            report_2.asset_count(),
            report_2.persisted_count()
        );
        std::process::exit(1);
    }

    if report_1.has_scan_errors() || report_2.has_scan_errors() {
        eprintln!("FAIL: scan reported errors");
        std::process::exit(1);
    }

    println!("LIBRARY SERVICE");
    println!("---------------");
    println!("PASS: scan -> persist -> rescan is idempotent");
    println!("PASS: database counts are stable");
    println!("PASS: asset/track DB IDs are stable");
}

fn snapshot(
    service: &LibraryService,
    report: &offline_player_app_core::library_service::LibraryScanReport,
) -> Snapshot {
    let stored_ids = report
        .stored
        .iter()
        .map(|stored| (stored.asset_id, stored.track_ids.clone()))
        .collect();

    Snapshot {
        assets: service.asset_count().unwrap_or_else(|error| {
            eprintln!("asset count failed: {error}");
            std::process::exit(1);
        }),
        artists: service.artist_count().unwrap_or_else(|error| {
            eprintln!("artist count failed: {error}");
            std::process::exit(1);
        }),
        albums: service.album_count().unwrap_or_else(|error| {
            eprintln!("album count failed: {error}");
            std::process::exit(1);
        }),
        tracks: service.track_count().unwrap_or_else(|error| {
            eprintln!("track count failed: {error}");
            std::process::exit(1);
        }),
        stored_ids,
    }
}

fn print_report(report: &offline_player_app_core::library_service::LibraryScanReport) {
    println!("scanned assets : {}", report.asset_count());
    println!("ignored files  : {}", report.ignored_count());
    println!("scan errors    : {}", report.error_count());
    println!("persisted      : {}", report.persisted_count());

    for (index, scanned) in report.scan.assets.iter().enumerate() {
        let stored = &report.stored[index];

        println!("  {}", scanned.asset.path.display());
        println!(
            "    asset_id={} track_ids={:?}",
            stored.asset_id, stored.track_ids
        );

        for track in &scanned.tracks {
            println!(
                "    track #{} start={} frames={} title={:?}",
                track.track.track_number,
                track.track.start_frame,
                track.track.frame_count.unwrap_or(0),
                track.track.title
            );
        }
    }

    for error in &report.scan.errors {
        println!("  ERROR {}: {}", error.path.display(), error.error);
    }
}

fn print_snapshot(snapshot: &Snapshot) {
    println!("assets   : {}", snapshot.assets);
    println!("artists  : {}", snapshot.artists);
    println!("albums   : {}", snapshot.albums);
    println!("tracks   : {}", snapshot.tracks);
    println!("stored IDs:");

    for (asset_id, track_ids) in &snapshot.stored_ids {
        println!("  asset_id={} track_ids={:?}", asset_id, track_ids);
    }
}
