#![cfg_attr(not(test), allow(dead_code))]

pub mod equalizer;
pub mod output_policy;
pub mod resampler;

pub use equalizer::{EqualizerSettings, GraphicEqualizer, EQUALIZER_BANDS_HZ};
pub use output_policy::{OutputPlan, OutputPolicy, OutputPolicyError};
pub use resampler::{LinearResampler, ResamplerError};

use std::fmt;

pub type PcmSample = i32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PcmRingConfig {
    pub capacity_samples: usize,
}

impl PcmRingConfig {
    pub fn new(capacity_samples: usize) -> Self {
        assert!(
            capacity_samples > 0,
            "PCM ring capacity must be greater than zero"
        );

        Self { capacity_samples }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PcmRingError {
    Full,
    Empty,
    InvalidLength,
}

impl fmt::Display for PcmRingError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Full => write!(f, "PCM ring buffer is full"),
            Self::Empty => write!(f, "PCM ring buffer is empty"),
            Self::InvalidLength => {
                write!(f, "PCM operation requires a non-zero length")
            }
        }
    }
}

impl std::error::Error for PcmRingError {}

pub struct PcmProducer {
    producer: rtrb::Producer<PcmSample>,
}

pub struct PcmConsumer {
    consumer: rtrb::Consumer<PcmSample>,
}

pub fn pcm_ring_buffer(config: PcmRingConfig) -> (PcmProducer, PcmConsumer) {
    let (producer, consumer) = rtrb::RingBuffer::<PcmSample>::new(config.capacity_samples);

    (PcmProducer { producer }, PcmConsumer { consumer })
}

impl PcmProducer {
    #[inline]
    pub fn slots(&self) -> usize {
        self.producer.slots()
    }

    #[inline]
    pub fn capacity_remaining(&self) -> usize {
        self.producer.slots()
    }

    #[inline]
    pub fn try_push(&mut self, sample: PcmSample) -> Result<(), PcmRingError> {
        self.producer.push(sample).map_err(|_| PcmRingError::Full)
    }

    pub fn push_slice(&mut self, src: &[PcmSample]) -> usize {
        if src.is_empty() {
            return 0;
        }

        let available = self.producer.slots();
        let count = src.len().min(available);

        if count == 0 {
            return 0;
        }

        let mut pushed = 0usize;

        for &sample in &src[..count] {
            match self.producer.push(sample) {
                Ok(()) => {
                    pushed += 1;
                }
                Err(_) => {
                    break;
                }
            }
        }

        pushed
    }
}

impl PcmConsumer {
    #[inline]
    pub fn len(&self) -> usize {
        self.consumer.slots()
    }

    #[inline]
    pub fn is_empty(&self) -> bool {
        self.consumer.slots() == 0
    }

    #[inline]
    pub fn try_pop(&mut self) -> Result<PcmSample, PcmRingError> {
        self.consumer.pop().map_err(|_| PcmRingError::Empty)
    }

    pub fn pop_slice(&mut self, dst: &mut [PcmSample]) -> usize {
        if dst.is_empty() {
            return 0;
        }

        let available = self.consumer.slots();
        let count = dst.len().min(available);

        if count == 0 {
            return 0;
        }

        let mut popped = 0usize;

        for slot in &mut dst[..count] {
            match self.consumer.pop() {
                Ok(sample) => {
                    *slot = sample;
                    popped += 1;
                }
                Err(_) => {
                    break;
                }
            }
        }

        popped
    }

    #[inline]
    pub fn fill_available(&mut self, dst: &mut [PcmSample]) -> usize {
        self.pop_slice(dst)
    }
}

/// Expand a signed integer PCM sample into a wider valid-bit domain.
///
/// Example:
///     i16 -> 24-bit:
///     32767 -> 8_388_352
///
/// This is bit-domain expansion, not gain normalization.
#[inline]
pub fn expand_signed_integer(
    sample: i32,
    source_bits: u32,
    output_bits: u32,
) -> Result<i32, PcmFormatError> {
    if source_bits == 0 || output_bits == 0 || source_bits > 32 || output_bits > 32 {
        return Err(PcmFormatError::InvalidBitDepth);
    }

    if source_bits > output_bits {
        return Err(PcmFormatError::SourceWiderThanOutput {
            source_bits,
            output_bits,
        });
    }

    let shift = output_bits - source_bits;

    if shift == 0 {
        return Ok(sample);
    }

    //
    // source_bits <= output_bits <= 32.
    //
    // We explicitly reject 32-bit output expansion because a
    // positive shift from a true 32-bit signed domain cannot fit.
    //
    if shift >= 31 {
        return Err(PcmFormatError::InvalidBitDepth);
    }

    Ok(sample << shift)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PcmFormatError {
    InvalidBitDepth,
    SourceWiderThanOutput { source_bits: u32, output_bits: u32 },
}

impl fmt::Display for PcmFormatError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidBitDepth => {
                write!(f, "invalid PCM bit depth")
            }

            Self::SourceWiderThanOutput {
                source_bits,
                output_bits,
            } => {
                write!(
                    f,
                    "source PCM is wider than output: \
                     {} bits -> {} bits",
                    source_bits, output_bits,
                )
            }
        }
    }
}

impl std::error::Error for PcmFormatError {}

pub struct AudioEngine;

impl AudioEngine {
    pub fn new() -> Self {
        Self
    }
}

impl Default for AudioEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_ring_and_splits_handles() {
        let config = PcmRingConfig::new(8);

        let (_producer, _consumer) = pcm_ring_buffer(config);
    }

    #[test]
    fn producer_and_consumer_exchange_samples() {
        let config = PcmRingConfig::new(8);

        let (mut producer, mut consumer) = pcm_ring_buffer(config);

        assert_eq!(producer.push_slice(&[1, 2, 3, 4],), 4);

        assert_eq!(consumer.len(), 4);

        let mut output = [0i32; 4];

        assert_eq!(consumer.pop_slice(&mut output,), 4);

        assert_eq!(output, [1, 2, 3, 4]);

        assert!(consumer.is_empty());
    }

    #[test]
    fn producer_does_not_overwrite_full_ring() {
        let config = PcmRingConfig::new(4);

        let (mut producer, mut consumer) = pcm_ring_buffer(config);

        assert_eq!(producer.push_slice(&[10, 20, 30, 40, 50],), 4);

        let mut output = [0i32; 4];

        assert_eq!(consumer.pop_slice(&mut output,), 4);

        assert_eq!(output, [10, 20, 30, 40]);
    }

    #[test]
    fn consumer_returns_empty_when_no_data_exists() {
        let config = PcmRingConfig::new(8);

        let (_producer, mut consumer) = pcm_ring_buffer(config);

        assert_eq!(consumer.try_pop(), Err(PcmRingError::Empty));
    }

    #[test]
    fn audio_engine_has_compatibility_constructor() {
        let _engine = AudioEngine::new();
    }

    #[test]
    fn expands_i16_to_24bit() {
        assert_eq!(expand_signed_integer(0, 16, 24), Ok(0));

        assert_eq!(expand_signed_integer(1, 16, 24), Ok(256));

        assert_eq!(expand_signed_integer(-1, 16, 24), Ok(-256));

        assert_eq!(
            expand_signed_integer(i16::MAX as i32, 16, 24),
            Ok(8_388_352)
        );

        assert_eq!(
            expand_signed_integer(i16::MIN as i32, 16, 24),
            Ok(-8_388_608)
        );
    }

    #[test]
    fn leaves_same_bit_depth_unchanged() {
        assert_eq!(expand_signed_integer(123_456, 24, 24), Ok(123_456));
    }

    #[test]
    fn rejects_narrowing() {
        assert_eq!(
            expand_signed_integer(100, 24, 16),
            Err(PcmFormatError::SourceWiderThanOutput {
                source_bits: 24,
                output_bits: 16,
            })
        );
    }
}
