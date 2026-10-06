import '../../core/audio/signal_path.dart';

/// Representation of an active audio output route.
class AudioDeviceRoute {
  const AudioDeviceRoute(this.route, this.name);

  final OutputRoute route;
  final String name;

  @override
  String toString() => 'AudioDeviceRoute(route: $route, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDeviceRoute &&
          runtimeType == other.runtimeType &&
          route == other.route &&
          name == other.name;

  @override
  int get hashCode => Object.hash(route, name);
}

/// Platform-neutral interface for querying output audio route and hardware device.
abstract interface class AudioRouteService {
  /// Queries the currently active audio route, or returns null if not available
  /// or unneeded on this platform (e.g. handled directly by audio engine HAL).
  Future<AudioDeviceRoute?> current();
}
