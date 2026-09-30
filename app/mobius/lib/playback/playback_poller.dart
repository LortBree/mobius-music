import 'dart:async';

/// A self-rescheduling poll loop that runs fast only while it has to.
///
/// While [isActive] reports true (audio is playing: the position moves and
/// end-of-track handling must run on time) it ticks every [activeInterval];
/// otherwise nothing changes on its own, so it backs off to [idleInterval].
/// Call [wake] after a user action that may have started playback so the
/// fast cadence resumes immediately instead of after the idle delay.
class PlaybackPoller {
  PlaybackPoller({
    required this.onTick,
    required this.isActive,
    this.activeInterval = const Duration(milliseconds: 200),
    this.idleInterval = const Duration(seconds: 1),
  });

  final void Function() onTick;
  final bool Function() isActive;
  final Duration activeInterval;
  final Duration idleInterval;

  Timer? _timer;
  Duration? _scheduled;
  bool _ticking = false;
  bool _running = false;

  bool get isRunning => _running;

  /// The interval of the currently pending tick; exposed for tests.
  Duration? get scheduledInterval => _scheduled;

  void start() {
    if (_running) return;
    _running = true;
    _schedule();
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _scheduled = null;
  }

  /// Switches to the fast cadence now if playback became active while an
  /// idle tick was pending. Safe to call from inside [onTick].
  void wake() {
    if (!_running || _ticking) return;
    if (_scheduled == idleInterval && _safeIsActive()) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    final interval = _safeIsActive() ? activeInterval : idleInterval;
    _scheduled = interval;
    _timer = Timer(interval, _tick);
  }

  void _tick() {
    if (!_running) return;
    _ticking = true;
    try {
      onTick();
    } finally {
      _ticking = false;
    }
    if (_running) _schedule();
  }

  bool _safeIsActive() {
    try {
      return isActive();
    } catch (_) {
      return false;
    }
  }
}
