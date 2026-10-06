import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/theme/mobius_theme.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/playback/playback_settings.dart';
import 'package:mobius/playback/player_controller.dart';
import 'package:mobius/playback/presentation/volume_floating_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeOfflinePlayer implements OfflinePlayer {
  double currentVolume = 1.0;
  double currentHardwareVolume = 0.36;
  bool isBitPerfect = true;
  String outputApi = 'AAudio';

  @override
  void setVolume(double volume) {
    currentVolume = volume;
  }

  @override
  void setSoftwareVolume(double volume) {
    currentVolume = volume;
  }

  @override
  void setHardwareVolume(double volume) {
    currentHardwareVolume = volume;
  }

  @override
  void setBitPerfectMode(bool enabled) {
    isBitPerfect = enabled;
  }

  bool get bitPerfectMode => isBitPerfect;

  @override
  SignalPath get signalPath => SignalPath(
        sourceFormat: 'FLAC',
        sourceSampleRate: 96000,
        sourceBitsPerSample: 24,
        sourceChannels: 2,
        lossless: true,
        outputSampleRate: 96000,
        outputChannels: 2,
        outputBitsPerSample: 24,
        outputIsFloat: false,
        resampling: false,
        equalizerActive: false,
        equalizerBands: 0,
        volume: 1.0,
        bufferMs: 20,
        underrunSamples: 0,
        callbackCount: 100,
        outputApi: outputApi,
        deviceName: 'FiiO JA11',
        route: OutputRoute.usb,
        bitPerfect: isBitPerfect,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeOfflinePlayer fakePlayer;
  late PlayerController controller;

  setUp(() {
    fakePlayer = _FakeOfflinePlayer();
    controller = PlayerController(fakePlayer);
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets('VolumeFloatingPanel is initially off-screen and shows on volume change', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
                dismissDuration: const Duration(milliseconds: 500),
              ),
            ],
          ),
        ),
      ),
    );

    final panelFinder = find.byType(VolumeFloatingPanel);
    expect(panelFinder, findsOneWidget);

    final state = tester.state<VolumeFloatingPanelState>(panelFinder);
    expect(state.isVisible, isFalse);

    // Trigger volume change
    controller.setVolume(0.75);
    await tester.pump(); // Start slide animation

    expect(state.isVisible, isTrue);
    expect(find.text('75%'), findsOneWidget);

    // After dismiss duration, panel hides
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(state.isVisible, isFalse);
  });

  testWidgets('VolumeFloatingPanel vertical drag adjusts volume', (tester) async {
    controller.setVolume(0.5);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
                dismissDuration: const Duration(milliseconds: 1000),
              ),
            ],
          ),
        ),
      ),
    );

    // Show panel
    controller.setVolume(0.6);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final state = tester.state<VolumeFloatingPanelState>(find.byType(VolumeFloatingPanel));
    expect(state.isVisible, isTrue);

    // Drag down on the pill container to lower volume
    final gestureTarget = find.byType(GestureDetector).first;
    await tester.drag(gestureTarget, const Offset(0, 50));
    await tester.pump();

    expect(controller.volume < 0.6, isTrue);
  });

  testWidgets('VolumeFloatingPanel shows DAC badge and dB in USB DAC mode', (tester) async {
    fakePlayer.outputApi = 'Direct UAC2';
    expect(controller.isUsbDacActive, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
                dismissDuration: const Duration(milliseconds: 500),
              ),
            ],
          ),
        ),
      ),
    );

    // Trigger hardware volume change with changed value
    controller.setHardwareVolume(0.7);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final state = tester.state<VolumeFloatingPanelState>(find.byType(VolumeFloatingPanel));
    expect(state.isVisible, isTrue);

    // Displays DAC badge
    expect(find.text('DAC'), findsOneWidget);
    expect(find.byIcon(Icons.headphones_rounded), findsOneWidget);
  });

  testWidgets('PlayerController supports volume normalization and bypasses in bit-perfect', (tester) async {
    // Standard mode (bit-perfect false, not USB DAC)
    fakePlayer.outputApi = 'AAudio';
    controller.setBitPerfectMode(false);
    expect(controller.isBitPerfectMode, isFalse);

    controller.setVolume(1.0);
    expect(fakePlayer.currentVolume, equals(1.0));

    // Enable Volume Normalization: software volume is scaled by headroom
    controller.setVolumeNormalization(true);
    expect(controller.volumeNormalization, isTrue);
    expect(fakePlayer.currentVolume < 1.0, isTrue);
    expect((fakePlayer.currentVolume - 0.84).abs() < 0.01, isTrue);

    // Re-enabling Bit-Perfect mode with USB DAC bypasses normalization (locks software volume to 1.0)
    fakePlayer.outputApi = 'Direct UAC2';
    controller.setBitPerfectMode(true);
    expect(controller.isBitPerfectMode, isTrue);
    expect(fakePlayer.currentVolume, equals(1.0));

    // Disabling Bit-Perfect restores normalization scaling
    fakePlayer.outputApi = 'AAudio';
    controller.setBitPerfectMode(false);
    expect(fakePlayer.currentVolume < 1.0, isTrue);

    // Disabling Volume Normalization restores full unattenuated user volume
    controller.setVolumeNormalization(false);
    expect(controller.volumeNormalization, isFalse);
    expect(fakePlayer.currentVolume, equals(1.0));
  });

  testWidgets('showVolumePanel and stepVolume trigger VolumeFloatingPanel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
                dismissDuration: const Duration(milliseconds: 500),
              ),
            ],
          ),
        ),
      ),
    );

    final state = tester.state<VolumeFloatingPanelState>(find.byType(VolumeFloatingPanel));
    expect(state.isVisible, isFalse);

    // showVolumePanel triggers display
    controller.showVolumePanel();
    await tester.pump();
    expect(state.isVisible, isTrue);

    // Let it dismiss
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(state.isVisible, isFalse);

    // stepVolume triggers display and adjusts volume
    controller.setVolume(0.5, triggerPanel: false);
    controller.stepVolume(0.1);
    await tester.pump();
    expect(state.isVisible, isTrue);
    expect(controller.volume, closeTo(0.6, 0.01));
  });

  testWidgets('Dismiss timer is paused during active drag', (tester) async {
    controller.setVolume(0.5);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
                dismissDuration: const Duration(milliseconds: 400),
              ),
            ],
          ),
        ),
      ),
    );

    // Trigger panel
    controller.showVolumePanel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final state = tester.state<VolumeFloatingPanelState>(find.byType(VolumeFloatingPanel));
    expect(state.isVisible, isTrue);

    // Start drag gesture on the GestureDetector
    final gesture = await tester.startGesture(tester.getCenter(find.byType(GestureDetector).first));
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    // Advance past dismissal duration while holding drag
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.isVisible, isTrue); // Should still be visible because drag is held

    // End drag
    await gesture.up();
    await tester.pump();

    // Now advance past dismiss duration after release
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(state.isVisible, isFalse);
  });

  testWidgets('VolumeFloatingPanel tap anywhere on pill instantly jumps to that level', (tester) async {
    controller.setVolume(0.2, triggerPanel: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
                dismissDuration: const Duration(milliseconds: 1000),
              ),
            ],
          ),
        ),
      ),
    );

    controller.showVolumePanel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Get the pill bounding rect
    final gestureFinder = find.byType(GestureDetector).first;
    final pillRect = tester.getRect(gestureFinder);

    // Tap near top (top 20% -> volume should be ~0.8)
    await tester.tapAt(Offset(pillRect.center.dx, pillRect.top + pillRect.height * 0.2));
    await tester.pump();

    expect(controller.volume, closeTo(0.8, 0.05));

    // Tap at 60% from top (40% from bottom -> volume should be ~0.4)
    await tester.tapAt(Offset(pillRect.center.dx, pillRect.top + pillRect.height * 0.6));
    await tester.pump();
    expect(controller.volume, closeTo(0.4, 0.05));

    // Allow dismiss timer to complete
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
  });
  testWidgets('VolumeFloatingPanel contains zero gradients and uses flat solid theme colors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
              ),
            ],
          ),
        ),
      ),
    );

    controller.showVolumePanel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Assert zero gradients across the entire floating panel tree
    final gradientContainers = find.byWidgetPredicate((widget) {
      if (widget is Container && widget.decoration is BoxDecoration) {
        return (widget.decoration as BoxDecoration).gradient != null;
      }
      return false;
    });
    expect(gradientContainers, findsNothing);
  });

  testWidgets('USB DAC mode uses unified violet-blue theme color and not green or magenta', (tester) async {
    fakePlayer.outputApi = 'Direct UAC2';
    expect(controller.isUsbDacActive, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: MobiusTheme.dark(),
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
              ),
            ],
          ),
        ),
      ),
    );

    controller.showVolumePanel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Active fill container should use unified lilac/violet with reduced opacity
    final expectedViolet = const Color(0xFF8A63D2).withValues(alpha: 0.82);
    final violetFills = find.byWidgetPredicate((widget) {
      if (widget is Container && widget.decoration is BoxDecoration) {
        return (widget.decoration as BoxDecoration).color == expectedViolet;
      }
      return widget is Container && widget.color == expectedViolet;
    });
    expect(violetFills, findsOneWidget);

    final greenFills = find.byWidgetPredicate((widget) {
      if (widget is Container && widget.decoration is BoxDecoration) {
        return (widget.decoration as BoxDecoration).color == const Color(0xFF7FD99A);
      }
      return widget is Container && widget.color == const Color(0xFF7FD99A);
    });
    expect(greenFills, findsNothing);

    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pumpAndSettle();
  });

  testWidgets('VolumeFloatingPanel does NOT show on app launch or when triggerPanel is false', (tester) async {
    SharedPreferences.setMockInitialValues({
      PlaybackSettings.volumeKey: 0.65,
    });

    // Initial state before widget pumps
    controller.setVolume(0.4, triggerPanel: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
              ),
            ],
          ),
        ),
      ),
    );

    final state = tester.state<VolumeFloatingPanelState>(find.byType(VolumeFloatingPanel));
    expect(state.isVisible, isFalse);

    // Simulate startup restore
    await PlaybackSettings.restore(controller);
    await tester.pump();

    // Volume was restored to 0.65, but panel MUST NOT be visible!
    expect(controller.volume, closeTo(0.65, 0.01));
    expect(state.isVisible, isFalse);

    // Now press hardware volume button
    controller.stepVolume(0.05);
    await tester.pump();

    // Now the panel shows!
    expect(state.isVisible, isTrue);
    expect(find.text('70%'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pumpAndSettle();
  });

  testWidgets('VolumeFloatingPanel does NOT show on initial restore when triggerPanel is false', (tester) async {
    controller.setVolume(0.3, triggerPanel: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
              ),
            ],
          ),
        ),
      ),
    );

    final panelFinder = find.byType(VolumeFloatingPanel);
    final state = tester.state<VolumeFloatingPanelState>(panelFinder);
    expect(state.isVisible, isFalse);

    // Further volume updates with triggerPanel: false (e.g. normalization, settings sync) remain hidden
    controller.setVolume(0.5, triggerPanel: false);
    await tester.pump();
    expect(state.isVisible, isFalse);
  });

  testWidgets('Continuous volume button presses update the slider continuously on every step', (tester) async {
    controller.setVolume(0.50, triggerPanel: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              VolumeFloatingPanel(
                controller: controller,
                dismissDuration: const Duration(milliseconds: 1000),
              ),
            ],
          ),
        ),
      ),
    );

    // Initial step from hardware volume button: shows panel and updates to 55%
    controller.stepVolume(0.05);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('55%'), findsOneWidget);

    // Second step while panel is already showing: updates to 60%
    controller.stepVolume(0.05);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('60%'), findsOneWidget);

    // Third step: updates to 65%
    controller.stepVolume(0.05);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('65%'), findsOneWidget);

    // Fourth step: updates to 70%
    controller.stepVolume(0.05);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('70%'), findsOneWidget);

    // Settle animation and dismiss
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    final state = tester.state<VolumeFloatingPanelState>(find.byType(VolumeFloatingPanel));
    expect(state.isVisible, isFalse);
  });
}
