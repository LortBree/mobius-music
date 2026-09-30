import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/app/widgets/animated_mobius_background.dart';

Widget _host({
  required bool animate,
  bool reduceMotion = false,
  AmbientConfig config = const AmbientConfig(),
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AmbientBackground(
        animate: animate,
        config: config,
        child: const SizedBox(),
      ),
    ),
  );
}

AmbientBackgroundState _state(WidgetTester tester) =>
    tester.state<AmbientBackgroundState>(find.byType(AmbientBackground));

void main() {
  testWidgets('animates while animate is true', (tester) async {
    await tester.pumpWidget(_host(animate: true));
    expect(_state(tester).isAnimating, isTrue);
  });

  testWidgets('does not animate while animate is false', (tester) async {
    await tester.pumpWidget(_host(animate: false));
    expect(_state(tester).isAnimating, isFalse);
  });

  testWidgets('stops and resumes when animate flips', (tester) async {
    await tester.pumpWidget(_host(animate: true));
    expect(_state(tester).isAnimating, isTrue);

    await tester.pumpWidget(_host(animate: false));
    expect(_state(tester).isAnimating, isFalse);

    await tester.pumpWidget(_host(animate: true));
    expect(_state(tester).isAnimating, isTrue);
  });

  testWidgets('respects platform reduce-motion', (tester) async {
    await tester.pumpWidget(_host(animate: true, reduceMotion: true));
    expect(_state(tester).isAnimating, isFalse);
  });

  testWidgets('stops while the app is hidden and resumes after', (
    tester,
  ) async {
    await tester.pumpWidget(_host(animate: true));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(_state(tester).isAnimating, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(_state(tester).isAnimating, isTrue, reason: 'visible, unfocused');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(_state(tester).isAnimating, isTrue);
  });

  testWidgets('shader frames are capped at maxFrameRate', (tester) async {
    await tester.pumpWidget(_host(animate: true));
    var frames = 0;
    _state(tester).frameClock.addListener(() => frames++);

    // One second at a 120 Hz display cadence.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(microseconds: 8333));
    }

    expect(frames, inInclusiveRange(28, 31));
  });

  testWidgets('elapsed time freezes while stopped', (tester) async {
    await tester.pumpWidget(_host(animate: true));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(_host(animate: false));
    final frozen = _state(tester).frameClock.value;

    await tester.pump(const Duration(seconds: 2));
    expect(_state(tester).frameClock.value, frozen);
  });
}
