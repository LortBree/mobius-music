import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../platform/android/android_audio_route.dart';
import '../../platform/platform_services.dart';
import '../audio/signal_path.dart';

/// Platform audio output route.
///
/// Delegates to [PlatformServices.audioRoute] (backed by [AndroidAudioRouteService] on Android).
class AudioRoute {
  const AudioRoute(this.route, this.name);

  final OutputRoute route;
  final String name;

  static Future<AudioRoute?> current({
    @visibleForTesting MethodChannel? channel,
    bool? isAndroid,
  }) async {
    if (channel != null || isAndroid != null) {
      final res = await AndroidAudioRouteService.queryCurrent(
        channel: channel,
        isAndroid: isAndroid,
      );
      if (res == null) return null;
      return AudioRoute(res.route, res.name);
    }

    final res = await PlatformServices.audioRoute.current();
    if (res == null) return null;
    return AudioRoute(res.route, res.name);
  }

  @visibleForTesting
  static OutputRoute parseRoute(String? type) =>
      AndroidAudioRouteService.parseRoute(type);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioRoute &&
          runtimeType == other.runtimeType &&
          route == other.route &&
          name == other.name;

  @override
  int get hashCode => Object.hash(route, name);
}
