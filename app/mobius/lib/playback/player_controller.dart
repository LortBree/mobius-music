import 'dart:async';

import '../core/ffi/offline_player.dart';
import 'audio_output_policy.dart';

class PlayerController {
  PlayerController(this._player);

  final OfflinePlayer _player;

  final AudioOutputPolicy _audioOutputPolicy =
      const AudioOutputPolicy();

  Timer? _sleepTimer;
  bool _sleepAtEndOfTrack = false;

  AudioOutputMode _audioOutputMode =
      AudioOutputMode.auto;
  double _volume = 1.0;

  void load(int trackId) {
    _player.loadTrack(trackId);
  }

  void play() {
    _player.play();
  }

  void pause() {
    _player.pause();
  }

  void stop() {
    _player.stop();
  }

  void seekToFrame(int frame) {
    _player.seekToFrame(frame);
  }

  double get volume => _volume;

  void setVolume(double volume) {
    final next = volume.clamp(0.0, 1.0);
    _player.setVolume(next);
    _volume = next;
  }

  void setEqualizerGains(List<double> gainsDb) {
    if (gainsDb.length != 10) {
      throw ArgumentError.value(gainsDb.length, 'gainsDb.length', 'Must be 10');
    }
    _player.setEqualizerGains(gainsDb);
  }

  void setQueue(List<int> trackIds) {
    _player.setQueue(trackIds);
  }

  void clearQueue() {
    _player.clearQueue();
  }

  void addToQueue(int trackId) {
    _player.addToQueue(trackId);
  }

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepAtEndOfTrack = false;
    _sleepTimer = Timer(duration, () {
      _sleepTimer = null;
      if (state == OfflinePlayerState.playing) {
        pause();
      }
    });
  }

  void sleepAtEndOfTrack() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAtEndOfTrack = true;
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAtEndOfTrack = false;
  }

  /// Advances according to the shared repeat semantics.
  ///
  /// Repeat Track repeats the current item.
  /// Repeat Queue wraps to the first item.
  /// Repeat Off advances normally.
  void next() {
    switch (repeatMode) {
      case OfflinePlayerRepeatMode.off:
        _player.nextQueueAndPlay();
        break;

      case OfflinePlayerRepeatMode.track:
        _player.repeatCurrentQueueTrackAndPlay();
        break;

      case OfflinePlayerRepeatMode.queue:
        final length = queueLength;

        if (length <= 0) {
          return;
        }

        final index = queueCurrentIndex;

        if (index >= length - 1) {
          _player.selectAndPlayQueueIndex(0);
        } else {
          _player.nextQueueAndPlay();
        }
        break;
    }
  }

  void previous() {
    _player.previousQueueAndPlay();
  }

  void select(int index) {
    _player.selectAndLoadQueueIndex(index);
  }

  void selectAndPlay(int index) {
    _player.selectAndPlayQueueIndex(index);
  }

  void repeatCurrent() {
    _player.repeatCurrentQueueTrackAndPlay();
  }

  void advance() {
    _player.advanceQueueAndPlay();
  }

  bool advanceIfAtEnd() {
    return _player.advanceQueueIfAtEnd();
  }

  /// Handles natural end-of-track progression.
  ///
  /// UI pages can call this from their existing display timers.
  /// Repeat/EOF policy remains centralized here rather than living
  /// separately in LibraryPage and NowPlayingPage.
  void pollPlayback() {
    if (state != OfflinePlayerState.playing) {
      return;
    }

    final duration = durationSeconds;

    if (duration <= 0) {
      return;
    }

    final position = currentSeconds;

    if (_sleepAtEndOfTrack && position >= duration - 0.15) {
      cancelSleepTimer();
      pause();
      return;
    }

    if (position >= duration - 0.15) {
      advanceIfAtEnd();
    }
  }

  OfflinePlayerState get state {
    return _player.state;
  }

  int get currentFrame {
    return _player.currentFrame;
  }

  double get currentSeconds {
    return _player.currentSeconds;
  }

  double get durationSeconds {
    return _player.durationSeconds;
  }

  int get totalFrames {
    return _player.totalFrames;
  }

  int get sampleRate {
    return _player.sampleRate;
  }

  int get channels {
    return _player.channels;
  }

  int get bitsPerSample {
    return _player.bitsPerSample;
  }

  TrackTechnicalInfo get technicalInfo {
    return _player.technicalInfo;
  }

  AudioOutputMode get audioOutputMode {
    return _audioOutputMode;
  }

  void setAudioOutputMode(
    AudioOutputMode mode,
  ) {
    _player.setOutputMode(_toOfflineOutputMode(mode));
    _audioOutputMode = mode;
  }

  OfflinePlayerOutputMode get outputMode {
    return _player.outputMode;
  }

  void setOutputMode(
    OfflinePlayerOutputMode mode,
  ) {
    _player.setOutputMode(mode);
    _audioOutputMode = _toAudioOutputMode(mode);
  }

  AudioOutputDecision get audioOutputDecision {
    final sourceRate = sampleRate;

    if (sourceRate <= 0) {
      throw StateError(
        'Current track has an invalid sample rate.',
      );
    }

    return _audioOutputPolicy.resolve(
      sourceRate: sourceRate,
      mode: _audioOutputMode,
    );
  }

  int get effectiveOutputRate {
    return audioOutputDecision.effectiveRate;
  }

  AudioPlaybackStatus get audioPlaybackStatus {
    return audioOutputDecision.status;
  }

  bool get isNativePlayback {
    return audioOutputDecision.isNative;
  }

  bool get isResampling {
    return audioOutputDecision.isResample;
  }

  int get queueLength {
    return _player.queueLength;
  }

  List<int> get queueTrackIds => _player.queueTrackIds;

  int get queueUpNextCount => _player.queueUpNextCount;

  void reorderQueueSegment(int start, List<int> trackIds) {
    _player.reorderQueueSegment(start, trackIds);
  }

  int get queueCurrentIndex {
    return _player.queueCurrentIndex;
  }

  int get currentTrackId {
    return _player.queueCurrentTrackId;
  }

  OfflinePlayerRepeatMode get repeatMode {
    return _player.repeatMode;
  }

  void setRepeatMode(
    OfflinePlayerRepeatMode mode,
  ) {
    _player.setRepeatMode(mode);
  }

  void toggleRepeatMode() {
    final nextMode =
        switch (repeatMode) {
      OfflinePlayerRepeatMode.off =>
        OfflinePlayerRepeatMode.track,
      OfflinePlayerRepeatMode.track =>
        OfflinePlayerRepeatMode.queue,
      OfflinePlayerRepeatMode.queue =>
        OfflinePlayerRepeatMode.off,
    };

    setRepeatMode(nextMode);
  }

  // ---------------------------------------------------------------------------
  // Output mode mapping
  // ---------------------------------------------------------------------------

  OfflinePlayerOutputMode _toOfflineOutputMode(
    AudioOutputMode mode,
  ) {
    switch (mode) {
      case AudioOutputMode.auto:
        return OfflinePlayerOutputMode.auto;

      case AudioOutputMode.khz44_1:
        return OfflinePlayerOutputMode.khz44_1;

      case AudioOutputMode.khz48:
        return OfflinePlayerOutputMode.khz48;

      case AudioOutputMode.khz96:
        return OfflinePlayerOutputMode.khz96;
    }
  }

  AudioOutputMode _toAudioOutputMode(
    OfflinePlayerOutputMode mode,
  ) {
    switch (mode) {
      case OfflinePlayerOutputMode.auto:
        return AudioOutputMode.auto;

      case OfflinePlayerOutputMode.khz44_1:
        return AudioOutputMode.khz44_1;

      case OfflinePlayerOutputMode.khz48:
        return AudioOutputMode.khz48;

      case OfflinePlayerOutputMode.khz96:
        return AudioOutputMode.khz96;
    }
  }
}
