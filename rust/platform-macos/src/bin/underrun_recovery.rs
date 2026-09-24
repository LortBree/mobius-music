use std::{f64::consts::PI, thread, time::Duration};

use offline_player_audio_core::{pcm_ring_buffer, PcmProducer, PcmRingConfig, PcmRingError};

use offline_player_platform_macos::{default_output_device, output_virtual_format, PcmOutput};

const RING_CAPACITY_SAMPLES: usize = 131_072;
const SINE_FREQUENCY_HZ: f64 = 1_000.0;
const SINE_AMPLITUDE: f64 = 0.20;

fn push_sample(producer: &mut PcmProducer, sample: i32) {
    loop {
        match producer.try_push(sample) {
            Ok(()) => return,

            Err(PcmRingError::Full) => {
                //
                // The realtime consumer must never block.
                // Only the producer may wait for ring space.
                //
                thread::yield_now();
            }

            Err(PcmRingError::Empty) => {
                unreachable!("producer cannot report Empty");
            }

            Err(PcmRingError::InvalidLength) => {
                unreachable!("single sample push cannot have InvalidLength");
            }
        }
    }
}

fn fill_sine(producer: &mut PcmProducer, sample_rate: u32, channels: u32, frames: usize) {
    let max_amplitude = i32::MAX as f64;

    for frame in 0..frames {
        let t = frame as f64 / sample_rate as f64;

        let value = (2.0 * PI * SINE_FREQUENCY_HZ * t).sin() * SINE_AMPLITUDE * max_amplitude;

        let sample = value as i32;

        for _channel in 0..channels {
            push_sample(producer, sample);
        }
    }
}

fn main() {
    println!("=== CORE AUDIO UNDERRUN -> REFILL -> RECOVERY TEST ===");

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

    if format.channels != 2 {
        eprintln!(
            "FAIL: this test expects 2-channel output, got {}",
            format.channels
        );

        std::process::exit(1);
    }

    //
    // One producer / one realtime consumer.
    //
    let config = PcmRingConfig::new(RING_CAPACITY_SAMPLES);

    let (mut producer, consumer) = pcm_ring_buffer(config);

    let output = PcmOutput::open(device, consumer, format.sample_rate, format.channels, 16)
        .unwrap_or_else(|err| {
            eprintln!("FAIL: PcmOutput::open failed: {err}");

            std::process::exit(1);
        });

    println!("PcmOutput opened.");

    //
    // ----------------------------------------------------------------
    // PHASE 1: STARVATION
    // ----------------------------------------------------------------
    //
    println!("\n--- PHASE 1: EMPTY RING / STARVATION ---");

    output.start().unwrap_or_else(|err| {
        eprintln!("FAIL: AudioDeviceStart failed: {err}");

        std::process::exit(1);
    });

    println!("Output started with EMPTY PCM ring.");

    thread::sleep(Duration::from_millis(500));

    let starvation = output.telemetry();

    println!("Starvation telemetry:");

    println!("  callbacks = {}", starvation.callback_count);

    println!("  requested = {}", starvation.requested_samples);

    println!("  consumed  = {}", starvation.consumed_samples);

    println!("  underrun  = {}", starvation.underrun_samples);

    if starvation.callback_count == 0 {
        eprintln!("FAIL: callback never ran.");

        std::process::exit(1);
    }

    if starvation.requested_samples == 0 {
        eprintln!("FAIL: callback requested zero samples.");

        std::process::exit(1);
    }

    if starvation.underrun_samples == 0 {
        eprintln!("FAIL: starvation produced no underrun.");

        std::process::exit(1);
    }

    if starvation.consumed_samples != 0 {
        eprintln!(
            "FAIL: consumer unexpectedly received {} samples during empty-ring phase.",
            starvation.consumed_samples
        );

        std::process::exit(1);
    }

    println!("PASS: starvation detected.");

    //
    // ----------------------------------------------------------------
    // PHASE 2: REFILL SAME RING / SAME OUTPUT
    // ----------------------------------------------------------------
    //
    println!("\n--- PHASE 2: REFILL SAME RING ---");

    let refill_frames = (format.sample_rate as usize) / 2;

    println!(
        "Injecting {} frames of {:.0} Hz sine...",
        refill_frames, SINE_FREQUENCY_HZ
    );

    let callback_count_before_refill = starvation.callback_count;

    let underrun_before_refill = starvation.underrun_samples;

    let consumed_before_refill = starvation.consumed_samples;

    fill_sine(
        &mut producer,
        format.sample_rate,
        format.channels,
        refill_frames,
    );

    //
    // Let CoreAudio consume the newly available PCM.
    //
    thread::sleep(Duration::from_millis(500));

    let recovery = output.telemetry();

    println!("Recovery telemetry:");

    println!("  callbacks = {}", recovery.callback_count);

    println!("  requested = {}", recovery.requested_samples);

    println!("  consumed  = {}", recovery.consumed_samples);

    println!("  underrun  = {}", recovery.underrun_samples);

    //
    // ----------------------------------------------------------------
    // PHASE 3: VALIDATE RECOVERY
    // ----------------------------------------------------------------
    //
    println!("\n--- PHASE 3: VALIDATE RECOVERY ---");

    if recovery.callback_count <= callback_count_before_refill {
        eprintln!("FAIL: callback count did not advance after refill.");

        std::process::exit(1);
    }

    if recovery.consumed_samples <= consumed_before_refill {
        eprintln!("FAIL: no PCM was consumed after refill.");

        std::process::exit(1);
    }

    if recovery.underrun_samples < underrun_before_refill {
        eprintln!("FAIL: underrun counter went backwards.");

        std::process::exit(1);
    }

    let newly_consumed = recovery
        .consumed_samples
        .saturating_sub(consumed_before_refill);

    let newly_underrun = recovery
        .underrun_samples
        .saturating_sub(underrun_before_refill);

    println!("Newly consumed : {} samples", newly_consumed);

    println!("New underrun   : {} samples", newly_underrun);

    if newly_consumed == 0 {
        eprintln!("FAIL: playback did not recover.");

        std::process::exit(1);
    }

    //
    // We intentionally do not require newly_underrun == 0.
    //
    // The initial half-second of starvation plus the finite refill can
    // leave the ring empty again before the final observation.
    //
    println!("PASS: CoreAudio callback continued running after refill.");

    println!("PASS: the SAME PcmOutput consumed newly supplied PCM.");

    println!("PASS: playback recovered without restarting the device.");

    //
    // Stop exactly once at the end.
    //
    output.stop().unwrap_or_else(|err| {
        eprintln!("FAIL: AudioDeviceStop failed: {err}");

        std::process::exit(1);
    });

    println!("Output stopped cleanly.");

    println!("\nCore Audio underrun recovery test passed.");
}
