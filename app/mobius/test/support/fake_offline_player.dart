import 'package:mobius/core/ffi/offline_player.dart';

/// A minimal fake [OfflinePlayer] for widget tests that need a real shell or
/// Now Playing page but no actual audio engine. It reports an idle player with
/// no loaded track and an empty library/queue, which is enough for the shells
/// to render their empty state. A single track can be simulated by passing
/// [track] (and optionally [playing]).
class FakeOfflinePlayer implements OfflinePlayer {
  FakeOfflinePlayer({this.track, this.playing = false, SignalPath? signalPath})
    : _signalPath = signalPath;

  /// When non-null, the player reports this as the single loaded/queued track.
  final TrackMetadata? track;
  final bool playing;

  /// Explicit signal path to report, overriding the default derived one. When
  /// a test wants to exercise the Signal path UI it injects a fixed one here.
  final SignalPath? _signalPath;

  bool get _hasTrack => track != null;

  /// Mirrors the real engine getter: throws when nothing is loaded (so
  /// `PlayerController.readSignalPath()` resolves to null), otherwise returns
  /// the injected path or a plausible default built from the fake track.
  @override
  SignalPath get signalPath {
    if (!_hasTrack) {
      throw const OfflinePlayerException(5, 'No track loaded');
    }
    return _signalPath ??
        const SignalPath(
          sourceFormat: 'FLAC',
          sourceSampleRate: 44100,
          sourceBitsPerSample: 16,
          sourceChannels: 2,
          lossless: true,
          outputSampleRate: 48000,
          outputChannels: 2,
          outputBitsPerSample: 32,
          outputIsFloat: true,
          resampling: true,
          equalizerActive: false,
          equalizerBands: 10,
          volume: 1.0,
          bitPerfect: false,
          bufferMs: 120,
          underrunSamples: 0,
          callbackCount: 1024,
          outputApi: 'CoreAudio',
          route: OutputRoute.speaker,
          deviceName: 'Built-in Speaker',
        );
  }

  @override
  OfflinePlayerState get state => _hasTrack
      ? (playing ? OfflinePlayerState.playing : OfflinePlayerState.paused)
      : OfflinePlayerState.idle;

  @override
  OfflinePlayerRepeatMode get repeatMode => OfflinePlayerRepeatMode.off;

  @override
  OfflinePlayerOutputMode get outputMode => OfflinePlayerOutputMode.auto;

  @override
  double get currentSeconds => 0;

  @override
  double get durationSeconds => _hasTrack ? 180 : 0;

  @override
  int get currentFrame => 0;

  @override
  int get totalFrames => _hasTrack ? 180 * 44100 : 0;

  @override
  int get sampleRate => _hasTrack ? 44100 : 0;

  @override
  int get channels => 2;

  @override
  int get bitsPerSample => 16;

  @override
  int get effectiveOutputRate => _hasTrack ? 48000 : 0;

  @override
  int get queueLength => _hasTrack ? 1 : 0;

  @override
  int get queueCurrentIndex => 0;

  @override
  int get queueCurrentTrackId => track?.trackId ?? 0;

  @override
  int get queueUpNextCount => 0;

  final List<int> queuedTrackIds = [];

  @override
  void addToQueue(int trackId) {
    queuedTrackIds.add(trackId);
  }

  @override
  List<int> get queueTrackIds => _hasTrack ? [track!.trackId] : const <int>[];

  @override
  List<int> getTrackIds() => _hasTrack ? [track!.trackId] : const <int>[];

  @override
  TrackMetadata getTrackMetadata(int trackId) {
    final t = track;
    if (t != null && t.trackId == trackId) return t;
    throw StateError('No track $trackId');
  }

  @override
  TrackArtwork? getTrackArtwork(int trackId) => null;

  @override
  TrackTechnicalInfo get technicalInfo => const TrackTechnicalInfo(
    format: 'FLAC',
    sampleRate: 44100,
    bitsPerSample: 16,
    channels: 2,
  );

  // Everything else (mutating calls, FFI-only members) is unused by these
  // tests; fail loudly if a test path unexpectedly reaches one.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
