use std::{thread, time::Duration};

use offline_player_platform_macos::{
    default_output_device, nominal_sample_rate, output_format, set_nominal_sample_rate,
};

fn wait_for_physical_rate(
    device_id: u32,
    target_rate: u32,
) -> Result<(), Box<dyn std::error::Error>> {
    for attempt in 0..20 {
        thread::sleep(Duration::from_millis(50));

        let physical = output_format(device_id)?;

        println!(
            "Poll {:02}: physical = {} Hz / {} ch / {} bit",
            attempt + 1,
            physical.sample_rate,
            physical.channels,
            physical.bits_per_channel,
        );

        if physical.sample_rate == target_rate {
            return Ok(());
        }
    }

    Err(format!("CoreAudio did not reach {} Hz", target_rate).into())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let device_id = default_output_device()?;

    println!("Device           : {}", device_id);

    let original_nominal = nominal_sample_rate(device_id)?;

    let original_physical = output_format(device_id)?;

    println!("Original nominal : {:.0} Hz", original_nominal);

    println!(
        "Original physical: {} Hz / {} ch / {} bit",
        original_physical.sample_rate,
        original_physical.channels,
        original_physical.bits_per_channel,
    );

    let target_rate = 44_100.0;

    println!();
    println!("Requesting       : {:.0} Hz", target_rate);

    set_nominal_sample_rate(device_id, target_rate)?;

    let negotiation_result = wait_for_physical_rate(device_id, target_rate as u32);

    match negotiation_result {
        Ok(()) => {
            let negotiated = output_format(device_id)?;

            println!();
            println!(
                "Negotiated physical: {} Hz / {} ch / {} bit",
                negotiated.sample_rate, negotiated.channels, negotiated.bits_per_channel,
            );

            if negotiated.sample_rate != target_rate as u32 {
                return Err("physical format verification failed".into());
            }
        }

        Err(err) => {
            eprintln!("Negotiation failed: {err}");

            //
            // Best-effort restore.
            //
            let _ = set_nominal_sample_rate(device_id, original_nominal);

            return Err(err);
        }
    }

    println!();
    println!("Restoring       : {:.0} Hz", original_nominal);

    set_nominal_sample_rate(device_id, original_nominal)?;

    wait_for_physical_rate(device_id, original_physical.sample_rate)?;

    let restored = output_format(device_id)?;

    println!();
    println!(
        "Restored physical: {} Hz / {} ch / {} bit",
        restored.sample_rate, restored.channels, restored.bits_per_channel,
    );

    if restored.sample_rate != original_physical.sample_rate {
        return Err("physical format restoration failed".into());
    }

    println!();
    println!("M1.6.1 PASS");

    Ok(())
}
