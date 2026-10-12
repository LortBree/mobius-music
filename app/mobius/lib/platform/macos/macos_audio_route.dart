import 'package:flutter/services.dart';

import '../../core/audio/signal_path.dart';
import '../shared/audio_route_service.dart';

/// macOS implementation of [AudioRouteService] querying CoreAudio default output device
/// via the `mobius/audio_route` channel.
class MacOSAudioRouteService implements AudioRouteService {
  const MacOSAudioRouteService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('mobius/audio_route');

  final MethodChannel _channel;

  @override
  Future<AudioDeviceRoute?> current() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('current');
      if (map == null) return null;
      return AudioDeviceRoute(
        parseRoute(map['type'] as String?),
        (map['name'] as String?) ?? '',
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static OutputRoute parseRoute(String? type) => switch (type) {
        'speaker' => OutputRoute.speaker,
        'wired' => OutputRoute.wired,
        'bluetooth' => OutputRoute.bluetooth,
        'usb' => OutputRoute.usb,
        _ => OutputRoute.unknown,
      };
}

