import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../core/ffi/offline_player.dart';
import '../../../playback/player_controller.dart';
import '../data/ffi_library_repository.dart';
import '../data/user_collections.dart';
import 'track_context_menu.dart';

const _ink = Color(0xFFEDEDED);
const _muted = Color(0xFF9A9A9A);
const _panel = Color(0xFF1A1A1A);
const _accent = Color(0xFFB58AF4);
const _favoritesCollectionId = '\u0000mobius_favorites';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({
    super.key,
    required this.repository,
    required this.playerController,
    required this.collections,
    required this.onGoToArtist,
    required this.onGoToAlbum,
    this.collectionsVersion = 0,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final UserCollections collections;
  final ValueChanged<String> onGoToArtist;
  final ValueChanged<TrackMetadata> onGoToAlbum;
  final int collectionsVersion;

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  Map<String, List<int>> _playlists = {};
  Map<String, Uint8List> _covers = {};
  Set<int> _favoriteTrackIds = {};
  bool _loading = true;
  bool _creating = false;
  String? _editingName;
  String? _selectedPlaylistName;
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant PlaylistsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collectionsVersion != widget.collectionsVersion) {
      _reload();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final playlists = await widget.collections.playlists();
    final favoriteTrackIds = await widget.collections.favorites();
    final covers = <String, Uint8List>{};
    for (final name in playlists.keys) {
      final cover = await widget.collections.playlistCover(name);
      if (cover != null) covers[name] = cover;
    }
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _favoriteTrackIds = favoriteTrackIds;
      _covers = covers;
      if (_selectedPlaylistName != null &&
          _selectedPlaylistName != _favoritesCollectionId &&
          !playlists.containsKey(_selectedPlaylistName)) {
        _selectedPlaylistName = null;
      }
      _loading = false;
    });
  }

  Future<void> _createPlaylist() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (name.toLowerCase() == 'favorites') {
      _showCollectionError(
        context,
        StateError('"Favorites" is reserved for your saved tracks.'),
      );
      return;
    }
    try {
      final editingName = _editingName;
      if (editingName == null) {
        await widget.collections.createPlaylist(name);
      } else {
        await widget.collections.renamePlaylist(editingName, name);
      }
      _nameController.clear();
      if (mounted) {
        setState(() {
          _creating = false;
          _editingName = null;
        });
      }
      await _reload();
    } catch (error) {
      if (mounted) _showCollectionError(context, error);
    }
  }

  Future<void> _deletePlaylist(String name) async {
    await widget.collections.deletePlaylist(name);
    await _reload();
  }

  void _editPlaylist(String name) {
    setState(() {
      _editingName = name;
      _nameController.text = name;
      _creating = true;
    });
  }

  Future<void> _chooseCover(String name) async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 4 * 1024 * 1024) {
      if (mounted) {
        _showCollectionError(context, 'Choose an image smaller than 4 MB.');
      }
      return;
    }
    await widget.collections.setPlaylistCover(name, bytes);
    await _reload();
  }

  void _openPlaylist(String name) {
    setState(() => _selectedPlaylistName = name);
  }

  void _openFavorites() {
    setState(() => _selectedPlaylistName = _favoritesCollectionId);
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlaylistName = _selectedPlaylistName;
    if (selectedPlaylistName != null) {
      final isFavorites = selectedPlaylistName == _favoritesCollectionId;
      final trackIds = isFavorites
          ? _favoriteTrackIds.toList()
          : _playlists[selectedPlaylistName];
      if (trackIds != null) {
        return _PlaylistDetailPage(
          key: ValueKey(selectedPlaylistName),
          name: isFavorites ? 'Favorites' : selectedPlaylistName,
          trackIds: List<int>.from(trackIds),
          cover: isFavorites ? null : _covers[selectedPlaylistName],
          isFavorites: isFavorites,
          repository: widget.repository,
          playerController: widget.playerController,
          collections: widget.collections,
          onGoToArtist: widget.onGoToArtist,
          onGoToAlbum: widget.onGoToAlbum,
          onBack: () {
            setState(() => _selectedPlaylistName = null);
            _reload();
          },
          onChanged: _reload,
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 36, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _CollectionHeading(title: 'Playlists')),
              FilledButton.icon(
                onPressed: () => setState(() {
                  _creating = true;
                  _editingName = null;
                  _nameController.clear();
                }),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New playlist'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_playlists.length} ${_playlists.length == 1 ? 'playlist' : 'playlists'}',
            style: const TextStyle(color: _muted),
          ),
          if (_creating) ...[
            const SizedBox(height: 16),
            Material(
              color: _panel,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: _editingName == null
                              ? 'Playlist name'
                              : 'Rename playlist',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _createPlaylist(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel',
                      onPressed: () => setState(() {
                        _creating = false;
                        _editingName = null;
                        _nameController.clear();
                      }),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    IconButton.filled(
                      tooltip: _editingName == null
                          ? 'Create playlist'
                          : 'Save name',
                      onPressed: _createPlaylist,
                      icon: const Icon(Icons.check_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Expanded(
              child: GridView.builder(
                itemCount: _playlists.length + 1,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisExtent: 316,
                  crossAxisSpacing: 24,
                  mainAxisSpacing: 28,
                ),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _PlaylistCard(
                      key: const ValueKey(_favoritesCollectionId),
                      name: 'Favorites',
                      trackCount: _favoriteTrackIds.length,
                      cover: null,
                      isFavorites: true,
                      onTap: _openFavorites,
                      onEdit: () {},
                      onChooseCover: () {},
                      onDelete: () {},
                    );
                  }
                  final name = _playlists.keys.elementAt(index - 1);
                  final ids = _playlists[name]!;
                  return _PlaylistCard(
                    key: ValueKey(name),
                    name: name,
                    trackCount: ids.length,
                    cover: _covers[name],
                    isFavorites: false,
                    onTap: () => _openPlaylist(name),
                    onEdit: () => _editPlaylist(name),
                    onChooseCover: () => _chooseCover(name),
                    onDelete: () => _deletePlaylist(name),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    super.key,
    required this.name,
    required this.trackCount,
    required this.cover,
    required this.isFavorites,
    required this.onTap,
    required this.onEdit,
    required this.onChooseCover,
    required this.onDelete,
  });

  final String name;
  final int trackCount;
  final Uint8List? cover;
  final bool isFavorites;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onChooseCover;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: cover == null
                        ? isFavorites
                              ? const _FavoritesPlaceholder()
                              : const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF57417E),
                                        Color(0xFF201C2A),
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.queue_music_rounded,
                                      color: Colors.white,
                                      size: 56,
                                    ),
                                  ),
                                )
                        : Image.memory(cover!, fit: BoxFit.cover),
                  ),
                ),
                if (!isFavorites)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: const CircleBorder(),
                      child: PopupMenuButton<String>(
                        tooltip: 'Playlist options',
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              onEdit();
                              break;
                            case 'cover':
                              onChooseCover();
                              break;
                            case 'delete':
                              onDelete();
                              break;
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Rename')),
                          PopupMenuItem(
                            value: 'cover',
                            child: Text('Change cover image'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete playlist'),
                          ),
                        ],
                        icon: const Icon(Icons.more_horiz, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
            style: const TextStyle(color: _muted),
          ),
        ],
      ),
    ),
  );
}

class _FavoritesPlaceholder extends StatelessWidget {
  const _FavoritesPlaceholder();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF57417E), Color(0xFF201C2A)],
      ),
    ),
    child: Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_rounded,
                color: const Color(0xFFB58AF4),
                size: size * 0.34,
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _PlaylistDetailPage extends StatefulWidget {
  const _PlaylistDetailPage({
    super.key,
    required this.name,
    required this.trackIds,
    required this.cover,
    required this.repository,
    required this.playerController,
    required this.collections,
    required this.onGoToArtist,
    required this.onGoToAlbum,
    required this.isFavorites,
    required this.onBack,
    required this.onChanged,
  });

  final String name;
  final List<int> trackIds;
  final Uint8List? cover;
  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final UserCollections collections;
  final ValueChanged<String> onGoToArtist;
  final ValueChanged<TrackMetadata> onGoToAlbum;
  final bool isFavorites;
  final VoidCallback onBack;
  final VoidCallback onChanged;

  @override
  State<_PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<_PlaylistDetailPage> {
  final Map<int, ImageProvider> _artworkCache = {};
  late final List<TrackMetadata> _tracks = widget.trackIds
      .map((id) {
        try {
          return widget.repository.getTrackMetadata(id);
        } catch (_) {
          return null;
        }
      })
      .whereType<TrackMetadata>()
      .toList();
  Future<void> _remove(TrackMetadata track) async {
    if (widget.isFavorites) {
      await widget.collections.toggleFavorite(track.trackId);
      if (mounted) {
        setState(
          () => _tracks.removeWhere((item) => item.trackId == track.trackId),
        );
        widget.onChanged();
      }
      return;
    }
    await widget.collections.removeFromPlaylist(widget.name, track.trackId);
    if (mounted) {
      setState(() => _tracks.remove(track));
      widget.onChanged();
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (widget.isFavorites) return;
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final track = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, track);
    });
    await widget.collections.reorderPlaylist(
      widget.name,
      _tracks.map((track) => track.trackId).toList(),
    );
  }

  void _play(int index) {
    widget.playerController.setQueue(
      _tracks.map((track) => track.trackId).toList(),
    );
    widget.playerController.selectAndPlay(index);
  }

  ImageProvider? _artworkFor(int trackId) {
    final cached = _artworkCache[trackId];
    if (cached != null) return cached;
    try {
      final artwork = widget.repository.getTrackArtwork(trackId);
      if (artwork == null || artwork.isEmpty) return null;
      final image = ResizeImage(
        MemoryImage(artwork.data),
        width: 96,
        height: 96,
      );
      _artworkCache[trackId] = image;
      return image;
    } catch (_) {
      return null;
    }
  }

  int get _safeCurrentTrackId {
    try {
      return widget.playerController.currentTrackId;
    } catch (_) {
      // An empty queue has no current track; playlist browsing should still
      // work before playback starts.
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

  int? _currentSampleRate(bool isCurrent) {
    if (!isCurrent) return null;
    try {
      return widget.playerController.sampleRate;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTrackId = _safeCurrentTrackId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlaylistHero(
          name: widget.name,
          trackCount: _tracks.length,
          cover: widget.cover,
          onBack: widget.onBack,
          isFavorites: widget.isFavorites,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 36, 4),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _tracks.isEmpty ? null : () => _play(0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8A63D2),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(104, 44),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_tracks.length} ${_tracks.length == 1 ? 'song' : 'songs'}',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 18, 32, 12),
          child: _PlaylistTableHeader(),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Divider(height: 1, color: Color(0xFF2A2A2A)),
        ),
        if (_tracks.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                widget.isFavorites
                    ? 'Favorite a track from your library to see it here.'
                    : 'Add tracks from your library using the playlist menu.',
                style: TextStyle(color: _muted),
              ),
            ),
          )
        else
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              itemCount: _tracks.length,
              onReorder: _reorder,
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final track = _tracks[index];
                final isCurrent = track.trackId == currentTrackId;
                return TrackContextMenu(
                  key: ValueKey('context-${track.trackId}'),
                  track: track,
                  collections: widget.collections,
                  playerController: widget.playerController,
                  removeLabel: widget.isFavorites
                      ? 'Remove from Favorites'
                      : 'Remove from playlist',
                  onRemove: () => _remove(track),
                  onChanged: widget.onChanged,
                  onGoToArtist: trackArtistName(track).isEmpty
                      ? null
                      : () => widget.onGoToArtist(trackArtistName(track)),
                  onGoToAlbum: track.album.trim().isEmpty
                      ? null
                      : () => widget.onGoToAlbum(track),
                  child: _PlaylistTrackRow(
                    key: ValueKey(track.trackId),
                    index: index,
                    track: track,
                    artwork: _artworkFor(track.trackId),
                    isCurrent: isCurrent,
                    isReorderable: !widget.isFavorites,
                    duration: _currentDuration(isCurrent),
                    sampleRate: _currentSampleRate(isCurrent),
                    onPlay: () => _play(index),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _PlaylistHero extends StatelessWidget {
  const _PlaylistHero({
    required this.name,
    required this.trackCount,
    required this.cover,
    required this.onBack,
    required this.isFavorites,
  });

  final String name;
  final int trackCount;
  final Uint8List? cover;
  final VoidCallback onBack;
  final bool isFavorites;

  @override
  Widget build(BuildContext context) => Container(
    height: 286,
    padding: const EdgeInsets.fromLTRB(32, 20, 36, 26),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF493273), Color(0xFF302344), Color(0x001A1A1A)],
        stops: [0, 0.62, 1],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to playlists',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
            Text(
              isFavorites ? 'SAVED MUSIC' : 'PLAYLIST',
              style: TextStyle(
                color: Color(0xFFE4D7FF),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _PlaylistCover(cover: cover, size: 184, isFavorites: isFavorites),
            const SizedBox(width: 24),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 44,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Mobius  •  $trackCount ${trackCount == 1 ? 'song' : 'songs'}',
                      style: const TextStyle(color: Color(0xFFD0C8D9)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({
    required this.cover,
    required this.size,
    required this.isFavorites,
  });

  final Uint8List? cover;
  final double size;
  final bool isFavorites;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 10)),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: cover == null
        ? isFavorites
              ? const _FavoritesPlaceholder()
              : const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF8055C7), Color(0xFF33234E)],
                    ),
                  ),
                  child: Icon(
                    Icons.queue_music_rounded,
                    color: Colors.white,
                    size: 68,
                  ),
                )
        : Image.memory(cover!, fit: BoxFit.cover),
  );
}

class _PlaylistTableHeader extends StatelessWidget {
  const _PlaylistTableHeader();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 36,
    child: Row(
      children: [
        SizedBox(width: 62, child: Center(child: _TableLabel('#'))),
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
        SizedBox(width: 96),
      ],
    ),
  );
}

class _PlaylistTrackRow extends StatelessWidget {
  const _PlaylistTrackRow({
    super.key,
    required this.index,
    required this.track,
    required this.artwork,
    required this.isCurrent,
    required this.isReorderable,
    required this.duration,
    required this.sampleRate,
    required this.onPlay,
  });

  final int index;
  final TrackMetadata track;
  final ImageProvider? artwork;
  final bool isCurrent;
  final bool isReorderable;
  final double? duration;
  final int? sampleRate;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isCurrent ? const Color(0xFF30263C) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 72,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isReorderable)
                          ReorderableDragStartListener(
                            index: index,
                            child: const Icon(
                              Icons.drag_handle_rounded,
                              size: 17,
                              color: _muted,
                            ),
                          ),
                        const SizedBox(width: 5),
                        Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isCurrent ? _accent : _muted,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: artwork == null
                                ? const ColoredBox(
                                    color: Color(0xFF292631),
                                    child: Icon(
                                      Icons.music_note_rounded,
                                      color: _muted,
                                    ),
                                  )
                                : Image(
                                    image: artwork!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
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
                                track.title.trim().isEmpty
                                    ? 'Unknown title'
                                    : track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 14,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                track.artist.trim().isEmpty
                                    ? 'Unknown artist'
                                    : track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    flex: 4,
                    child: Text(
                      track.album.trim().isEmpty
                          ? 'Unknown album'
                          : track.album,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 28),
                  SizedBox(
                    width: 82,
                    child: Text(
                      duration == null
                          ? '--'
                          : _formatPlaylistDuration(duration!),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                  SizedBox(
                    width: 88,
                    child: Text(
                      sampleRate == null || sampleRate! <= 0
                          ? '--'
                          : '${(sampleRate! / 1000).toStringAsFixed(sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 96),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatPlaylistDuration(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '--';
  final total = seconds.floor();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

class _CollectionHeading extends StatelessWidget {
  const _CollectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      color: _ink,
      fontSize: 42,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _TableLabel extends StatelessWidget {
  const _TableLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: _muted, fontSize: 13));
}

void _showCollectionError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(error.toString())));
}
