import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/keyboard/text_input_focus.dart';
import '../features/library/data/ffi_library_repository.dart';
import '../playback/player_controller.dart';
import 'player_shell_state.dart';
import 'widgets/animated_mobius_background.dart';
import 'theme/mobius_theme.dart';
import 'mobius_app.dart' show ThemeModeController;
import '../playback/presentation/mini_player.dart';

/// Layout constants pulled out of the widget so tuning them doesn't mean
/// hunting through build methods.
class _MobiusMetrics {
  const _MobiusMetrics._();

  static const double minSidebarWidth = 76;
  static const double maxSidebarWidth = 420;
  static const double collapsedThreshold = 156;
  static const double initialSidebarWidth = 300;
  static const double topBarHeight = 72;
  static const double miniPlayerHeight = 112;
  static const double sidebarDividerWidth = 16;
}

class _NavEntry {
  const _NavEntry(this.icon, this.label);

  final IconData icon;
  final String label;
}

const List<_NavEntry> _kPrimaryNavEntries = [
  _NavEntry(Icons.library_music_outlined, 'Library'),
  _NavEntry(Icons.album_outlined, 'Albums'),
  _NavEntry(Icons.person_outline_rounded, 'Artists'),
  _NavEntry(Icons.playlist_play_rounded, 'Playlists'),
  _NavEntry(Icons.graphic_eq_rounded, 'Sound'),
];
const _NavEntry _kSettingsNavEntry = _NavEntry(
  Icons.settings_outlined,
  'Settings',
);

class MobiusShell extends StatefulWidget {
  const MobiusShell({
    super.key,
    required this.repository,
    required this.playerController,
    required this.themeController,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final ThemeModeController themeController;

  @override
  State<MobiusShell> createState() => _MobiusShellState();
}

class _MobiusShellState extends State<MobiusShell> with PlayerShellState {
  @override
  FfiLibraryRepository get repository => widget.repository;
  @override
  PlayerController get playerController => widget.playerController;
  @override
  ThemeModeController get themeController => widget.themeController;

  /// Surface colours for the current theme, resolved fresh each build so they
  /// flip with light/dark mode.
  MobiusSurfaces get _colors => MobiusSurfaces.of(context);

  double _sidebarWidth = _MobiusMetrics.initialSidebarWidth;

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

  bool get _sidebarCollapsed =>
      _sidebarWidth < _MobiusMetrics.collapsedThreshold;

  void _resizeSidebar(DragUpdateDetails details) {
    final nextWidth = (_sidebarWidth + details.delta.dx).clamp(
      _MobiusMetrics.minSidebarWidth,
      _MobiusMetrics.maxSidebarWidth,
    );

    if (nextWidth == _sidebarWidth) {
      return;
    }

    setState(() {
      _sidebarWidth = nextWidth;
    });
  }

  KeyEventResult _handleKeyboardShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (isEditingText()) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    final shift = keyboard.isShiftPressed;
    final controlOrMeta = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (controlOrMeta || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (!shift && key == LogicalKeyboardKey.space) {
      playPause();
      return KeyEventResult.handled;
    }

    if (shift && key == LogicalKeyboardKey.arrowLeft) {
      previous();
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.arrowRight) {
      next();
      return KeyEventResult.handled;
    }

    if (!shift && key == LogicalKeyboardKey.arrowLeft) {
      seekTo(playerController.currentSeconds - 5);
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.arrowRight) {
      seekTo(playerController.currentSeconds + 5);
      return KeyEventResult.handled;
    }

    if (!shift && key == LogicalKeyboardKey.arrowUp) {
      _changeVolume(0.05);
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.arrowDown) {
      _changeVolume(-0.05);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _changeVolume(double delta) {
    try {
      playerController.setVolume(playerController.volume + delta);
    } catch (error) {
      showError(error);
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyboardShortcut,
      child: Scaffold(
        backgroundColor: _colors.background,
        body: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: AnimatedMobiusBackground(
                // Freeze the ambient drift while idle so the window stops
                // repainting at display rate when nothing is playing.
                animate: isPlaying,
                child: Row(
                  children: [
                    SizedBox(width: _sidebarWidth, child: _buildSidebar()),
                    _buildSidebarDivider(),
                    Expanded(child: buildPage(selectedPage)),
                  ],
                ),
              ),
            ),
            _buildMiniPlayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: _MobiusMetrics.topBarHeight,
      decoration: BoxDecoration(
        color: _colors.header,
        border: Border(bottom: BorderSide(color: _colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Text(
            'MOBIUS',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: _colors.textPrimary,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSidebarDivider() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: _resizeSidebar,
        child: SizedBox(
          width: _MobiusMetrics.sidebarDividerWidth,
          height: double.infinity,
          child: Center(child: Container(width: 1, color: _colors.border)),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final collapsed = _sidebarCollapsed;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 8 : 20,
        18,
        collapsed ? 8 : 20,
        24,
      ),
      child: Column(
        children: [
          for (var i = 0; i < _kPrimaryNavEntries.length; i++)
            _sidebarItem(
              entry: _kPrimaryNavEntries[i],
              selected: selectedPage == i,
              collapsed: collapsed,
              onTap: () => selectedPage = i,
            ),
          const Spacer(),
          _sidebarItem(
            entry: _kSettingsNavEntry,
            selected: selectedPage == kSettingsPageIndex,
            collapsed: collapsed,
            onTap: () => selectedPage = kSettingsPageIndex,
          ),
        ],
      ),
    );
  }

  Widget _sidebarItem({
    required _NavEntry entry,
    required bool selected,
    required bool collapsed,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? _colors.selection : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (!collapsed) const SizedBox(width: 18),
                Icon(
                  entry.icon,
                  size: 24,
                  color: selected ? _colors.accent : _colors.textSecondary,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? _colors.textPrimary
                            : _colors.textSecondary,
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Mini player
  // ---------------------------------------------------------------------

  Widget _buildMiniPlayer() {
    return MiniPlayer(
      height: _MobiusMetrics.miniPlayerHeight,
      track: currentTrackMetadata,
      artwork: currentArtworkImage,
      position: position,
      duration: currentDuration,
      isPlaying: isPlaying,
      isFavorite: currentTrackIsFavorite,
      repeatMode: repeatMode,
      onOpenNowPlaying: openNowPlaying,
      onPrevious: previous,
      onPlayPause: playPause,
      onNext: next,
      onSeekPreview: seekPreview,
      onSeek: seekTo,
      onToggleFavorite: toggleCurrentFavorite,
      onAddToPlaylist: addCurrentTrackToPlaylist,
      onToggleRepeat: toggleRepeat,
      onOpenQueue: openQueue,
    );
  }
}
