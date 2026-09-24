use std::io;

use offline_player_platform_macos::{default_output_device, list_output_devices, SilenceOutput};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let devices = list_output_devices()?;

    println!(
        "Found {} playback-capable CoreAudio device(s).",
        devices.len()
    );

    for device_id in &devices {
        println!("Output device: {}", device_id);
    }

    let device_id = default_output_device()?;

    println!("Opening CoreAudio output device {}", device_id);

    let output = SilenceOutput::open(device_id)?;

    println!("IOProc created.");
    println!("Starting device...");

    output.start()?;

    println!("Running silence output.");
    println!("Press Enter to stop.");

    let mut input = String::new();
    io::stdin().read_line(&mut input)?;

    output.stop()?;

    println!("Stopped cleanly.");

    drop(output);

    Ok(())
}
