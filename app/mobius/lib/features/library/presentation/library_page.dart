import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';

import '../../../core/ffi/offline_player.dart';
import '../../../playback/player_controller.dart';
import '../data/ffi_library_repository.dart';
import '../data/user_collections.dart';
import '../../../playback/playback_time_format.dart';
import 'track_context_menu.dart';

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
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 36, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.favoritesOnly ? 'Favorites' : 'Library',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w600,
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
          _buildTableHeader(),
          Divider(height: 1, color: MobiusColors.borderOf(context)),
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
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
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
