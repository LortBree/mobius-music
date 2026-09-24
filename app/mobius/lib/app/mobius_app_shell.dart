import 'package:flutter/material.dart';

import '../core/ffi/offline_player.dart';
import '../features/library/data/ffi_library_repository.dart';
import 'mobius_shell.dart';
import '../playback/player_controller.dart';

class MobiusApp extends StatefulWidget {
  const MobiusApp({
    super.key,
    required this.player,
  });

  final OfflinePlayer player;

  @override
  State<MobiusApp> createState() => _MobiusAppState();
}

class _MobiusAppState extends State<MobiusApp> {
  late final FfiLibraryRepository _libraryRepository;
  late final PlayerController _playerController;

  @override
  void initState() {
    super.initState();

    _libraryRepository =
        FfiLibraryRepository(widget.player);

    _playerController =
        PlayerController(widget.player);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mobius',
      theme: _buildTheme(),
      home: MobiusShell(
        repository: _libraryRepository,
        playerController: _playerController,
      ),
    );
  }

  @override
  void dispose() {
    widget.player.dispose();
    super.dispose();
  }

  ThemeData _buildTheme() {
    const background = Color(0xFF121212);
    const surface = Color(0xFF1A1A1A);
    const elevated = Color(0xFF2A2A2A);
    const primary = Color(0xFF8A63D2);
    const text = Color(0xFFEDEDED);
    const secondaryText = Color(0xFF9A9A9A);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        surface: surface,
        onSurface: text,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          color: text,
          fontSize: 15,
        ),
        bodyMedium: TextStyle(
          color: secondaryText,
          fontSize: 14,
        ),
        titleLarge: TextStyle(
          color: text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: elevated,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(
        color: text,
      ),
    );
  }
}
