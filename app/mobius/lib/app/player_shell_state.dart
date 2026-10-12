import 'dart:async';

import 'package:flutter/material.dart';

import '../core/ffi/offline_player.dart';
import '../features/home/presentation/home_page.dart';
import '../features/library/data/ffi_library_repository.dart';
import '../features/library/data/user_collections.dart';
import '../features/library/presentation/library_page.dart';
import '../features/library/presentation/search_page.dart';
import '../features/library/presentation/albums_page.dart';
import '../features/library/presentation/artists_page.dart';
import '../features/library/presentation/collections_pages.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/sound/presentation/sound_page.dart';
import '../playback/player_controller.dart';
import '../playback/playback_poller.dart';
import '../playback/presentation/now_playing_page.dart';
import 'mobius_app.dart' show ThemeModeController;

/// The width at or above which the desktop shell renders; below it the mobile
/// shell renders. One source of truth for the adaptive split.
const double kMobileBreakpoint = 900;

/// Page indices shared by both shells. The desktop sidebar exposes all entries;
/// the mobile bottom nav drops [kSoundPageIndex] (Sound is reached from inside
/// Settings on mobile) but reuses the same indices for the pages it keeps.
const int kHomePageIndex = 0;
const int kLibraryPageIndex = 1;
const int kAlbumsPageIndex = 2;
const int kArtistsPageIndex = 3;
const int kPlaylistsPageIndex = 4;
const int kSoundPageIndex = 5;
const int kSettingsPageIndex = 6;

/// Mobile-only Search page index. The desktop sidebar does not expose it (it
/// has its own in-page library search); it is only reached from the mobile
/// bottom nav, so it sits past the shared desktop indices.
const int kSearchPageIndex = 7;

/// A plain snapshot of everything a shell reads off [PlayerController].
/// Exists purely so the read path lives in one place instead of being
/// duplicated across the sync/update methods.
class PlayerSnapshot {
  const PlayerSnapshot({
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

/// Shared player-state ownership and transport logic for the app shells.
///
/// This is extracted verbatim from the original `_MobiusShellState` so BOTH
/// the desktop [MobiusShell] and the phone `MobileShell` own player state the
/// same way — values down, callbacks up — without duplicating ~250 lines or
/// reaching into [PlayerController]. It stays on plain `setState`
/// (constraint 2.4): the mixin calls `setState` directly on the host State.
///
/// A host State must:
///   * provide [repository], [playerController] and [themeController];
///   * call [initPlayerShell] from `initState` and [disposePlayerShell] from
///     `dispose`;
///   * read the snapshot fields (e.g. [currentTrackMetadata], [playerState])
///     and call the transport methods ([playPause], [next], …) from `build`.
mixin PlayerShellState<T extends StatefulWidget> on State<T> {
  // ---- Host-provided dependencies ---------------------------------------
  FfiLibraryRepository get repository;
  PlayerController get playerController;
  ThemeModeController get themeController;

  // ---- Shared collaborators / state -------------------------------------
  final UserCollections collections = UserCollections();

  int _selectedPage = 0;
  int _libraryVersion = 0;
  int _favoritesVersion = 0;
  int _albumNavigationRequest = 0;
  int _artistNavigationRequest = 0;
  TrackMetadata? _albumNavigationTrack;
  String? _artistNavigationName;

  static const Duration _pollInterval = Duration(milliseconds: 200);

  late final PlaybackPoller _poller = PlaybackPoller(
    onTick: _updatePlayer,
    isActive: () => _playerState == OfflinePlayerState.playing,
    activeInterval: _pollInterval,
  );
  final ValueNotifier<double> _position = ValueNotifier<double>(0);

  int _currentTrackId = 0;
  TrackMetadata? _currentTrackMetadata;
  ImageProvider? _currentArtworkImage;
  double _currentDuration = 0;
  bool _currentTrackIsFavorite = false;

  OfflinePlayerState _playerState = OfflinePlayerState.idle;
  OfflinePlayerRepeatMode _repeatMode = OfflinePlayerRepeatMode.off;

  late final _PlayerLifecycleObserver _lifecycleObserver =
      _PlayerLifecycleObserver(() {
    _syncPlayer();
    _poller.wake();
    if (mounted) {
      setState(() {});
    }
  });

  // ---- Read-only accessors for subclass build methods -------------------
  int get selectedPage => _selectedPage;
  int get libraryVersion => _libraryVersion;
  int get favoritesVersion => _favoritesVersion;
  int get currentTrackId => _currentTrackId;
  TrackMetadata? get currentTrackMetadata => _currentTrackMetadata;
  ImageProvider? get currentArtworkImage => _currentArtworkImage;
  double get currentDuration => _currentDuration;
  bool get currentTrackIsFavorite => _currentTrackIsFavorite;
  OfflinePlayerState get playerState => _playerState;
  OfflinePlayerRepeatMode get repeatMode => _repeatMode;
  ValueNotifier<double> get position => _position;
  bool get isPlaying => _playerState == OfflinePlayerState.playing;

  set selectedPage(int value) {
    if (value == _selectedPage) return;
    setState(() => _selectedPage = value);
    onSelectedPageChanged();
  }

  /// Lets a shell reset any page-local navigation when its selected content
  /// destination changes. Desktop keeps its existing in-place page switching.
  @protected
  void onSelectedPageChanged() {}

  // ---- Lifecycle --------------------------------------------------------
  void initPlayerShell() {
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _syncPlayer();
    playerController.commands.addListener(_onPlayerCommand);
    playerController.pendingTrackId.addListener(_onPendingTrack);
    _poller.start();
  }

  void disposePlayerShell() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    playerController.commands.removeListener(_onPlayerCommand);
    playerController.pendingTrackId.removeListener(_onPendingTrack);
    _poller.stop();
    _position.dispose();
  }

  /// A track change is about to block the UI thread (device re-clock): show
  /// the target track now so that frame is what stays on screen.
  void _onPendingTrack() {
    final trackId = playerController.pendingTrackId.value;
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

  // ---- Player state syncing ---------------------------------------------
  PlayerSnapshot _readSnapshot() {
    final controller = playerController;
    return PlayerSnapshot(
      trackId: controller.currentTrackId,
      position: controller.currentSeconds,
      duration: controller.durationSeconds,
      state: controller.state,
      repeatMode: controller.repeatMode,
    );
  }

  void _applySnapshot(PlayerSnapshot snapshot) {
    final trackChanged = snapshot.trackId != _currentTrackId;
    final needsMetadata = _currentTrackMetadata == null && snapshot.trackId > 0;
    if (trackChanged || needsMetadata) {
      _loadArtworkForTrack(snapshot.trackId);
      _loadCurrentFavoriteStatus(snapshot.trackId);
    }

    _currentTrackId = snapshot.trackId;
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

  Future<void> _updatePlayer() async {
    if (!mounted) {
      return;
    }

    try {
      try {
        await playerController.pollPlayback();
      } catch (error) {
        // The next track failed to open (unreadable file, revoked folder
        // access, decode error). Retrying every tick would re-attempt the
        // load forever while the finished track sits on screen, so stop and
        // tell the user instead of failing silently.
        try {
          playerController.stop();
        } catch (_) {}
        if (mounted) showError(error);
      }
      // A track switch is in flight: the announced track is on screen and the
      // engine still reports the old one, so don't revert to it.
      if (!mounted || playerController.pendingTrackId.value != null) {
        return;
      }
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

  static final Map<String, ImageProvider> _albumMiniArtworkCache = {};

  void _loadArtworkForTrack(int trackId) {
    if (trackId <= 0) {
      _currentTrackMetadata = null;
      _currentArtworkImage = null;
      return;
    }

    try {
      final metadata = repository.getTrackMetadata(trackId);
      _currentTrackMetadata = metadata;

      final albumKey = metadata.album.trim().isNotEmpty &&
              metadata.artist.trim().isNotEmpty
          ? '${metadata.artist.trim().toLowerCase()} - ${metadata.album.trim().toLowerCase()}'
          : 'track_$trackId';

      if (_albumMiniArtworkCache.containsKey(albumKey)) {
        _currentArtworkImage = _albumMiniArtworkCache[albumKey];
        return;
      }

      final artwork = repository.getTrackArtwork(trackId);

      if (artwork == null || artwork.data.isEmpty) {
        _currentArtworkImage = null;
        return;
      }

      final provider = ResizeImage(
        MemoryImage(artwork.data),
        width: 128,
        height: 128,
      );
      _currentArtworkImage = provider;
      _albumMiniArtworkCache[albumKey] = provider;
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
        final favorites = await collections.favorites();
        if (!mounted || _currentTrackId != trackId) return;
        setState(() => _currentTrackIsFavorite = favorites.contains(trackId));
      } catch (_) {}
    }());
  }

  void refreshLibrary() {
    if (!mounted) {
      return;
    }

    setState(() {
      _libraryVersion++;
    });
  }

  void goToArtist(String artist) {
    setState(() {
      _artistNavigationName = artist;
      _artistNavigationRequest++;
      _selectedPage = kArtistsPageIndex;
    });
    onSelectedPageChanged();
  }

  void goToAlbum(TrackMetadata track) {
    setState(() {
      _albumNavigationTrack = track;
      _albumNavigationRequest++;
      _selectedPage = kAlbumsPageIndex;
    });
    onSelectedPageChanged();
  }

  Future<void> toggleCurrentFavorite() async {
    final trackId = _currentTrackId;
    if (trackId <= 0) return;
    final isFavorite = await collections.toggleFavorite(trackId);
    if (!mounted || _currentTrackId != trackId) return;
    setState(() {
      _currentTrackIsFavorite = isFavorite;
      _favoritesVersion++;
    });
  }

  Future<void> addCurrentTrackToPlaylist() async {
    final trackId = _currentTrackId;
    if (trackId <= 0) return;
    final playlists = await collections.playlists();
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
    await collections.addToPlaylist(name, trackId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Added to $name.')));
    refreshLibrary();
  }

  // ---- Transport actions ------------------------------------------------
  void openNowPlaying({bool openQueue = false, bool openLyrics = false}) {
    if (_currentTrackId <= 0) {
      return;
    }

    try {
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) {
                return NowPlayingPage(
                  repository: repository,
                  playerController: playerController,
                  collections: collections,
                  initialOpenQueue: openQueue,
                  initialOpenLyrics: openLyrics,
                  isFavorite: _currentTrackIsFavorite,
                  onToggleFavorite: toggleCurrentFavorite,
                  onAddToPlaylist: addCurrentTrackToPlaylist,
                );
              },
            ),
          )
          .then((_) {
            if (!mounted) return;
            _syncPlayer();
            _loadCurrentFavoriteStatus(_currentTrackId);
            setState(() {});
          });
    } catch (error) {
      showError(error);
    }
  }

  void previous() => runTransportAction(playerController.previous);

  void next() => runTransportAction(playerController.next);

  void playPause() {
    if (_currentTrackId <= 0) {
      return;
    }

    runTransportAction(() {
      if (_playerState == OfflinePlayerState.playing) {
        playerController.pause();
      } else {
        playerController.play();
      }
    });
  }

  void toggleRepeat() => runTransportAction(playerController.toggleRepeatMode);

  /// Shared wrapper for the "call into the controller, resync, repaint,
  /// surface errors" pattern used by every transport button.
  Future<void> runTransportAction(FutureOr<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      _syncPlayer();
      setState(() {});
    } catch (error) {
      if (mounted) showError(error);
    }
  }

  void openQueue() => openNowPlaying(openQueue: true);
  void openLyrics() => openNowPlaying(openLyrics: true);

  void seekTo(double value) {
    if (_currentDuration <= 0) {
      return;
    }

    if (value >= _currentDuration - 0.5) {
      playerController.next();
      _syncPlayer();
      setState(() {});
      return;
    }

    final ratio = (value / _currentDuration).clamp(0.0, 1.0);
    final totalFrames = playerController.totalFrames;

    if (totalFrames <= 0) {
      _syncPlayer();
      setState(() {});
      return;
    }

    final maxSafeFrame = totalFrames > 22050 ? totalFrames - 22050 : totalFrames;
    final frame = (ratio * totalFrames).round().clamp(0, maxSafeFrame);

    try {
      playerController.seekToFrame(frame);
      _syncPlayer();
      setState(() {});
    } catch (error) {
      showError(error);
    }
  }

  void seekPreview(double value) => _position.value = value;

  void showError(Object error) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  // ---- Content page selection (shared by both shells) -------------------
  /// Builds the page for [index]. [onOpenSound] is passed to [SettingsPage]
  /// so the mobile shell can render a "Sound" row that pushes [SoundPage];
  /// the desktop shell passes `null` (Sound is a sidebar tab there), leaving
  /// the Settings page unchanged.
  Widget buildPage(
    int index, {
    VoidCallback? onOpenSound,
    Key? libraryKey,
  }) {
    switch (index) {
      case kHomePageIndex:
        return HomePage(
          repository: repository,
          playerController: playerController,
          onOpenNowPlaying: openNowPlaying,
          onLibraryChanged: refreshLibrary,
          onGoToLibrary: () => selectedPage = kLibraryPageIndex,
          onGoToAlbum: goToAlbum,
          onGoToArtist: goToArtist,
          libraryVersion: _libraryVersion,
          favoritesVersion: _favoritesVersion,
        );

      case kLibraryPageIndex:
        return LibraryPage(
          key: libraryKey,
          repository: repository,
          playerController: playerController,
          onOpenNowPlaying: openNowPlaying,
          onLibraryChanged: refreshLibrary,
          onGoToArtist: goToArtist,
          onGoToAlbum: goToAlbum,
          collections: collections,
          currentTrackId: _currentTrackId,
          libraryVersion: _libraryVersion,
          favoritesVersion: _favoritesVersion,
        );

      case kAlbumsPageIndex:
        return AlbumsPage(
          key: ValueKey(_albumNavigationRequest),
          repository: repository,
          playerController: playerController,
          collections: collections,
          initialTrack: _albumNavigationTrack,
          onLibraryChanged: refreshLibrary,
          onGoToArtist: goToArtist,
          onGoToAlbum: goToAlbum,
          libraryVersion: _libraryVersion,
        );

      case kArtistsPageIndex:
        return ArtistsPage(
          key: ValueKey(_artistNavigationRequest),
          repository: repository,
          playerController: playerController,
          collections: collections,
          initialArtistName: _artistNavigationName,
          onLibraryChanged: refreshLibrary,
          onGoToArtist: goToArtist,
          onGoToAlbum: goToAlbum,
          libraryVersion: _libraryVersion,
        );

      case kPlaylistsPageIndex:
        return PlaylistsPage(
          repository: repository,
          playerController: playerController,
          collections: collections,
          onGoToArtist: goToArtist,
          onGoToAlbum: goToAlbum,
          collectionsVersion: _libraryVersion,
          favoritesVersion: _favoritesVersion,
        );

      case kSoundPageIndex:
        return SoundPage(playerController: playerController);

      case kSearchPageIndex:
        return SearchPage(
          repository: repository,
          playerController: playerController,
          collections: collections,
          onGoToArtist: goToArtist,
          onGoToAlbum: goToAlbum,
          onLibraryChanged: refreshLibrary,
          currentTrackId: _currentTrackId,
          libraryVersion: _libraryVersion,
        );

      case kSettingsPageIndex:
        return SettingsPage(
          playerController: playerController,
          repository: repository,
          onLibraryChanged: refreshLibrary,
          themeController: themeController,
          onOpenSound: onOpenSound,
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

class _PlayerLifecycleObserver with WidgetsBindingObserver {
  _PlayerLifecycleObserver(this._onResumed);
  final VoidCallback _onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }
}
