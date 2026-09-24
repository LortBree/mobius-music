import 'package:flutter/material.dart';

import '../data/ffi_library_repository.dart';
import '../../../playback/player_controller.dart';
import '../../../core/ffi/offline_player.dart';
import '../data/user_collections.dart';
import 'track_context_menu.dart';

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
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumEntry {
  _AlbumEntry({
    required this.title,
    required this.artist,
    required this.trackIds,
    required this.artwork,
  });

  final String title;
  final String artist;
  final List<int> trackIds;
  final TrackArtwork? artwork;
}

class _AlbumsPageState extends State<AlbumsPage> {
  List<_AlbumEntry> _albums = const [];
  _AlbumEntry? _selectedAlbum;
  bool _loading = true;
  Object? _error;

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

        if (builder.artwork == null) {
          try {
            final artwork = widget.repository.getTrackArtwork(trackId);

            if (artwork != null && artwork.data.isNotEmpty) {
              builder.artwork = artwork;
            }
          } catch (_) {}
        }
      }

      final albums =
          groups.values
              .map(
                (builder) => _AlbumEntry(
                  title: builder.title,
                  artist: builder.artist,
                  trackIds: List.unmodifiable(builder.trackIds),
                  artwork: builder.artwork,
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
          style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 15),
        ),
      );
    }

    if (_albums.isEmpty) {
      return const Center(
        child: Text(
          'No albums found.',
          style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 15),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 36, 24),
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Text(
              'Albums',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w600,
                color: Color(0xFFEDEDED),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
          SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final album = _albums[index];

              return _AlbumCard(album: album, onTap: () => _openAlbum(album));
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
  TrackArtwork? artwork;
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final _AlbumEntry album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final artwork = album.artwork;

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
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: artwork != null && artwork.data.isNotEmpty
                        ? Image.memory(
                            artwork.data,
                            cacheWidth: 440,
                            cacheHeight: 440,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) {
                              return const _ArtworkPlaceholder();
                            },
                        )
                        : const _ArtworkPlaceholder(),
                  ),
              ),
              const SizedBox(height: 12),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFEDEDED),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                album.artist.isEmpty ? 'Unknown Artist' : album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
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
    return const Center(
      child: Icon(Icons.album_outlined, size: 54, color: Color(0xFF6A3FC0)),
    );
  }
}

class _AlbumDetailPage extends StatelessWidget {
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

  void _playAlbum() {
    if (album.trackIds.isEmpty) {
      return;
    }

    playerController.setQueue(album.trackIds);
    playerController.selectAndPlay(0);
  }

  @override
  Widget build(BuildContext context) {
    final artwork = album.artwork;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 36, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to albums',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 6),
              const Text(
                'ALBUM',
                style: TextStyle(
                  color: Color(0xFFC4A8F0),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: artwork != null && artwork.data.isNotEmpty
                    ? Image.memory(
                        artwork.data,
                        cacheWidth: 960,
                        cacheHeight: 960,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) {
                          return const _ArtworkPlaceholder();
                        },
                      )
                    : const _ArtworkPlaceholder(),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFEDEDED),
                          fontSize: 34,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.artist.isEmpty ? 'Unknown Artist' : album.artist,
                        style: const TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${album.trackIds.length} tracks',
                        style: const TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _playAlbum,
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Play Album'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8A63D2),
                          foregroundColor: const Color(0xFFFAFAFA),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          Expanded(
            child: ListView.separated(
              itemCount: album.trackIds.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFF2A2A2A)),
              itemBuilder: (context, index) {
                final trackId = album.trackIds[index];
                final metadata = _metadataForTrack(trackId);

                return TrackContextMenu(
                  track: metadata,
                  collections: collections,
                  playerController: playerController,
                  removeLabel: 'Remove from Library',
                  onRemove: () async {
                    await collections.removeFromLibrary(trackId);
                    onLibraryChanged();
                  },
                  onChanged: onLibraryChanged,
                  onGoToArtist: trackArtistName(metadata).isEmpty
                      ? null
                      : () => onGoToArtist(trackArtistName(metadata)),
                  onGoToAlbum: metadata.album.trim().isEmpty
                      ? null
                      : () => onGoToAlbum(metadata),
                  child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                    width: 34,
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9A9A9A),
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  title: Text(
                    metadata.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFEDEDED),
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    metadata.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9A9A9A),
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Play',
                    onPressed: () {
                      playerController.setQueue(album.trackIds);
                      playerController.selectAndPlay(index);
                    },
                    icon: const Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFFC4A8F0),
                    ),
                  ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  TrackMetadata _metadataForTrack(int trackId) {
    return repository.getTrackMetadata(trackId);
  }
}
