import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/features/settings/presentation/equalizer_panel.dart';
import 'package:mobius/features/sound/presentation/sound_page.dart';
import 'package:mobius/playback/playback_settings.dart';
import 'package:mobius/playback/player_controller.dart';
import 'package:mobius/playback/presentation/volume_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SoundPlayer implements OfflinePlayer {
  OfflinePlayerOutputMode mode = OfflinePlayerOutputMode.auto;
  List<double>? gains;
  double? volume;

  @override
  OfflinePlayerOutputMode get outputMode => mode;
  @override
  void setOutputMode(OfflinePlayerOutputMode value) => mode = value;
  @override
  void setEqualizerGains(List<double> value) => gains = value;
  @override
  void setVolume(double value) => volume = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, PlayerController controller) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: MobiusTheme.dark(),
      home: Scaffold(body: SoundPage(playerController: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows output mode and the equalizer', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, PlayerController(_SoundPlayer()));

    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Output mode'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.byType(EqualizerPanel), findsOneWidget);
  });

  testWidgets('applies the saved EQ on open, as Settings used to', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PlaybackSettings.equalizerEnabledKey: true,
      PlaybackSettings.equalizerGainsKey: List.filled(10, '3'),
    });
    final player = _SoundPlayer();
    await _pump(tester, PlayerController(player));

    expect(player.gains, List<double>.filled(10, 3));
  });

  testWidgets('changing output mode reaches the player and is saved', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final player = _SoundPlayer();
    await _pump(tester, PlayerController(player));

    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('48 kHz').last);
    await tester.pumpAndSettle();

    expect(player.mode, OfflinePlayerOutputMode.khz48);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(PlaybackSettings.outputModeKey),
      OfflinePlayerOutputMode.khz48.name,
    );
  });

  testWidgets('shows the Volume section and control', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, PlayerController(_SoundPlayer()));

    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('Output volume'), findsOneWidget);
    expect(find.byType(VolumeControl), findsOneWidget);
  });

  testWidgets('dragging the volume slider reaches the player and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final player = _SoundPlayer();
    await _pump(tester, PlayerController(player));

    await tester.drag(
      find.descendant(
        of: find.byType(VolumeControl),
        matching: find.byType(Slider),
      ),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();

    expect(player.volume, isNotNull, reason: 'drag should reach the player');
    expect(player.volume, lessThan(1.0));

    // Release commits the value immediately (saveVolumeNow), not only via the
    // debounce.
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getDouble(PlaybackSettings.volumeKey), isNotNull);
  });
}
