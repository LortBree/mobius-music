import '../../platform/platform_services.dart';
import '../../platform/shared/folder_access_service.dart';

/// Platform-neutral access to the user's music folders.
///
/// Delegates to [FolderAccessService] via [PlatformServices.folderAccess], which
/// routes to macOS security-scoped bookmarks or Android Storage Access Framework (SAF)
/// depending on the current runtime platform.
abstract final class FolderAccess {
  /// Lets the user choose a music folder. Returns a filesystem path, or null
  /// when cancelled.
  static Future<String?> pickFolder({
    String confirmButtonText = 'Choose Folder',
  }) {
    return PlatformServices.folderAccess.pickFolder(
      confirmButtonText: confirmButtonText,
    );
  }

  /// Makes sure the app may read audio files. Always true off Android.
  static Future<bool> ensureReadPermission() {
    return PlatformServices.folderAccess.ensureReadPermission();
  }

  /// Persists access to [path] across launches.
  static Future<bool> persist(String path) {
    return PlatformServices.folderAccess.persist(path);
  }

  /// Re-opens access to a previously persisted [path]; returns the usable path.
  static Future<String?> restore(String path) {
    return PlatformServices.folderAccess.restore(path);
  }

  /// Re-opens every previously persisted folder.
  static Future<List<String>> restoreAll() {
    return PlatformServices.folderAccess.restoreAll();
  }

  /// Drops access to [path].
  static Future<void> remove(String path) {
    return PlatformServices.folderAccess.remove(path);
  }

  /// Returns the app-private files directory (Android: host context.filesDir,
  /// macOS: ~/Library/Application Support/Mobius/Library).
  static Future<String> appDataDirectory() {
    return PlatformServices.folderAccess.appDataDirectory();
  }
}
