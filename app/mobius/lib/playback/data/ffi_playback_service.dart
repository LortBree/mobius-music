import '../../core/ffi/offline_player.dart';

abstract interface class PlaybackService {
  void load(int trackId);

  void play();

  void pause();

  void stop();

  void seekToFrame(int frame);

  OfflinePlayerState get state;

  int get currentFrame;

  double get currentSeconds;

  double get durationSeconds;
}

class FfiPlaybackService implements PlaybackService {
  FfiPlaybackService(this._player);

  final OfflinePlayer _player;

  @override
  void load(int trackId) {
    _player.loadTrack(trackId);
  }

  @override
  void play() {
    _player.play();
  }

  @override
  void pause() {
    _player.pause();
  }

  @override
  void stop() {
    _player.stop();
  }

  @override
  void seekToFrame(int frame) {
    _player.seekToFrame(frame);
  }

  @override
  OfflinePlayerState get state {
    return _player.state;
  }

  @override
  int get currentFrame {
    return _player.currentFrame;
  }

  @override
  double get currentSeconds {
    return _player.currentSeconds;
  }

  @override
  double get durationSeconds {
    return _player.durationSeconds;
  }
}