// Exercises the real Rust dylib through the Dart bindings, so a signature
// drift between offline_player.h, the Rust export and the Dart typedefs
// fails here instead of at app start.
//
// Requires a built library: `cargo build -p offline-player-ffi --release`
// from the repository root. Skipped when it is missing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobius/core/ffi/offline_player.dart';

final _dylib = File(
  '${Directory.current.path}/../../target/release/liboffline_player_ffi.dylib',
);

void main() {
  final skip = _dylib.existsSync()
      ? false
      : 'Rust dylib not built (${_dylib.path})';

  test('bindings load and track ids round-trip on an empty library', () {
    final dir = Directory.systemTemp.createTempSync('mobius-ffi-test');
    final player = OfflinePlayer.open(
      libraryPath: _dylib.path,
      dbPath: '${dir.path}/library.sqlite',
    );

    try {
      expect(player.getTrackCount(), 0);
      expect(player.getTrackIds(), isEmpty);
    } finally {
      player.dispose();
      dir.deleteSync(recursive: true);
    }
  }, skip: skip);
}
