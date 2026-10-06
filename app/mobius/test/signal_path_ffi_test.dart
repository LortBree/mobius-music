// Exercises the real Rust dylib through the signal-path binding, so a
// signature drift between offline_player.h, the Rust `offline_player_signal_path`
// export and the Dart typedefs/struct fails here instead of at app start.
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

  test('signalPath binding resolves and throws when nothing is loaded', () {
    final dir = Directory.systemTemp.createTempSync('mobius-signal-path-test');
    // Opening the library resolves every lookup eagerly, including the new
    // `offline_player_signal_path` symbol — a missing export throws here.
    final player = OfflinePlayer.open(
      libraryPath: _dylib.path,
      dbPath: '${dir.path}/library.sqlite',
    );

    try {
      // Nothing loaded -> engine reports NotFound (code 4), surfaced as an
      // OfflinePlayerException, never UnimplementedError.
      expect(
        () => player.signalPath,
        throwsA(
          isA<OfflinePlayerException>().having((e) => e.code, 'code', 4),
        ),
      );
    } finally {
      player.dispose();
      dir.deleteSync(recursive: true);
    }
  }, skip: skip);
}
