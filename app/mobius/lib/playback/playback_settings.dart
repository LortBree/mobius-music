import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/ffi/offline_player.dart';
import 'player_controller.dart';

/// Persists the playback settings the engine does not remember itself
/// (volume, output mode, equalizer) and re-applies them at startup, so the
/// first track after launch already plays the way the user left it -- not
/// only after the Settings page happens to be opened.
class PlaybackSettings {
  PlaybackSettings._();

  static const String volumeKey = 'playback_volume_v1';
  static const String outputModeKey = 'output_mode_v1';
  static const String equalizerGainsKey = 'equalizer_gains_v1';
  static const String equalizerEnabledKey = 'equalizer_enabled_v1';

  static const List<double> flatGains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  /// Stored gains, validated; anything malformed falls back to flat.
  static List<double> parseGains(List<String>? stored) {
    if (stored == null || stored.length != 10) {
      return List<double>.from(flatGains);
    }
    return stored.map<double>((value) {
      final parsed = double.tryParse(value) ?? 0;
      return parsed.isFinite ? parsed.clamp(-12.0, 12.0).toDouble() : 0.0;
    }).toList();
  }

  /// Applies every stored setting to [controller]. Each one is applied
  /// independently, so one bad value cannot block the others.
  static Future<void> restore(PlayerController controller) async {
    final prefs = await SharedPreferences.getInstance();

    final volume = prefs.getDouble(volumeKey);
    if (volume != null && volume.isFinite) {
      _tryApply(() => controller.setVolume(volume));
    }

    final modeName = prefs.getString(outputModeKey);
    if (modeName != null) {
      for (final mode in OfflinePlayerOutputMode.values) {
        if (mode.name == modeName) {
          _tryApply(() => controller.setOutputMode(mode));
          break;
        }
      }
    }

    final enabled = prefs.getBool(equalizerEnabledKey) ?? false;
    final gains = parseGains(prefs.getStringList(equalizerGainsKey));
    _tryApply(() => controller.setEqualizerGains(enabled ? gains : flatGains));
  }

  static void _tryApply(void Function() apply) {
    try {
      apply();
    } catch (_) {
      // A stale or rejected value must not stop the app from starting;
      // the engine keeps its default for that setting.
    }
  }

  static Future<void> saveOutputMode(OfflinePlayerOutputMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(outputModeKey, mode.name);
  }

  static Timer? _volumeSave;

  /// Volume changes in 5% steps on key repeat; write it once it settles.
  static void saveVolumeSoon(double volume) {
    _volumeSave?.cancel();
    _volumeSave = Timer(const Duration(milliseconds: 400), () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(volumeKey, volume);
    });
  }

  /// Persist the volume immediately, cancelling any pending debounced write.
  /// Used when a slider drag ends, so the final value is never dropped.
  static Future<void> saveVolumeNow(double volume) async {
    _volumeSave?.cancel();
    _volumeSave = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(volumeKey, volume);
  }
}
