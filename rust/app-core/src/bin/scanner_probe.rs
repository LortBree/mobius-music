use std::{env, path::Path};

use offline_player_app_core::scanner::Scanner;

fn main() {
    let root_arg = match env::args().nth(1) {
        Some(value) => value,

        None => {
            eprintln!("usage: scanner_probe <directory-or-file>");

            std::process::exit(2);
        }
    };

    let root = Path::new(&root_arg);

    println!("SCAN ROOT");
    println!("=========");
    println!("{}", root.display());

    println!();

    let mut scanner = Scanner::new();

    let result = match scanner.scan_directory(root) {
        Ok(result) => result,

        Err(error) => {
            eprintln!("scan failed: {error}");

            std::process::exit(1);
        }
    };

    println!("RESULT");
    println!("======");

    println!("assets: {}", result.assets.len());

    println!("ignored files: {}", result.ignored_files.len());

    println!("errors: {}", result.errors.len());

    println!();

    for (index, scanned) in result.assets.iter().enumerate() {
        println!("ASSET #{}", index + 1);

        println!("  path          : {}", scanned.asset.path.display());

        println!("  asset id      : {}", scanned.asset.id.0);

        println!("  sample rate   : {} Hz", scanned.asset.sample_rate);

        println!("  channels      : {}", scanned.asset.channels);

        println!("  bits/sample   : {}", scanned.asset.bits_per_sample);

        println!(
            "  total frames  : {}",
            scanned
                .asset
                .total_frames
                .map(|value| value.to_string())
                .unwrap_or_else(|| "<none>".to_owned())
        );

        println!();

        println!("  EMBEDDED");

        println!(
            "    title       : {}",
            scanned.metadata.title.as_deref().unwrap_or("<none>")
        );

        println!(
            "    artist      : {}",
            scanned.metadata.artist.as_deref().unwrap_or("<none>")
        );

        println!(
            "    album       : {}",
            scanned.metadata.album.as_deref().unwrap_or("<none>")
        );

        println!(
            "    album artist: {}",
            scanned.metadata.album_artist.as_deref().unwrap_or("<none>")
        );

        println!(
            "    composer    : {}",
            scanned.metadata.composer.as_deref().unwrap_or("<none>")
        );

        println!(
            "    genre       : {}",
            scanned.metadata.genre.as_deref().unwrap_or("<none>")
        );

        println!(
            "    date        : {}",
            scanned.metadata.date.as_deref().unwrap_or("<none>")
        );

        println!(
            "    track no    : {}",
            scanned
                .metadata
                .track_number
                .map(|value| value.to_string())
                .unwrap_or_else(|| "<none>".to_owned())
        );

        println!(
            "    disc no     : {}",
            scanned
                .metadata
                .disc_number
                .map(|value| value.to_string())
                .unwrap_or_else(|| "<none>".to_owned())
        );

        println!();

        println!("  TRACKS: {}", scanned.tracks.len());

        for scanned_track in &scanned.tracks {
            let track = &scanned_track.track;

            println!(
                "    #{:02} {}",
                track.track_number,
                track.title.as_deref().unwrap_or("<untitled>")
            );

            println!("      id          : {}", track.id.0);

            println!("      asset id    : {}", track.asset_id.0);

            println!("      start frame : {}", track.start_frame);

            println!(
                "      frame count : {}",
                track
                    .frame_count
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "<none>".to_owned())
            );

            println!(
                "      performer   : {}",
                track.performer.as_deref().unwrap_or("<none>")
            );

            println!(
                "      album       : {}",
                track.album.as_deref().unwrap_or("<none>")
            );

            println!(
                "      source      : {}",
                scanned_track.source_path.display()
            );
        }

        println!();
    }

    if !result.ignored_files.is_empty() {
        println!("IGNORED");
        println!("=======");

        for path in &result.ignored_files {
            println!("  {}", path.display());
        }

        println!();
    }

    if !result.errors.is_empty() {
        println!("ERRORS");
        println!("======");

        for error in &result.errors {
            println!("  {}: {}", error.path.display(), error.error);
        }
    }
}
