import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../shared/platform_paths_service.dart';

/// macOS implementation of [PlatformPathsService].
class MacOSPlatformPathsService implements PlatformPathsService {
  const MacOSPlatformPathsService();

  @override
  String libraryPath() {
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

  @override
  Future<String> databasePath() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('Unable to determine the user home directory.');
    }

    final directory = Directory(
      '$home/Library/Application Support/Mobius/Library',
    );
    directory.createSync(recursive: true);

    return File('${directory.path}/mobius_library.sqlite3').path;
  }

  @override
  ffi.DynamicLibrary openLibrary(String path) {
    final bundledLibrary = File(path);
    if (bundledLibrary.existsSync()) {
      return ffi.DynamicLibrary.open(bundledLibrary.path);
    }

    final fallback = File('target/debug/liboffline_player_ffi.dylib');
    if (fallback.existsSync()) {
      return ffi.DynamicLibrary.open(fallback.path);
    }

    return ffi.DynamicLibrary.open(path);
  }
}
