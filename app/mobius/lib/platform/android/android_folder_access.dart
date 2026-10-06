import 'package:flutter/services.dart';

import '../shared/folder_access_service.dart';

/// Android implementation of [FolderAccessService] using the Storage Access
/// Framework (SAF) and Android runtime audio media permissions over the
/// `mobius/android_storage` channel.
class AndroidFolderAccessService implements FolderAccessService {
  const AndroidFolderAccessService();

  static const MethodChannel _channel = MethodChannel('mobius/android_storage');

  @override
  Future<String?> pickFolder({String confirmButtonText = 'Choose Folder'}) async {
    if (!await ensureReadPermission()) return null;
    return _channel.invokeMethod<String>('pickFolder');
  }

  @override
  Future<bool> ensureReadPermission() async {
    final granted = await _channel.invokeMethod<bool>('ensureAudioPermission');
    return granted ?? false;
  }

  @override
  Future<bool> persist(String path) {
    // On Android, media permission is the grant; no bookmark needed.
    return Future.value(true);
  }

  @override
  Future<String?> restore(String path) {
    return Future.value(path);
  }

  @override
  Future<List<String>> restoreAll() {
    return Future.value(const <String>[]);
  }

  @override
  Future<void> remove(String path) {
    return Future.value();
  }

  @override
  Future<String> appDataDirectory() async {
    final dir = await _channel.invokeMethod<String>('appDataDirectory');
    if (dir == null || dir.isEmpty) {
      throw StateError('Host did not return appDataDirectory.');
    }
    return dir;
  }
}
