import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ffi/offline_player.dart';
import '../features/library/data/ffi_library_repository.dart';
import '../features/library/presentation/library_page.dart';
import '../features/library/presentation/albums_page.dart';
import '../features/library/presentation/artists_page.dart';
import '../features/library/presentation/collections_pages.dart';
import '../features/library/data/user_collections.dart';
import '../features/settings/presentation/settings_page.dart';
import '../playback/player_controller.dart';
import 'widgets/animated_mobius_background.dart';
import 'theme/mobius_theme.dart';
import 'mobius_app.dart' show ThemeModeController;
import '../playback/presentation/now_playing_page.dart';
import '../playback/playback_poller.dart';
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
  static const Duration pollInterval = Duration(milliseconds: 200);
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
];
const _NavEntry _kSettingsNavEntry = _NavEntry(
  Icons.settings_outlined,
  'Settings',
);
const int _kSettingsPageIndex = 4;

/// A plain snapshot of everything the shell reads off [PlayerController].
/// Exists purely so `_syncPlayer` and `_updatePlayer` can share one read
/// path instead of duplicating the same five field reads.
class _PlayerSnapshot {
  const _PlayerSnapshot({
    required this.trackId,
    required this.position,
    required this.duration,
    required this.state,
    required this.repeatMode,
  });

  final int trackId;
  final double position;
  final double duration;
  final OfflinePlayerState state;
  final OfflinePlayerRepeatMode repeatMode;
}

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

class _MobiusShellState extends State<MobiusShell> {
  /// Surface colours for the current theme, resolved fresh each build so they
  /// flip with light/dark mode.
  MobiusSurfaces get _colors => MobiusSurfaces.of(context);

  final UserCollections _collections = UserCollections();
  double _sidebarWidth = _MobiusMetrics.initialSidebarWidth;
  int _selectedPage = 0;
  int _libraryVersion = 0;
  int _albumNavigationRequest = 0;
  int _artistNavigationRequest = 0;
  TrackMetadata? _albumNavigationTrack;
  String? _artistNavigationName;

  // Fast (pollInterval) only while playing; this loop also drives natural
  // end-of-track advance via pollPlayback, so it keeps running while the
  // window is hidden.
  late final PlaybackPoller _poller = PlaybackPoller(
    onTick: _updatePlayer,
    isActive: () => _playerState == OfflinePlayerState.playing,
    activeInterval: _MobiusMetrics.pollInterval,
  );
  final ValueNotifier<double> _position = ValueNotifier<double>(0);

  int _currentTrackId = 0;
  TrackMetadata? _currentTrackMetadata;
  ImageProvider? _currentArtworkImage;
  double _currentDuration = 0;
  bool _currentTrackIsFavorite = false;

  OfflinePlayerState _playerState = OfflinePlayerState.idle;
  OfflinePlayerRepeatMode _repeatMode = OfflinePlayerRepeatMode.off;

  @override
  void initState() {
    super.initState();

    _syncPlayer();

    widget.playerController.commands.addListener(_onPlayerCommand);
    widget.playerController.pendingTrackId.addListener(_onPendingTrack);
    _poller.start();
  }

  @override
  void dispose() {
    widget.playerController.commands.removeListener(_onPlayerCommand);
    widget.playerController.pendingTrackId.removeListener(_onPendingTrack);
    _poller.stop();
    _position.dispose();
    super.dispose();
  }

  /// A track change is about to block the UI thread (device re-clock):
  /// show the target track now so that frame is what stays on screen.
  void _onPendingTrack() {
    final trackId = widget.playerController.pendingTrackId.value;
    if (!mounted || trackId == null || trackId == _currentTrackId) return;
    setState(() {
      _currentTrackId = trackId;
      _loadArtworkForTrack(trackId);
      _loadCurrentFavoriteStatus(trackId);
      _position.value = 0;
      _currentDuration = 0;
    });
  }

  /// Any page (library, queue, Now Playing) may have just changed playback:
  /// refresh right away and resume the fast cadence if it started. Deferred
  /// to a microtask so a command issued mid-build never triggers setState.
  void _onPlayerCommand() {
    scheduleMicrotask(() {
      if (!mounted) return;
      _updatePlayer();
      _poller.wake();
    });
  }

  // ---------------------------------------------------------------------
  // Player state syncing
  // ---------------------------------------------------------------------

  _PlayerSnapshot _readSnapshot() {
    final controller = widget.playerController;
    return _PlayerSnapshot(
      trackId: controller.currentTrackId,
      position: controller.currentSeconds,
      duration: controller.durationSeconds,
      state: controller.state,
      repeatMode: controller.repeatMode,
    );
  }

  void _applySnapshot(_PlayerSnapshot snapshot) {
    final trackChanged = snapshot.trackId != _currentTrackId;
    if (trackChanged) {
      _loadArtworkForTrack(snapshot.trackId);
    }

    _currentTrackId = snapshot.trackId;
    if (trackChanged) {
      _loadCurrentFavoriteStatus(snapshot.trackId);
    }
    _position.value = snapshot.position;
    _currentDuration = snapshot.duration;
    _playerState = snapshot.state;
    _repeatMode = snapshot.repeatMode;
  }

  void _syncPlayer() {
    try {
      _applySnapshot(_readSnapshot());
    } catch (_) {
      _currentTrackId = 0;
      _currentTrackMetadata = null;
      _currentArtworkImage = null;
      _currentTrackIsFavorite = false;
      _position.value = 0;
      _currentDuration = 0;
      _playerState = OfflinePlayerState.idle;
      _repeatMode = OfflinePlayerRepeatMode.off;
    }
  }

  void _updatePlayer() {
    if (!mounted) {
      return;
    }

    try {
      widget.playerController.pollPlayback();
      final snapshot = _readSnapshot();
      final discreteStateChanged =
          snapshot.trackId != _currentTrackId ||
          snapshot.duration != _currentDuration ||
          snapshot.state != _playerState ||
          snapshot.repeatMode != _repeatMode;

      if (discreteStateChanged) {
        setState(() => _applySnapshot(snapshot));
      } else {
        _position.value = snapshot.position;
      }
    } catch (_) {}
  }

  void _loadArtworkForTrack(int trackId) {
    if (trackId <= 0) {
      _currentTrackMetadata = null;
      _currentArtworkImage = null;
      return;
    }

    try {
      _currentTrackMetadata = widget.repository.getTrackMetadata(trackId);
      final artwork = widget.repository.getTrackArtwork(trackId);

      if (artwork == null || artwork.data.isEmpty) {
        _currentArtworkImage = null;
        return;
      }

      _currentArtworkImage = ResizeImage(
        MemoryImage(artwork.data),
        width: 128,
        height: 128,
      );
    } catch (_) {
      _currentArtworkImage = null;
    }
  }

  void _loadCurrentFavoriteStatus(int trackId) {
    if (trackId <= 0) {
      _currentTrackIsFavorite = false;
      return;
    }
    unawaited(() async {
      try {
        final favorites = await _collections.favorites();
        if (!mounted || _currentTrackId != trackId) return;
        setState(() => _currentTrackIsFavorite = favorites.contains(trackId));
      } catch (_) {}
    }());
  }

  void _refreshLibrary() {
    if (!mounted) {
      return;
    }

    setState(() {
      _libraryVersion++;
    });
  }

  void _goToArtist(String artist) {
    setState(() {
      _artistNavigationName = artist;
      _artistNavigationRequest++;
      _selectedPage = 2;
    });
  }

  void _goToAlbum(TrackMetadata track) {
    setState(() {
      _albumNavigationTrack = track;
      _albumNavigationRequest++;
      _selectedPage = 1;
    });
  }

  Future<void> _toggleCurrentFavorite() async {
    final trackId = _currentTrackId;
    if (trackId <= 0) return;
    final isFavorite = await _collections.toggleFavorite(trackId);
    if (!mounted || _currentTrackId != trackId) return;
    setState(() => _currentTrackIsFavorite = isFavorite);
    _refreshLibrary();
  }

  Future<void> _addCurrentTrackToPlaylist() async {
    final trackId = _currentTrackId;
    if (trackId <= 0) return;
    final playlists = await _collections.playlists();
    if (!mounted) return;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Create a playlist first.')));
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add to playlist'),
        children: [
          for (final name in playlists.keys)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (name == null) return;
    await _collections.addToPlaylist(name, trackId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Added to $name.')));
    _refreshLibrary();
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

  // ---------------------------------------------------------------------
  // Transport actions
  // ---------------------------------------------------------------------

  void _openNowPlaying({bool openQueue = false}) {
    if (_currentTrackId <= 0) {
      return;
    }

    try {
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) {
                return NowPlayingPage(
                  repository: widget.repository,
                  playerController: widget.playerController,
                  initialOpenQueue: openQueue,
                );
              },
            ),
          )
          .then((_) {
            if (!mounted) return;
            _syncPlayer();
            setState(() {});
          });
    } catch (error) {
      _showError(error);
    }
  }

  void _previous() => _runTransportAction(widget.playerController.previous);

  void _next() => _runTransportAction(widget.playerController.next);

  void _playPause() {
    if (_currentTrackId <= 0) {
      return;
    }

    _runTransportAction(() {
      if (_playerState == OfflinePlayerState.playing) {
        widget.playerController.pause();
      } else {
        widget.playerController.play();
      }
    });
  }

  void _toggleRepeat() =>
      _runTransportAction(widget.playerController.toggleRepeatMode);

  /// Shared wrapper for the "call into the controller, resync, repaint,
  /// surface errors" pattern used by every transport button.
  Future<void> _runTransportAction(FutureOr<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      _syncPlayer();
      setState(() {});
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _openQueue() {
    _openNowPlaying(openQueue: true);
  }

  KeyEventResult _handleKeyboardShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
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
      _playPause();
      return KeyEventResult.handled;
    }

    if (shift && key == LogicalKeyboardKey.arrowLeft) {
      _previous();
      return KeyEventResult.handled;
    }
    if (shift && key == LogicalKeyboardKey.arrowRight) {
      _next();
      return KeyEventResult.handled;
    }

    if (!shift && key == LogicalKeyboardKey.arrowLeft) {
      _seekTo(widget.playerController.currentSeconds - 5);
      return KeyEventResult.handled;
    }
    if (!shift && key == LogicalKeyboardKey.arrowRight) {
      _seekTo(widget.playerController.currentSeconds + 5);
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
      widget.playerController.setVolume(
        widget.playerController.volume + delta,
      );
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  void _seekTo(double value) {
    if (_currentDuration <= 0) {
      return;
    }

    final ratio = (value / _currentDuration).clamp(0.0, 1.0);
    final totalFrames = widget.playerController.totalFrames;

    if (totalFrames <= 0) {
      _syncPlayer();
      setState(() {});
      return;
    }

    final frame = (ratio * totalFrames).round().clamp(0, totalFrames);

    try {
      widget.playerController.seekToFrame(frame);
      _syncPlayer();
      setState(() {});
    } catch (error) {
      _showError(error);
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
                animate: _playerState == OfflinePlayerState.playing,
                child: Row(
                  children: [
                    SizedBox(width: _sidebarWidth, child: _buildSidebar()),
                    _buildSidebarDivider(),
                    Expanded(child: _buildContent()),
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
          child: Center(
            child: Container(width: 1, color: _colors.border),
          ),
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
              selected: _selectedPage == i,
              collapsed: collapsed,
              onTap: () => setState(() => _selectedPage = i),
            ),
          const Spacer(),
          _sidebarItem(
            entry: _kSettingsNavEntry,
            selected: _selectedPage == _kSettingsPageIndex,
            collapsed: collapsed,
            onTap: () => setState(() => _selectedPage = _kSettingsPageIndex),
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
                  color: selected
                      ? _colors.accent
                      : _colors.textSecondary,
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

  Widget _buildContent() {
    switch (_selectedPage) {
      case 0:
        return LibraryPage(
          repository: widget.repository,
          playerController: widget.playerController,
          onOpenNowPlaying: _openNowPlaying,
          onLibraryChanged: _refreshLibrary,
          onGoToArtist: _goToArtist,
          onGoToAlbum: _goToAlbum,
          collections: _collections,
          currentTrackId: _currentTrackId,
          libraryVersion: _libraryVersion,
        );

      case 1:
        return AlbumsPage(
          key: ValueKey(_albumNavigationRequest),
          repository: widget.repository,
          playerController: widget.playerController,
          collections: _collections,
          initialTrack: _albumNavigationTrack,
          onLibraryChanged: _refreshLibrary,
          onGoToArtist: _goToArtist,
          onGoToAlbum: _goToAlbum,
          libraryVersion: _libraryVersion,
        );

      case 2:
        return ArtistsPage(
          key: ValueKey(_artistNavigationRequest),
          repository: widget.repository,
          playerController: widget.playerController,
          collections: _collections,
          initialArtistName: _artistNavigationName,
          onLibraryChanged: _refreshLibrary,
          onGoToArtist: _goToArtist,
          onGoToAlbum: _goToAlbum,
          libraryVersion: _libraryVersion,
        );

      case 3:
        return PlaylistsPage(
          repository: widget.repository,
          playerController: widget.playerController,
          collections: _collections,
          onGoToArtist: _goToArtist,
          onGoToAlbum: _goToAlbum,
          collectionsVersion: _libraryVersion,
        );

      case 4:
        return SettingsPage(
          playerController: widget.playerController,
          repository: widget.repository,
          onLibraryChanged: _refreshLibrary,
          themeController: widget.themeController,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------
  // Mini player
  // ---------------------------------------------------------------------

  Widget _buildMiniPlayer() {
    return MiniPlayer(
      height: _MobiusMetrics.miniPlayerHeight,
      track: _currentTrackMetadata,
      artwork: _currentArtworkImage,
      position: _position,
      duration: _currentDuration,
      isPlaying: _playerState == OfflinePlayerState.playing,
      isFavorite: _currentTrackIsFavorite,
      repeatMode: _repeatMode,
      onOpenNowPlaying: _openNowPlaying,
      onPrevious: _previous,
      onPlayPause: _playPause,
      onNext: _next,
      onSeekPreview: (value) => _position.value = value,
      onSeek: _seekTo,
      onToggleFavorite: _toggleCurrentFavorite,
      onAddToPlaylist: _addCurrentTrackToPlaylist,
      onToggleRepeat: _toggleRepeat,
      onOpenQueue: _openQueue,
    );
  }
}
