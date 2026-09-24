pub const EQUALIZER_BANDS_HZ: [f32; 10] = [
    31.0, 62.0, 125.0, 250.0, 500.0, 1_000.0, 2_000.0, 4_000.0, 8_000.0, 16_000.0,
];

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EqualizerSettings {
    pub gains_db: [f32; 10],
}

impl Default for EqualizerSettings {
    fn default() -> Self {
        Self {
            gains_db: [0.0; 10],
        }
    }
}

#[derive(Clone, Copy)]
struct Coefficients {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

#[derive(Clone, Copy, Default)]
struct State {
    z1: f64,
    z2: f64,
}

pub struct GraphicEqualizer {
    sample_rate: f64,
    channels: usize,
    source_bits: u32,
    settings: EqualizerSettings,
    target_settings: EqualizerSettings,
    coefficients: [Coefficients; 10],
    states: Vec<[State; 10]>,
}

impl GraphicEqualizer {
    pub fn new(sample_rate: u32, channels: usize, source_bits: u32) -> Self {
        let safe_rate = sample_rate.max(1) as f64;
        let channels = channels.max(1);
        let source_bits = source_bits.clamp(2, 32);
        let settings = EqualizerSettings::default();
        Self {
            sample_rate: safe_rate,
            channels,
            source_bits,
            settings,
            target_settings: settings,
            coefficients: coefficients(safe_rate, settings),
            states: vec![[State::default(); 10]; channels],
        }
    }

    pub fn process(&mut self, samples: &mut [i32], settings: EqualizerSettings) {
        let settings = EqualizerSettings {
            gains_db: settings.gains_db.map(|gain| {
                if gain.is_finite() {
                    gain.clamp(-12.0, 12.0)
                } else {
                    0.0
                }
            }),
        };
        if settings != self.target_settings {
            self.target_settings = settings;
        }
        let mut changed = false;
        for band in 0..10 {
            let current = self.settings.gains_db[band];
            let target = self.target_settings.gains_db[band];
            let next = current + (target - current) * 0.2;
            if (target - next).abs() > 0.005 {
                changed = true;
            }
            self.settings.gains_db[band] = if (target - next).abs() <= 0.005 {
                target
            } else {
                next
            };
        }
        if changed || self.settings != self.target_settings {
            self.coefficients = coefficients(self.sample_rate, self.settings);
        }

        if self
            .settings
            .gains_db
            .iter()
            .all(|gain| gain.abs() <= 0.0001)
            && self
                .target_settings
                .gains_db
                .iter()
                .all(|gain| gain.abs() <= 0.0001)
        {
            self.states.fill([State::default(); 10]);
            return;
        }

        let scale = 2.0_f64.powi((self.source_bits - 1) as i32);
        let min_sample = -scale;
        let max_sample = scale - 1.0;
        for (index, sample) in samples.iter_mut().enumerate() {
            let channel = index % self.channels;
            let mut output = *sample as f64 / scale;
            for band in 0..10 {
                let coefficient = self.coefficients[band];
                let state = &mut self.states[channel][band];
                let filtered = coefficient.b0 * output + state.z1;
                state.z1 = coefficient.b1 * output - coefficient.a1 * filtered + state.z2;
                state.z2 = coefficient.b2 * output - coefficient.a2 * filtered;
                output = filtered;
            }
            *sample = (output * scale).round().clamp(min_sample, max_sample) as i32;
        }
    }
}

fn coefficients(sample_rate: f64, settings: EqualizerSettings) -> [Coefficients; 10] {
    std::array::from_fn(|index| {
        let frequency = (EQUALIZER_BANDS_HZ[index] as f64).min(sample_rate * 0.49);
        let gain_db = settings.gains_db[index] as f64;
        let q = 1.4_f64;
        let a = 10.0_f64.powf(gain_db / 40.0);
        let omega = 2.0 * std::f64::consts::PI * frequency / sample_rate;
        let cos = omega.cos();
        let alpha = omega.sin() / (2.0 * q);
        let a0 = 1.0 + alpha / a;
        Coefficients {
            b0: (1.0 + alpha * a) / a0,
            b1: (-2.0 * cos) / a0,
            b2: (1.0 - alpha * a) / a0,
            a1: (-2.0 * cos) / a0,
            a2: (1.0 - alpha / a) / a0,
        }
    })
}
