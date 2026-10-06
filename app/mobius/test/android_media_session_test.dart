import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/core/platform/android_media_session.dart';
import 'package:mobius/features/library/data/ffi_library_repository.dart';
import 'package:mobius/playback/player_controller.dart';

/// Fake engine: drives state/position/metadata the way the real engine would,
/// and records the transport commands the bridge issues so host->controller
/// routing can be asserted. Only the members the controller + bridge touch are
/// implemented; everything else routes through noSuchMethod.
class _FakePlayer implements OfflinePlayer {
  OfflinePlayerState playState = OfflinePlayerState.stopped;
  int trackId = 0;
  double position = 0;
  double duration = 0;
  int frames = 0;

  final List<String> calls = <String>[];
  int? lastSeekFrame;

  // Metadata the repository will hand back for [trackId].
  final Map<int, TrackMetadata> metadata = {};

  @override
  OfflinePlayerState get state => playState;

  @override
  int get queueCurrentTrackId => trackId;

  @override
  double get currentSeconds => position;

  @override
  double get durationSeconds => duration;

  @override
  int get totalFrames => frames;

  @override
  void play() {
    playState = OfflinePlayerState.playing;
    calls.add('play');
  }

  @override
  void pause() {
    playState = OfflinePlayerState.paused;
    calls.add('pause');
  }

  @override
  void seekToFrame(int frame) {
    lastSeekFrame = frame;
    calls.add('seek:$frame');
  }

  @override
  void nextQueueAndPlay() => calls.add('next');

  @override
  void previousQueueAndPlay() => calls.add('previous');

  @override
  OfflinePlayerRepeatMode get repeatMode => OfflinePlayerRepeatMode.off;

  @override
  int get queueCurrentIndex => 0;

  @override
  int get queueLength => 1;

  @override
  List<int> get queueTrackIds => [trackId];

  @override
  TrackMetadata getTrackMetadata(int id) =>
      metadata[id] ??
      TrackMetadata(
        trackId: id,
        title: 'Title $id',
        artist: 'Artist $id',
        album: 'Album $id',
        albumArtist: '',
        composer: '',
        date: '',
        genre: '',
        trackNumber: 0,
        discNumber: 0,
        hasDiscNumber: false,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mobius/playback_service');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _FakePlayer player;
  late PlayerController controller;
  late FfiLibraryRepository repository;
  late List<MethodCall> hostCalls;

  setUp(() {
    player = _FakePlayer();
    controller = PlayerController(
      player,
      yieldFrame: () async {},
      beginPlaybackActivity: () async {},
      endPlaybackActivity: () async {},
    );
    repository = FfiLibraryRepository(player);
    hostCalls = <MethodCall>[];

    // Record every `update` the bridge sends to the host.
    messenger.setMockMethodCallHandler(channel, (call) async {
      hostCalls.add(call);
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  AndroidMediaSessionBridge makeBridge() => AndroidMediaSessionBridge(
        controller,
        repository,
        channel: channel,
        isAndroidOverride: true,
      );

  test('start pushes an initial update to the host', () async {
    player.trackId = 7;
    player.duration = 100;
    player.frames = 441000;
    final bridge = makeBridge();
    bridge.start();
    await Future<void>.value();

    final updateCalls = hostCalls.where((c) => c.method == 'update').toList();
    expect(updateCalls, isNotEmpty);
    final args = updateCalls.first.arguments as Map;
    expect(updateCalls.first.method, 'update');
    expect(args['title'], 'Title 7');
    expect(args['artist'], 'Artist 7');
    expect(args['durationMs'], 100000);
    expect(args['isPlaying'], false);
    bridge.dispose();
  });

  test('a play command flips isPlaying in the next update', () async {
    player.trackId = 1;
    final bridge = makeBridge();
    bridge.start();
    await Future<void>.value();
    hostCalls.clear();

    controller.play();
    await Future<void>.value();

    expect(hostCalls, isNotEmpty);
    final args = hostCalls.last.arguments as Map;
    expect(args['isPlaying'], true);
    bridge.dispose();
  });

  test('does nothing off Android', () async {
    final bridge = AndroidMediaSessionBridge(
      controller,
      repository,
      channel: channel,
      isAndroidOverride: false,
    );
    bridge.start();
    await Future<void>.value();
    expect(hostCalls, isEmpty);
    bridge.dispose();
  });

  group('host -> controller commands', () {
    late AndroidMediaSessionBridge bridge;

    setUp(() {
      player.trackId = 3;
      player.duration = 200; // 200 s
      player.frames = 8_820_000; // 44100 * 200
      bridge = makeBridge();
      bridge.start();
    });

    tearDown(() => bridge.dispose());

    Future<void> sendCommand(Map<String, dynamic> args) async {
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('command', args)),
        (_) {},
      );
    }

    test('play drives the controller', () async {
      await sendCommand({'action': 'play'});
      expect(player.calls, contains('play'));
    });

    test('pause drives the controller', () async {
      await sendCommand({'action': 'pause'});
      expect(player.calls, contains('pause'));
    });

    test('next drives the controller', () async {
      await sendCommand({'action': 'next'});
      expect(player.calls, contains('next'));
    });

    test('previous drives the controller', () async {
      await sendCommand({'action': 'previous'});
      expect(player.calls, contains('previous'));
    });

    test('seek converts positionMs to a frame via totalFrames', () async {
      // 100 s of 200 s => half => 4_410_000 of 8_820_000 frames.
      await sendCommand({'action': 'seek', 'positionMs': 100000});
      expect(player.lastSeekFrame, 4_410_000);
    });

    test('seek clamps a position past the end to totalFrames', () async {
      await sendCommand({'action': 'seek', 'positionMs': 999999});
      expect(player.lastSeekFrame, player.frames);
    });

    test('an unknown action is ignored', () async {
      final before = List<String>.from(player.calls);
      await sendCommand({'action': 'frobnicate'});
      expect(player.calls, before);
    });
  });

  test('dispose stops further updates', () async {
    player.trackId = 1;
    final bridge = makeBridge();
    bridge.start();
    await Future<void>.value();
    bridge.dispose();
    hostCalls.clear();

    controller.play();
    await Future<void>.value();
    expect(hostCalls, isEmpty);
  });

  test('concurrent updates are serialized, not interleaved', () async {
    player.trackId = 1;

    // Gate the host handler so an `update` is in flight when the next trigger
    // arrives; record enter/exit so we can prove no two overlap.
    var active = 0;
    var maxActive = 0;
    final gates = <Completer<void>>[];
    final order = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'update') return true;
      active++;
      maxActive = active > maxActive ? active : maxActive;
      order.add('enter:${(call.arguments as Map)['positionMs']}');
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      order.add('exit:${(call.arguments as Map)['positionMs']}');
      active--;
      return true;
    });

    final bridge = makeBridge();
    bridge.start(); // force push #1 begins and blocks on gate[0]
    await Future<void>.value();
    expect(gates, hasLength(1));

    // Trigger more pushes while #1 is still blocked: they must coalesce into a
    // single pending re-run, not start concurrently.
    player.position = 1; // 1000 ms -> state changed
    controller.play();
    player.position = 2;
    controller.play();
    await Future<void>.value();
    expect(gates, hasLength(1), reason: 'no second send while first in flight');

    // Release #1; exactly one coalesced follow-up should then run.
    gates[0].complete();
    await Future<void>.value();
    await Future<void>.value();
    if (gates.length > 1) {
      gates[1].complete();
      await Future<void>.value();
    }

    expect(maxActive, 1, reason: 'sends never overlapped');
    // Every enter is immediately followed by its matching exit (ordered).
    for (var i = 0; i < order.length; i += 2) {
      expect(order[i].startsWith('enter:'), isTrue);
      expect(order[i + 1].startsWith('exit:'), isTrue);
      expect(order[i].substring(6), order[i + 1].substring(5));
    }
    bridge.dispose();
  });
}
