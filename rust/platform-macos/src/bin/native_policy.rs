use offline_player_audio_core::{OutputPlan, OutputPolicy};

fn main() {
    let supported_rates = [44100, 48000];

    println!("== Native output policy ==");

    for source_rate in [44100, 48000, 96000, 192000] {
        match OutputPolicy::plan_native(source_rate, &supported_rates) {
            Ok(OutputPlan::Native { sample_rate }) => {
                println!("{source_rate} Hz -> Native {sample_rate} Hz");
            }

            Ok(OutputPlan::Resample {
                source_sample_rate,
                output_sample_rate,
            }) => {
                println!(
                    "{source_sample_rate} Hz -> \
                     Resample {output_sample_rate} Hz"
                );
            }

            Err(error) => {
                println!("{source_rate} Hz -> Error: {error}");
            }
        }
    }

    println!();
    println!("== Native policy assertions ==");

    let plan =
        OutputPolicy::plan_native(44100, &supported_rates).expect("44.1 kHz policy should succeed");

    let sample_rate = match plan {
        OutputPlan::Native { sample_rate } => sample_rate,

        OutputPlan::Resample {
            source_sample_rate,
            output_sample_rate,
        } => {
            panic!(
                "expected native output, got resample: \
                 source_sample_rate={source_sample_rate}, \
                 output_sample_rate={output_sample_rate}"
            );
        }
    };

    assert_eq!(
        sample_rate, 44100,
        "44.1 kHz source should use native 44.1 kHz output"
    );

    let plan =
        OutputPolicy::plan_native(48000, &supported_rates).expect("48 kHz policy should succeed");

    let sample_rate = match plan {
        OutputPlan::Native { sample_rate } => sample_rate,

        OutputPlan::Resample {
            source_sample_rate,
            output_sample_rate,
        } => {
            panic!(
                "expected native output, got resample: \
                 source_sample_rate={source_sample_rate}, \
                 output_sample_rate={output_sample_rate}"
            );
        }
    };

    assert_eq!(
        sample_rate, 48000,
        "48 kHz source should use native 48 kHz output"
    );

    println!("Native policy assertions passed.");
}
