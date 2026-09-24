import 'package:flutter/services.dart';

class MacOSFolderAccess {
  MacOSFolderAccess._();

  static const MethodChannel _channel =
      MethodChannel('mobius/security_scoped_folder');

  static Future<bool> saveBookmark(String path) async {
    final result = await _channel.invokeMethod<bool>(
      'saveBookmark',
      <String, Object>{
        'path': path,
      },
    );

    return result ?? false;
  }

  static Future<String?> restoreBookmark(String path) {
    return _channel.invokeMethod<String>(
      'restoreBookmark',
      <String, Object>{
        'path': path,
      },
    );
  }

  static Future<List<String>> restoreAllBookmarks() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'restoreAllBookmarks',
    );

    return result
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];
  }

  static Future<bool> removeBookmark(String path) async {
    final result = await _channel.invokeMethod<bool>(
      'removeBookmark',
      <String, Object>{
        'path': path,
      },
    );

    return result ?? false;
  }
}
