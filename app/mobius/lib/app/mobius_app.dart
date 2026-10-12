import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ffi/offline_player.dart';
import '../core/platform/android_media_session.dart';
import '../features/library/data/ffi_library_repository.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import 'adaptive_shell.dart';
import 'theme/mobius_theme.dart';
import '../playback/playback_settings.dart';
import '../playback/player_controller.dart';
import '../playback/presentation/volume_floating_panel.dart';
import 'widgets/mobius_loading_view.dart';

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
  late final AndroidMediaSessionBridge _androidMediaSession;

  ThemeMode _themeMode = ThemeMode.dark;
  bool _isReady = false;
  bool _isOnboarded = true;

  @override
  void initState() {
    super.initState();

    _libraryRepository = FfiLibraryRepository(widget.player);
    _playerController = PlayerController(
      widget.player,
      onVolumeChanged: PlaybackSettings.saveVolumeSoon,
    );
    // No-op off Android: mirrors playback into the media notification and
    // lock screen, and routes their buttons back to the controller.
    _androidMediaSession =
        AndroidMediaSessionBridge(_playerController, _libraryRepository)
          ..start();

    _initApp();
  }

  Future<void> _initApp() async {
    final preferences = await SharedPreferences.getInstance();
    final onboarded =
        preferences.getBool(OnboardingPage.onboardingCompletedKey) ?? false;
    final folders = preferences.getStringList('music_folders') ?? [];
    final hasFoldersOrOnboarded = onboarded || folders.isNotEmpty;

    await Future.wait([
      PlaybackSettings.restore(_playerController),
      _loadThemeMode(),
      Future<void>.delayed(const Duration(milliseconds: 700)),
    ]);
    if (!mounted) return;
    setState(() {
      _isOnboarded = hasFoldersOrOnboarded;
      _isReady = true;
    });
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
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            VolumeFloatingPanel(controller: _playerController),
          ],
        );
      },
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: !_isReady
            ? const Scaffold(
                key: ValueKey('startup_loading'),
                backgroundColor: Colors.black,
                body: MobiusLoadingView(
                  size: 280,
                  backgroundColor: Colors.black,
                ),
              )
            : !_isOnboarded
                ? OnboardingPage(
                    key: const ValueKey('onboarding_page'),
                    repository: _libraryRepository,
                    onComplete: () {
                      setState(() => _isOnboarded = true);
                    },
                  )
                : AdaptiveShell(
                    key: const ValueKey('adaptive_shell'),
                    repository: _libraryRepository,
                    playerController: _playerController,
                    themeController: ThemeModeController(
                      mode: _themeMode,
                      setMode: _setThemeMode,
                    ),
                  ),
      ),
    );
  }

  @override
  void dispose() {
    _androidMediaSession.dispose();
    _playerController.dispose();
    widget.player.dispose();
    super.dispose();
  }
}
