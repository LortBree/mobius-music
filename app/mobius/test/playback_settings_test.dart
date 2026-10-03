import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/core/cache/lru_cache.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/playback/playback_settings.dart';
import 'package:mobius/playback/player_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SettingsPlayer implements OfflinePlayer {
  double? volume;
  OfflinePlayerOutputMode? mode;
  List<double>? gains;

  @override
  void setVolume(double value) => volume = value;
  @override
  void setOutputMode(OfflinePlayerOutputMode value) => mode = value;
  @override
  void setEqualizerGains(List<double> value) => gains = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackSettings.restore', () {
    test('re-applies volume, output mode and enabled EQ at startup', () async {
      SharedPreferences.setMockInitialValues({
        PlaybackSettings.volumeKey: 0.3,
        PlaybackSettings.outputModeKey: OfflinePlayerOutputMode.khz48.name,
        PlaybackSettings.equalizerEnabledKey: true,
        PlaybackSettings.equalizerGainsKey: [
          '3',
          '2',
          '1',
          '0',
          '0',
          '0',
          '0',
          '0',
          '0',
          '99',
        ],
      });
      final player = _SettingsPlayer();
      await PlaybackSettings.restore(PlayerController(player));

      expect(player.volume, 0.3);
      expect(player.mode, OfflinePlayerOutputMode.khz48);
      expect(player.gains, [3, 2, 1, 0, 0, 0, 0, 0, 0, 12]); // clamped
    });

    test(
      'a disabled EQ is applied flat; nothing stored leaves defaults',
      () async {
        SharedPreferences.setMockInitialValues({
          PlaybackSettings.equalizerEnabledKey: false,
          PlaybackSettings.equalizerGainsKey: List.filled(10, '5'),
        });
        final player = _SettingsPlayer();
        await PlaybackSettings.restore(PlayerController(player));

        expect(player.gains, PlaybackSettings.flatGains);
        expect(player.volume, isNull);
        expect(player.mode, isNull);
      },
    );

    test('an unknown stored output mode is ignored', () async {
      SharedPreferences.setMockInitialValues({
        PlaybackSettings.outputModeKey: 'khz768',
      });
      final player = _SettingsPlayer();
      await PlaybackSettings.restore(PlayerController(player));
      expect(player.mode, isNull);
    });
  });

  test('volume changes are reported for persistence', () {
    final seen = <double>[];
    final controller = PlayerController(
      _SettingsPlayer(),
      onVolumeChanged: seen.add,
    );
    controller.setVolume(1.4);
    expect(seen, [1.0]);
  });

  test('LruCache evicts the least recently used entry and caches nulls', () {
    final cache = LruCache<int, String?>(2)
      ..put(1, 'a')
      ..put(2, null);
    cache.get(1); // 1 is now most recent
    cache.put(3, 'c');
    expect(cache.containsKey(2), isFalse);
    expect(cache.get(1), 'a');
    expect(cache.containsKey(3), isTrue);

    final nulls = LruCache<int, String?>(4)..put(7, null);
    expect(nulls.containsKey(7), isTrue);
    expect(nulls.get(7), isNull);
  });
}
