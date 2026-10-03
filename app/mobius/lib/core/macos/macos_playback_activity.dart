import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tells the macOS host to hold or release an `NSProcessInfo` activity
/// assertion while audio is playing.
///
/// Without the assertion, macOS App-Naps the process when the window is
/// minimized or on another Space, which throttles the decoder thread that
/// refills the PCM ring and stalls background playback. The assertion also
/// keeps the Mac awake while music plays, matching other music players.
///
/// Calls are no-ops on platforms other than macOS, and failures are swallowed
/// so playback is never blocked by a missing or misbehaving platform channel.
class MacOSPlaybackActivity {
  MacOSPlaybackActivity._();

  static const MethodChannel _channel =
      MethodChannel('mobius/playback_activity');

  static bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Begins the activity assertion. Idempotent on the host side.
  static Future<void> start() async {
    if (!_isSupported) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('start');
    } on PlatformException {
      // Keeping the Mac awake is best-effort; never block playback on it.
    } on MissingPluginException {
      // Channel not registered (e.g. in a test host): ignore.
    }
  }

  /// Releases the activity assertion. Idempotent on the host side.
  static Future<void> stop() async {
    if (!_isSupported) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('stop');
    } on PlatformException {
      // Ignore: the assertion is released on next stop or process exit.
    } on MissingPluginException {
      // Channel not registered (e.g. in a test host): ignore.
    }
  }
}
