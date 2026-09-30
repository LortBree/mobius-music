import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../data/ffi_library_repository.dart';
import '../../../playback/player_controller.dart';
import '../../../core/ffi/offline_player.dart';
import '../data/user_collections.dart';
import 'group_artwork.dart';
import 'track_context_menu.dart';

class ArtistsPage extends StatefulWidget {
  const ArtistsPage({
    super.key,
    required this.repository,
    required this.playerController,
    required this.collections,
    required this.onLibraryChanged,
    required this.onGoToArtist,
    required this.onGoToAlbum,
    this.initialArtistName,
    this.libraryVersion = 0,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final UserCollections collections;
  final VoidCallback onLibraryChanged;
  final ValueChanged<String> onGoToArtist;
  final ValueChanged<TrackMetadata> onGoToAlbum;
  final String? initialArtistName;
  final int libraryVersion;

  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistEntry {
  _ArtistEntry({
    required this.name,
    required this.trackIds,
  }) : artwork = GroupArtworkSource(trackIds);

  final String name;
  final List<int> trackIds;
  final GroupArtworkSource artwork;
}

class _ArtistBuilder {
  _ArtistBuilder(this.name);

  final String name;
  final List<int> trackIds = [];
}

class _ArtistsPageState extends State<ArtistsPage> {
  List<_ArtistEntry> _artists = const [];
  _ArtistEntry? _selectedArtist;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  @override
  void didUpdateWidget(covariant ArtistsPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.libraryVersion != widget.libraryVersion) {
      _loadArtists();
    }
  }

  Future<void> _loadArtists() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final removedIds = await widget.collections.removedLibraryTrackIds();
      final groups = <String, _ArtistBuilder>{};
      final count = widget.repository.getTrackCount();

      for (var i = 0; i < count; i++) {
        final trackId = widget.repository.getTrackIdAt(i);
        if (removedIds.contains(trackId)) continue;
        final metadata = widget.repository.getTrackMetadata(trackId);

        final name = _resolveArtist(metadata);
        if (name.isEmpty) {
          continue;
        }

        final key = name.toLowerCase();
        final builder = groups.putIfAbsent(key, () => _ArtistBuilder(name));

        builder.trackIds.add(trackId);
      }

      final artists =
          groups.values
              .map(
                (builder) => _ArtistEntry(
                  name: builder.name,
                  trackIds: List.unmodifiable(builder.trackIds),
                ),
              )
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _artists = artists;
        final requested = widget.initialArtistName?.toLowerCase();
        if (requested != null) {
          for (final artist in artists) {
            if (artist.name.toLowerCase() == requested) {
              _selectedArtist = artist;
              break;
            }
          }
        } else if (_selectedArtist != null) {
          final previousName = _selectedArtist!.name.toLowerCase();
          _selectedArtist = null;
          for (final artist in artists) {
            if (artist.name.toLowerCase() == previousName) {
              _selectedArtist = artist;
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
        _artists = const [];
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

  void _openArtist(_ArtistEntry artist) {
    setState(() => _selectedArtist = artist);
  }

  @override
  Widget build(BuildContext context) {
    final selectedArtist = _selectedArtist;
    if (selectedArtist != null) {
      return _ArtistDetailPage(
        artist: selectedArtist,
        repository: widget.repository,
        playerController: widget.playerController,
        collections: widget.collections,
        onLibraryChanged: widget.onLibraryChanged,
        onGoToArtist: widget.onGoToArtist,
        onGoToAlbum: widget.onGoToAlbum,
        onBack: () => setState(() => _selectedArtist = null),
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
          'Unable to load artists.',
          style: TextStyle(color: MobiusColors.textOf(context), fontSize: 15),
        ),
      );
    }

    if (_artists.isEmpty) {
      return Center(
        child: Text(
          'No artists found.',
          style: TextStyle(color: MobiusColors.textDimOf(context), fontSize: 15),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 36, 24),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Text(
              'Artists',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w600,
                color: MobiusColors.textOf(context),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
          SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final artist = _artists[index];

              return _ArtistCard(
                artist: artist,
                repository: widget.repository,
                onTap: () => _openArtist(artist),
              );
            }, childCount: _artists.length),
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

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({
    required this.artist,
    required this.repository,
    required this.onTap,
  });

  final _ArtistEntry artist;
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
                      source: artist.artwork,
                      decodeSize: 440,
                      filterQuality: FilterQuality.medium,
                      placeholder: const _ArtistPlaceholder(),
                    ),
                  ),
              ),
              const SizedBox(height: 12),
              Text(
                artist.name,
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
                '${artist.trackIds.length} tracks',
                style: TextStyle(color: MobiusColors.textDimOf(context), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistPlaceholder extends StatelessWidget {
  const _ArtistPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.person_outline_rounded,
        size: 54,
        color: MobiusColors.accentOf(context),
      ),
    );
  }
}

class _ArtistDetailPage extends StatelessWidget {
  const _ArtistDetailPage({
    required this.artist,
    required this.repository,
    required this.playerController,
    required this.collections,
    required this.onLibraryChanged,
    required this.onGoToArtist,
    required this.onGoToAlbum,
    required this.onBack,
  });

  final _ArtistEntry artist;
  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final UserCollections collections;
  final VoidCallback onLibraryChanged;
  final ValueChanged<String> onGoToArtist;
  final ValueChanged<TrackMetadata> onGoToAlbum;
  final VoidCallback onBack;

  void _playArtist() {
    if (artist.trackIds.isEmpty) {
      return;
    }

    playerController.setQueue(artist.trackIds);
    playerController.selectAndPlay(0);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 36, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to artists',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 6),
              Text(
                'ARTIST',
                style: TextStyle(
                  color: MobiusColors.accentLightOf(context),
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
                  color: MobiusColors.panelOf(context),
                  borderRadius: BorderRadius.circular(110),
                ),
                clipBehavior: Clip.antiAlias,
                // 220 logical px; 440 covers a 2x display.
                child: GroupArtwork(
                  repository: repository,
                  source: artist.artwork,
                  decodeSize: 440,
                  filterQuality: FilterQuality.high,
                  placeholder: const _ArtistPlaceholder(),
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
                        artist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MobiusColors.textOf(context),
                          fontSize: 34,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${artist.trackIds.length} tracks',
                        style: TextStyle(
                          color: MobiusColors.textDimOf(context),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _playArtist,
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Play Artist'),
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
          const SizedBox(height: 36),
          Expanded(
            child: ListView.separated(
              itemCount: artist.trackIds.length,
              separatorBuilder: (context, __) =>
                  Divider(height: 1, color: MobiusColors.borderOf(context)),
              itemBuilder: (context, index) {
                final trackId = artist.trackIds[index];
                final metadata = repository.getTrackMetadata(trackId);

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
                      style: TextStyle(
                        color: MobiusColors.textDimOf(context),
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  title: Text(
                    metadata.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MobiusColors.textOf(context),
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    metadata.album.isEmpty ? metadata.artist : metadata.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MobiusColors.textDimOf(context),
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Play',
                    onPressed: () {
                      playerController.setQueue(artist.trackIds);
                      playerController.selectAndPlay(index);
                    },
                    icon: Icon(
                      Icons.play_arrow_rounded,
                      color: MobiusColors.accentLightOf(context),
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
}
