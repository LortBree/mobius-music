use std::{thread, time::Duration};

use offline_player_audio_core::{pcm_ring_buffer, PcmRingConfig};

use offline_player_platform_macos::{default_output_device, output_virtual_format, PcmOutput};

fn main() {
    println!("=== CORE AUDIO UNDERRUN TEST ===");

    let device = default_output_device().unwrap_or_else(|err| {
        eprintln!("FAIL: cannot get default output device: {err}");
        std::process::exit(1);
    });

    println!("Device ID   : {}", device);

    let format = output_virtual_format(device).unwrap_or_else(|err| {
        eprintln!("FAIL: cannot read virtual output format: {err}");
        std::process::exit(1);
    });

    println!("Output      : {:?}", format);

    if format.sample_rate == 0 || format.channels == 0 {
        eprintln!("FAIL: invalid output format");
        std::process::exit(1);
    }

    //
    // Deliberately create an empty ring.
    //
    let config = PcmRingConfig::new(4_096);

    let (_producer, consumer) = pcm_ring_buffer(config);

    //
    // Use the source format expected by our current PCM path.
    //
    let source_sample_rate = format.sample_rate;

    let source_channels = format.channels;

    let source_bits = 16u32;

    let output = PcmOutput::open(
        device,
        consumer,
        source_sample_rate,
        source_channels,
        source_bits,
    )
    .unwrap_or_else(|err| {
        eprintln!("FAIL: PcmOutput::open failed: {err}");
        std::process::exit(1);
    });

    println!("PcmOutput opened.");

    let before = output.telemetry();

    println!(
        "Before start: callbacks={} requested={} consumed={} underrun={}",
        before.callback_count,
        before.requested_samples,
        before.consumed_samples,
        before.underrun_samples,
    );

    output.start().unwrap_or_else(|err| {
        eprintln!("FAIL: AudioDeviceStart failed: {err}");
        std::process::exit(1);
    });

    println!("Output started with EMPTY PCM ring.");

    //
    // Give CoreAudio enough time to invoke the callback repeatedly.
    //
    thread::sleep(Duration::from_millis(500));

    let after = output.telemetry();

    println!(
        "After 500ms: callbacks={} requested={} consumed={} underrun={}",
        after.callback_count,
        after.requested_samples,
        after.consumed_samples,
        after.underrun_samples,
    );

    output.stop().unwrap_or_else(|err| {
        eprintln!("FAIL: AudioDeviceStop failed: {err}");
        std::process::exit(1);
    });

    println!("Output stopped cleanly.");

    //
    // Assertions.
    //
    if after.callback_count == 0 {
        eprintln!("FAIL: CoreAudio callback was never invoked.");
        std::process::exit(1);
    }

    if after.requested_samples == 0 {
        eprintln!("FAIL: CoreAudio requested zero samples.");
        std::process::exit(1);
    }

    if after.consumed_samples != 0 {
        eprintln!(
            "FAIL: empty ring unexpectedly produced {} samples.",
            after.consumed_samples
        );
        std::process::exit(1);
    }

    if after.underrun_samples == 0 {
        eprintln!("FAIL: underrun was not detected.");
        std::process::exit(1);
    }

    if after.underrun_samples != after.requested_samples {
        eprintln!(
            "FAIL: underrun accounting mismatch: requested={} underrun={}",
            after.requested_samples, after.underrun_samples,
        );
        std::process::exit(1);
    }

    println!();
    println!("PASS: callback stayed alive during starvation.");

    println!("PASS: empty ring produced silence instead of blocking/crashing.");

    println!("PASS: underrun telemetry exactly matches missing samples.");

    println!("Core Audio underrun test passed.");
}
