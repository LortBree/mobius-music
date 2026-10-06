import '../../platform/macos/macos_playback_activity.dart';

class MacOSPlaybackActivity {
  MacOSPlaybackActivity._();

  static const MacOSPlaybackActivityService _service =
      MacOSPlaybackActivityService();

  static Future<void> start() => _service.start();

  static Future<void> stop() => _service.stop();
}
