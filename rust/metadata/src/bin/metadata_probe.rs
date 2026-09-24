use std::env;
use std::path::Path;

fn print_field(name: &str, value: &Option<String>) {
    println!("{name}: {}", value.as_deref().unwrap_or("<none>"));
}

fn main() {
    let path = match env::args().nth(1) {
        Some(path) => path,
        None => {
            eprintln!("usage: metadata_probe <audio-file>");
            std::process::exit(2);
        }
    };

    let path = Path::new(&path);

    println!("FILE");
    println!("====");
    println!("path: {}", path.display());
    println!();

    match offline_player_metadata::read(path) {
        Ok(metadata) => {
            println!("METADATA");
            println!("========");

            print_field("title", &metadata.title);
            print_field("artist", &metadata.artist);
            print_field("album", &metadata.album);
            print_field("album_artist", &metadata.album_artist);
            print_field("composer", &metadata.composer);
            print_field("genre", &metadata.genre);
            print_field("date", &metadata.date);

            println!(
                "track_number: {}",
                metadata
                    .track_number
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "<none>".to_owned())
            );

            println!(
                "disc_number: {}",
                metadata
                    .disc_number
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "<none>".to_owned())
            );
        }

        Err(error) => {
            eprintln!("metadata read failed: {error}");
            std::process::exit(1);
        }
    }
}
