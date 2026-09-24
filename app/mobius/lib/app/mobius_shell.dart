import 'dart:async';

import 'package:flutter/gestures.dart';
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
import '../playback/presentation/now_playing_page.dart';

/// Centralized palette so colors aren't repeated as raw hex literals
/// throughout the widget tree.
class _MobiusColors {
  const _MobiusColors._();

  static const background = Color(0xFF121212);
  static const header = Color(0xFF19181F);
  static const border = Color(0xFF2A2A2A);
  static const textPrimary = Color(0xFFEDEDED);
  static const textSecondary = Color(0xFF9A9A9A);
  static const accent = Color(0xFF8A63D2);
  static const accentLight = Color(0xFFC4A8F0);
  static const onAccent = Color(0xFFFAFAFA);
}

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
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;

  @override
  State<MobiusShell> createState() => _MobiusShellState();
}

class _MobiusShellState extends State<MobiusShell> {
  final UserCollections _collections = UserCollections();
  double _sidebarWidth = _MobiusMetrics.initialSidebarWidth;
  int _selectedPage = 0;
  int _libraryVersion = 0;
  int _albumNavigationRequest = 0;
  int _artistNavigationRequest = 0;
  TrackMetadata? _albumNavigationTrack;
  String? _artistNavigationName;

  Timer? _playerTimer;
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

    _playerTimer = Timer.periodic(
      _MobiusMetrics.pollInterval,
      (_) => _updatePlayer(),
    );
  }

  @override
  void dispose() {
    _playerTimer?.cancel();
    _position.dispose();
    super.dispose();
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
  void _runTransportAction(void Function() action) {
    try {
      action();
      _syncPlayer();
      setState(() {});
    } catch (error) {
      _showError(error);
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
        backgroundColor: _MobiusColors.background,
        body: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: AnimatedMobiusBackground(
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
      decoration: const BoxDecoration(
        color: _MobiusColors.header,
        border: Border(bottom: BorderSide(color: _MobiusColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: const Row(
        children: [
          Text(
            'MOBIUS',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: _MobiusColors.textPrimary,
            ),
          ),
          Spacer(),
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
            child: Container(width: 1, color: _MobiusColors.border),
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
        color: selected ? const Color(0xFF292631) : Colors.transparent,
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
                      ? _MobiusColors.accent
                      : _MobiusColors.textSecondary,
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
                            ? _MobiusColors.textPrimary
                            : _MobiusColors.textSecondary,
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
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------
  // Mini player
  // ---------------------------------------------------------------------

  Widget _buildMiniPlayer() {
    return ValueListenableBuilder<double>(
      valueListenable: _position,
      builder: (context, position, child) => _buildMiniPlayerAt(position),
    );
  }

  Widget _buildMiniPlayerAt(double position) {
    final track = _currentTrackMetadata;
    final isPlaying = _playerState == OfflinePlayerState.playing;
    final repeatActive = _repeatMode != OfflinePlayerRepeatMode.off;
    final maxDuration = _currentDuration > 0 ? _currentDuration : 1.0;
    final progress = position.clamp(0.0, maxDuration).toDouble();

    return Container(
      height: _MobiusMetrics.miniPlayerHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF1D1B24),
        border: Border(top: BorderSide(color: Color(0xFF34313D))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: _buildMiniPlayerTrackInfo(track)),
          const SizedBox(width: 20),
          Expanded(
            flex: 5,
            child: _buildMiniPlayerTransport(
              track: track,
              isPlaying: isPlaying,
              progress: progress,
              maxDuration: maxDuration,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: _buildMiniPlayerTrailingActions(
              track: track,
              repeatActive: repeatActive,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPlayerTrackInfo(TrackMetadata? track) {
    return InkWell(
      onTap: track == null ? null : _openNowPlaying,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          _buildMiniArtwork(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _MobiusColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track?.artist ?? 'Select a track',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _MobiusColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPlayerTransport({
    required TrackMetadata? track,
    required bool isPlaying,
    required double progress,
    required double maxDuration,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous',
              onPressed: track == null ? null : _previous,
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 27,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 48,
              height: 48,
              child: FilledButton(
                onPressed: track == null ? null : _playPause,
                style: FilledButton.styleFrom(
                  backgroundColor: _MobiusColors.accent,
                  foregroundColor: _MobiusColors.onAccent,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Next',
              onPressed: track == null ? null : _next,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 27,
            ),
          ],
        ),
        const SizedBox(height: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _MiniSeekBar(
            position: progress,
            duration: maxDuration,
            enabled: _currentDuration > 0,
            formatTime: _formatTime,
            onChanged: (value) {
              _position.value = value;
            },
            onChangeEnd: _seekTo,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniPlayerTrailingActions({
    required TrackMetadata? track,
    required bool repeatActive,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: _currentTrackIsFavorite
              ? 'Remove from Favorites'
              : 'Add to Favorites',
          onPressed: track == null ? null : _toggleCurrentFavorite,
          icon: Icon(
            _currentTrackIsFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
          iconSize: 21,
          color: _currentTrackIsFavorite
              ? _MobiusColors.accentLight
              : _MobiusColors.textSecondary,
        ),
        IconButton(
          tooltip: 'Add to playlist',
          onPressed: track == null ? null : _addCurrentTrackToPlaylist,
          icon: const Icon(Icons.playlist_add_rounded),
          iconSize: 22,
          color: _MobiusColors.textSecondary,
        ),
        IconButton(
          tooltip: _repeatLabel(),
          onPressed: track == null ? null : _toggleRepeat,
          icon: Icon(_repeatIcon()),
          iconSize: 22,
          color: repeatActive
              ? _MobiusColors.accentLight
              : _MobiusColors.textSecondary,
        ),
        IconButton(
          tooltip: 'Queue',
          onPressed: track == null ? null : _openQueue,
          icon: const Icon(Icons.queue_music_rounded),
          iconSize: 22,
          color: _MobiusColors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildMiniArtwork() {
    final artworkImage = _currentArtworkImage;

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: _MobiusColors.border,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: artworkImage != null
          ? Image(
              image: artworkImage,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) {
                return const Center(
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 26,
                    color: _MobiusColors.textSecondary,
                  ),
                );
              },
            )
          : const Center(
              child: Icon(
                Icons.music_note_rounded,
                size: 26,
                color: _MobiusColors.textSecondary,
              ),
            ),
    );
  }

  String _repeatLabel() {
    switch (_repeatMode) {
      case OfflinePlayerRepeatMode.off:
        return 'Repeat off';
      case OfflinePlayerRepeatMode.track:
        return 'Repeat one';
      case OfflinePlayerRepeatMode.queue:
        return 'Repeat queue';
    }
  }

  IconData _repeatIcon() {
    switch (_repeatMode) {
      case OfflinePlayerRepeatMode.off:
        return Icons.repeat_rounded;
      case OfflinePlayerRepeatMode.track:
        return Icons.repeat_one_rounded;
      case OfflinePlayerRepeatMode.queue:
        return Icons.repeat_rounded;
    }
  }

  String _formatTime(double seconds) {
    if (!seconds.isFinite || seconds < 0) {
      return '00:00';
    }

    final total = seconds.floor();
    final minutes = total ~/ 60;
    final remaining = total % 60;

    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }
}

class _MiniSeekBar extends StatefulWidget {
  const _MiniSeekBar({
    required this.position,
    required this.duration,
    required this.enabled,
    required this.formatTime,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double position;
  final double duration;
  final bool enabled;
  final String Function(double) formatTime;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_MiniSeekBar> createState() => _MiniSeekBarState();
}

class _MiniSeekBarState extends State<_MiniSeekBar> {
  double? _hoverValue;
  bool _dragging = false;

  double _valueFromX(double x, double width) {
    if (width <= 0 || widget.duration <= 0) {
      return 0;
    }

    final fraction = (x / width).clamp(0.0, 1.0);
    return fraction * widget.duration;
  }

  void _updateHover(PointerHoverEvent event, double width) {
    if (!widget.enabled || _dragging) {
      return;
    }

    setState(() {
      _hoverValue = _valueFromX(event.localPosition.dx, width);
    });
  }

  void _startDrag(DragStartDetails details, double width) {
    if (!widget.enabled) {
      return;
    }

    final value = _valueFromX(details.localPosition.dx, width);

    setState(() {
      _dragging = true;
      _hoverValue = value;
    });

    widget.onChanged(value);
  }

  void _updateDrag(DragUpdateDetails details, double width) {
    if (!widget.enabled) {
      return;
    }

    final value = _valueFromX(details.localPosition.dx, width);

    setState(() {
      _hoverValue = value;
    });

    widget.onChanged(value);
  }

  void _endDrag(DragEndDetails details, double width) {
    if (!widget.enabled || _hoverValue == null) {
      return;
    }

    final value = _hoverValue!.clamp(0.0, widget.duration);

    widget.onChangeEnd(value);

    if (!mounted) {
      return;
    }

    setState(() {
      _dragging = false;
    });
  }

  void _clearHover(PointerExitEvent event) {
    if (_dragging) {
      return;
    }

    setState(() {
      _hoverValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayedValue =
        (_dragging && _hoverValue != null ? _hoverValue! : widget.position)
            .clamp(0.0, widget.duration);

    final showTooltip = widget.enabled && _hoverValue != null;

    return SizedBox(
      height: 42,
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              widget.formatTime(widget.position),
              style: const TextStyle(
                color: _MobiusColors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                final fraction = widget.duration > 0
                    ? (displayedValue / widget.duration).clamp(0.0, 1.0)
                    : 0.0;

                final hoverFraction = _hoverValue != null && widget.duration > 0
                    ? (_hoverValue! / widget.duration).clamp(0.0, 1.0)
                    : fraction;

                const tooltipWidth = 58.0;
                final tooltipLeft = (hoverFraction * width - tooltipWidth / 2)
                    .clamp(
                      0.0,
                      (width - tooltipWidth).clamp(0.0, double.infinity),
                    );

                return MouseRegion(
                  onHover: (event) => _updateHover(event, width),
                  onExit: _clearHover,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (showTooltip)
                        Positioned(
                          left: tooltipLeft,
                          top: -14,
                          child: IgnorePointer(
                            child: Container(
                              width: tooltipWidth,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _MobiusColors.border,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.formatTime(_hoverValue!),
                                style: const TextStyle(
                                  color: _MobiusColors.textPrimary,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 7,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (details) =>
                              _startDrag(details, width),
                          onHorizontalDragUpdate: (details) =>
                              _updateDrag(details, width),
                          onHorizontalDragEnd: (details) =>
                              _endDrag(details, width),
                          onTapDown: (details) {
                            final value = _valueFromX(
                              details.localPosition.dx,
                              width,
                            );
                            widget.onChanged(value);
                            widget.onChangeEnd(value);
                          },
                          child: SizedBox(
                            height: 28,
                            child: CustomPaint(
                              painter: _MiniSeekBarPainter(fraction: fraction),
                            ),
                          ),
                        ),
                      ),
                      if (widget.enabled)
                        Positioned(
                          left: (fraction * width - 5).clamp(0.0, width - 10),
                          top: 16,
                          child: const IgnorePointer(child: _SeekBarThumb()),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Text(
              widget.formatTime(widget.duration),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _MobiusColors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeekBarThumb extends StatelessWidget {
  const _SeekBarThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _MobiusColors.accentLight,
      ),
    );
  }
}

class _MiniSeekBarPainter extends CustomPainter {
  const _MiniSeekBarPainter({required this.fraction});

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = _MobiusColors.border
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = _MobiusColors.accent
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final y = size.height / 2;
    final endX = size.width * fraction;

    canvas.drawLine(Offset(0, y), Offset(size.width, y), trackPaint);

    if (endX > 0) {
      canvas.drawLine(Offset(0, y), Offset(endX, y), activePaint);
    }
  }

  @override
  bool shouldRepaint(_MiniSeekBarPainter oldDelegate) {
    return oldDelegate.fraction != fraction;
  }
}
