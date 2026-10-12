import 'package:flutter/material.dart';

import '../core/platform/app_lifecycle_bridge.dart';
import '../features/library/data/ffi_library_repository.dart';
import '../features/library/presentation/library_page.dart'
    show LibraryPageState;
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
  GlobalKey<NavigatorState> _contentNavigatorKey = GlobalKey<NavigatorState>();

  @override
  FfiLibraryRepository get repository => widget.repository;
  @override
  PlayerController get playerController => widget.playerController;
  @override
  ThemeModeController get themeController => widget.themeController;

  static const double _miniPlayerHeight = 62;

  /// Bottom-nav destinations: Home · Library · Search · Settings.
  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.library_music_outlined),
      selectedIcon: Icon(Icons.library_music_rounded),
      label: 'Library',
    ),
    NavigationDestination(
      icon: Icon(Icons.search_rounded),
      selectedIcon: Icon(Icons.search_rounded),
      label: 'Search',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
  ];

  /// Shared page index for each bottom-nav tab.
  static const List<int> _tabToPageIndex = [
    kHomePageIndex,
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
    final targetPage = _tabToPageIndex[tabIndex];
    if (selectedPage == targetPage) {
      final nav = _contentNavigatorKey.currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((route) => route.isFirst);
      }
      if (targetPage == kLibraryPageIndex) {
        _libraryKey.currentState?.handleBack();
      }
      return;
    }
    _contentNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    selectedPage = targetPage;
  }

  @override
  void onSelectedPageChanged() {
    _contentNavigatorKey = GlobalKey<NavigatorState>();
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

        // 1. If the nested content navigator has pushed sub-routes (e.g. detail pages, sound), pop them first.
        final nav = _contentNavigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
          return;
        }

        // 2. If currently on Home page, move app to background without killing activity.
        if (selectedPage == kHomePageIndex) {
          await AppLifecycleBridge.moveTaskToBack();
          return;
        }

        // 3. If on Library page, let it handle sub-tab navigation or go back to Home
        if (selectedPage == kLibraryPageIndex) {
          if (_libraryKey.currentState?.handleBack() == true) {
            return;
          }
          selectedPage = kHomePageIndex;
          return;
        }

        // 4. If on any other page (Search, Settings, etc.), return to Home page
        selectedPage = kHomePageIndex;
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
                  child: NavigatorPopHandler<void>(
                    onPopWithResult: (_) {
                      final nav = _contentNavigatorKey.currentState;
                      if (nav != null && nav.canPop()) {
                        nav.pop();
                      }
                    },
                    child: Navigator(
                      key: _contentNavigatorKey,
                      onGenerateInitialRoutes: (navigator, initialRoute) => [
                        MaterialPageRoute<void>(
                          builder: (_) => buildPage(
                            selectedPage,
                            onOpenSound: _openSound,
                            libraryKey: _libraryKey,
                          ),
                        ),
                      ],
                    ),
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
                      onPrevious: previous,
                      onNext: next,
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
