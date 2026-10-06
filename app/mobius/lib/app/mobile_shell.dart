import 'package:flutter/material.dart';

import '../core/platform/app_lifecycle_bridge.dart';
import '../features/library/data/ffi_library_repository.dart';
import '../features/library/presentation/library_page.dart' show LibraryPageState;
import '../features/sound/presentation/sound_page.dart';
import '../playback/player_controller.dart';
import '../playback/presentation/mobile_mini_player.dart';
import 'mobius_app.dart' show ThemeModeController;
import 'player_shell_state.dart';
import 'theme/colors.dart';
import 'theme/mobius_theme.dart';
import 'widgets/animated_mobius_background.dart';

/// Phone layout: a bottom [NavigationBar] shell that reuses every content page
/// and the shared [PlayerShellState] (same player-state ownership as the
/// desktop [MobiusShell] — values down, callbacks up).
class MobileShell extends StatefulWidget {
  const MobileShell({
    super.key,
    required this.repository,
    required this.playerController,
    required this.themeController,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final ThemeModeController themeController;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> with PlayerShellState {
  final GlobalKey<LibraryPageState> _libraryKey = GlobalKey<LibraryPageState>();

  @override
  FfiLibraryRepository get repository => widget.repository;
  @override
  PlayerController get playerController => widget.playerController;
  @override
  ThemeModeController get themeController => widget.themeController;

  static const double _miniPlayerHeight = 62;

  /// Bottom-nav destinations (v4): Library · Search · Settings. Albums,
  /// Artists and Playlists are reached from inside Library's tabs and from
  /// search results, not from the bottom bar. Sound is reached from Settings.
  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.library_music_outlined),
      label: 'Library',
    ),
    NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Search'),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      label: 'Settings',
    ),
  ];

  /// Shared page index for each bottom-nav tab.
  static const List<int> _tabToPageIndex = [
    kLibraryPageIndex,
    kSearchPageIndex,
    kSettingsPageIndex,
  ];

  @override
  void initState() {
    super.initState();
    initPlayerShell();
  }

  @override
  void dispose() {
    disposePlayerShell();
    super.dispose();
  }

  /// Which bottom-nav tab is highlighted for the current shared page. Pages
  /// not represented in the bar (e.g. Sound) fall back to no selection by
  /// clamping to Library — Sound is only ever a pushed route, never selected
  /// as a tab.
  int get _selectedTab {
    final index = _tabToPageIndex.indexOf(selectedPage);
    return index < 0 ? 0 : index;
  }

  void _onTabSelected(int tabIndex) {
    selectedPage = _tabToPageIndex[tabIndex];
  }

  void _openSound() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: MobiusColors.backgroundOf(context),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: MobiusColors.textOf(context),
            elevation: 0,
            title: const Text('Sound'),
          ),
          body: SafeArea(
            child: SoundPage(playerController: widget.playerController),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = MobiusSurfaces.of(context);
    final hasTrack = currentTrackMetadata != null;

    final baseAmbient = MobiusTheme.ambientFor(Theme.of(context).brightness);
    final mobileAmbient = AmbientConfig(
      base: baseAmbient.base,
      violet: baseAmbient.violet,
      magenta: baseAmbient.magenta,
      blue: baseAmbient.blue,
      cyan: baseAmbient.cyan,
      intensity: 0.72,
      falloffTop: 0.02,
      falloffBottom: 0.96,
      animationSpeed: baseAmbient.animationSpeed,
      warmMode: baseAmbient.warmMode,
      enabled: baseAmbient.enabled,
      maxFrameRate: baseAmbient.maxFrameRate,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 1. If currently on Library page, let it handle sub-tab/detail navigation first
        if (selectedPage == kLibraryPageIndex) {
          if (_libraryKey.currentState?.handleBack() == true) {
            return;
          }
          // Already on Songs tab (home): move app to background without killing activity or state
          await AppLifecycleBridge.moveTaskToBack();
          return;
        }

        // 2. If on any other page (Search, Settings, etc.), return to Library page
        setState(() => selectedPage = kLibraryPageIndex);
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: AnimatedMobiusBackground(
          // Freeze the ambient drift while idle, exactly as the desktop shell.
          animate: isPlaying,
          config: mobileAmbient,
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                Positioned.fill(
                  child: buildPage(
                    selectedPage,
                    onOpenSound: _openSound,
                    libraryKey: _libraryKey,
                  ),
                ),
                if (hasTrack)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: MobileMiniPlayer(
                      height: _miniPlayerHeight,
                      track: currentTrackMetadata,
                      artwork: currentArtworkImage,
                      position: position,
                      duration: currentDuration,
                      isPlaying: isPlaying,
                      isFavorite: currentTrackIsFavorite,
                      repeatMode: repeatMode,
                      onOpenNowPlaying: openNowPlaying,
                      onToggleRepeat: toggleRepeat,
                      onToggleFavorite: toggleCurrentFavorite,
                      onPlayPause: playPause,
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: _onTabSelected,
          destinations: _destinations,
        ),
      ),
    );
  }
}
