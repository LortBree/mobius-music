import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/playback/player_controller.dart';

/// Records the order of native calls; only the queue surface is real.
class _FakePlayer implements OfflinePlayer {
  _FakePlayer(this.log);

  final List<String> log;
  List<int> ids = [10, 20, 30];
  int index = 0;
  OfflinePlayerRepeatMode mode = OfflinePlayerRepeatMode.off;
  Object? failWith;

  @override
  List<int> get queueTrackIds => ids;
  @override
  int get queueLength => ids.length;
  @override
  int get queueCurrentIndex => index;
  @override
  int get queueCurrentTrackId => ids[index];
  @override
  OfflinePlayerRepeatMode get repeatMode => mode;

  void _move(String name, int to) {
    if (failWith != null) throw failWith!;
    log.add('native:$name');
    index = to;
  }

  @override
  void nextQueueAndPlay() => _move('next', index + 1);
  @override
  void previousQueueAndPlay() => _move('previous', index - 1);
  @override
  void selectAndPlayQueueIndex(int i) => _move('select', i);
  @override
  void repeatCurrentQueueTrackAndPlay() => _move('repeat', index);

  // End-of-track surface for pollPlayback.
  OfflinePlayerState playState = OfflinePlayerState.playing;
  double position = 0;
  double duration = 100;
  @override
  OfflinePlayerState get state => playState;
  @override
  double get currentSeconds => position;
  @override
  double get durationSeconds => duration;
  @override
  bool advanceQueueIfAtEnd() {
    if (position < duration || index + 1 >= ids.length) {
      log.add('native:advance-noop');
      return false;
    }
    _move('advance', index + 1);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<String> log;
  late _FakePlayer player;
  late PlayerController controller;

  setUp(() {
    log = [];
    player = _FakePlayer(log);
    controller = PlayerController(
      player,
      yieldFrame: () async => log.add('frame'),
    );
    controller.pendingTrackId.addListener(
      () => log.add('pending:${controller.pendingTrackId.value}'),
    );
    controller.commands.addListener(() => log.add('command'));
  });

  test('next announces the target and paints before the native load', () async {
    await controller.next();
    expect(log, [
      'pending:20',
      'frame',
      'native:next',
      'command',
      'pending:null',
    ]);
  });

  test('selectAndPlay announces the selected queue entry', () async {
    await controller.selectAndPlay(2);
    expect(log.first, 'pending:30');
    expect(log, contains('native:select'));
    expect(controller.pendingTrackId.value, isNull);
  });

  test('previous announces the entry before the current one', () async {
    player.index = 2;
    await controller.previous();
    expect(log.first, 'pending:20');
  });

  test(
    'no announcement or frame wait when the track does not change',
    () async {
      player.mode = OfflinePlayerRepeatMode.track;
      await controller.next();
      expect(log, ['native:repeat', 'command']);
    },
  );

  test('repeat-queue next announces the wrap to the first entry', () async {
    player
      ..index = 2
      ..mode = OfflinePlayerRepeatMode.queue;
    await controller.next();
    expect(log.first, 'pending:10');
  });

  test('a failing load still clears the announcement and rethrows', () async {
    player.failWith = StateError('device busy');
    await expectLater(controller.next(), throwsStateError);
    expect(controller.pendingTrackId.value, isNull);
    expect(log, isNot(contains('command')));
  });

  group('natural end of track', () {
    test('announces the next track before the blocking advance', () async {
      player.position = 100;
      await controller.pollPlayback();
      expect(log, [
        'pending:20',
        'frame',
        'native:advance',
        'command',
        'pending:null',
      ]);
    });

    test('does nothing before the track has ended', () async {
      player.position = 99.95;
      await controller.pollPlayback();
      expect(log, isEmpty);
    });

    test('last track with repeat off: no announcement, no command', () async {
      player
        ..index = 2
        ..position = 100;
      await controller.pollPlayback();
      expect(log, ['native:advance-noop']);
    });

    test(
      'a second poll during the frame wait does not advance twice',
      () async {
        player.position = 100;
        final first = controller.pollPlayback();
        await controller.pollPlayback();
        await first;
        expect(log.where((e) => e == 'native:advance'), hasLength(1));
      },
    );
  });
}
