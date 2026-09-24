use offline_player_platform_macos::{default_output_device, output_format, output_virtual_format};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let device_id = default_output_device()?;

    let physical = output_format(device_id)?;

    let virtual_format = output_virtual_format(device_id)?;

    println!("Device: {}", device_id);

    println!();
    println!("=== PHYSICAL FORMAT ===");
    println!("Sample rate       : {} Hz", physical.sample_rate);
    println!("Channels          : {}", physical.channels);
    println!("Bits/channel      : {}", physical.bits_per_channel);
    println!("Bytes/frame       : {}", physical.bytes_per_frame);
    println!("Format ID         : 0x{:08X}", physical.format_id);
    println!("Format flags      : 0x{:08X}", physical.format_flags);

    println!();
    println!("=== VIRTUAL FORMAT ===");
    println!("Sample rate       : {} Hz", virtual_format.sample_rate);
    println!("Channels          : {}", virtual_format.channels);
    println!("Bits/channel      : {}", virtual_format.bits_per_channel);
    println!("Bytes/frame       : {}", virtual_format.bytes_per_frame);
    println!("Format ID         : 0x{:08X}", virtual_format.format_id);
    println!("Format flags      : 0x{:08X}", virtual_format.format_flags);

    Ok(())
}
