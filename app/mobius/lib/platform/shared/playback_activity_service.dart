/// Platform-neutral interface for asserting background playback activity.
abstract interface class PlaybackActivityService {
  /// Asserts that playback is active, preventing the OS from suspending the process.
  Future<void> start();

  /// Releases the background playback activity assertion.
  Future<void> stop();
}
