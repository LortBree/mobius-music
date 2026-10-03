import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/features/settings/presentation/equalizer_panel.dart';
import 'package:mobius/playback/equalizer_response.dart';

void main() {
  group('EqualizerResponse', () {
    test('a single band peaks at exactly its gain at its centre', () {
      final gains = List<double>.filled(10, 0)..[0] = 6;
      expect(EqualizerResponse.responseDb(gains, 31), closeTo(6, 1e-6));
    });

    test('flat and cut-only curves need no preamp', () {
      expect(EqualizerResponse.autoPreampDb(List.filled(10, 0)), 0);
      expect(EqualizerResponse.autoPreampDb(List.filled(10, -6)), 0);
    });

    test('preamp matches the engine for overlapping boosts', () {
      // Same value the Rust auto_preamp_db produces (independently
      // computed): two adjacent +6 dB bands, solved to hit +6 dB at both
      // centres, bulge to about +6.06 dB between them.
      final gains = List<double>.filled(10, 0)
        ..[0] = 6
        ..[1] = 6;
      expect(EqualizerResponse.autoPreampDb(gains), closeTo(-6.0590, 1e-3));
    });

    test('the curve passes through every set gain (dots on the line)', () {
      const cases = <List<double>>[
        [3, 6, 4, 9, -12, -3, 2, 5, 1, -4],
        [12, -12, 12, -12, 12, -12, 12, -12, 12, -12],
        [12, 12, 12, 12, 12, 12, 12, 12, 12, 12],
      ];
      for (final gains in cases) {
        for (var band = 0; band < 10; band++) {
          expect(
            EqualizerResponse.responseDb(
              gains,
              EqualizerResponse.bandsHz[band],
            ),
            closeTo(gains[band], 0.05),
            reason: 'band $band of $gains',
          );
        }
      }
    });

    test('every preset is recognised by name, anything else is Custom', () {
      for (final entry in EqualizerPresets.all.entries) {
        expect(EqualizerPresets.nameFor(entry.value), entry.key);
      }
      expect(
        EqualizerPresets.nameFor(List.filled(10, 1.25)),
        EqualizerPresets.custom,
      );
    });
  });

  group('EqualizerPanel', () {
    Future<List<(List<double>, bool)>> pump(
      WidgetTester tester, {
      List<double>? gains,
      bool enabled = true,
    }) async {
      final calls = <(List<double>, bool)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: MobiusTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 700,
              child: EqualizerPanel(
                gains: gains ?? List.filled(10, 0),
                enabled: enabled,
                onGainsChanged: (g, {required commit}) =>
                    calls.add((g, commit)),
                onEnabledChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      return calls;
    }

    testWidgets('choosing a preset commits its curve', (tester) async {
      final calls = await pump(tester);
      await tester.tap(find.text('Bass boost'));
      expect(calls.single.$1, EqualizerPresets.all['Bass boost']);
      expect(calls.single.$2, isTrue);
    });

    testWidgets('dragging a band previews, then commits on release', (
      tester,
    ) async {
      final calls = await pump(tester);
      final graph = find.byType(EqualizerGraph);
      final box = tester.getRect(graph);
      // Start near the left end (31 Hz band), mid height (0 dB), drag up.
      final start = Offset(box.left + 60, box.center.dy);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(0, -40));
      await gesture.moveBy(const Offset(0, -20));
      await gesture.up();
      await tester.pumpAndSettle();

      final previews = calls.where((c) => !c.$2).toList();
      expect(previews, isNotEmpty);
      expect(previews.last.$1[0], greaterThan(0));
      // Other bands untouched.
      expect(previews.last.$1.sublist(1), everyElement(0));
      expect(calls.last.$2, isTrue);
    });

    testWidgets('shows the auto preamp for a boosted curve', (tester) async {
      await pump(
        tester,
        gains: List<double>.filled(10, 0)
          ..[0] = 6
          ..[1] = 6,
      );
      expect(find.textContaining('Auto preamp -6.1 dB'), findsOneWidget);
    });

    testWidgets('disabled panel ignores input', (tester) async {
      final calls = await pump(tester, enabled: false);
      await tester.tap(find.text('Rock'), warnIfMissed: false);
      expect(calls, isEmpty);
    });
  });
}
