import 'package:flutter/services.dart';

import '../shared/playback_activity_service.dart';

/// Android implementation of [PlaybackActivityService] that starts and stops
/// the media playback foreground service via `mobius/playback_service`.
class AndroidPlaybackActivityService implements PlaybackActivityService {
  const AndroidPlaybackActivityService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('mobius/playback_service');

  final MethodChannel _channel;

  @override
  Future<void> start() => _invoke('start');

  @override
  Future<void> stop() => _invoke('stop');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<bool>(method);
    } on PlatformException {
      // Best-effort: never block playback on the service.
    } on MissingPluginException {
      // Channel not registered (e.g. in a test host): ignore.
    }
  }
}
