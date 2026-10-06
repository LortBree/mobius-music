import 'dart:ffi' as ffi;
import 'dart:io';

import '../shared/platform_paths_service.dart';
import 'android_folder_access.dart';

/// Android implementation of [PlatformPathsService].
class AndroidPlatformPathsService implements PlatformPathsService {
  const AndroidPlatformPathsService();

  @override
  String libraryPath() => 'liboffline_player_ffi.so';

  @override
  Future<String> databasePath() async {
    const folderAccess = AndroidFolderAccessService();
    final dir = await folderAccess.appDataDirectory();
    final directory = Directory('$dir/Library')..createSync(recursive: true);
    return File('${directory.path}/mobius_library.sqlite3').path;
  }

  @override
  ffi.DynamicLibrary openLibrary(String path) {
    // Packaged by Gradle under lib/<abi>/ and resolved by name.
    return ffi.DynamicLibrary.open('liboffline_player_ffi.so');
  }
}
