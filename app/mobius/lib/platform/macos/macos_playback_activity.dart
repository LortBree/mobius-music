import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../shared/playback_activity_service.dart';

/// macOS implementation of [PlaybackActivityService] holding an `NSProcessInfo`
/// activity assertion over the `mobius/playback_activity` channel.
class MacOSPlaybackActivityService implements PlaybackActivityService {
  const MacOSPlaybackActivityService();

  static const MethodChannel _channel =
      MethodChannel('mobius/playback_activity');

  static bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Future<void> start() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<bool>('start');
    } on PlatformException {
      // Best-effort: keeping Mac awake never blocks playback.
    } on MissingPluginException {
      // Channel not registered (e.g. test runner): ignore.
    }
  }

  @override
  Future<void> stop() async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } on PlatformException {
      // Ignore: assertion is released on next stop or exit.
    } on MissingPluginException {
      // Channel not registered: ignore.
    }
  }
}
