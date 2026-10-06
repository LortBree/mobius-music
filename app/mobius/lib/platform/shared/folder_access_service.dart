/// Platform-neutral interface for accessing music directories.
abstract interface class FolderAccessService {
  /// Lets the user choose a music folder. Returns a filesystem path, or null
  /// when cancelled.
  Future<String?> pickFolder({String confirmButtonText = 'Choose Folder'});

  /// Ensures read permissions for audio files are granted.
  Future<bool> ensureReadPermission();

  /// Persists access to [path] across application launches.
  Future<bool> persist(String path);

  /// Re-opens access to a previously persisted [path]; returns the usable path.
  Future<String?> restore(String path);

  /// Restores access to every known persisted path.
  Future<List<String>> restoreAll();

  /// Revokes / removes a persisted path.
  Future<void> remove(String path);

  /// Application-private storage directory path (e.g. for the database).
  Future<String> appDataDirectory();
}
