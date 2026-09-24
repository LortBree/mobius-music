use std::{env, path::Path};

use offline_player_app_core::{
    library_store::LibraryStore,
    scanner::{ScanResult, Scanner},
};

fn main() {
    let path_arg = env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: library_import_probe <audio-file-or-directory>");
        std::process::exit(2);
    });

    let root = Path::new(&path_arg);

    println!("IMPORT IDEMPOTENCY PROBE");
    println!("=======================");
    println!("{}", root.display());
    println!();

    let mut store = LibraryStore::open_in_memory().unwrap_or_else(|error| {
        eprintln!("database open failed: {error}");
        std::process::exit(1);
    });

    println!("PASS 1");
    println!("------");

    let mut scanner_1 = Scanner::new();

    let result_1 = scanner_1.scan_directory(root).unwrap_or_else(|error| {
        eprintln!("first scan failed: {error}");
        std::process::exit(1);
    });

    print_scan_result(&result_1);

    for scanned in &result_1.assets {
        let stored = store.persist_scan(scanned).unwrap_or_else(|error| {
            eprintln!(
                "first persist failed for {}: {}",
                scanned.asset.path.display(),
                error
            );
            std::process::exit(1);
        });

        println!(
            "persisted: {} -> asset_id={} track_ids={:?}",
            scanned.asset.path.display(),
            stored.asset_id,
            stored.track_ids
        );
    }

    println!();

    let first_counts = read_counts(&store);

    println!("DATABASE AFTER PASS 1");
    println!("--------------------");
    print_counts(first_counts);

    println!();
    println!("PASS 2");
    println!("------");

    let mut scanner_2 = Scanner::new();

    let result_2 = scanner_2.scan_directory(root).unwrap_or_else(|error| {
        eprintln!("second scan failed: {error}");
        std::process::exit(1);
    });

    print_scan_result(&result_2);

    for scanned in &result_2.assets {
        let stored = store.persist_scan(scanned).unwrap_or_else(|error| {
            eprintln!(
                "second persist failed for {}: {}",
                scanned.asset.path.display(),
                error
            );
            std::process::exit(1);
        });

        println!(
            "persisted: {} -> asset_id={} track_ids={:?}",
            scanned.asset.path.display(),
            stored.asset_id,
            stored.track_ids
        );
    }

    println!();

    let second_counts = read_counts(&store);

    println!("DATABASE AFTER PASS 2");
    println!("--------------------");
    print_counts(second_counts);

    println!();

    if first_counts != second_counts {
        eprintln!("FAIL: database counts changed after rescan");
        std::process::exit(1);
    }

    println!("IDEMPOTENCY");
    println!("-----------");
    println!("PASS: rescan did not create duplicate records");
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Counts {
    assets: i64,
    artists: i64,
    albums: i64,
    tracks: i64,
}

fn read_counts(store: &LibraryStore) -> Counts {
    Counts {
        assets: store.asset_count().unwrap_or_else(|error| {
            eprintln!("asset count failed: {error}");
            std::process::exit(1);
        }),
        artists: store.artist_count().unwrap_or_else(|error| {
            eprintln!("artist count failed: {error}");
            std::process::exit(1);
        }),
        albums: store.album_count().unwrap_or_else(|error| {
            eprintln!("album count failed: {error}");
            std::process::exit(1);
        }),
        tracks: store.track_count().unwrap_or_else(|error| {
            eprintln!("track count failed: {error}");
            std::process::exit(1);
        }),
    }
}

fn print_counts(counts: Counts) {
    println!("assets   : {}", counts.assets);
    println!("artists  : {}", counts.artists);
    println!("albums   : {}", counts.albums);
    println!("tracks   : {}", counts.tracks);
}

fn print_scan_result(result: &ScanResult) {
    println!("scanner assets : {}", result.assets.len());
    println!("ignored        : {}", result.ignored_files.len());
    println!("errors         : {}", result.errors.len());

    if !result.errors.is_empty() {
        for error in &result.errors {
            println!("ERROR: {}: {}", error.path.display(), error.error);
        }

        std::process::exit(1);
    }
}
