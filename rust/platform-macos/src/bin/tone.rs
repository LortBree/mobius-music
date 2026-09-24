use std::{thread, time::Duration};

use offline_player_platform_macos::{
    default_output_device, dump_available_virtual_formats, nominal_sample_rate, output_format,
    output_virtual_format, set_nominal_sample_rate, SineOutput,
};

fn print_formats(device_id: u32, label: &str) -> Result<(), Box<dyn std::error::Error>> {
    let physical = output_format(device_id)?;
    let virtual_format = output_virtual_format(device_id)?;
    let nominal = nominal_sample_rate(device_id)?;

    println!("=== {label} ===");
    println!("Nominal rate     : {:.0} Hz", nominal);
    println!("Physical rate    : {} Hz", physical.sample_rate);
    println!(
        "Physical         : {} ch / {} bit / {} bytes-frame",
        physical.channels, physical.bits_per_channel, physical.bytes_per_frame
    );
    println!("Virtual rate     : {} Hz", virtual_format.sample_rate);
    println!(
        "Virtual          : {} ch / {} bit / {} bytes-frame",
        virtual_format.channels, virtual_format.bits_per_channel, virtual_format.bytes_per_frame
    );
    println!("Virtual flags    : 0x{:08X}", virtual_format.format_flags);
    println!();

    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let device_id = default_output_device()?;

    println!("Device          : {device_id}");
    println!();

    dump_available_virtual_formats(device_id)?;
    println!();

    print_formats(device_id, "INITIAL FORMAT")?;

    println!("Switching device to 48000 Hz...");
    set_nominal_sample_rate(device_id, 48_000.0)?;

    thread::sleep(Duration::from_millis(500));

    print_formats(device_id, "AFTER 48000 Hz SWITCH")?;

    let virtual_format = output_virtual_format(device_id)?;

    if virtual_format.sample_rate != 48_000 {
        return Err(format!(
            "48 kHz switch failed: current virtual rate is {} Hz",
            virtual_format.sample_rate
        )
        .into());
    }

    println!("Creating 1 kHz sine at 48 kHz...");

    let sine = SineOutput::open(device_id, 1_000.0, 0.20)?;

    println!("Sine IOProc created.");

    sine.start()?;

    println!("Started.");
    println!("Playing 1 kHz sine at 48 kHz for 5 seconds...");

    thread::sleep(Duration::from_secs(5));

    sine.stop()?;

    println!("Sine stopped cleanly.");
    println!();

    println!("Restoring device to 44100 Hz...");
    set_nominal_sample_rate(device_id, 44_100.0)?;

    thread::sleep(Duration::from_millis(500));

    print_formats(device_id, "RESTORED FORMAT")?;

    let restored = output_virtual_format(device_id)?;

    if restored.sample_rate != 44_100 {
        return Err(format!(
            "Failed to restore 44.1 kHz: current virtual rate is {} Hz",
            restored.sample_rate
        )
        .into());
    }

    println!("Sample-rate switching test passed.");

    Ok(())
}
