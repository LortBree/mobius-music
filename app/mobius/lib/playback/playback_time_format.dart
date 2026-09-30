/// Formats a playback position/duration as `m:ss` (minutes are not padded,
/// and grow past 59 rather than rolling into hours).
///
/// Non-finite or negative input renders as `00:00`, matching the placeholder
/// the player UI has always shown while native state is unavailable.
String formatPlaybackTime(double seconds) {
  if (!seconds.isFinite || seconds < 0) {
    return '00:00';
  }

  final total = seconds.floor();
  final minutes = total ~/ 60;
  final remaining = total % 60;

  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}
