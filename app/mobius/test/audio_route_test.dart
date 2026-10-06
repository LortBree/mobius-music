import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/core/audio/signal_path.dart';
import 'package:mobius/core/platform/audio_route.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mobius/audio_route_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('off Android it never touches the channel', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      called = true;
      return null;
    });
    expect(await AudioRoute.current(channel: channel, isAndroid: false), isNull);
    expect(called, isFalse);
  });

  test('maps the host answer to a route and name', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'current');
      return {'type': 'bluetooth', 'name': 'WH-1000XM5'};
    });
    final route = await AudioRoute.current(channel: channel, isAndroid: true);
    expect(route!.route, OutputRoute.bluetooth);
    expect(route.name, 'WH-1000XM5');
  });

  test('a missing channel or host error yields null, never throws', () async {
    expect(await AudioRoute.current(channel: channel, isAndroid: true), isNull);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'x'),
    );
    expect(await AudioRoute.current(channel: channel, isAndroid: true), isNull);
  });

  test('unknown types map to unknown', () {
    expect(AudioRoute.parseRoute('hdmi'), OutputRoute.unknown);
    expect(AudioRoute.parseRoute(null), OutputRoute.unknown);
    expect(AudioRoute.parseRoute('usb'), OutputRoute.usb);
  });
}
