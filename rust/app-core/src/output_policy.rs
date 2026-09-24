#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputPolicy {
    Auto,
    Fixed { sample_rate: u32 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputPlan {
    Native {
        sample_rate: u32,
    },
    Resample {
        source_sample_rate: u32,
        output_sample_rate: u32,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputPolicyError {
    InvalidSourceSampleRate,
    InvalidRequestedSampleRate,
    NoSupportedOutputRate,
    RequestedRateUnsupported { requested_sample_rate: u32 },
    NoSupportedRateWithoutUpsampling { source_sample_rate: u32 },
}

impl std::fmt::Display for OutputPolicyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidSourceSampleRate => {
                write!(f, "source sample rate must be greater than zero")
            }

            Self::InvalidRequestedSampleRate => {
                write!(f, "requested output sample rate must be greater than zero")
            }

            Self::NoSupportedOutputRate => {
                write!(f, "output device reports no supported sample rates")
            }

            Self::RequestedRateUnsupported {
                requested_sample_rate,
            } => write!(
                f,
                "requested output sample rate {} Hz is not supported by the output device",
                requested_sample_rate
            ),

            Self::NoSupportedRateWithoutUpsampling { source_sample_rate } => write!(
                f,
                "no supported output rate is available without upsampling source rate {} Hz",
                source_sample_rate
            ),
        }
    }
}

impl std::error::Error for OutputPolicyError {}

impl OutputPolicy {
    pub fn plan(
        self,
        source_sample_rate: u32,
        supported_sample_rates: &[u32],
    ) -> Result<OutputPlan, OutputPolicyError> {
        if source_sample_rate == 0 {
            return Err(OutputPolicyError::InvalidSourceSampleRate);
        }

        if supported_sample_rates.is_empty() {
            return Err(OutputPolicyError::NoSupportedOutputRate);
        }

        match self {
            Self::Auto => {
                // Auto mode keeps high-resolution sources on the widely
                // supported 44.1/48 kHz path instead of renegotiating devices
                // at 96 kHz or above. Use native output when the source is
                // already within that ceiling.
                const AUTO_MAX_SAMPLE_RATE: u32 = 48_000;
                let ceiling = source_sample_rate.min(AUTO_MAX_SAMPLE_RATE);
                let output_sample_rate = supported_sample_rates
                    .iter()
                    .copied()
                    .filter(|&rate| rate > 0 && rate <= ceiling)
                    .max();

                let Some(output_sample_rate) = output_sample_rate else {
                    if supported_sample_rates.contains(&source_sample_rate) {
                        return Ok(OutputPlan::Native {
                            sample_rate: source_sample_rate,
                        });
                    }

                    return Err(OutputPolicyError::NoSupportedRateWithoutUpsampling {
                        source_sample_rate,
                    });
                };

                if output_sample_rate == source_sample_rate {
                    return Ok(OutputPlan::Native {
                        sample_rate: source_sample_rate,
                    });
                }

                Ok(OutputPlan::Resample {
                    source_sample_rate,
                    output_sample_rate,
                })
            }

            Self::Fixed { sample_rate } => {
                if sample_rate == 0 {
                    return Err(OutputPolicyError::InvalidRequestedSampleRate);
                }

                if !supported_sample_rates.contains(&sample_rate) {
                    return Err(OutputPolicyError::RequestedRateUnsupported {
                        requested_sample_rate: sample_rate,
                    });
                }

                //
                // Fixed is a maximum output rate, not a forced target.
                //
                // Never upsample a source just because the user selected
                // a higher output rate.
                //
                if source_sample_rate <= sample_rate {
                    return Ok(OutputPlan::Native {
                        sample_rate: source_sample_rate,
                    });
                }

                Ok(OutputPlan::Resample {
                    source_sample_rate,
                    output_sample_rate: sample_rate,
                })
            }
        }
    }

    pub fn plan_native(
        source_sample_rate: u32,
        supported_sample_rates: &[u32],
    ) -> Result<OutputPlan, OutputPolicyError> {
        Self::Fixed {
            sample_rate: source_sample_rate,
        }
        .plan(source_sample_rate, supported_sample_rates)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MAC_BUILTIN_RATES: &[u32] = &[44_100, 48_000];

    #[test]
    fn auto_keeps_44100_native() {
        assert_eq!(
            OutputPolicy::Auto.plan(44_100, MAC_BUILTIN_RATES),
            Ok(OutputPlan::Native {
                sample_rate: 44_100
            })
        );
    }

    #[test]
    fn auto_keeps_48000_native() {
        assert_eq!(
            OutputPolicy::Auto.plan(48_000, MAC_BUILTIN_RATES),
            Ok(OutputPlan::Native {
                sample_rate: 48_000
            })
        );
    }

    #[test]
    fn auto_resamples_96000_to_48000() {
        assert_eq!(
            OutputPolicy::Auto.plan(96_000, MAC_BUILTIN_RATES),
            Ok(OutputPlan::Resample {
                source_sample_rate: 96_000,
                output_sample_rate: 48_000,
            })
        );
    }

    #[test]
    fn auto_resamples_192000_to_48000() {
        assert_eq!(
            OutputPolicy::Auto.plan(192_000, MAC_BUILTIN_RATES),
            Ok(OutputPlan::Resample {
                source_sample_rate: 192_000,
                output_sample_rate: 48_000,
            })
        );
    }

    #[test]
    fn auto_does_not_upsample_32000() {
        assert_eq!(
            OutputPolicy::Auto.plan(32_000, MAC_BUILTIN_RATES),
            Err(OutputPolicyError::NoSupportedRateWithoutUpsampling {
                source_sample_rate: 32_000,
            })
        );
    }

    #[test]
    fn fixed_44100_keeps_44100_native() {
        assert_eq!(
            OutputPolicy::Fixed {
                sample_rate: 44_100
            }
            .plan(44_100, MAC_BUILTIN_RATES),
            Ok(OutputPlan::Native {
                sample_rate: 44_100
            })
        );
    }

    #[test]
    fn fixed_44100_resamples_48000_to_44100() {
        assert_eq!(
            OutputPolicy::Fixed {
                sample_rate: 44_100
            }
            .plan(48_000, MAC_BUILTIN_RATES),
            Ok(OutputPlan::Resample {
                source_sample_rate: 48_000,
                output_sample_rate: 44_100,
            })
        );
    }

    #[test]
    fn fixed_48000_keeps_44100_native() {
        assert_eq!(
            OutputPolicy::Fixed {
                sample_rate: 48_000
            }
            .plan(44_100, MAC_BUILTIN_RATES),
            Ok(OutputPlan::Native {
                sample_rate: 44_100
            })
        );
    }

    #[test]
    fn fixed_48000_keeps_48000_native() {
        assert_eq!(
            OutputPolicy::Fixed {
                sample_rate: 48_000
            }
            .plan(48_000, MAC_BUILTIN_RATES),
            Ok(OutputPlan::Native {
                sample_rate: 48_000
            })
        );
    }

    #[test]
    fn fixed_48000_resamples_96000_to_48000() {
        assert_eq!(
            OutputPolicy::Fixed {
                sample_rate: 48_000
            }
            .plan(96_000, MAC_BUILTIN_RATES),
            Ok(OutputPlan::Resample {
                source_sample_rate: 96_000,
                output_sample_rate: 48_000,
            })
        );
    }
}
