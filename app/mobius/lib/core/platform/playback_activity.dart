import '../../platform/platform_services.dart';

/// Keeps the OS from suspending playback while music is playing.
///
/// * macOS: the `NSProcessInfo` activity assertion ([MacOSPlaybackActivityService]).
/// * Android: starts/stops the media foreground service over the
///   `mobius/playback_service` channel ([AndroidPlaybackActivityService]).
///
/// Best-effort on every platform: a missing channel (tests, other hosts) or a
/// platform error never blocks playback.
abstract final class PlaybackActivity {
  static Future<void> start() => PlatformServices.playbackActivity.start();

  static Future<void> stop() => PlatformServices.playbackActivity.stop();
}
