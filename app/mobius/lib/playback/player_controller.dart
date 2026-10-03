import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/ffi/offline_player.dart';
import '../core/macos/macos_playback_activity.dart';
import 'audio_output_policy.dart';

class PlayerController {
  PlayerController(
    this._player, {
    Future<void> Function()? yieldFrame,
    this.onVolumeChanged,
    Future<void> Function()? beginPlaybackActivity,
    Future<void> Function()? endPlaybackActivity,
  })  : _yieldFrame = yieldFrame ?? _endOfFrame,
        _beginPlaybackActivity =
            beginPlaybackActivity ?? MacOSPlaybackActivity.start,
        _endPlaybackActivity =
            endPlaybackActivity ?? MacOSPlaybackActivity.stop;

  final OfflinePlayer _player;
  final Future<void> Function() _yieldFrame;

  /// Called after every accepted volume change (used to persist it).
  final void Function(double volume)? onVolumeChanged;

  /// Host hooks that hold/release the macOS App-Nap + idle-sleep assertion so
  /// background playback does not stall. Injectable for tests.
  final Future<void> Function() _beginPlaybackActivity;
  final Future<void> Function() _endPlaybackActivity;

  /// Tracks whether the activity assertion is currently held, so we only call
  /// the host when the playing/not-playing state actually flips.
  bool _playbackActivityHeld = false;

  static Future<void> _endOfFrame() => SchedulerBinding.instance.endOfFrame;

  final ValueNotifier<int?> _pendingTrackId = ValueNotifier<int?>(null);

  /// The track a user command is about to switch to, published one frame
  /// BEFORE the native load runs.
  ///
  /// A bit-perfect track change may re-clock the output device, and that
  /// native call blocks this (UI) thread for up to ~1 s. Publishing the
  /// target first lets views paint the new title and artwork, so the pause
  /// reads as "loading the next song" instead of a frozen app.
  ValueListenable<int?> get pendingTrackId => _pendingTrackId;

  /// Runs [action] after announcing [targetTrackId]. When
  /// [notifyUnlessFalse] is set and [action] returns `false` (nothing
  /// changed), no command is signalled.
  Future<void> _switchTrack(
    int? targetTrackId,
    Object? Function() action, {
    bool notifyUnlessFalse = false,
  }) async {
    var announced = false;
    if (targetTrackId != null &&
        targetTrackId > 0 &&
        targetTrackId != _safeCurrentTrackId()) {
      _pendingTrackId.value = targetTrackId;
      announced = true;
      await _yieldFrame();
    }

    try {
      final result = action();
      if (!(notifyUnlessFalse && result == false)) _commandIssued();
    } finally {
      if (announced) _pendingTrackId.value = null;
    }
  }

  int _safeCurrentTrackId() {
    try {
      return currentTrackId;
    } catch (_) {
      return 0;
    }
  }

  int? _queueTrackIdAt(int index) {
    try {
      final ids = queueTrackIds;
      return index >= 0 && index < ids.length ? ids[index] : null;
    } catch (_) {
      return null;
    }
  }

  /// Where [next] will land, mirroring its repeat semantics.
  int? _nextTarget() {
    try {
      final index = queueCurrentIndex;
      final length = queueLength;
      switch (repeatMode) {
        case OfflinePlayerRepeatMode.off:
          return _queueTrackIdAt(index + 1);
        case OfflinePlayerRepeatMode.track:
          return null; // same track: no rate change, nothing to announce
        case OfflinePlayerRepeatMode.queue:
          return _queueTrackIdAt(index >= length - 1 ? 0 : index + 1);
      }
    } catch (_) {
      return null;
    }
  }

  final ValueNotifier<int> _commandCount = ValueNotifier<int>(0);

  /// Fires after every command that can change playback or queue state, so
  /// views can refresh immediately and poll slowly while nothing plays.
  Listenable get commands => _commandCount;

  void _commandIssued() {
    _commandCount.value++;
    _syncPlaybackActivity();
  }

  /// Holds the macOS activity assertion while the engine is actually playing
  /// and releases it otherwise. Driven off the engine's own state (not the
  /// specific command) so every play/pause/stop/next/auto-advance path is
  /// covered. Only calls the host when the held/not-held state flips.
  void _syncPlaybackActivity() {
    final playing = _safeIsPlaying();
    if (playing == _playbackActivityHeld) {
      return;
    }

    _playbackActivityHeld = playing;
    if (playing) {
      unawaited(_beginPlaybackActivity());
    } else {
      unawaited(_endPlaybackActivity());
    }
  }

  bool _safeIsPlaying() {
    try {
      return state == OfflinePlayerState.playing;
    } catch (_) {
      return false;
    }
  }

  final AudioOutputPolicy _audioOutputPolicy = const AudioOutputPolicy();

  Timer? _sleepTimer;
  bool _sleepAtEndOfTrack = false;

  AudioOutputMode _audioOutputMode = AudioOutputMode.auto;
  double _volume = 1.0;
  final ValueNotifier<double> _volumeNotifier = ValueNotifier<double>(1.0);

  /// The current output volume, 0.0–1.0, as a listenable so views can keep a
  /// volume slider in sync with keyboard-driven changes without polling.
  ValueListenable<double> get volumeListenable => _volumeNotifier;

  /// Releases the volume notifier. Call when the controller is torn down.
  void dispose() {
    if (_playbackActivityHeld) {
      _playbackActivityHeld = false;
      unawaited(_endPlaybackActivity());
    }
    _volumeNotifier.dispose();
  }

  void load(int trackId) {
    _player.loadTrack(trackId);
    _commandIssued();
  }

  void play() {
    _player.play();
    _commandIssued();
  }

  void pause() {
    _player.pause();
    _commandIssued();
  }

  void stop() {
    _player.stop();
    _commandIssued();
  }

  void seekToFrame(int frame) {
    _player.seekToFrame(frame);
    _commandIssued();
  }

  double get volume => _volume;

  void setVolume(double volume) {
    final next = volume.clamp(0.0, 1.0);
    _player.setVolume(next);
    _volume = next;
    _volumeNotifier.value = next;
    onVolumeChanged?.call(next);
  }

  void setEqualizerGains(List<double> gainsDb) {
    if (gainsDb.length != 10) {
      throw ArgumentError.value(gainsDb.length, 'gainsDb.length', 'Must be 10');
    }
    _player.setEqualizerGains(gainsDb);
  }

  void setQueue(List<int> trackIds) {
    _player.setQueue(trackIds);
    _commandIssued();
  }

  void clearQueue() {
    _player.clearQueue();
    _commandIssued();
  }

  void addToQueue(int trackId) {
    _player.addToQueue(trackId);
    _commandIssued();
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
  Future<void> next() => _switchTrack(_nextTarget(), _next);

  void _next() {
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

  Future<void> previous() {
    int? target;
    try {
      final index = queueCurrentIndex;
      target = index > 0 ? _queueTrackIdAt(index - 1) : null;
    } catch (_) {}
    return _switchTrack(target, _player.previousQueueAndPlay);
  }

  void select(int index) {
    _player.selectAndLoadQueueIndex(index);
    _commandIssued();
  }

  Future<void> selectAndPlay(int index) => _switchTrack(
    _queueTrackIdAt(index),
    () => _player.selectAndPlayQueueIndex(index),
  );

  void repeatCurrent() {
    _player.repeatCurrentQueueTrackAndPlay();
    _commandIssued();
  }

  void advance() {
    _player.advanceQueueAndPlay();
    _commandIssued();
  }

  bool advanceIfAtEnd() {
    final advanced = _player.advanceQueueIfAtEnd();
    if (advanced) _commandIssued();
    return advanced;
  }

  bool _autoAdvancing = false;

  /// Handles natural end-of-track progression.
  ///
  /// UI pages can call this from their existing display timers.
  /// Repeat/EOF policy remains centralized here rather than living
  /// separately in LibraryPage and NowPlayingPage.
  ///
  /// When the track has really ended (position reached duration, which is
  /// exactly the engine's own end-of-track test), the upcoming track is
  /// announced through [pendingTrackId] before the blocking native advance,
  /// the same way a user-initiated [next] is.
  Future<void> pollPlayback() async {
    if (_autoAdvancing || state != OfflinePlayerState.playing) {
      return;
    }

    final duration = durationSeconds;

    if (duration <= 0) {
      return;
    }

    final position = currentSeconds;

    if (position < duration - 0.15) {
      return;
    }

    if (_sleepAtEndOfTrack) {
      cancelSleepTimer();
      pause();
      return;
    }

    if (position < duration) {
      return;
    }

    _autoAdvancing = true;
    try {
      await _switchTrack(
        _nextTarget(),
        _player.advanceQueueIfAtEnd,
        notifyUnlessFalse: true,
      );
    } finally {
      _autoAdvancing = false;
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

  void setAudioOutputMode(AudioOutputMode mode) {
    _player.setOutputMode(_toOfflineOutputMode(mode));
    _audioOutputMode = mode;
  }

  OfflinePlayerOutputMode get outputMode {
    return _player.outputMode;
  }

  void setOutputMode(OfflinePlayerOutputMode mode) {
    _player.setOutputMode(mode);
    _audioOutputMode = _toAudioOutputMode(mode);
  }

  AudioOutputDecision get audioOutputDecision {
    final sourceRate = sampleRate;

    if (sourceRate <= 0) {
      throw StateError('Current track has an invalid sample rate.');
    }

    // Prefer the rate the engine actually negotiated with the device: it is
    // the ground truth for whether playback is bit-perfect. The device-blind
    // policy is only an estimate and is used as a fallback when nothing is
    // loaded (effective rate 0).
    final engineRate = _player.effectiveOutputRate;
    if (engineRate > 0) {
      return AudioOutputDecision(
        sourceRate: sourceRate,
        requestedRate: engineRate,
        effectiveRate: engineRate,
        status: engineRate == sourceRate
            ? AudioPlaybackStatus.native
            : AudioPlaybackStatus.resample,
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
    _commandIssued();
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

  void setRepeatMode(OfflinePlayerRepeatMode mode) {
    _player.setRepeatMode(mode);
    _commandIssued();
  }

  void toggleRepeatMode() {
    final nextMode = switch (repeatMode) {
      OfflinePlayerRepeatMode.off => OfflinePlayerRepeatMode.track,
      OfflinePlayerRepeatMode.track => OfflinePlayerRepeatMode.queue,
      OfflinePlayerRepeatMode.queue => OfflinePlayerRepeatMode.off,
    };

    setRepeatMode(nextMode);
  }

  // ---------------------------------------------------------------------------
  // Output mode mapping
  // ---------------------------------------------------------------------------

  OfflinePlayerOutputMode _toOfflineOutputMode(AudioOutputMode mode) {
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

  AudioOutputMode _toAudioOutputMode(OfflinePlayerOutputMode mode) {
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
