import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/mobius_app.dart';
import 'core/ffi/offline_player.dart';
import 'core/platform/folder_access.dart';
import 'platform/platform_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  OfflinePlayer? player;

  try {
    // Restore all security-scoped folder permissions before the player
    // and the rest of the UI can access the user's music files.
    await FolderAccess.restoreAll();

    final libraryPath = PlatformServices.paths.libraryPath();
    final dbPath = await PlatformServices.paths.databasePath();

    player = OfflinePlayer.open(
      libraryPath: libraryPath,
      dbPath: dbPath,
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
