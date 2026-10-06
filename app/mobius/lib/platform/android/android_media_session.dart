import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/ffi/offline_player.dart';
import '../../features/library/data/ffi_library_repository.dart';
import '../../playback/player_controller.dart';

/// Bridges the Rust-driven [PlayerController] to the Android media session host
/// (channel `mobius/playback_service`).
///
/// It keeps the OS media notification / lock screen in sync with what the
/// engine is actually playing, and turns notification / lock-screen / headset /
/// Bluetooth button presses back into controller commands.
class AndroidMediaSessionBridge {
  AndroidMediaSessionBridge(
    this._controller,
    this._repository, {
    MethodChannel channel = const MethodChannel('mobius/playback_service'),
    bool? isAndroidOverride,
    Duration tick = const Duration(seconds: 1),
  })  : _channel = channel,
        _isAndroid = isAndroidOverride ?? (!kIsWeb && Platform.isAndroid),
        _tick = tick;

  final PlayerController _controller;
  final FfiLibraryRepository _repository;
  final MethodChannel _channel;
  final bool _isAndroid;
  final Duration _tick;

  Timer? _timer;
  bool _started = false;

  bool _pushing = false;
  bool _pushPending = false;
  bool _pendingForce = false;

  int? _lastTrackId;
  int? _lastArtworkTrackId;
  bool? _lastPlaying;
  int _lastPositionMs = -1;

  /// Begins mirroring state and handling host commands. No-op off Android, or
  /// if already started.
  void start() {
    if (!_isAndroid || _started) return;
    _started = true;
    _channel.setMethodCallHandler(_handleHostCall);
    _controller.commands.addListener(_onCommand);
    _channel.invokeMethod<bool>('start');
    _syncTimer();
    _pushUpdate(force: true);
  }

  void _onCommand() {
    _syncTimer();
    _pushUpdate();
  }

  void _syncTimer() {
    final playing = _safePlaying();
    if (playing && _timer == null) {
      _timer = Timer.periodic(_tick, (_) => _pushUpdate());
    } else if (!playing && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  Future<void> _pushUpdate({bool force = false}) async {
    if (_pushing) {
      _pushPending = true;
      _pendingForce = _pendingForce || force;
      return;
    }
    _pushing = true;
    try {
      await _pushUpdateOnce(force: force);
      while (_pushPending) {
        _pushPending = false;
        final pendingForce = _pendingForce;
        _pendingForce = false;
        await _pushUpdateOnce(force: pendingForce);
      }
    } finally {
      _pushing = false;
    }
  }

  Future<void> _pushUpdateOnce({bool force = false}) async {
    final trackId = _safeCurrentTrackId();
    final playing = _safePlaying();
    final positionMs = (_safeCurrentSeconds() * 1000).round();

    final positionChanged = (positionMs - _lastPositionMs).abs() >= 500;
    final changed = force ||
        trackId != _lastTrackId ||
        playing != _lastPlaying ||
        positionChanged;
    if (!changed) return;

    _lastTrackId = trackId;
    _lastPlaying = playing;
    _lastPositionMs = positionMs;

    final metadata = _safeMetadata(trackId);
    final durationMs = (_safeDurationSeconds() * 1000).round();

    Uint8List? artworkBytes;
    if (trackId != null && trackId > 0) {
      if (trackId != _lastArtworkTrackId) {
        try {
          final artwork = _repository.getTrackArtwork(trackId);
          if (artwork != null && artwork.data.isNotEmpty) {
            artworkBytes = artwork.data;
            _lastArtworkTrackId = trackId;
          }
        } catch (_) {}
      }
    } else {
      _lastArtworkTrackId = null;
    }

    try {
      await _channel.invokeMethod<bool>('update', <String, dynamic>{
        'title': metadata?.title ?? '',
        'artist': metadata?.artist ?? '',
        'album': metadata?.album ?? '',
        'durationMs': durationMs,
        'positionMs': positionMs,
        'isPlaying': playing,
        'artworkPath': null,
        'artworkData': artworkBytes,
      });
    } on PlatformException {
      // Best-effort: never let notification break playback.
    } on MissingPluginException {
      // Ignore when channel missing.
    }
  }

  Future<dynamic> _handleHostCall(MethodCall call) async {
    if (call.method != 'command') return null;
    final args = (call.arguments as Map?) ?? const {};
    final action = args['action'] as String?;
    switch (action) {
      case 'play':
        _controller.play();
      case 'pause':
        _controller.pause();
      case 'next':
        await _controller.next();
      case 'previous':
        await _controller.previous();
      case 'seek':
        _seekToMs((args['positionMs'] as num?)?.toInt() ?? 0);
      case 'volumeStep':
        final dir = (args['direction'] as num?)?.toInt() ??
            (args['positionMs'] as num?)?.toInt() ??
            0;
        _controller.stepVolume(dir * 0.05);
      default:
        break;
    }
    return null;
  }

  void _seekToMs(int positionMs) {
    final totalFrames = _safeTotalFrames();
    final durationSeconds = _safeDurationSeconds();
    if (totalFrames <= 0 || durationSeconds <= 0) return;
    final clampedMs = positionMs.clamp(0, (durationSeconds * 1000).round());
    final ratio = clampedMs / (durationSeconds * 1000);
    final frame = (ratio * totalFrames).round().clamp(0, totalFrames);
    _controller.seekToFrame(frame);
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _pushPending = false;
    _pendingForce = false;
    _timer?.cancel();
    _timer = null;
    _controller.commands.removeListener(_onCommand);
    _channel.setMethodCallHandler(null);
  }

  bool _safePlaying() {
    try {
      return _controller.state == OfflinePlayerState.playing;
    } catch (_) {
      return false;
    }
  }

  int? _safeCurrentTrackId() {
    try {
      final id = _controller.currentTrackId;
      return id > 0 ? id : null;
    } catch (_) {
      return null;
    }
  }

  double _safeCurrentSeconds() {
    try {
      return _controller.currentSeconds;
    } catch (_) {
      return 0;
    }
  }

  double _safeDurationSeconds() {
    try {
      return _controller.durationSeconds;
    } catch (_) {
      return 0;
    }
  }

  int _safeTotalFrames() {
    try {
      return _controller.totalFrames;
    } catch (_) {
      return 0;
    }
  }

  TrackMetadata? _safeMetadata(int? trackId) {
    if (trackId == null) return null;
    try {
      return _repository.getTrackMetadata(trackId);
    } catch (_) {
      return null;
    }
  }
}
