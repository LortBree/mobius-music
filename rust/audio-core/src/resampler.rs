use std::fmt;

use crate::PcmSample;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResamplerError {
    InvalidSampleRate,
    InvalidChannels,
    SampleCountNotFrameAligned,
}

impl fmt::Display for ResamplerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidSampleRate => write!(f, "sample rate must be greater than zero"),
            Self::InvalidChannels => write!(f, "channel count must be greater than zero"),
            Self::SampleCountNotFrameAligned => write!(f, "PCM sample count is not frame aligned"),
        }
    }
}

impl std::error::Error for ResamplerError {}

/// Dependency-free linear PCM sample-rate converter for interleaved integer PCM.
///
/// This is intentionally kept off the realtime audio callback. The decoder worker
/// produces source-rate PCM and this converter turns it into the output rate before
/// the samples enter the realtime ring buffer.
pub struct LinearResampler {
    source_rate: u32,
    target_rate: u32,
    channels: usize,
    step: f64,
    next_position: f64,
    frames: Vec<PcmSample>,
}

impl LinearResampler {
    pub fn new(
        source_rate: u32,
        target_rate: u32,
        channels: usize,
    ) -> Result<Self, ResamplerError> {
        if source_rate == 0 || target_rate == 0 {
            return Err(ResamplerError::InvalidSampleRate);
        }

        if channels == 0 {
            return Err(ResamplerError::InvalidChannels);
        }

        Ok(Self {
            source_rate,
            target_rate,
            channels,
            step: source_rate as f64 / target_rate as f64,
            next_position: 0.0,
            frames: Vec::new(),
        })
    }

    pub fn source_rate(&self) -> u32 {
        self.source_rate
    }

    pub fn target_rate(&self) -> u32 {
        self.target_rate
    }

    pub fn channels(&self) -> usize {
        self.channels
    }

    /// Process an interleaved source block and append output-rate samples to `out`.
    pub fn process(
        &mut self,
        input: &[PcmSample],
        out: &mut Vec<PcmSample>,
    ) -> Result<(), ResamplerError> {
        if input.len() % self.channels != 0 {
            return Err(ResamplerError::SampleCountNotFrameAligned);
        }

        if input.is_empty() {
            return Ok(());
        }

        self.frames.extend_from_slice(input);
        self.emit_available(out);
        self.compact();

        Ok(())
    }

    /// Flush the final source frame into the output stream.
    pub fn flush(&mut self, out: &mut Vec<PcmSample>) -> Result<(), ResamplerError> {
        if self.frames.is_empty() {
            return Ok(());
        }

        let frame_count = self.frames.len() / self.channels;

        while self.next_position < frame_count as f64 {
            let left = self.next_position.floor() as usize;
            let right = (left + 1).min(frame_count - 1);
            let fraction = self.next_position - left as f64;

            for channel in 0..self.channels {
                let a = self.frames[left * self.channels + channel] as f64;
                let b = self.frames[right * self.channels + channel] as f64;
                out.push(linear_interpolate(a, b, fraction));
            }

            self.next_position += self.step;
        }

        self.frames.clear();
        self.next_position = 0.0;

        Ok(())
    }

    fn emit_available(&mut self, out: &mut Vec<PcmSample>) {
        let frame_count = self.frames.len() / self.channels;

        while self.next_position + 1.0 < frame_count as f64 {
            let left = self.next_position.floor() as usize;
            let right = left + 1;
            let fraction = self.next_position - left as f64;

            for channel in 0..self.channels {
                let a = self.frames[left * self.channels + channel] as f64;
                let b = self.frames[right * self.channels + channel] as f64;
                out.push(linear_interpolate(a, b, fraction));
            }

            self.next_position += self.step;
        }
    }

    fn compact(&mut self) {
        let frame_count = self.frames.len() / self.channels;

        if frame_count <= 1 {
            return;
        }

        let retain_frame = self.next_position.floor().max(1.0) as usize - 1;

        if retain_frame == 0 {
            return;
        }

        let retain_sample = retain_frame * self.channels;
        self.frames.drain(..retain_sample);
        self.next_position -= retain_frame as f64;
    }
}

#[inline]
fn linear_interpolate(a: f64, b: f64, fraction: f64) -> PcmSample {
    let value = a + (b - a) * fraction;
    value.round().clamp(i32::MIN as f64, i32::MAX as f64) as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn downsample_96k_to_48k_halves_frame_rate() {
        let mut resampler = LinearResampler::new(96_000, 48_000, 1).unwrap();
        let mut output = Vec::new();

        resampler
            .process(&[0, 100, 200, 300, 400, 500], &mut output)
            .unwrap();
        resampler.flush(&mut output).unwrap();

        assert_eq!(output, vec![0, 200, 400]);
    }

    #[test]
    fn upsampling_44_1_to_48_preserves_endpoints() {
        let mut resampler = LinearResampler::new(44_100, 48_000, 1).unwrap();
        let mut output = Vec::new();

        resampler.process(&[0, 100, 200], &mut output).unwrap();
        resampler.flush(&mut output).unwrap();

        assert_eq!(output.first(), Some(&0));
        assert_eq!(output.last(), Some(&200));
        assert!(output.len() >= 3);
    }

    #[test]
    fn stereo_interleaving_is_preserved() {
        let mut resampler = LinearResampler::new(96_000, 48_000, 2).unwrap();
        let mut output = Vec::new();

        resampler
            .process(&[0, 10, 100, 110, 200, 210], &mut output)
            .unwrap();
        resampler.flush(&mut output).unwrap();

        assert_eq!(&output[..2], &[0, 10]);
        assert_eq!(&output[2..4], &[200, 210]);
    }
}
