use std::{env, path::Path};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = env::args()
        .nth(1)
        .ok_or("usage: cargo run -p offline-player-decoder --bin probe -- <file>")?;
    let info = offline_player_decoder::probe(Path::new(&path))?;

    println!("File        : {}", info.path.display());
    println!("Codec       : {}", info.codec);
    println!("Sample rate : {} Hz", info.format.sample_rate);
    println!("Channels    : {}", info.format.channels);
    println!("Bit depth   : {:?}", info.format.sample_format);
    println!("Total frames: {:?}", info.total_frames);
    println!("Duration    : {:?} s", info.duration_seconds());
    Ok(())
}
