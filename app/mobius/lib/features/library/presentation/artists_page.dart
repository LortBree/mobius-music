import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../data/ffi_library_repository.dart';
import '../../../playback/player_controller.dart';
import '../../../core/ffi/offline_player.dart';
import '../data/user_collections.dart';
import 'group_artwork.dart';
import 'track_context_menu.dart';
import 'track_list_row.dart';

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
      padding: const EdgeInsets.fromLTRB(32, 12, 36, 24),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Text(
              'Artists',
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

class _ArtistAlbumGroup {
  _ArtistAlbumGroup({required this.title, required this.year})
    : artwork = GroupArtworkSource(<int>[]);

  final String title;
  final String year;
  final List<TrackMetadata> tracks = [];
  final List<int> trackIds = [];
  final GroupArtworkSource artwork;
}

class _ArtistDetailPage extends StatefulWidget {
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

  @override
  State<_ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<_ArtistDetailPage> {
  /// Flat, library-ordered track list (also the play queue order).
  late final List<TrackMetadata> _tracks = widget.artist.trackIds
      .map((id) {
        try {
          return widget.repository.getTrackMetadata(id);
        } catch (_) {
          return null;
        }
      })
      .whereType<TrackMetadata>()
      .toList();

  /// Tracks grouped by album, preserving first-seen (library) order. Each
  /// track's index into [_tracks] is remembered so playing a row sets the
  /// right queue index.
  late final List<_ArtistAlbumGroup> _groups = _buildGroups();

  /// trackId -> its index in [_tracks], for the play action.
  late final Map<int, int> _indexOf = {
    for (var i = 0; i < _tracks.length; i++) _tracks[i].trackId: i,
  };

  List<_ArtistAlbumGroup> _buildGroups() {
    final byAlbum = <String, _ArtistAlbumGroup>{};
    final order = <String>[];
    for (final track in _tracks) {
      final album = track.album.trim();
      final key = album.toLowerCase();
      final group = byAlbum.putIfAbsent(key, () {
        order.add(key);
        return _ArtistAlbumGroup(
          title: album.isEmpty ? 'Unknown album' : album,
          year: _yearFrom(track.date),
        );
      });
      group.tracks.add(track);
      group.trackIds.add(track.trackId);
    }
    for (final group in byAlbum.values) {
      group.artwork.trackIds.addAll(group.trackIds);
    }
    return [for (final key in order) byAlbum[key]!];
  }

  /// Pulls a 4-digit year out of a free-form date string (e.g. "1997",
  /// "1997-08-21"); empty when none is present.
  static String _yearFrom(String date) {
    final match = RegExp(r'\d{4}').firstMatch(date);
    return match?.group(0) ?? '';
  }

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
      widget.playerController.setQueue(widget.artist.trackIds);
      widget.playerController.selectAndPlay(index);
    } catch (error) {
      _showError(error);
    }
  }

  void _playArtist() => _play(0);

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final currentTrackId = _safeCurrentTrackId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 36, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to artists',
                onPressed: widget.onBack,
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
                  repository: widget.repository,
                  source: widget.artist.artwork,
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
                        widget.artist.name,
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
                        '${widget.artist.trackIds.length} tracks',
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
          const SizedBox(height: 28),
          Expanded(
            child: ListView.builder(
              itemCount: _groups.length,
              itemBuilder: (context, groupIndex) {
                final group = _groups[groupIndex];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (groupIndex > 0) const SizedBox(height: 20),
                    _ArtistAlbumHeader(
                      group: group,
                      repository: widget.repository,
                    ),
                    const SizedBox(height: 6),
                    for (var i = 0; i < group.tracks.length; i++)
                      _buildRow(context, group, i, currentTrackId),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    _ArtistAlbumGroup group,
    int indexInGroup,
    int currentTrackId,
  ) {
    final metadata = group.tracks[indexInGroup];
    final trackId = metadata.trackId;
    final isCurrent = trackId == currentTrackId;
    final queueIndex = _indexOf[trackId] ?? 0;
    final displayNumber = metadata.trackNumber > 0
        ? metadata.trackNumber
        : indexInGroup + 1;

    return TrackContextMenu(
      key: ValueKey('context-$trackId'),
      track: metadata,
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
        isCurrent: isCurrent,
        duration: _currentDuration(isCurrent),
        onPlay: () => _play(queueIndex),
      ),
    );
  }
}

/// Album group header on the artist page: a small cover, the album title and
/// its year when known.
class _ArtistAlbumHeader extends StatelessWidget {
  const _ArtistAlbumHeader({required this.group, required this.repository});

  final _ArtistAlbumGroup group;
  final FfiLibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 44,
              height: 44,
              child: ColoredBox(
                color: MobiusColors.panelOf(context),
                child: GroupArtwork(
                  repository: repository,
                  source: group.artwork,
                  decodeSize: 88,
                  filterQuality: FilterQuality.medium,
                  placeholder: Icon(
                    Icons.album_outlined,
                    size: 22,
                    color: MobiusColors.textDimOf(context),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MobiusColors.textOf(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (group.year.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    group.year,
                    style: TextStyle(
                      color: MobiusColors.textDimOf(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
