import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../shared/folder_access_service.dart';

/// macOS implementation of [FolderAccessService] using security-scoped bookmarks
/// and standard macOS directory pickers.
class MacOSFolderAccessService implements FolderAccessService {
  const MacOSFolderAccessService();

  static const MethodChannel _channel =
      MethodChannel('mobius/security_scoped_folder');

  @override
  Future<String?> pickFolder({String confirmButtonText = 'Choose Folder'}) {
    return getDirectoryPath(confirmButtonText: confirmButtonText);
  }

  @override
  Future<bool> ensureReadPermission() async {
    // macOS file picker / security-scoped bookmarks handle authorization.
    return true;
  }

  @override
  Future<bool> persist(String path) async {
    final result = await _channel.invokeMethod<bool>(
      'saveBookmark',
      <String, Object>{'path': path},
    );
    return result ?? false;
  }

  @override
  Future<String?> restore(String path) {
    return _channel.invokeMethod<String>(
      'restoreBookmark',
      <String, Object>{'path': path},
    );
  }

  @override
  Future<List<String>> restoreAll() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'restoreAllBookmarks',
    );
    return result?.whereType<String>().toList(growable: false) ??
        const <String>[];
  }

  @override
  Future<void> remove(String path) async {
    await _channel.invokeMethod<bool>(
      'removeBookmark',
      <String, Object>{'path': path},
    );
  }

  @override
  Future<String> appDataDirectory() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('Unable to determine the user home directory.');
    }
    final directory = Directory(
      '$home/Library/Application Support/Mobius/Library',
    );
    directory.createSync(recursive: true);
    return directory.path;
  }
}
