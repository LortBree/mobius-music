import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../../../app/player_shell_state.dart' show kMobileBreakpoint;
import '../data/ffi_library_repository.dart';
import '../../../playback/player_controller.dart';
import '../../../core/ffi/offline_player.dart';
import '../data/user_collections.dart';
import 'group_artwork.dart';
import 'track_context_menu.dart';
import 'track_list_row.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({
    super.key,
    required this.repository,
    required this.playerController,
    required this.collections,
    required this.onLibraryChanged,
    required this.onGoToArtist,
    required this.onGoToAlbum,
    this.initialTrack,
    this.libraryVersion = 0,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final UserCollections collections;
  final VoidCallback onLibraryChanged;
  final ValueChanged<String> onGoToArtist;
  final ValueChanged<TrackMetadata> onGoToAlbum;
  final TrackMetadata? initialTrack;
  final int libraryVersion;

  @override
  State<AlbumsPage> createState() => AlbumsPageState();
}

class _AlbumEntry {
  _AlbumEntry({
    required this.title,
    required this.artist,
    required this.trackIds,
  }) : artwork = GroupArtworkSource(trackIds);

  final String title;
  final String artist;
  final List<int> trackIds;
  final GroupArtworkSource artwork;
}

class AlbumsPageState extends State<AlbumsPage> {
  List<_AlbumEntry> _albums = const [];
  _AlbumEntry? _selectedAlbum;
  bool _loading = true;
  Object? _error;

  /// Returns true if back navigation was consumed (closing album detail).
  bool handleBack() {
    if (_selectedAlbum != null) {
      setState(() => _selectedAlbum = null);
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  @override
  void didUpdateWidget(covariant AlbumsPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.libraryVersion != widget.libraryVersion) {
      _loadAlbums();
    }
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final removedIds = await widget.collections.removedLibraryTrackIds();
      final groups = <String, _AlbumBuilder>{};
      final count = widget.repository.getTrackCount();

      for (var i = 0; i < count; i++) {
        final trackId = widget.repository.getTrackIdAt(i);
        if (removedIds.contains(trackId)) continue;
        final metadata = widget.repository.getTrackMetadata(trackId);

        final album = metadata.album.trim();
        if (album.isEmpty) {
          continue;
        }

        final artist = _resolveArtist(metadata);
        final key = '$album\u0000$artist';

        final builder = groups.putIfAbsent(
          key,
          () => _AlbumBuilder(title: album, artist: artist),
        );

        builder.trackIds.add(trackId);
      }

      final albums =
          groups.values
              .map(
                (builder) => _AlbumEntry(
                  title: builder.title,
                  artist: builder.artist,
                  trackIds: List.unmodifiable(builder.trackIds),
                ),
              )
              .toList()
            ..sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _albums = albums;
        final requested = widget.initialTrack;
        if (requested != null) {
          final requestedArtist = requested.albumArtist.trim().isEmpty
              ? requested.artist.trim()
              : requested.albumArtist.trim();
          for (final album in albums) {
            if (album.title == requested.album.trim() &&
                album.artist == requestedArtist) {
              _selectedAlbum = album;
              break;
            }
          }
        } else if (_selectedAlbum != null) {
          final previous = _selectedAlbum!;
          _selectedAlbum = null;
          for (final album in albums) {
            if (album.title == previous.title &&
                album.artist == previous.artist) {
              _selectedAlbum = album;
              break;
            }
          }
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _albums = const [];
        _loading = false;
        _error = error;
      });
    }
  }

  String _resolveArtist(TrackMetadata metadata) {
    final albumArtist = metadata.albumArtist.trim();
    if (albumArtist.isNotEmpty) {
      return albumArtist;
    }

    return metadata.artist.trim();
  }

  void _openAlbum(_AlbumEntry album) {
    setState(() => _selectedAlbum = album);
  }

  @override
  Widget build(BuildContext context) {
    final selectedAlbum = _selectedAlbum;
    if (selectedAlbum != null) {
      return _AlbumDetailPage(
        album: selectedAlbum,
        playerController: widget.playerController,
        repository: widget.repository,
        collections: widget.collections,
        onLibraryChanged: widget.onLibraryChanged,
        onGoToArtist: widget.onGoToArtist,
        onGoToAlbum: widget.onGoToAlbum,
        onBack: () => setState(() => _selectedAlbum = null),
      );
    }

    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          'Unable to load albums.',
          style: TextStyle(color: MobiusColors.textOf(context), fontSize: 15),
        ),
      );
    }

    if (_albums.isEmpty) {
      return Center(
        child: Text(
          'No albums found.',
          style: TextStyle(color: MobiusColors.textDimOf(context), fontSize: 15),
        ),
      );
    }

    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    if (isMobile) {
      // Mobile: no internal page title (the Library tab owns it); a 2-column
      // grid of rounded covers with the track-count chip overlaid.
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
        itemCount: _albums.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 18,
          childAspectRatio: 0.72,
        ),
        itemBuilder: (context, index) {
          final album = _albums[index];
          return _MobileAlbumCard(
            album: album,
            repository: widget.repository,
            onTap: () => _openAlbum(album),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 36, 24),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Text(
              'Albums',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w600,
                // Match SettingsPageHeader's tight line box so every page
                // title sits at the same height above the page padding.
                height: 1.05,
                color: MobiusColors.textOf(context),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
          SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final album = _albums[index];

              return _AlbumCard(
                album: album,
                repository: widget.repository,
                onTap: () => _openAlbum(album),
              );
            }, childCount: _albums.length),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 300,
              crossAxisSpacing: 24,
              mainAxisSpacing: 30,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumBuilder {
  _AlbumBuilder({required this.title, required this.artist});

  final String title;
  final String artist;
  final List<int> trackIds = [];
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.album,
    required this.repository,
    required this.onTap,
  });

  final _AlbumEntry album;
  final LibraryRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: MobiusColors.panelOf(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: GroupArtwork(
                      repository: repository,
                      source: album.artwork,
                      decodeSize: 440,
                      filterQuality: FilterQuality.medium,
                      placeholder: const _ArtworkPlaceholder(),
                    ),
                  ),
              ),
              const SizedBox(height: 12),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: MobiusColors.textOf(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                album.artist.isEmpty ? 'Unknown Artist' : album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: MobiusColors.textDimOf(context), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(Icons.album_outlined, size: 54, color: MobiusColors.accentOf(context)),
    );
  }
}

/// Mobile 2-column album card: a rounded(16) cover with a translucent scrim
/// chip bottom-right. Library metadata carries no per-album bit depth / rate,
/// so the chip shows the track count (the available fact) rather than a
/// fabricated quality tag.
class _MobileAlbumCard extends StatelessWidget {
  const _MobileAlbumCard({
    required this.album,
    required this.repository,
    required this.onTap,
  });

  final _AlbumEntry album;
  final LibraryRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: MobiusColors.panelOf(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: GroupArtwork(
                        repository: repository,
                        source: album.artwork,
                        decodeSize: 440,
                        filterQuality: FilterQuality.medium,
                        placeholder: const _ArtworkPlaceholder(),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: MobiusColors.scrimOf(
                          context,
                        ).withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${album.trackIds.length}',
                        style: TextStyle(
                          color: MobiusColors.onScrimOf(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: MobiusColors.textOf(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              album.artist.isEmpty ? 'Unknown Artist' : album.artist,
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
    );
  }
}

class _AlbumDetailPage extends StatefulWidget {
  const _AlbumDetailPage({
    required this.album,
    required this.playerController,
    required this.repository,
    required this.collections,
    required this.onLibraryChanged,
    required this.onGoToArtist,
    required this.onGoToAlbum,
    required this.onBack,
  });

  final _AlbumEntry album;
  final PlayerController playerController;
  final FfiLibraryRepository repository;
  final UserCollections collections;
  final VoidCallback onLibraryChanged;
  final ValueChanged<String> onGoToArtist;
  final ValueChanged<TrackMetadata> onGoToAlbum;
  final VoidCallback onBack;

  @override
  State<_AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<_AlbumDetailPage> {
  late final List<TrackMetadata> _tracks = widget.album.trackIds
      .map((id) {
        try {
          return widget.repository.getTrackMetadata(id);
        } catch (_) {
          return null;
        }
      })
      .whereType<TrackMetadata>()
      .toList();

  @override
  void initState() {
    super.initState();
    widget.playerController.commands.addListener(_onPlayerCommand);
  }

  @override
  void dispose() {
    widget.playerController.commands.removeListener(_onPlayerCommand);
    super.dispose();
  }

  void _onPlayerCommand() {
    if (mounted) setState(() {});
  }

  /// The album artist, used to decide whether a per-track artist is worth
  /// repeating under the title.
  String get _albumArtist => widget.album.artist.trim();

  /// Whether the album spans more than one disc (and we have disc numbers).
  bool get _multiDisc {
    final discs = <int>{};
    for (final track in _tracks) {
      if (track.hasDiscNumber) discs.add(track.discNumber);
    }
    return discs.length > 1;
  }

  int get _safeCurrentTrackId {
    try {
      return widget.playerController.currentTrackId;
    } catch (_) {
      return 0;
    }
  }

  double? _currentDuration(bool isCurrent) {
    if (!isCurrent) return null;
    try {
      return widget.playerController.durationSeconds;
    } catch (_) {
      return null;
    }
  }

  void _play(int index) {
    try {
      widget.playerController.setQueue(widget.album.trackIds);
      widget.playerController.selectAndPlay(index);
    } catch (error) {
      _showError(error);
    }
  }

  void _playAlbum() => _play(0);

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    final currentTrackId = _safeCurrentTrackId;
    final showDiscHeaders = _multiDisc;
    final albumArtistLower = _albumArtist.toLowerCase();
    int? renderedDisc;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 32,
        isMobile ? 12 : 24,
        isMobile ? 16 : 36,
        isMobile ? 90 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMobile) ...[
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to albums',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 6),
                Text(
                  'ALBUM',
                  style: TextStyle(
                    color: MobiusColors.accentLightOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (isMobile) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: MobiusColors.panelOf(context),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GroupArtwork(
                    repository: widget.repository,
                    source: widget.album.artwork,
                    decodeSize: 220,
                    filterQuality: FilterQuality.medium,
                    placeholder: const _ArtworkPlaceholder(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ALBUM',
                        style: TextStyle(
                          color: MobiusColors.accentLightOf(context),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.album.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MobiusColors.textOf(context),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.album.artist.isEmpty
                            ? 'Unknown Artist'
                            : widget.album.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MobiusColors.textDimOf(context),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.album.trackIds.length} tracks',
                        style: TextStyle(
                          color: MobiusColors.textDimOf(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: _playAlbum,
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text('Play Album'),
                style: FilledButton.styleFrom(
                  backgroundColor: MobiusColors.accentOf(context),
                  foregroundColor: MobiusColors.onAccentOf(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: MobiusColors.panelOf(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GroupArtwork(
                    repository: widget.repository,
                    source: widget.album.artwork,
                    decodeSize: 440,
                    filterQuality: FilterQuality.high,
                    placeholder: const _ArtworkPlaceholder(),
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.album.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MobiusColors.textOf(context),
                            fontSize: 34,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.album.artist.isEmpty
                              ? 'Unknown Artist'
                              : widget.album.artist,
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          '${widget.album.trackIds.length} tracks',
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _playAlbum,
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('Play Album'),
                          style: FilledButton.styleFrom(
                            backgroundColor: MobiusColors.accentOf(context),
                            foregroundColor: MobiusColors.onAccentOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: _tracks.length,
              itemBuilder: (context, index) {
                final metadata = _tracks[index];
                final trackId = metadata.trackId;
                final isCurrent = trackId == currentTrackId;

                final displayNumber = metadata.trackNumber > 0
                    ? metadata.trackNumber
                    : index + 1;

                final trackArtist = metadata.artist.trim();
                final subtitle =
                    trackArtist.isNotEmpty &&
                        trackArtist.toLowerCase() != albumArtistLower
                    ? trackArtist
                    : null;

                final row = TrackContextMenu(
                  key: ValueKey('context-$trackId'),
                  track: metadata,
                  repository: widget.repository,
                  collections: widget.collections,
                  playerController: widget.playerController,
                  removeLabel: 'Remove from Library',
                  onRemove: () async {
                    await widget.collections.removeFromLibrary(trackId);
                    widget.onLibraryChanged();
                  },
                  onChanged: widget.onLibraryChanged,
                  onGoToArtist: trackArtistName(metadata).isEmpty
                      ? null
                      : () => widget.onGoToArtist(trackArtistName(metadata)),
                  onGoToAlbum: metadata.album.trim().isEmpty
                      ? null
                      : () => widget.onGoToAlbum(metadata),
                  child: TrackListRow(
                    key: ValueKey(trackId),
                    trackNumber: displayNumber,
                    title: metadata.title,
                    artistSubtitle: subtitle,
                    isCurrent: isCurrent,
                    duration: _currentDuration(isCurrent),
                    onPlay: () => _play(index),
                    onMore: () {
                      TrackContextMenu.showForTrack(
                        context: context,
                        position: Offset.zero,
                        track: metadata,
                        repository: widget.repository,
                        collections: widget.collections,
                        playerController: widget.playerController,
                        removeLabel: 'Remove from Library',
                        onRemove: () async {
                          await widget.collections.removeFromLibrary(trackId);
                          widget.onLibraryChanged();
                        },
                        onChanged: widget.onLibraryChanged,
                        onGoToArtist: trackArtistName(metadata).isEmpty
                            ? null
                            : () => widget.onGoToArtist(trackArtistName(metadata)),
                        onGoToAlbum: metadata.album.trim().isEmpty
                            ? null
                            : () => widget.onGoToAlbum(metadata),
                      );
                    },
                  ),
                );

                if (showDiscHeaders &&
                    metadata.hasDiscNumber &&
                    metadata.discNumber != renderedDisc) {
                  renderedDisc = metadata.discNumber;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TrackListDiscHeader(discNumber: metadata.discNumber),
                      row,
                    ],
                  );
                }

                return row;
              },
            ),
          ),
        ],
      ),
    );
  }
}

