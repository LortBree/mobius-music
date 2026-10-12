import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../../../core/ffi/offline_player.dart';
import '../../../playback/player_controller.dart';
import '../data/ffi_library_repository.dart';
import '../data/user_collections.dart';
import 'group_artwork.dart';
import 'track_context_menu.dart';

/// Mobile Search page: a top search field and results grouped into Songs,
/// Albums and Artists.
///
/// Reuses the SAME in-memory filtering approach as [LibraryPage] (load every
/// track once from the repository, then filter client-side); it does NOT add a
/// repository search API. Tapping a song plays the filtered songs as the
/// queue; tapping an album/artist navigates via the shell callbacks.
class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.repository,
    required this.playerController,
    required this.collections,
    required this.onGoToArtist,
    required this.onGoToAlbum,
    required this.onLibraryChanged,
    this.currentTrackId,
    this.libraryVersion = 0,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final UserCollections collections;
  final ValueChanged<String> onGoToArtist;
  final ValueChanged<TrackMetadata> onGoToAlbum;
  final VoidCallback onLibraryChanged;
  final int? currentTrackId;
  final int libraryVersion;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final List<TrackMetadata> _tracks = [];
  final TextEditingController _controller = TextEditingController();

  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryVersion != widget.libraryVersion) {
      _loadLibrary();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

      _tracks
        ..clear()
        ..addAll(tracks);

      if (mounted) {
        setState(() => _loading = false);
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

  List<TrackMetadata> get _matchingSongs {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return _tracks
        .where((track) {
          final haystack = [
            track.title,
            track.artist,
            track.album,
            track.albumArtist,
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  List<String> get _matchingAlbums {
    final songs = _matchingSongs;
    final seen = <String>{};
    final albums = <String>[];
    for (final track in songs) {
      final album = track.album.trim();
      if (album.isEmpty) continue;
      if (seen.add(album.toLowerCase())) albums.add(album);
    }
    albums.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return albums;
  }

  List<String> get _matchingArtists {
    final songs = _matchingSongs;
    final seen = <String>{};
    final artists = <String>[];
    for (final track in songs) {
      final artist = track.artist.trim();
      if (artist.isEmpty) continue;
      if (seen.add(artist.toLowerCase())) artists.add(artist);
    }
    artists.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return artists;
  }

  Future<void> _playSong(TrackMetadata track) async {
    try {
      final songs = _matchingSongs;
      final ids = songs.map((item) => item.trackId).toList();
      final index = ids.indexOf(track.trackId);
      if (index < 0) return;
      await widget.playerController.setQueueAndPlay(ids, index);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  /// Finds a representative track for an album name, so album taps can reuse
  /// the shell's album navigation (which takes a track).
  TrackMetadata? _trackForAlbum(String album) {
    for (final track in _tracks) {
      if (track.album.trim().toLowerCase() == album.toLowerCase()) return track;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              height: 1.05,
              color: MobiusColors.textOf(context),
            ),
          ),
          const SizedBox(height: 16),
          _buildSearchField(),
          const SizedBox(height: 16),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _controller,
      autofocus: false,
      onChanged: (value) => setState(() => _query = value),
      style: TextStyle(color: MobiusColors.textOf(context), fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Songs, albums, artists…',
        hintStyle: TextStyle(
          color: MobiusColors.textDimOf(context),
          fontSize: 15,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: MobiusColors.textDimOf(context),
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18),
                color: MobiusColors.textDimOf(context),
                onPressed: () {
                  _controller.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: MobiusColors.panelOf(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MobiusColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MobiusColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: MobiusColors.accentOf(context)),
        ),
      ),
    );
  }

  Widget _buildResults() {
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
    if (_query.trim().isEmpty) {
      return Center(
        child: Text(
          'Search your library',
          style: TextStyle(color: MobiusColors.textDimOf(context)),
        ),
      );
    }

    final songs = _matchingSongs;
    final albums = _matchingAlbums;
    final artists = _matchingArtists;

    if (songs.isEmpty && albums.isEmpty && artists.isEmpty) {
      return Center(
        child: Text(
          'No results for "${_query.trim()}"',
          textAlign: TextAlign.center,
          style: TextStyle(color: MobiusColors.textDimOf(context)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 124),
      children: [
        if (songs.isNotEmpty) ...[
          _sectionHeader('Songs'),
          for (final track in songs) _songRow(track),
          const SizedBox(height: 8),
        ],
        if (artists.isNotEmpty) ...[
          _sectionHeader('Artists'),
          for (final artist in artists)
            _simpleRow(
              icon: Icons.person_outline_rounded,
              label: artist,
              onTap: () => widget.onGoToArtist(artist),
            ),
          const SizedBox(height: 8),
        ],
        if (albums.isNotEmpty) ...[
          _sectionHeader('Albums'),
          for (final album in albums)
            _simpleRow(
              icon: Icons.album_outlined,
              label: album,
              onTap: () {
                final track = _trackForAlbum(album);
                if (track != null) widget.onGoToAlbum(track);
              },
            ),
          const SizedBox(height: 72),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          color: MobiusColors.textDimOf(context),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _songRow(TrackMetadata track) {
    final isCurrent = track.trackId == widget.currentTrackId;
    final title = track.title.trim().isEmpty ? 'Unknown title' : track.title;
    final subtitle = [
      track.artist.trim().isEmpty ? 'Unknown artist' : track.artist,
      if (track.album.trim().isNotEmpty) track.album,
    ].join(' · ');

    return TrackContextMenu(
      track: track,
      repository: widget.repository,
      collections: widget.collections,
      playerController: widget.playerController,
      removeLabel: 'Remove from Library',
      onRemove: () async {
        await widget.collections.removeFromLibrary(track.trackId);
        if (!mounted) return;
        setState(() {
          _tracks.removeWhere((item) => item.trackId == track.trackId);
        });
        widget.onLibraryChanged();
      },
      onChanged: widget.onLibraryChanged,
      onGoToArtist: track.artist.trim().isEmpty
          ? null
          : () => widget.onGoToArtist(track.artist),
      onGoToAlbum: track.album.trim().isEmpty
          ? null
          : () => widget.onGoToAlbum(track),
      child: Material(
        color: isCurrent
            ? MobiusColors.accentOf(context).withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _playSong(track),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: MobiusColors.panelOf(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GroupArtwork(
                    repository: widget.repository,
                    source: GroupArtworkSource([track.trackId]),
                    decodeSize: 88,
                    filterQuality: FilterQuality.medium,
                    placeholder: Center(
                      child: Icon(
                        Icons.music_note_rounded,
                        size: 20,
                        color: MobiusColors.textDimOf(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
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
                      final position = box.localToGlobal(
                        Offset(0, box.size.height),
                      );
                      TrackContextMenu.showForTrack(
                        context: context,
                        position: position,
                        track: track,
                        repository: widget.repository,
                        collections: widget.collections,
                        playerController: widget.playerController,
                        removeLabel: 'Remove from Library',
                        onRemove: () async {
                          await widget.collections.removeFromLibrary(
                            track.trackId,
                          );
                          if (!mounted) return;
                          setState(() {
                            _tracks.removeWhere(
                              (item) => item.trackId == track.trackId,
                            );
                          });
                          widget.onLibraryChanged();
                        },
                        onChanged: widget.onLibraryChanged,
                        onGoToArtist: track.artist.trim().isEmpty
                            ? null
                            : () => widget.onGoToArtist(track.artist),
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
      ),
    );
  }

  Widget _simpleRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: MobiusColors.textDimOf(context)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MobiusColors.textOf(context),
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: MobiusColors.textDimOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
