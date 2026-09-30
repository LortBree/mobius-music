import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/playback/playback_poller.dart';

void main() {
  testWidgets('ticks fast while active and slow while idle', (tester) async {
    var active = true;
    var ticks = 0;
    final poller = PlaybackPoller(onTick: () => ticks++, isActive: () => active)
      ..start();

    await tester.pump(const Duration(seconds: 1));
    expect(ticks, 5, reason: '200 ms while playing');

    active = false;
    ticks = 0;
    await tester.pump(const Duration(milliseconds: 200)); // pending fast tick
    await tester.pump(const Duration(seconds: 3));
    expect(ticks, 4, reason: 'one last fast tick, then 1 s idle ticks');

    poller.stop();
  });

  testWidgets('wake switches to the fast cadence immediately', (tester) async {
    var active = false;
    var ticks = 0;
    final poller = PlaybackPoller(onTick: () => ticks++, isActive: () => active)
      ..start();
    expect(poller.scheduledInterval, const Duration(seconds: 1));

    active = true;
    poller.wake();
    expect(poller.scheduledInterval, const Duration(milliseconds: 200));

    await tester.pump(const Duration(milliseconds: 200));
    expect(ticks, 1);
    poller.stop();
  });

  testWidgets(
    'stop cancels pending ticks and a throwing isActive counts as idle',
    (tester) async {
      var ticks = 0;
      final poller = PlaybackPoller(
        onTick: () => ticks++,
        isActive: () => throw StateError('player gone'),
      )..start();
      expect(poller.scheduledInterval, const Duration(seconds: 1));

      poller.stop();
      await tester.pump(const Duration(seconds: 5));
      expect(ticks, 0);
      expect(poller.isRunning, isFalse);
    },
  );
}
