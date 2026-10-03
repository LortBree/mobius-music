import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ffi/offline_player.dart';
import '../features/library/data/ffi_library_repository.dart';
import 'mobius_shell.dart';
import 'theme/mobius_theme.dart';
import '../playback/playback_settings.dart';
import '../playback/player_controller.dart';

/// Lets descendants (the Settings page) read and change the app theme mode
/// without a state-management dependency -- consistent with the app's plain
/// setState + constructor-injection conventions.
class ThemeModeController {
  const ThemeModeController({required this.mode, required this.setMode});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> setMode;
}

class MobiusApp extends StatefulWidget {
  const MobiusApp({super.key, required this.player});

  final OfflinePlayer player;

  @override
  State<MobiusApp> createState() => _MobiusAppState();
}

class _MobiusAppState extends State<MobiusApp> {
  static const String _themeModeKey = 'theme_mode_v1';

  late final FfiLibraryRepository _libraryRepository;
  late final PlayerController _playerController;

  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();

    _libraryRepository = FfiLibraryRepository(widget.player);
    _playerController = PlayerController(
      widget.player,
      onVolumeChanged: PlaybackSettings.saveVolumeSoon,
    );

    unawaited(PlaybackSettings.restore(_playerController));
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(_themeModeKey);
    final mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeModeKey, mode.name);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mobius Music',
      theme: MobiusTheme.light(),
      darkTheme: MobiusTheme.dark(),
      themeMode: _themeMode,
      home: MobiusShell(
        repository: _libraryRepository,
        playerController: _playerController,
        themeController: ThemeModeController(
          mode: _themeMode,
          setMode: _setThemeMode,
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.player.dispose();
    super.dispose();
  }
}
