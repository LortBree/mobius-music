import '../shared/audio_route_service.dart';

/// macOS implementation of [AudioRouteService].
///
/// On macOS, CoreAudio HAL handles device discovery, device naming, and routing
/// natively in the audio engine, so host-level route interrogation is unneeded.
class MacOSAudioRouteService implements AudioRouteService {
  const MacOSAudioRouteService();

  @override
  Future<AudioDeviceRoute?> current() async => null;
}
