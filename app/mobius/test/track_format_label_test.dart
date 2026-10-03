import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/core/ffi/offline_player.dart';

void main() {
  test('maps known extensions to display labels, case-insensitively', () {
    expect(TrackTechnicalInfo.formatFromPath('/m/a/01 Song.flac'), 'FLAC');
    expect(TrackTechnicalInfo.formatFromPath('/m/a/02.WAV'), 'WAV');
    expect(TrackTechnicalInfo.formatFromPath('/m/a/03.aiff'), 'AIFF');
    expect(TrackTechnicalInfo.formatFromPath('/m/a/04.aif'), 'AIFF');
    expect(TrackTechnicalInfo.formatFromPath('/m/a/05.wv'), 'WavPack');
  });

  test('upper-cases unknown extensions and handles missing ones', () {
    expect(TrackTechnicalInfo.formatFromPath('/m/a/x.mka'), 'MKA');
    expect(TrackTechnicalInfo.formatFromPath('/m/a/noext'), '');
    expect(TrackTechnicalInfo.formatFromPath('/m/a.dir/noext'), '');
    expect(TrackTechnicalInfo.formatFromPath('/m/a/.hidden'), '');
    expect(TrackTechnicalInfo.formatFromPath(''), '');
  });
}
