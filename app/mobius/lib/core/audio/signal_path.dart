/// Live description of how the current track reaches the speaker, for the
/// Signal path UI. Produced by the engine (FFI `offline_player_signal_path`)
/// plus, on Android, the output route reported by the host.
///
/// Honesty rule: [bitPerfect] comes ONLY from the engine's ground truth; it is
/// never inferred from a sample-rate comparison, and it is always false on
/// Android (the system mixer owns that route).
class SignalPath {
  const SignalPath({
    required this.sourceFormat,
    required this.sourceSampleRate,
    required this.sourceBitsPerSample,
    required this.sourceChannels,
    required this.lossless,
    required this.outputSampleRate,
    required this.outputChannels,
    required this.outputBitsPerSample,
    required this.outputIsFloat,
    required this.resampling,
    required this.equalizerActive,
    required this.equalizerBands,
    required this.volume,
    required this.bitPerfect,
    required this.bufferMs,
    required this.underrunSamples,
    required this.callbackCount,
    required this.outputApi,
    required this.route,
    required this.deviceName,
  });

  /// Display format of the file, e.g. 'FLAC', 'WAV'.
  final String sourceFormat;
  final int sourceSampleRate;
  final int sourceBitsPerSample;
  final int sourceChannels;
  final bool lossless;

  /// What the engine actually hands to the OS / device.
  final int outputSampleRate;
  final int outputChannels;
  final int outputBitsPerSample;
  final bool outputIsFloat;

  /// True when the engine converts the sample rate before output.
  final bool resampling;

  /// True when the EQ is enabled AND at least one band is non-zero.
  final bool equalizerActive;
  final int equalizerBands;

  /// Software volume, 0..1 (1 = untouched).
  final double volume;

  /// Engine-confirmed bit-perfect path. Always false on Android.
  final bool bitPerfect;

  /// Audio currently buffered ahead of the device, in milliseconds.
  final int bufferMs;
  final int underrunSamples;
  final int callbackCount;

  /// Output backend, e.g. 'AAudio', 'CoreAudio'.
  final String outputApi;
  final OutputRoute route;

  /// Human-readable output device ('Built-in speaker', a DAC name...). May be
  /// empty when the platform cannot tell.
  final String deviceName;

  /// DSP stages that alter the samples (EQ, software volume below 1).
  bool get dspActive => equalizerActive || volume < 0.999;
}

/// Where the audio physically goes.
enum OutputRoute { unknown, speaker, wired, bluetooth, usb }
