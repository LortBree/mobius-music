import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/mobius_app.dart';
import 'core/ffi/offline_player.dart';
import 'core/macos/macos_folder_access.dart';

String _libraryPath() {
  if (kDebugMode) {
    final override = Platform.environment['MOBIUS_RUST_LIBRARY'];
    if (override != null && override.isNotEmpty) {
      return override;
    }

    final searchStarts = <Directory>[
      Directory.current.absolute,
      File(Platform.resolvedExecutable).parent,
    ];

    for (final start in searchStarts) {
      var directory = start;
      while (true) {
        final workspaceMarker = File(
          '${directory.path}/rust/ffi/Cargo.toml',
        );
        if (workspaceMarker.existsSync()) {
          return File(
            '${directory.path}/target/debug/liboffline_player_ffi.dylib',
          ).path;
        }

        final parent = directory.parent;
        if (parent.path == directory.path) {
          break;
        }
        directory = parent;
      }
    }

    throw StateError(
      'Unable to locate the Mobius Rust workspace. Set MOBIUS_RUST_LIBRARY '
      'to the path of liboffline_player_ffi.dylib.',
    );
  }

  final executable = File(Platform.resolvedExecutable);
  final contentsDirectory = executable.parent.parent;

  return File(
    '${contentsDirectory.path}/Frameworks/'
    'liboffline_player_ffi.dylib',
  ).path;
}

String _databasePath() {
  final home = Platform.environment['HOME'];

  if (home == null || home.isEmpty) {
    throw StateError('Unable to determine the user home directory.');
  }

  final directory = Directory(
    '$home/Library/Application Support/Mobius/Library',
  );

  directory.createSync(recursive: true);

  return File(
    '${directory.path}/mobius_library.sqlite3',
  ).path;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  OfflinePlayer? player;

  try {
    // Restore all security-scoped folder permissions before the player
    // and the rest of the UI can access the user's music files.
    await MacOSFolderAccess.restoreAllBookmarks();

    player = OfflinePlayer.open(
      libraryPath: _libraryPath(),
      dbPath: _databasePath(),
    );

    runApp(
      MobiusApp(
        player: player,
      ),
    );
  } catch (error, stackTrace) {
    debugPrint(
      'Failed to start Mobius: $error',
    );

    debugPrintStack(
      stackTrace: stackTrace,
    );

    player?.dispose();

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Failed to start Mobius\n\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
