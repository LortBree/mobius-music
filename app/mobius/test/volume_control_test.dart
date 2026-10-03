import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/playback/presentation/volume_control.dart';

Widget _host({
  required ValueNotifier<double> volume,
  required List<double> changed,
  required List<double> ended,
  bool enabled = true,
}) {
  return MaterialApp(
    theme: MobiusTheme.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: VolumeControl(
            volume: volume,
            enabled: enabled,
            onChanged: changed.add,
            onChangeEnd: ended.add,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('dragging the slider moves the controller value', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final volume = ValueNotifier<double>(0.5);
    final changed = <double>[];
    final ended = <double>[];
    await tester.pumpWidget(
      _host(volume: volume, changed: changed, ended: ended),
    );

    // Drag the slider thumb to the right: the value should rise and a final
    // value should be committed exactly once on release.
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(changed, isNotEmpty, reason: 'drag should emit onChanged');
    expect(changed.last, greaterThan(0.5));
    expect(ended, hasLength(1), reason: 'release should commit once');
    expect(ended.single, greaterThan(0.5));
  });

  testWidgets('mute toggles to zero and restores the previous level', (
    tester,
  ) async {
    final volume = ValueNotifier<double>(0.7);
    final changed = <double>[];
    final ended = <double>[];
    await tester.pumpWidget(
      _host(volume: volume, changed: changed, ended: ended),
    );

    // Speaker shows an audible level, so the button mutes.
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();

    expect(changed.last, 0.0);
    expect(ended.last, 0.0);

    // Reflect the muted state back in (the controller would normally drive
    // this) and tap again to restore the captured level.
    volume.value = 0.0;
    await tester.pump();
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();

    expect(changed.last, 0.7, reason: 'should restore the pre-mute level');
    expect(ended.last, 0.7);
  });

  testWidgets('the slider follows controller-driven (keyboard) changes', (
    tester,
  ) async {
    final volume = ValueNotifier<double>(0.2);
    await tester.pumpWidget(
      _host(volume: volume, changed: [], ended: []),
    );

    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.2);

    // Simulate a keyboard volume change arriving through the listenable.
    volume.value = 0.9;
    await tester.pump();

    expect(tester.widget<Slider>(find.byType(Slider)).value, 0.9);
  });

  testWidgets('disabled control ignores input', (tester) async {
    final volume = ValueNotifier<double>(0.5);
    final changed = <double>[];
    final ended = <double>[];
    await tester.pumpWidget(
      _host(
        volume: volume,
        changed: changed,
        ended: ended,
        enabled: false,
      ),
    );

    await tester.tap(find.byTooltip('Mute'));
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(changed, isEmpty);
    expect(ended, isEmpty);
  });
}
