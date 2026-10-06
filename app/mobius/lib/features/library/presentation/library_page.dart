import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../../../app/player_shell_state.dart' show kMobileBreakpoint;

import '../../../core/ffi/offline_player.dart';
import '../../../playback/player_controller.dart';
import '../data/ffi_library_repository.dart';
import '../data/user_collections.dart';
import '../../../playback/playback_time_format.dart';
import 'albums_page.dart';
import 'artists_page.dart';
import 'collections_pages.dart';
import 'group_artwork.dart';
import 'track_context_menu.dart';
import '../../../app/widgets/mobius_loading_view.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.repository,
    required this.playerController,
    required this.onOpenNowPlaying,
    required this.onLibraryChanged,
    required this.onGoToArtist,
    required this.onGoToAlbum,
    required this.collections,
    this.favoritesOnly = false,
    this.currentTrackId,
    this.libraryVersion = 0,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final VoidCallback onOpenNowPlaying;
  final VoidCallback onLibraryChanged;
  final ValueChanged<String> onGoToArtist;
  final ValueChanged<TrackMetadata> onGoToAlbum;
  final UserCollections collections;
  final bool favoritesOnly;
  final int? currentTrackId;
  final int libraryVersion;

  @override
  State<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends State<LibraryPage> {
  final GlobalKey<AlbumsPageState> _albumsKey = GlobalKey<AlbumsPageState>();
  final GlobalKey<ArtistsPageState> _artistsKey = GlobalKey<ArtistsPageState>();
  final GlobalKey<PlaylistsPageState> _playlistsKey = GlobalKey<PlaylistsPageState>();

  final List<TrackMetadata> _tracks = [];
  // Bumped whenever _tracks is mutated; part of the _visibleTracks cache key.
  int _tracksVersion = 0;
  Object? _visibleTracksKey;
  List<TrackMetadata>? _visibleTracksCache;

  String _searchQuery = '';
  String? _genreFilter;
  _LibrarySort _sort = _LibrarySort.title;
  bool _sortAscending = true;
  bool _compactView = false;

  bool _loading = true;
  String? _error;

  /// Which mobile text-tab is active (Songs/Albums/Artists/Playlists). Only
  /// used on the mobile (< 900) path; desktop ignores it.
  _MobileLibraryTab _mobileTab = _MobileLibraryTab.songs;


  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.libraryVersion != widget.libraryVersion) {
      _loadLibrary();
    }
  }

  Future<void> _loadLibrary() async {
    try {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }

      final count = widget.repository.getTrackCount();
      final tracks = <TrackMetadata>[];
      final removedIds = await widget.collections.removedLibraryTrackIds();

      for (var i = 0; i < count; i++) {
        final id = widget.repository.getTrackIdAt(i);
        if (removedIds.contains(id)) continue;
        tracks.add(widget.repository.getTrackMetadata(id));
      }

      if (widget.favoritesOnly) {
        final favoriteIds = await widget.collections.favorites();
        tracks.removeWhere((track) => !favoriteIds.contains(track.trackId));
      }

      _tracks
        ..clear()
        ..addAll(tracks);
      _tracksVersion++;

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  List<TrackMetadata> get _visibleTracks {
    // Filtering + sorting the whole library is read several times per
    // build; recompute only when an input actually changed.
    final key = (
      _tracksVersion,
      _searchQuery,
      _genreFilter,
      _sort,
      _sortAscending,
    );
    final cached = _visibleTracksCache;
    if (cached != null && key == _visibleTracksKey) {
      return cached;
    }

    final query = _searchQuery.trim().toLowerCase();

    bool matches(TrackMetadata track) {
      if (_genreFilter != null &&
          track.genre.trim().toLowerCase() != _genreFilter!.toLowerCase()) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final haystack = [
        track.title,
        track.artist,
        track.album,
        track.albumArtist,
        track.composer,
        track.genre,
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }

    final sorted = _tracks.where(matches).toList(growable: false);

    int compare(TrackMetadata a, TrackMetadata b) {
      String value(TrackMetadata track) {
        switch (_sort) {
          case _LibrarySort.title:
            return track.title.trim().toLowerCase();
          case _LibrarySort.artist:
            return track.artist.trim().toLowerCase();
          case _LibrarySort.album:
            return track.album.trim().toLowerCase();
          case _LibrarySort.releaseDate:
            return track.date.trim().toLowerCase();
        }
      }

      final result = value(a).compareTo(value(b));
      return _sortAscending ? result : -result;
    }

    sorted.sort(compare);
    _visibleTracksKey = key;
    _visibleTracksCache = sorted;
    return sorted;
  }

  List<String> get _genres {
    return _tracks
        .map((track) => track.genre.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  bool get _hasFilters =>
      _searchQuery.trim().isNotEmpty || _genreFilter != null;

  void _setSort(_LibrarySort sort) {
    setState(() {
      if (_sort == sort) {
        _sortAscending = !_sortAscending;
      } else {
        _sort = sort;
        _sortAscending = true;
      }
    });
  }

  Future<void> _playTrack(TrackMetadata track) async {
    try {
      final visibleTracks = _visibleTracks;
      final queueIds = visibleTracks.map((item) => item.trackId).toList();

      widget.playerController.setQueue(queueIds);

      final index = queueIds.indexOf(track.trackId);

      if (index < 0) {
        return;
      }

      await widget.playerController.selectAndPlay(index);

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _removeTrack(TrackMetadata track) async {
    if (widget.favoritesOnly) {
      await widget.collections.toggleFavorite(track.trackId);
    } else {
      await widget.collections.removeFromLibrary(track.trackId);
    }
    if (!mounted) return;
    setState(() {
      _tracks.removeWhere((item) => item.trackId == track.trackId);
      _tracksVersion++;
    });
    widget.onLibraryChanged();
  }

  int? get _currentSampleRate {
    if (widget.currentTrackId == null) {
      return null;
    }

    try {
      final rate = widget.playerController.sampleRate;
      return rate > 0 ? rate : null;
    } catch (_) {
      return null;
    }
  }

  double? get _currentDuration {
    if (widget.currentTrackId == null) {
      return null;
    }

    try {
      final duration = widget.playerController.durationSeconds;
      return duration > 0 ? duration : null;
    } catch (_) {
      return null;
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

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    return isMobile ? _buildMobile(context) : _buildDesktop(context);
  }

  // ---------------------------------------------------------------------
  /// Returns true if back navigation was handled internally (closing detail or switching tab to songs).
  bool handleBack() {
    if (!mounted) return false;
    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    if (!isMobile) return false;

    if (_mobileTab == _MobileLibraryTab.albums) {
      if (_albumsKey.currentState?.handleBack() == true) {
        return true;
      }
      setState(() => _mobileTab = _MobileLibraryTab.songs);
      return true;
    }

    if (_mobileTab == _MobileLibraryTab.artists) {
      if (_artistsKey.currentState?.handleBack() == true) {
        return true;
      }
      setState(() => _mobileTab = _MobileLibraryTab.songs);
      return true;
    }

    if (_mobileTab == _MobileLibraryTab.playlists) {
      if (_playlistsKey.currentState?.handleBack() == true) {
        return true;
      }
      setState(() => _mobileTab = _MobileLibraryTab.songs);
      return true;
    }

    return false;
  }

  // Mobile (< 900): One UI v4 — large title, text tabs, grouped Songs.
  // ---------------------------------------------------------------------
  Widget _buildMobile(BuildContext context) {
    // Albums/Artists/Playlists reuse the existing page widgets (restyle, not
    // re-implement data). They render as plain content and are mobile-aware.
    switch (_mobileTab) {
      case _MobileLibraryTab.albums:
        return _mobileTabScaffold(
          context,
          child: AlbumsPage(
            key: _albumsKey,
            repository: widget.repository,
            playerController: widget.playerController,
            collections: widget.collections,
            onLibraryChanged: widget.onLibraryChanged,
            onGoToArtist: widget.onGoToArtist,
            onGoToAlbum: widget.onGoToAlbum,
            libraryVersion: widget.libraryVersion,
          ),
        );
      case _MobileLibraryTab.artists:
        return _mobileTabScaffold(
          context,
          child: ArtistsPage(
            key: _artistsKey,
            repository: widget.repository,
            playerController: widget.playerController,
            collections: widget.collections,
            onLibraryChanged: widget.onLibraryChanged,
            onGoToArtist: widget.onGoToArtist,
            onGoToAlbum: widget.onGoToAlbum,
            libraryVersion: widget.libraryVersion,
          ),
        );
      case _MobileLibraryTab.playlists:
        return _mobileTabScaffold(
          context,
          child: PlaylistsPage(
            key: _playlistsKey,
            repository: widget.repository,
            playerController: widget.playerController,
            collections: widget.collections,
            onGoToArtist: widget.onGoToArtist,
            onGoToAlbum: widget.onGoToAlbum,
            collectionsVersion: widget.libraryVersion,
          ),
        );
      case _MobileLibraryTab.songs:
        return _mobileTabScaffold(
          context,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildMobileSongs(context),
          ),
        );
    }
  }

  /// The shared mobile chrome: large title + counts, top-right search/overflow,
  /// and the glowing text-tab bar, with [child] below.
  Widget _mobileTabScaffold(BuildContext context, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.favoritesOnly ? 'Favorites' : 'Library',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w600,
                          height: 1.05,
                          color: MobiusColors.textOf(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _mobileCountsSubtitle(),
                        style: TextStyle(
                          fontSize: 14,
                          color: MobiusColors.textDimOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildMobileFilterMenu(context),
                _buildMobileOverflowMenu(context),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildMobileTabBar(context),
          const SizedBox(height: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  String _mobileCountsSubtitle() {
    if (_loading) return '…';
    final count = _tracks.length;
    switch (_mobileTab) {
      case _MobileLibraryTab.songs:
        return '$count ${count == 1 ? 'song' : 'songs'}';
      case _MobileLibraryTab.albums:
        return 'Albums';
      case _MobileLibraryTab.artists:
        return 'Artists';
      case _MobileLibraryTab.playlists:
        return 'Playlists';
    }
  }

  Widget _buildMobileFilterMenu(BuildContext context) {
    return IconButton(
      tooltip: 'Filter genre',
      icon: Icon(
        Icons.tune_rounded,
        color: _genreFilter != null
            ? MobiusColors.accentOf(context)
            : MobiusColors.textDimOf(context),
      ),
      onPressed: () => _openMobileGenreFilter(context),
    );
  }

  void _openMobileGenreFilter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MobiusColors.panelOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.65,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MobiusColors.borderOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        'Filter Genre',
                        style: TextStyle(
                          color: MobiusColors.textOf(context),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (_genreFilter != null)
                        TextButton(
                          onPressed: () {
                            setState(() => _genreFilter = null);
                            Navigator.pop(ctx);
                          },
                          child: const Text('Reset'),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: MobiusColors.borderOf(context)),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: _genreFilter == null
                              ? MobiusColors.accentOf(context)
                              : Colors.transparent,
                        ),
                        title: const Text('All genres'),
                        onTap: () {
                          setState(() => _genreFilter = null);
                          Navigator.pop(ctx);
                        },
                      ),
                      for (final genre in _genres)
                        ListTile(
                          leading: Icon(
                            Icons.check_rounded,
                            size: 20,
                            color: _genreFilter == genre
                                ? MobiusColors.accentOf(context)
                                : Colors.transparent,
                          ),
                          title: Text(genre),
                          onTap: () {
                            setState(() => _genreFilter = genre);
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileOverflowMenu(BuildContext context) {
    return PopupMenuButton<_LibrarySort>(
      tooltip: 'Sort',
      color: MobiusColors.panelOf(context),
      icon: Icon(
        Icons.more_vert_rounded,
        color: MobiusColors.textDimOf(context),
      ),
      onSelected: _setSort,
      itemBuilder: (context) => [
        for (final entry in const [
          (_LibrarySort.title, 'Title'),
          (_LibrarySort.artist, 'Artist'),
          (_LibrarySort.album, 'Album'),
          (_LibrarySort.releaseDate, 'Release date'),
        ])
          PopupMenuItem<_LibrarySort>(
            value: entry.$1,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.$2,
                    style: TextStyle(color: MobiusColors.textOf(context)),
                  ),
                ),
                if (_sort == entry.$1)
                  Icon(
                    _sortAscending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 17,
                    color: MobiusColors.accentOf(context),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMobileTabBar(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final tab in _MobileLibraryTab.values)
            _MobileTab(
              label: tab.label,
              selected: _mobileTab == tab,
              onTap: () => setState(() => _mobileTab = tab),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileSongs(BuildContext context) {
    if (_loading) {
      return const MobiusLoadingView(
        size: 220,
        backgroundColor: Colors.transparent,
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: MobiusColors.unsupported),
        ),
      );
    }

    final tracks = _visibleTracks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tracks.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                widget.favoritesOnly ? 'No favorites yet' : 'No tracks found',
                style: TextStyle(color: MobiusColors.textDimOf(context)),
              ),
            ),
          )
        else if (tracks.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                'No tracks match your filters',
                style: TextStyle(color: MobiusColors.textDimOf(context)),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 90),
              itemCount: tracks.length,
              itemBuilder: (context, i) =>
                  _buildMobileSongRow(context, tracks[i], i),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileSongRow(
    BuildContext context,
    TrackMetadata track,
    int index,
  ) {
    final isCurrent = track.trackId == widget.currentTrackId;
    final title = track.title.trim().isEmpty ? 'Unknown title' : track.title;
    final artist = track.artist.trim().isEmpty
        ? 'Unknown artist'
        : track.artist;
    final album = track.album.trim();
    final subtitle = album.isEmpty ? artist : '$artist · $album';

    final row = Material(
      color: isCurrent
          ? MobiusColors.accentOf(context).withValues(alpha: 0.20)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _playTrack(track),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GroupArtwork(
                        repository: widget.repository,
                        source: GroupArtworkSource([track.trackId]),
                        decodeSize: 88,
                        filterQuality: FilterQuality.medium,
                        placeholder: Container(
                          color: MobiusColors.borderOf(context).withValues(alpha: 0.4),
                          alignment: Alignment.center,
                          child: Icon(
                            isCurrent
                                ? Icons.equalizer_rounded
                                : Icons.music_note_rounded,
                            size: 20,
                            color: isCurrent
                                ? MobiusColors.accentLightOf(context)
                                : MobiusColors.textDimOf(context),
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          color: MobiusColors.accentOf(context).withValues(alpha: 0.35),
                          child: Center(
                            child: Icon(
                              Icons.equalizer_rounded,
                              size: 20,
                              color: MobiusColors.accentLightOf(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? MobiusColors.accentOf(context)
                            : MobiusColors.textOf(context),
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MobiusColors.textDimOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (btnContext) => IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  iconSize: 20,
                  color: MobiusColors.textDimOf(context),
                  tooltip: 'More options',
                  onPressed: () {
                    final box = btnContext.findRenderObject() as RenderBox;
                    final position = box.localToGlobal(Offset(0, box.size.height));
                    TrackContextMenu.showForTrack(
                      context: context,
                      position: position,
                      track: track,
                      repository: widget.repository,
                      collections: widget.collections,
                      playerController: widget.playerController,
                      removeLabel: widget.favoritesOnly
                          ? 'Remove from Favorites'
                          : 'Remove from Library',
                      onRemove: () => _removeTrack(track),
                      onChanged: widget.onLibraryChanged,
                      onGoToArtist: trackArtistName(track).isEmpty
                          ? null
                          : () => widget.onGoToArtist(trackArtistName(track)),
                      onGoToAlbum: track.album.trim().isEmpty
                          ? null
                          : () => widget.onGoToAlbum(track),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return TrackContextMenu(
      key: ValueKey('song-${track.trackId}-$index'),
      track: track,
      repository: widget.repository,
      collections: widget.collections,
      playerController: widget.playerController,
      removeLabel: widget.favoritesOnly
          ? 'Remove from Favorites'
          : 'Remove from Library',
      onRemove: () => _removeTrack(track),
      onChanged: widget.onLibraryChanged,
      onGoToArtist: trackArtistName(track).isEmpty
          ? null
          : () => widget.onGoToArtist(trackArtistName(track)),
      onGoToAlbum: track.album.trim().isEmpty
          ? null
          : () => widget.onGoToAlbum(track),
      child: row,
    );
  }

  // ---------------------------------------------------------------------
  // Desktop (>= 900): unchanged.
  // ---------------------------------------------------------------------
  Widget _buildDesktop(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 36, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.favoritesOnly ? 'Favorites' : 'Library',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w600,
              // Match SettingsPageHeader's tight line box so every page title
              // sits at the same height above the page padding.
              height: 1.05,
              color: MobiusColors.textOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.favoritesOnly
                ? '${_tracks.length} saved ${_tracks.length == 1 ? 'track' : 'tracks'}'
                : _hasFilters
                ? '${_visibleTracks.length} of ${_tracks.length} tracks'
                : '${_tracks.length} tracks',
            style: TextStyle(
              fontSize: 17,
              color: MobiusColors.textDimOf(context),
            ),
          ),
          const SizedBox(height: 24),
          _buildSearchAndFilters(),
          const SizedBox(height: 20),
          // The fixed-column table header is a desktop affordance; mobile list
          // rows carry their own layout and the header would overflow at phone
          // widths, so it (and its divider) render only on the desktop path.
          if (MediaQuery.sizeOf(context).width >= kMobileBreakpoint) ...[
            _buildTableHeader(),
            Divider(height: 1, color: MobiusColors.borderOf(context)),
          ],
          const SizedBox(height: 4),
          Expanded(child: _buildTrackList()),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                style: TextStyle(
                  color: MobiusColors.textOf(context),
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search tracks, artists, albums...',
                  hintStyle: TextStyle(
                    color: MobiusColors.textDimOf(context),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: MobiusColors.textDimOf(context),
                  ),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: MobiusColors.textDimOf(context),
                          onPressed: () => setState(() => _searchQuery = ''),
                        ),
                  filled: true,
                  fillColor: MobiusColors.panelOf(
                    context,
                  ).withValues(alpha: 0.82),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: MobiusColors.borderOf(context),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: MobiusColors.borderOf(context),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: MobiusColors.accentOf(context),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _buildSortMenu(),
            const SizedBox(width: 8),
            _buildViewMenu(),
          ],
        ),
        if (_genres.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _genres.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildGenreChip('All', _genreFilter == null, null);
                }
                final genre = _genres[index - 1];
                return _buildGenreChip(genre, _genreFilter == genre, genre);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGenreChip(String label, bool selected, String? value) {
    return Material(
      color: selected
          ? MobiusColors.accentOf(context).withValues(alpha: 0.22)
          : MobiusColors.panelOf(context).withValues(alpha: 0.76),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _genreFilter = value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? MobiusColors.textOf(context)
                    : MobiusColors.textDimOf(context),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSortMenu() {
    return PopupMenuButton<_LibrarySortAction>(
      tooltip: 'Sort library',
      color: MobiusColors.panelOf(context),
      onSelected: (action) {
        if (action.sort != null) {
          _setSort(action.sort!);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_LibrarySortAction>(
          enabled: false,
          child: Text(
            'Sort by',
            style: TextStyle(
              color: MobiusColors.textOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...[
          _sortMenuItem(context, _LibrarySort.title, 'Title', true),
          _sortMenuItem(context, _LibrarySort.artist, 'Artist', true),
          _sortMenuItem(context, _LibrarySort.album, 'Album', true),
          _sortMenuItem(
            context,
            _LibrarySort.releaseDate,
            'Release date',
            true,
          ),
        ],
      ],
      child: _ToolbarButton(
        icon: Icons.sort_rounded,
        label: _sortLabel,
        trailing: _sortAscending
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded,
      ),
    );
  }

  PopupMenuItem<_LibrarySortAction> _sortMenuItem(
    BuildContext context,
    _LibrarySort sort,
    String label,
    bool supported,
  ) {
    final selected = _sort == sort && supported;
    return PopupMenuItem<_LibrarySortAction>(
      enabled: supported,
      value: _LibrarySortAction(
        sort: supported ? sort : null,
        label: label,
        selected: selected,
        ascending: _sortAscending,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              supported ? label : '$label (not available)',
              style: TextStyle(
                color: supported
                    ? MobiusColors.textOf(context)
                    : MobiusColors.textDimOf(context),
              ),
            ),
          ),
          if (selected)
            Icon(
              _sortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 17,
              color: MobiusColors.accentOf(context),
            ),
        ],
      ),
    );
  }

  String get _sortLabel {
    switch (_sort) {
      case _LibrarySort.title:
        return 'Title';
      case _LibrarySort.artist:
        return 'Artist';
      case _LibrarySort.album:
        return 'Album';
      case _LibrarySort.releaseDate:
        return 'Release date';
    }
  }

  Widget _buildViewMenu() {
    return PopupMenuButton<bool>(
      tooltip: 'View as',
      color: MobiusColors.panelOf(context),
      onSelected: (compact) => setState(() => _compactView = compact),
      itemBuilder: (context) => [
        PopupMenuItem<bool>(
          enabled: false,
          child: Text(
            'View as',
            style: TextStyle(
              color: MobiusColors.textOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        PopupMenuItem<bool>(
          value: true,
          child: _ViewMenuItem(
            icon: Icons.view_headline_rounded,
            label: 'Compact',
            selected: _compactView,
          ),
        ),
        PopupMenuItem<bool>(
          value: false,
          child: _ViewMenuItem(
            icon: Icons.view_list_rounded,
            label: 'List',
            selected: !_compactView,
          ),
        ),
      ],
      child: _ToolbarButton(
        icon: _compactView
            ? Icons.view_headline_rounded
            : Icons.view_list_rounded,
        label: _compactView ? 'Compact' : 'List',
      ),
    );
  }

  Widget _buildTableHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            SizedBox(width: 44, child: Center(child: _TableLabel('#'))),
            SizedBox(width: 16),
            Expanded(flex: 5, child: _TableLabel('Title')),
            SizedBox(width: 28),
            Expanded(flex: 4, child: _TableLabel('Album')),
            SizedBox(width: 28),
            SizedBox(
              width: 82,
              child: Align(
                alignment: Alignment.centerRight,
                child: _TableLabel('Duration'),
              ),
            ),
            SizedBox(width: 28),
            SizedBox(
              width: 88,
              child: Align(
                alignment: Alignment.centerRight,
                child: _TableLabel('Rate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackList() {
    if (_loading) {
      return const MobiusLoadingView(
        size: 220,
        backgroundColor: Colors.transparent,
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: MobiusColors.unsupported),
        ),
      );
    }

    final tracks = _visibleTracks;

    if (_tracks.isEmpty) {
      return Center(
        child: Text(
          widget.favoritesOnly ? 'No favorites yet' : 'No tracks found',
          style: TextStyle(color: MobiusColors.textDimOf(context)),
        ),
      );
    }

    if (tracks.isEmpty) {
      return Center(
        child: Text(
          'No tracks match your filters',
          style: TextStyle(color: MobiusColors.textDimOf(context)),
        ),
      );
    }

    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isCurrent = track.trackId == widget.currentTrackId;

        return TrackContextMenu(
          track: track,
          repository: widget.repository,
          collections: widget.collections,
          playerController: widget.playerController,
          removeLabel: widget.favoritesOnly
              ? 'Remove from Favorites'
              : 'Remove from Library',
          onRemove: () => _removeTrack(track),
          onChanged: widget.onLibraryChanged,
          onGoToArtist: trackArtistName(track).isEmpty
              ? null
              : () => widget.onGoToArtist(trackArtistName(track)),
          onGoToAlbum: track.album.trim().isEmpty
              ? null
              : () => widget.onGoToAlbum(track),
          child: _LibraryTrackRow(
            track: track,
            index: index,
            isCurrent: isCurrent,
            duration: isCurrent ? _currentDuration : null,
            sampleRate: isCurrent ? _currentSampleRate : null,
            onTap: () => _playTrack(track),
            compact: _compactView,
          ),
        );
      },
    );
  }
}

enum _LibrarySort { title, artist, album, releaseDate }

/// Mobile Library text-tabs. Albums/Artists/Playlists reuse the existing page
/// widgets; Songs is the Library's own grouped list.
enum _MobileLibraryTab {
  songs('Songs'),
  albums('Albums'),
  artists('Artists'),
  playlists('Playlists');

  const _MobileLibraryTab(this.label);
  final String label;
}

/// A single mobile text-tab with a short glowing accent bar under the active
/// one.
class _MobileTab extends StatelessWidget {
  const _MobileTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = MobiusColors.accentOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? MobiusColors.textOf(context)
                    : MobiusColors.textDimOf(context),
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 22 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibrarySortAction {
  const _LibrarySortAction({
    required this.sort,
    required this.label,
    required this.selected,
    required this.ascending,
  });

  final _LibrarySort? sort;
  final String label;
  final bool selected;
  final bool ascending;
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: MobiusColors.panelOf(context).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MobiusColors.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: MobiusColors.textDimOf(context)),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: MobiusColors.textDimOf(context),
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            trailing ?? Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: MobiusColors.textDimOf(context),
          ),
        ],
      ),
    );
  }
}

class _ViewMenuItem extends StatelessWidget {
  const _ViewMenuItem({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: selected
              ? MobiusColors.accentOf(context)
              : MobiusColors.textDimOf(context),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? MobiusColors.textOf(context)
                  : MobiusColors.textDimOf(context),
            ),
          ),
        ),
        if (selected)
          Icon(
            Icons.check_rounded,
            size: 18,
            color: MobiusColors.accentOf(context),
          ),
      ],
    );
  }
}

class _LibraryTrackRow extends StatelessWidget {
  const _LibraryTrackRow({
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.duration,
    required this.sampleRate,
    required this.onTap,
    required this.compact,
  });

  final TrackMetadata track;
  final int index;
  final bool isCurrent;
  final double? duration;
  final int? sampleRate;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final title = track.title.trim().isEmpty ? 'Unknown title' : track.title;
    final artist = track.artist.trim().isEmpty
        ? 'Unknown artist'
        : track.artist;
    final album = track.album.trim().isEmpty ? 'Unknown album' : track.album;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isCurrent
            ? MobiusColors.accentOf(context).withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: compact ? 56 : 72,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isCurrent)
                          Positioned(
                            left: 0,
                            child: Container(
                              width: 3,
                              height: 30,
                              decoration: BoxDecoration(
                                color: MobiusColors.accentLightOf(context),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        isCurrent
                            ? Icon(
                                Icons.equalizer_rounded,
                                size: 18,
                                color: MobiusColors.accentLightOf(context),
                              )
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: MobiusColors.textDimOf(context),
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                ),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MobiusColors.textOf(context),
                            fontSize: compact ? 13 : 14,
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        SizedBox(height: compact ? 2 : 4),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: compact ? 11 : 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    flex: 4,
                    child: Text(
                      album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MobiusColors.textDimOf(context),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                  SizedBox(
                    width: 82,
                    child: Text(
                      duration != null ? _formatTime(duration!) : '--',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: MobiusColors.textDimOf(context),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                  SizedBox(
                    width: 88,
                    child: Text(
                      sampleRate != null
                          ? _formatSampleRate(sampleRate!)
                          : '--',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: MobiusColors.textDimOf(context),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatSampleRate(int rate) {
    if (rate <= 0) {
      return '--';
    }

    if (rate % 1000 == 0) {
      return '${rate ~/ 1000} kHz';
    }

    return '${(rate / 1000).toStringAsFixed(1)} kHz';
  }

  String _formatTime(double seconds) => formatPlaybackTime(seconds);
}

class _TableLabel extends StatelessWidget {
  const _TableLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: MobiusColors.textDimOf(context), fontSize: 13),
    );
  }
}
