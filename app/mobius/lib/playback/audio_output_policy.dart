enum AudioOutputMode {
  auto,
  khz44_1,
  khz48,
  khz96,
}

enum AudioPlaybackStatus {
  native,
  resample,
}

class AudioOutputDecision {
  const AudioOutputDecision({
    required this.sourceRate,
    required this.requestedRate,
    required this.effectiveRate,
    required this.status,
  });

  final int sourceRate;
  final int? requestedRate;
  final int effectiveRate;
  final AudioPlaybackStatus status;

  bool get isNative => status == AudioPlaybackStatus.native;
  bool get isResample => status == AudioPlaybackStatus.resample;
}

class AudioOutputPolicy {
  const AudioOutputPolicy({this.maxOutputRate = 48000});

  final int maxOutputRate;

  AudioOutputDecision resolve({
    required int sourceRate,
    required AudioOutputMode mode,
  }) {
    if (sourceRate <= 0) {
      throw ArgumentError.value(
        sourceRate,
        'sourceRate',
        'Source sample rate must be greater than zero.',
      );
    }

    final requestedRate = _requestedRate(mode);
    final targetRate = requestedRate ?? maxOutputRate;
    final effectiveRate = _resolveEffectiveRate(
      sourceRate: sourceRate,
      targetRate: targetRate,
    );

    final status = effectiveRate == sourceRate
        ? AudioPlaybackStatus.native
        : AudioPlaybackStatus.resample;

    return AudioOutputDecision(
      sourceRate: sourceRate,
      requestedRate: requestedRate,
      effectiveRate: effectiveRate,
      status: status,
    );
  }

  int? _requestedRate(AudioOutputMode mode) {
    switch (mode) {
      case AudioOutputMode.auto:
        return null;
      case AudioOutputMode.khz44_1:
        return 44100;
      case AudioOutputMode.khz48:
        return 48000;
      case AudioOutputMode.khz96:
        return 96000;
    }
  }

  int _resolveEffectiveRate({
    required int sourceRate,
    required int targetRate,
  }) {
    if (sourceRate <= targetRate) {
      return sourceRate;
    }

    return targetRate;
  }
}

String formatSampleRate(int sampleRate) {
  if (sampleRate <= 0) {
    return 'Unknown';
  }

  final khz = sampleRate / 1000;
  final text = khz.toStringAsFixed(khz == khz.roundToDouble() ? 0 : 1);
  return '$text kHz';
}

String audioPlaybackStatusLabel(AudioPlaybackStatus status) {
  switch (status) {
    case AudioPlaybackStatus.native:
      return 'Native';
    case AudioPlaybackStatus.resample:
      return 'Resampled';
  }
}
