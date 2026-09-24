use std::{thread, time::Duration};

use offline_player_platform_macos::{
    default_output_device, nominal_sample_rate, output_format, set_nominal_sample_rate,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let device_id = default_output_device()?;

    let current_nominal = nominal_sample_rate(device_id)?;

    let current_physical = output_format(device_id)?;

    println!("Device            : {}", device_id);

    println!("Current nominal    : {:.0} Hz", current_nominal);

    println!(
        "Current physical   : {} Hz / {} ch / {} bit",
        current_physical.sample_rate, current_physical.channels, current_physical.bits_per_channel,
    );

    let target_rate = 44_100.0;

    println!();
    println!("Setting nominal    : {:.0} Hz", target_rate);

    set_nominal_sample_rate(device_id, target_rate)?;

    for attempt in 0..20 {
        thread::sleep(Duration::from_millis(50));

        let physical = output_format(device_id)?;

        println!(
            "Poll {:02}: {} Hz / {} ch / {} bit | \
             bytes/frame={} | format=0x{:08X} | flags=0x{:08X}",
            attempt + 1,
            physical.sample_rate,
            physical.channels,
            physical.bits_per_channel,
            physical.bytes_per_frame,
            physical.format_id,
            physical.format_flags,
        );

        if physical.sample_rate == target_rate as u32 {
            println!();
            println!("44.1 kHz is now active.");

            println!("Leave the device at 44.1 kHz for the next test.");

            return Ok(());
        }
    }

    Err(format!("failed to switch device {} to 44100 Hz", device_id).into())
}
