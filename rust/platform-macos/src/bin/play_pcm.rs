use std::{
    env,
    io::{self, Write},
    path::Path,
    thread,
};

use offline_player_audio_core::{pcm_ring_buffer, PcmRingConfig};

use offline_player_decoder::{probe, stream_to_pcm_i32};

use offline_player_platform_macos::{default_output_device, output_format, PcmOutput};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = env::args()
        .nth(1)
        .ok_or("usage: play_pcm <path-to-audio-file>")?;

    let path = Path::new(&path);

    let media = probe(path)?;

    println!("File         : {}", path.display());

    println!(
        "Source       : {} Hz / {} ch / {:?}",
        media.format.sample_rate, media.format.channels, media.format.sample_format
    );

    let device_id = default_output_device()?;

    let device_format = output_format(device_id)?;

    println!("Output       : device {}", device_id);

    println!(
        "Physical     : {} Hz / {} ch / {} bit",
        device_format.sample_rate, device_format.channels, device_format.bits_per_channel,
    );

    //
    // The first buffer is deliberately larger than one
    // CoreAudio callback period.
    //
    let ring_capacity =
        (device_format.sample_rate as usize) * (device_format.channels as usize) * 2;

    let config = PcmRingConfig::new(ring_capacity);

    let (mut producer, consumer) = pcm_ring_buffer(config);

    //
    // Start output only if source format matches the
    // physical stream exactly.
    //
    let output = PcmOutput::open(
        device_id,
        consumer,
        media.format.sample_rate,
        media.format.channels,
        match media.format.sample_format {
            offline_player_decoder::SampleFormat::SignedInt(bits) => bits as u32,

            offline_player_decoder::SampleFormat::Float(bits) => bits as u32,
        },
    )?;

    println!("IOProc created.");

    let producer_path = path.to_path_buf();

    let producer_thread = thread::spawn(move || stream_to_pcm_i32(&producer_path, &mut producer));

    println!("Starting playback...");

    output.start()?;

    println!("Playing. Press Enter to stop early.");

    let mut input = String::new();

    io::stdin().read_line(&mut input)?;

    //
    // Stop CoreAudio before the state containing
    // PcmConsumer is destroyed.
    //
    output.stop()?;

    let result = producer_thread
        .join()
        .map_err(|_| "decoder thread panicked")??;

    println!();
    println!("Decoded frames : {}", result.decoded_frames);

    println!("Pushed samples : {}", result.pushed_samples);

    println!("Stopped.");

    io::stdout().flush()?;

    Ok(())
}
