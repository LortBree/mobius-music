import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/playback/playback_time_format.dart';

void main() {
  test('formats minutes and zero-padded seconds', () {
    expect(formatPlaybackTime(0), '0:00');
    expect(formatPlaybackTime(5.9), '0:05');
    expect(formatPlaybackTime(65), '1:05');
    expect(formatPlaybackTime(3600 + 1), '60:01');
  });

  test('invalid input renders the placeholder', () {
    expect(formatPlaybackTime(-1), '00:00');
    expect(formatPlaybackTime(double.nan), '00:00');
    expect(formatPlaybackTime(double.infinity), '00:00');
  });
}
