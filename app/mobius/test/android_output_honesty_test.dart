import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/core/ffi/offline_player.dart';
import 'package:mobius/playback/audio_output_policy.dart';
import 'package:mobius/playback/player_controller.dart';

import 'support/fake_offline_player.dart';

/// Engine negotiated exactly the source rate -- the case that used to be
/// mislabelled "Bit-perfect" on Android.
class _RateMatchPlayer extends FakeOfflinePlayer {
  _RateMatchPlayer({required this.engineRate})
      : super(track: _track, playing: true);

  final int engineRate;

  @override
  int get effectiveOutputRate => engineRate;
}

const _track = TrackMetadata(
  trackId: 1,
  title: 'A',
  artist: 'Artist',
  album: 'Album',
  albumArtist: 'Artist',
  composer: '',
  date: '',
  genre: '',
  trackNumber: 1,
  discNumber: 1,
  hasDiscNumber: false,
);

PlayerController _controller({required bool android, int engineRate = 44100}) {
  return PlayerController(
    _RateMatchPlayer(engineRate: engineRate),
    beginPlaybackActivity: () async {},
    endPlaybackActivity: () async {},
    isAndroidHost: android,
  );
}

void main() {
  test('Android never reports native, even when the rates match', () {
    final decision = _controller(android: true).audioOutputDecision;
    expect(decision.status, AudioPlaybackStatus.resample);
  });

  test('macOS still reports native when the device runs at the source rate',
      () {
    final decision = _controller(android: false).audioOutputDecision;
    expect(decision.status, AudioPlaybackStatus.native);
  });

  test('macOS reports resample when the device rate differs', () {
    final decision =
        _controller(android: false, engineRate: 48000).audioOutputDecision;
    expect(decision.status, AudioPlaybackStatus.resample);
  });
}
