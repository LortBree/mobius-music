import 'dart:ffi' as ffi;

/// Platform-neutral interface for resolving application binary and database paths.
abstract interface class PlatformPathsService {
  /// Resolves the native Rust dynamic library path or filename for this platform.
  String libraryPath();

  /// Resolves the filesystem path to the persistent SQLite database.
  Future<String> databasePath();

  /// Opens the dynamic library using FFI for this platform.
  ffi.DynamicLibrary openLibrary(String path);
}
