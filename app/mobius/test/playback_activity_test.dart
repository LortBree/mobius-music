import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/playback/player_controller.dart';

/// Minimal fake whose [state] can be driven to mimic the engine flipping
/// between playing and paused/stopped. play/pause/stop set the state the way
/// the real engine would, so the controller's state-driven activity sync sees
/// the right value when it reads [state] after each command.
class _FakePlayer implements OfflinePlayer {
  OfflinePlayerState playState = OfflinePlayerState.stopped;

  @override
  OfflinePlayerState get state => playState;

  @override
  void play() => playState = OfflinePlayerState.playing;
  @override
  void pause() => playState = OfflinePlayerState.paused;
  @override
  void stop() => playState = OfflinePlayerState.stopped;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakePlayer player;
  late List<String> activity;
  late PlayerController controller;

  setUp(() {
    player = _FakePlayer();
    activity = [];
    controller = PlayerController(
      player,
      yieldFrame: () async {},
      beginPlaybackActivity: () async => activity.add('begin'),
      endPlaybackActivity: () async => activity.add('end'),
    );
  });

  test('play holds the macOS activity assertion exactly once', () async {
    controller.play();
    await Future<void>.value();
    expect(activity, ['begin']);
  });

  test('a second play while already playing does not re-assert', () async {
    controller.play();
    controller.play();
    await Future<void>.value();
    expect(activity, ['begin']);
  });

  test('pause releases the assertion after playing', () async {
    controller.play();
    controller.pause();
    await Future<void>.value();
    expect(activity, ['begin', 'end']);
  });

  test('stop releases the assertion after playing', () async {
    controller.play();
    controller.stop();
    await Future<void>.value();
    expect(activity, ['begin', 'end']);
  });

  test('pause while already stopped does not release again', () async {
    controller.play();
    controller.pause();
    controller.pause();
    await Future<void>.value();
    expect(activity, ['begin', 'end']);
  });

  test('resuming after a pause re-asserts', () async {
    controller.play();
    controller.pause();
    controller.play();
    await Future<void>.value();
    expect(activity, ['begin', 'end', 'begin']);
  });

  test('dispose releases a held assertion', () async {
    controller.play();
    await Future<void>.value();
    controller.dispose();
    await Future<void>.value();
    expect(activity, ['begin', 'end']);
  });

  test('dispose while not playing does not release', () async {
    controller.dispose();
    await Future<void>.value();
    expect(activity, isEmpty);
  });
}
