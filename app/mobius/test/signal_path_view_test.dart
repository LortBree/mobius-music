import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/audio/signal_path.dart';
import 'package:mobius/playback/presentation/signal_path_view.dart';

SignalPath _path({
  bool bitPerfect = false,
  bool resampling = true,
  bool equalizerActive = false,
  double volume = 1.0,
  OutputRoute route = OutputRoute.speaker,
  String deviceName = '',
}) {
  return SignalPath(
    sourceFormat: 'FLAC',
    sourceSampleRate: 48000,
    sourceBitsPerSample: 24,
    sourceChannels: 2,
    lossless: true,
    outputSampleRate: 48000,
    outputChannels: 2,
    outputBitsPerSample: 32,
    outputIsFloat: true,
    resampling: resampling,
    equalizerActive: equalizerActive,
    equalizerBands: 10,
    volume: volume,
    bitPerfect: bitPerfect,
    bufferMs: 96,
    underrunSamples: 3,
    callbackCount: 2048,
    outputApi: 'AAudio',
    route: route,
    deviceName: deviceName,
  );
}

Widget _host(Widget child) => MaterialApp(
  theme: MobiusTheme.dark(),
  home: Scaffold(body: child),
);

void main() {
  group('signalPathSummary', () {
    test('builds Source → stages → Device with EQ when active', () {
      final summary = signalPathSummary(
        _path(equalizerActive: true, deviceName: 'Pixel Buds'),
      );
      expect(summary, 'FLAC 24/48 → EQ → Resample → AAudio 48k → Pixel Buds');
    });

    test('omits EQ when inactive and uses route label without a device', () {
      final summary = signalPathSummary(
        _path(resampling: false, route: OutputRoute.speaker),
      );
      expect(summary, 'FLAC 24/48 → AAudio 48k → Speaker');
    });
  });

  testWidgets('strip shows "Nothing playing" and no tap for a null path', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(SignalPathStrip(path: null, onTap: () => tapped = true)),
    );
    expect(find.text('Nothing playing'), findsOneWidget);
    await tester.tap(find.text('Nothing playing'));
    expect(tapped, isFalse);
  });

  testWidgets('sheet shows STANDARD and dims bypassed stages', (tester) async {
    await tester.pumpWidget(
      _host(SignalPathSheet(path: _path(resampling: false))),
    );

    expect(find.text('Signal path'), findsOneWidget);
    expect(find.text('STANDARD'), findsOneWidget);
    expect(find.text('BIT-PERFECT'), findsNothing);

    // DSP passthrough (no EQ, full volume) and Resampler bypassed are shown
    // but dimmed (present-but-inactive), not hidden.
    expect(find.text('Passthrough'), findsOneWidget);
    expect(find.text('Bypassed'), findsOneWidget);

    // Telemetry row.
    expect(find.text('Buffer'), findsOneWidget);
    expect(find.text('Underruns'), findsOneWidget);
    expect(find.text('Callbacks'), findsOneWidget);
  });

  testWidgets('sheet shows BIT-PERFECT for a bit-perfect path', (tester) async {
    await tester.pumpWidget(
      _host(SignalPathSheet(path: _path(bitPerfect: true, resampling: false))),
    );
    expect(find.text('BIT-PERFECT'), findsOneWidget);
    expect(find.text('STANDARD'), findsNothing);
  });

  testWidgets('sheet shows "Nothing playing" for a null path', (tester) async {
    await tester.pumpWidget(_host(const SignalPathSheet(path: null)));
    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.text('Signal path'), findsNothing);
  });
}
