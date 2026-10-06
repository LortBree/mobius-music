import '../../platform/macos/macos_folder_access.dart';

class MacOSFolderAccess {
  MacOSFolderAccess._();

  static const MacOSFolderAccessService _service = MacOSFolderAccessService();

  static Future<bool> saveBookmark(String path) => _service.persist(path);

  static Future<String?> restoreBookmark(String path) => _service.restore(path);

  static Future<List<String>> restoreAllBookmarks() => _service.restoreAll();

  static Future<bool> removeBookmark(String path) async {
    await _service.remove(path);
    return true;
  }
}
