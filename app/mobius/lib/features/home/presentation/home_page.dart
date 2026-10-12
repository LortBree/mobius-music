import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/player_shell_state.dart' show kMobileBreakpoint;
import '../../../app/theme/colors.dart';
import '../../../core/ffi/offline_player.dart';
import '../../../core/platform/folder_access.dart';
import '../../../playback/player_controller.dart';
import '../../library/data/ffi_library_repository.dart';
import '../../library/presentation/group_artwork.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.playerController,
    required this.onOpenNowPlaying,
    required this.onLibraryChanged,
    required this.onGoToLibrary,
    required this.onGoToAlbum,
    required this.onGoToArtist,
    required this.libraryVersion,
    required this.favoritesVersion,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final VoidCallback onOpenNowPlaying;
  final VoidCallback onLibraryChanged;
  final VoidCallback onGoToLibrary;
  final void Function(TrackMetadata track) onGoToAlbum;
  final void Function(String artistName) onGoToArtist;
  final int libraryVersion;
  final int favoritesVersion;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<TrackMetadata> _recentTracks = [];
  Map<String, List<TrackMetadata>> _albumsMap = {};
  TrackMetadata? _spotlightTrack;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.libraryVersion != widget.libraryVersion) {
      _loadHomeData();
    }
  }

  void _loadHomeData() {
    setState(() => _loading = true);

    final trackCount = widget.repository.getTrackCount();
    final tracks = <TrackMetadata>[];
    final albums = <String, List<TrackMetadata>>{};

    final sampleSize = min(trackCount, 100);
    for (var i = 0; i < sampleSize; i++) {
      final id = widget.repository.getTrackIdAt(i);
      try {
        final meta = widget.repository.getTrackMetadata(id);
        tracks.add(meta);
        final albumKey = meta.album.trim().isNotEmpty
            ? meta.album.trim()
            : 'Unknown Album';
        albums.putIfAbsent(albumKey, () => []).add(meta);
      } catch (_) {}
    }

    TrackMetadata? spotlight;
    if (tracks.isNotEmpty) {
      final validAlbums = albums.values
          .where((list) => list.first.album.trim().isNotEmpty)
          .toList();
      if (validAlbums.isNotEmpty) {
        spotlight = validAlbums.first.first;
      } else {
        spotlight = tracks.first;
      }
    }

    setState(() {
      _recentTracks = tracks.take(15).toList();
      _albumsMap = albums;
      _spotlightTrack = spotlight;
      _loading = false;
    });
  }

  Future<void> _playTrack(TrackMetadata track) async {
    final trackIds = _recentTracks.map((t) => t.trackId).toList();
    final index = trackIds.indexOf(track.trackId);
    if (index >= 0) {
      await widget.playerController.setQueueAndPlay(trackIds, index);
    }
  }

  Future<void> _shuffleAll() async {
    final total = widget.repository.getTrackCount();
    if (total == 0) return;

    final allIds = <int>[];
    final limit = min(total, 500);
    for (var i = 0; i < limit; i++) {
      allIds.add(widget.repository.getTrackIdAt(i));
    }
    allIds.shuffle();

    await widget.playerController.setQueueAndPlay(allIds, 0);
  }

  Future<void> _addMusicFolder() async {
    final directory = await FolderAccess.pickFolder(
      confirmButtonText: 'Choose Music Folder',
    );
    if (directory == null || directory.isEmpty) return;

    await FolderAccess.persist(directory);
    widget.repository.scan(directory);
    widget.onLibraryChanged();
    _loadHomeData();
  }

  @override
  Widget build(BuildContext context) {
    final totalTracks = widget.repository.getTrackCount();
    final isDesktop = MediaQuery.of(context).size.width >= kMobileBreakpoint;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : totalTracks == 0
                ? _buildEmptyState()
                : CustomScrollView(
                    slivers: [
                      // Header
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 32 : 20,
                            vertical: 20,
                          ),
                          child: _buildHeader(totalTracks),
                        ),
                      ),

                      // Jump Back In (Active or recent)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 32 : 20,
                          ),
                          child: _buildJumpBackIn(),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),

                      // Recently Added Horizontal Rail
                      if (_recentTracks.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 32 : 20,
                            ),
                            child: _buildSectionTitle(
                              'RECENTLY ADDED',
                              onSeeAll: widget.onGoToLibrary,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        SliverToBoxAdapter(
                          child: _buildRecentlyAddedRail(isDesktop),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 36)),
                      ],

                      // Album Spotlight
                      if (_spotlightTrack != null) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 32 : 20,
                            ),
                            child: _buildAlbumSpotlight(isDesktop),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 36)),
                      ],

                      // Smart Mixes
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 32 : 20,
                          ),
                          child: _buildSmartMixes(),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 80)),
                    ],
                  ),
      ),
    );
  }

  Widget _buildHeader(int totalTracks) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MOBIUS',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: MobiusColors.nativeOf(context),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Local Library • $totalTracks tracks',
                  style: TextStyle(
                    color: MobiusColors.textDimOf(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        const Spacer(),
        IconButton.filled(
          onPressed: _addMusicFolder,
          icon: const Icon(Icons.create_new_folder_outlined, size: 20),
          tooltip: 'Add Music Folder',
          style: IconButton.styleFrom(
            backgroundColor: MobiusColors.accentOf(context).withValues(alpha: 0.15),
            foregroundColor: MobiusColors.accentOf(context),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: MobiusColors.panelOf(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.music_off_rounded,
                size: 56,
                color: MobiusColors.textDimOf(context),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your Library is Empty',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a folder with your music files to start listening bit-perfect offline.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MobiusColors.textDimOf(context),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _addMusicFolder,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Add Music Folder'),
              style: FilledButton.styleFrom(
                backgroundColor: MobiusColors.accentOf(context),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJumpBackIn() {
    final currentId = widget.playerController.currentTrackId;
    TrackMetadata? playingMeta;
    if (currentId > 0) {
      try {
        playingMeta = widget.repository.getTrackMetadata(currentId);
      } catch (_) {}
    }

    final isPlaying =
        widget.playerController.state == OfflinePlayerState.playing;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MobiusColors.panelOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MobiusColors.borderOf(context)),
      ),
      child: Row(
        children: [
          // Cover artwork or placeholder
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 58,
              height: 58,
              child: playingMeta != null
                  ? GroupArtwork(
                      repository: widget.repository,
                      source: GroupArtworkSource([playingMeta.trackId]),
                      decodeSize: 120,
                      filterQuality: FilterQuality.medium,
                      placeholder: _buildCoverPlaceholder(),
                    )
                  : _buildCoverPlaceholder(),
            ),
          ),
          const SizedBox(width: 16),

          // Track info or prompt
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  playingMeta != null ? 'NOW PLAYING' : 'READY TO PLAY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: MobiusColors.accentOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  playingMeta != null
                      ? playingMeta.title
                      : 'Shuffle Your Collection',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  playingMeta != null
                      ? playingMeta.artist
                      : 'Bit-perfect audio playback',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: MobiusColors.textDimOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Play / Pause Button
          IconButton.filled(
            onPressed: () {
              if (playingMeta != null) {
                if (isPlaying) {
                  widget.playerController.pause();
                } else {
                  widget.playerController.play();
                }
              } else {
                _shuffleAll();
              }
            },
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 28,
            ),
            style: IconButton.styleFrom(
              backgroundColor: MobiusColors.accentOf(context),
              foregroundColor: MobiusColors.onAccentOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {VoidCallback? onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: MobiusColors.textDimOf(context),
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Text(
              'See All',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MobiusColors.accentOf(context),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentlyAddedRail(bool isDesktop) {
    final itemWidth = isDesktop ? 160.0 : 130.0;
    final itemHeight = isDesktop ? 220.0 : 185.0;

    return SizedBox(
      height: itemHeight,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 20),
        scrollDirection: Axis.horizontal,
        itemCount: _recentTracks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final track = _recentTracks[index];
          return SizedBox(
            width: itemWidth,
            child: InkWell(
              onTap: () => _playTrack(track),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: GroupArtwork(
                        repository: widget.repository,
                        source: GroupArtworkSource([track.trackId]),
                        decodeSize: 220,
                        filterQuality: FilterQuality.medium,
                        placeholder: _buildCoverPlaceholder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: MobiusColors.textDimOf(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlbumSpotlight(bool isDesktop) {
    final track = _spotlightTrack!;
    final albumTracks = _albumsMap[track.album] ?? [track];

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MobiusColors.panelOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MobiusColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: isDesktop ? 120 : 90,
              height: isDesktop ? 120 : 90,
              child: GroupArtwork(
                repository: widget.repository,
                source: GroupArtworkSource([track.trackId]),
                decodeSize: 240,
                filterQuality: FilterQuality.medium,
                placeholder: _buildCoverPlaceholder(),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: MobiusColors.accentOf(context).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ALBUM SPOTLIGHT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: MobiusColors.accentOf(context),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  track.album.isNotEmpty ? track.album : track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${track.artist} • ${albumTracks.length} tracks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: MobiusColors.textDimOf(context),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    final ids = albumTracks.map((t) => t.trackId).toList();
                    widget.playerController.setQueueAndPlay(ids, 0);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Play Album'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MobiusColors.accentOf(context),
                    foregroundColor: MobiusColors.onAccentOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartMixes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('SMART MIXES'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MixCard(
                icon: Icons.shuffle_rounded,
                title: 'Shuffle All',
                subtitle: 'Entire library',
                color: MobiusColors.accentOf(context),
                onTap: _shuffleAll,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _MixCard(
                icon: Icons.star_rounded,
                title: 'Favorites',
                subtitle: 'Your starred tracks',
                color: MobiusColors.compatibleOf(context),
                onTap: widget.onGoToLibrary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      color: MobiusColors.panelOf(context),
      child: Icon(
        Icons.album_rounded,
        color: MobiusColors.textDimOf(context).withValues(alpha: 0.3),
        size: 32,
      ),
    );
  }
}

class _MixCard extends StatelessWidget {
  const _MixCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MobiusColors.panelOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MobiusColors.borderOf(context)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: MobiusColors.textDimOf(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
