use std::sync::{
    atomic::{AtomicU32, AtomicU64, Ordering},
    Arc,
};

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
    //
    // Linear input gain that keeps the boosted curve below full scale
    // (see `auto_preamp_db`), and the value the previous buffer ended on,
    // so a change is ramped across a buffer instead of stepped.
    //
    preamp: f64,
    applied_preamp: f64,
    //
    // Channel of the first sample in the next buffer. The realtime
    // callback may receive a buffer that does not start on a frame
    // boundary, and each channel has its own filter state.
    //
    next_channel: usize,
}

fn sanitize_gains(gains_db: [f32; 10]) -> [f32; 10] {
    gains_db.map(|gain| {
        if gain.is_finite() {
            gain.clamp(-12.0, 12.0)
        } else {
            0.0
        }
    })
}

impl GraphicEqualizer {
    pub fn new(sample_rate: u32, channels: usize, source_bits: u32) -> Self {
        Self::with_gains(sample_rate, channels, source_bits, [0.0; 10])
    }

    /// Starts already settled on `gains_db`, so a new track or a seek
    /// does not fade the curve in from flat.
    pub fn with_gains(
        sample_rate: u32,
        channels: usize,
        source_bits: u32,
        gains_db: [f32; 10],
    ) -> Self {
        let safe_rate = sample_rate.max(1) as f64;
        let channels = channels.max(1);
        let source_bits = source_bits.clamp(2, 32);
        let settings = EqualizerSettings {
            gains_db: sanitize_gains(gains_db),
        };
        let coefficients = coefficients(safe_rate, settings);
        let preamp = db_to_linear(auto_preamp_from(&coefficients, safe_rate));
        Self {
            sample_rate: safe_rate,
            channels,
            source_bits,
            settings,
            target_settings: settings,
            coefficients,
            states: vec![[State::default(); 10]; channels],
            preamp,
            applied_preamp: preamp,
            next_channel: 0,
        }
    }

    /// Never allocates, so it is safe to call from a realtime audio callback.
    pub fn process(&mut self, samples: &mut [i32], settings: EqualizerSettings) {
        let first_channel = self.next_channel;
        self.next_channel = (first_channel + samples.len()) % self.channels;

        let settings = EqualizerSettings {
            gains_db: sanitize_gains(settings.gains_db),
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
            self.preamp = db_to_linear(auto_preamp_from(&self.coefficients, self.sample_rate));
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
            self.preamp = 1.0;
            self.applied_preamp = 1.0;
            return;
        }

        let scale = 2.0_f64.powi((self.source_bits - 1) as i32);
        let min_sample = -scale;
        let max_sample = scale - 1.0;

        let frames = (samples.len() / self.channels).max(1);
        let preamp_start = self.applied_preamp;
        let preamp_step = (self.preamp - preamp_start) / frames as f64;

        for (index, sample) in samples.iter_mut().enumerate() {
            let position = first_channel + index;
            let channel = position % self.channels;
            let frame = position / self.channels;
            let preamp = preamp_start + preamp_step * (frame + 1).min(frames) as f64;
            let mut output = *sample as f64 / scale * preamp;
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
        self.applied_preamp = self.preamp;
    }
}

fn db_to_linear(db: f64) -> f64 {
    10.0_f64.powf(db / 20.0)
}

/// Equalizer gains shared between the UI-facing controller and the
/// realtime audio callback without a lock.
///
/// The callback must never block, so the gains live in atomics. A writer
/// stores all ten bands and then bumps `generation`; the callback re-reads
/// the bands only when the generation moved. A read that races a write can
/// see a mix of old and new bands for one buffer, but the generation it saw
/// is older than the finished write, so the next buffer reads it again and
/// the gain smoothing hides the one-buffer mix.
#[derive(Debug)]
pub struct SharedEqualizerGains {
    bands: [AtomicU32; 10],
    generation: AtomicU64,
}

impl Default for SharedEqualizerGains {
    fn default() -> Self {
        Self::new([0.0; 10])
    }
}

impl SharedEqualizerGains {
    pub fn new(gains_db: [f32; 10]) -> Self {
        let gains_db = sanitize_gains(gains_db);
        Self {
            bands: std::array::from_fn(|band| AtomicU32::new(gains_db[band].to_bits())),
            generation: AtomicU64::new(0),
        }
    }

    pub fn set(&self, gains_db: [f32; 10]) {
        for (band, gain) in sanitize_gains(gains_db).into_iter().enumerate() {
            self.bands[band].store(gain.to_bits(), Ordering::Relaxed);
        }
        self.generation.fetch_add(1, Ordering::Release);
    }

    pub fn get(&self) -> [f32; 10] {
        std::array::from_fn(|band| f32::from_bits(self.bands[band].load(Ordering::Relaxed)))
    }

    pub fn generation(&self) -> u64 {
        self.generation.load(Ordering::Acquire)
    }
}

/// The equalizer as run inside the audio output callback: it follows
/// `SharedEqualizerGains` with roughly one callback buffer of latency
/// (milliseconds), instead of the seconds of audio queued in the PCM ring.
pub struct RealtimeEqualizer {
    shared: Arc<SharedEqualizerGains>,
    seen_generation: u64,
    settings: EqualizerSettings,
    equalizer: GraphicEqualizer,
}

impl RealtimeEqualizer {
    pub fn new(
        shared: Arc<SharedEqualizerGains>,
        sample_rate: u32,
        channels: usize,
        source_bits: u32,
    ) -> Self {
        let seen_generation = shared.generation();
        let gains_db = shared.get();
        Self {
            shared,
            seen_generation,
            settings: EqualizerSettings { gains_db },
            equalizer: GraphicEqualizer::with_gains(sample_rate, channels, source_bits, gains_db),
        }
    }

    /// Lock-free and allocation-free.
    pub fn process(&mut self, samples: &mut [i32]) {
        let generation = self.shared.generation();
        if generation != self.seen_generation {
            self.seen_generation = generation;
            self.settings = EqualizerSettings {
                gains_db: self.shared.get(),
            };
        }
        self.equalizer.process(samples, self.settings);
    }
}

/// Input attenuation (dB, <= 0) that keeps the equalizer from clipping.
///
/// Boosting a band on a track that is already mastered near 0 dBFS pushes
/// the peaks past full scale, and the hard clamp then chops them: that is
/// the crackle heard at high volume with a bass or treble boost. Adjacent
/// bands overlap, so the real peak is the peak of the COMBINED response,
/// not the largest single gain (two neighbouring +6 dB bands peak higher
/// than +6 dB). This returns minus that peak, so a full-scale signal at the
/// most boosted frequency lands back at full scale.
pub fn auto_preamp_db(gains_db: [f32; 10], sample_rate: u32) -> f32 {
    let sample_rate = sample_rate.max(1) as f64;
    let coefficients = coefficients(sample_rate, EqualizerSettings { gains_db });
    auto_preamp_from(&coefficients, sample_rate) as f32
}

fn auto_preamp_from(coefficients: &[Coefficients; 10], sample_rate: f64) -> f64 {
    const POINTS: usize = 240;
    let low = 20.0_f64;
    let high = (20_000.0_f64).min(sample_rate * 0.49).max(low * 2.0);

    let log_points = (0..POINTS).map(|i| low * (high / low).powf(i as f64 / (POINTS - 1) as f64));
    // Band centres too, so a narrow peak between grid points is not missed.
    let centres = EQUALIZER_BANDS_HZ
        .iter()
        .map(|&f| f as f64)
        .filter(|&f| f <= high);

    let peak_db = log_points
        .chain(centres)
        .map(|frequency| response_db(coefficients, sample_rate, frequency))
        .fold(f64::NEG_INFINITY, f64::max);

    -peak_db.max(0.0)
}

fn response_db(coefficients: &[Coefficients; 10], sample_rate: f64, frequency: f64) -> f64 {
    coefficients
        .iter()
        .map(|c| band_response_db(c, sample_rate, frequency))
        .sum()
}

/// Filters for `settings`, with each band's filter gain SOLVED so the
/// combined response at every band centre equals the gain the user set.
///
/// The bands overlap (Q = 1.4 on octave spacing), so setting a filter to
/// +9 dB with a -12 dB neighbour only yields about +6.5 dB at its centre:
/// the curve missed the dots. Instead, the filter gains `g` are found so
/// that `response(g)(centre_i) == target_i` for every band (the
/// "proportional/compensated graphic EQ" approach). Allocation-free.
fn coefficients(sample_rate: f64, settings: EqualizerSettings) -> [Coefficients; 10] {
    let targets = settings.gains_db.map(|g| g as f64);
    let gains = solve_filter_gains(sample_rate, targets);
    std::array::from_fn(|index| band_coefficients(sample_rate, index, gains[index]))
}

/// Largest filter gain the solver may use; alternating extreme settings
/// would otherwise ask for very large opposing filters.
const MAX_FILTER_GAIN_DB: f64 = 24.0;

fn band_coefficients(sample_rate: f64, band: usize, gain_db: f64) -> Coefficients {
    let frequency = (EQUALIZER_BANDS_HZ[band] as f64).min(sample_rate * 0.49);
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
}

fn band_response_db(c: &Coefficients, sample_rate: f64, frequency: f64) -> f64 {
    let omega = 2.0 * std::f64::consts::PI * frequency / sample_rate;
    let (c1, s1) = (omega.cos(), -omega.sin());
    let (c2, s2) = ((2.0 * omega).cos(), -(2.0 * omega).sin());
    let num_re = c.b0 + c.b1 * c1 + c.b2 * c2;
    let num_im = c.b1 * s1 + c.b2 * s2;
    let den_re = 1.0 + c.a1 * c1 + c.a2 * c2;
    let den_im = c.a1 * s1 + c.a2 * s2;
    let num = num_re * num_re + num_im * num_im;
    let den = den_re * den_re + den_im * den_im;
    10.0 * (num / den.max(f64::MIN_POSITIVE)).log10()
}

/// Bands whose centre sits below ~0.45 x the sample rate. Higher ones are
/// squeezed against Nyquist (e.g. 16 kHz at 22.05 kHz) and would make the
/// system near-singular, so they keep their set gain unsolved.
fn solvable_bands(sample_rate: f64) -> [bool; 10] {
    EQUALIZER_BANDS_HZ.map(|f| (f as f64) <= sample_rate * 0.45)
}

/// Quasi-Newton solve: the interaction matrix (dB at centre i per dB of
/// band j) is nearly constant, so it is built once at 1 dB, inverted by
/// Gaussian elimination, and a few correction steps absorb the small
/// non-linearity. Mirrored exactly in `equalizer_response.dart`.
pub(crate) fn solve_filter_gains(sample_rate: f64, targets: [f64; 10]) -> [f64; 10] {
    if targets.iter().all(|g| g.abs() < 1e-9) {
        return [0.0; 10];
    }
    let active = solvable_bands(sample_rate);
    let centres: [f64; 10] =
        std::array::from_fn(|i| (EQUALIZER_BANDS_HZ[i] as f64).min(sample_rate * 0.49));

    // Unit-gain responses: column j = band j at +1 dB.
    let unit: [Coefficients; 10] = std::array::from_fn(|j| band_coefficients(sample_rate, j, 1.0));
    let mut matrix = [[0.0_f64; 10]; 10];
    for (i, row) in matrix.iter_mut().enumerate() {
        for (j, cell) in row.iter_mut().enumerate() {
            *cell = if active[i] && active[j] {
                band_response_db(&unit[j], sample_rate, centres[i])
            } else if i == j {
                1.0
            } else {
                0.0
            };
        }
    }

    let mut gains = targets;
    for _ in 0..12 {
        let filters: [Coefficients; 10] =
            std::array::from_fn(|j| band_coefficients(sample_rate, j, gains[j]));
        let mut residual = [0.0_f64; 10];
        let mut worst = 0.0_f64;
        for i in 0..10 {
            if !active[i] {
                continue;
            }
            let actual: f64 = filters
                .iter()
                .map(|c| band_response_db(c, sample_rate, centres[i]))
                .sum();
            residual[i] = targets[i] - actual;
            worst = worst.max(residual[i].abs());
        }
        if worst < 1e-7 {
            break;
        }
        let step = solve_linear(matrix, residual);
        for j in 0..10 {
            if active[j] {
                gains[j] = (gains[j] + step[j]).clamp(-MAX_FILTER_GAIN_DB, MAX_FILTER_GAIN_DB);
            }
        }
    }
    gains
}

/// Gaussian elimination with partial pivoting on a 10x10 system.
#[allow(clippy::needless_range_loop)] // index form mirrors the Dart port
fn solve_linear(mut a: [[f64; 10]; 10], mut b: [f64; 10]) -> [f64; 10] {
    for col in 0..10 {
        let pivot = (col..10)
            .max_by(|&x, &y| a[x][col].abs().total_cmp(&a[y][col].abs()))
            .unwrap_or(col);
        a.swap(col, pivot);
        b.swap(col, pivot);
        let diag = a[col][col];
        if diag.abs() < 1e-12 {
            continue;
        }
        for row in col + 1..10 {
            let factor = a[row][col] / diag;
            if factor == 0.0 {
                continue;
            }
            for k in col..10 {
                a[row][k] -= factor * a[col][k];
            }
            b[row] -= factor * b[col];
        }
    }
    let mut x = [0.0_f64; 10];
    for row in (0..10).rev() {
        let tail: f64 = (row + 1..10).map(|k| a[row][k] * x[k]).sum();
        let diag = a[row][row];
        x[row] = if diag.abs() < 1e-12 {
            0.0
        } else {
            (b[row] - tail) / diag
        };
    }
    x
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: u32 = 44_100;

    fn sine(frequency: f64, frames: usize, amplitude: f64, bits: u32) -> Vec<i32> {
        let scale = 2.0_f64.powi(bits as i32 - 1);
        (0..frames)
            .flat_map(|n| {
                let v = (2.0 * std::f64::consts::PI * frequency * n as f64 / RATE as f64).sin();
                let s = (v * amplitude * (scale - 1.0)).round() as i32;
                [s, s]
            })
            .collect()
    }

    /// Streams a continuous tone through in consecutive buffers (so the
    /// gain smoothing settles without a phase jump at every buffer edge)
    /// and returns the final buffer.
    fn settle(eq: &mut GraphicEqualizer, input: &[i32], gains: [f32; 10]) -> Vec<i32> {
        let mut out = Vec::new();
        for chunk in input.chunks(2048) {
            out = chunk.to_vec();
            eq.process(&mut out, EqualizerSettings { gains_db: gains });
        }
        out
    }

    /// Combined response at each band centre for the user's settings.
    fn centre_response(gains: [f32; 10], rate: u32) -> [f64; 10] {
        let rate = rate as f64;
        let c = coefficients(rate, EqualizerSettings { gains_db: gains });
        std::array::from_fn(|i| response_db(&c, rate, EQUALIZER_BANDS_HZ[i] as f64))
    }

    #[test]
    fn combined_curve_passes_through_every_set_gain() {
        // The screenshot case: neighbours pulled 250 Hz +9 down to ~+6.5.
        let cases: [[f32; 10]; 4] = [
            [3.0, 6.0, 4.0, 9.0, -12.0, -3.0, 2.0, 5.0, 1.0, -4.0],
            [
                12.0, -12.0, 12.0, -12.0, 12.0, -12.0, 12.0, -12.0, 12.0, -12.0,
            ],
            [12.0; 10],
            [0.0, 0.0, 0.0, 6.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        ];
        for rate in [44_100, 48_000, 96_000, 384_000] {
            for gains in cases {
                let actual = centre_response(gains, rate);
                for band in 0..10 {
                    let error = (actual[band] - gains[band] as f64).abs();
                    assert!(
                        error < 0.05,
                        "rate {rate} band {band}: set {} got {:.3}",
                        gains[band],
                        actual[band]
                    );
                }
            }
        }
    }

    #[test]
    fn bands_squeezed_against_nyquist_stay_stable() {
        // 16 kHz at 22.05 kHz is clamped next to 8 kHz; must not blow up.
        let gains = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 12.0, -12.0];
        let solved = solve_filter_gains(22_050.0, gains.map(f64::from));
        assert!(solved
            .iter()
            .all(|g| g.is_finite() && g.abs() <= MAX_FILTER_GAIN_DB));
    }

    #[test]
    fn flat_curve_needs_no_preamp() {
        assert_eq!(auto_preamp_db([0.0; 10], RATE), 0.0);
    }

    #[test]
    fn cuts_only_need_no_preamp() {
        assert!(auto_preamp_db([-6.0; 10], RATE) >= -0.01);
    }

    #[test]
    fn preamp_covers_the_combined_peak_of_neighbouring_boosts() {
        let mut gains = [0.0; 10];
        gains[0] = 6.0;
        gains[1] = 6.0;
        // The solved curve hits +6 dB at both centres and bulges slightly
        // between them, so the preamp covers a little more than 6 dB.
        assert!(auto_preamp_db(gains, RATE) < -6.0);
        // Same figure the UI's Dart mirror shows (equalizer_panel_test.dart).
        assert!((auto_preamp_db(gains, 48_000) + 6.0590).abs() < 1e-3);
        // All bands at +12 dB is a broad +12 dB (a bit more where they overlap).
        assert!(auto_preamp_db([12.0; 10], RATE) <= -12.0);
    }

    #[test]
    fn full_scale_bass_boost_does_not_clip() {
        // A 0 dBFS 62 Hz tone with the bass bands at +12 dB used to be
        // hard-clamped on every peak (the audible crackle).
        let mut gains = [0.0; 10];
        gains[0] = 12.0;
        gains[1] = 12.0;
        gains[2] = 8.0;
        let bits = 16;
        let max = (1 << (bits - 1)) - 1;
        let input = sine(62.0, 1024 * 60, 1.0, bits);

        let mut eq = GraphicEqualizer::new(RATE, 2, bits);
        let out = settle(&mut eq, &input, gains);

        let clipped = out.iter().filter(|&&s| s >= max || s <= -max).count();
        assert_eq!(clipped, 0, "{clipped} samples hit full scale");
        // And it is still boosted relative to the preamp, not just attenuated:
        // the tone stays near full scale.
        let peak = out.iter().map(|s| s.unsigned_abs()).max().unwrap();
        assert!(peak as f64 > 0.7 * max as f64, "peak {peak} of {max}");
    }

    #[test]
    fn flat_settings_are_bit_exact_passthrough() {
        let input = sine(1_000.0, 1024 * 60, 0.9, 24);
        let mut eq = GraphicEqualizer::new(RATE, 2, 24);
        let out = settle(&mut eq, &input, [0.0; 10]);
        assert_eq!(out.as_slice(), input.chunks(2048).last().unwrap());
    }

    fn rms(samples: &[i32]) -> f64 {
        (samples.iter().map(|&s| (s as f64).powi(2)).sum::<f64>() / samples.len() as f64).sqrt()
    }

    #[test]
    fn with_gains_starts_settled_instead_of_fading_in() {
        let mut gains = [0.0; 10];
        gains[5] = -12.0; // 1 kHz cut
        let input = sine(1_000.0, 4096, 0.5, 16);

        let mut settled = GraphicEqualizer::with_gains(RATE, 2, 16, gains);
        let mut first = input[..1024].to_vec();
        settled.process(&mut first, EqualizerSettings { gains_db: gains });

        // The very first buffer is already cut by most of the 12 dB.
        assert!(rms(&first[256..]) < rms(&input[256..1024]) * 0.4);
    }

    #[test]
    fn realtime_equalizer_follows_a_change_within_milliseconds() {
        let shared = Arc::new(SharedEqualizerGains::default());
        let mut eq = RealtimeEqualizer::new(Arc::clone(&shared), RATE, 2, 16);
        let input = sine(1_000.0, 44_100, 0.5, 16);
        let reference = rms(&input[..1024]);

        // 512-frame callbacks, like CoreAudio's default I/O buffer.
        let mut chunks = input.chunks(1024);
        for chunk in chunks.by_ref().take(8) {
            let mut buf = chunk.to_vec();
            eq.process(&mut buf);
            assert_eq!(buf, chunk, "flat must stay bit-exact");
        }

        let mut gains = [0.0; 10];
        gains[5] = -12.0;
        shared.set(gains);

        // ~40 callbacks of 512 frames is under half a second; the old path
        // only reached the speaker after the ~2 s PCM ring drained.
        let mut last = Vec::new();
        for chunk in chunks.by_ref().take(40) {
            last = chunk.to_vec();
            eq.process(&mut last);
        }
        let cut = rms(&last) / reference;
        assert!(cut < 0.3, "1 kHz only down to {cut:.3} of reference");
    }

    #[test]
    fn buffers_split_mid_frame_match_frame_aligned_buffers() {
        let mut gains = [0.0; 10];
        gains[0] = 9.0;
        gains[7] = -6.0;
        // Different signal per channel so a channel mix-up would show.
        let input: Vec<i32> = sine(62.0, 8192, 0.4, 16)
            .chunks(2)
            .zip(sine(4_000.0, 8192, 0.4, 16).chunks(2))
            .flat_map(|(l, r)| [l[0], r[1]])
            .collect();

        let mut aligned = GraphicEqualizer::with_gains(RATE, 2, 16, gains);
        let mut expected = input.clone();
        for chunk in expected.chunks_mut(1024) {
            aligned.process(chunk, EqualizerSettings { gains_db: gains });
        }

        let mut split = GraphicEqualizer::with_gains(RATE, 2, 16, gains);
        let mut actual = input.clone();
        for chunk in actual.chunks_mut(1023) {
            split.process(chunk, EqualizerSettings { gains_db: gains });
        }

        assert_eq!(actual, expected);
    }

    #[test]
    fn shared_gains_are_sanitized_and_versioned() {
        let shared = SharedEqualizerGains::default();
        let before = shared.generation();
        let mut gains = [0.0; 10];
        gains[0] = 40.0;
        gains[1] = f32::NAN;
        shared.set(gains);
        assert_ne!(shared.generation(), before);
        assert_eq!(shared.get()[0], 12.0);
        assert_eq!(shared.get()[1], 0.0);
    }
}
