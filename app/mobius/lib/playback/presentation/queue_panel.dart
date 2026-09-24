import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/ffi/offline_player.dart';
import '../../features/library/data/ffi_library_repository.dart';
import '../player_controller.dart';

class QueuePanel extends StatefulWidget {
  const QueuePanel({
    super.key,
    required this.repository,
    required this.playerController,
    required this.onTrackSelected,
    required this.onClose,
  });

  final FfiLibraryRepository repository;
  final PlayerController playerController;
  final VoidCallback onTrackSelected;
  final VoidCallback onClose;

  @override
  State<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<QueuePanel> {
  Timer? _queueTimer;
  List<int> _queueIds = const [];
  List<TrackMetadata> _queueTracks = const [];
  final Map<int, ImageProvider> _artworkCache = {};
  int _currentIndex = -1;
  int _upNextCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshQueue();
    _queueTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _refreshQueue(),
    );
  }

  @override
  void dispose() {
    _queueTimer?.cancel();
    super.dispose();
  }

  int _readCurrentIndex() {
    try {
      return widget.playerController.queueCurrentIndex;
    } catch (_) {
      return -1;
    }
  }

  void _refreshQueue() {
    try {
      final ids = widget.playerController.queueTrackIds;
      final currentIndex = _readCurrentIndex();
      final upNextCount = widget.playerController.queueUpNextCount;
      final idsChanged = ids.length != _queueIds.length ||
          ids.asMap().entries.any(
            (entry) => _queueIds[entry.key] != entry.value,
          );
      if (!idsChanged &&
          currentIndex == _currentIndex &&
          upNextCount == _upNextCount) {
        return;
      }

      final tracks = idsChanged
          ? ids.map(_metadataFor).toList(growable: false)
          : _queueTracks;
      if (!mounted) return;
      setState(() {
        _queueIds = ids;
        _queueTracks = tracks;
        _currentIndex = currentIndex;
        _upNextCount = upNextCount;
      });
    } catch (_) {
      // The player may not have an initialized queue yet.
    }
  }

  TrackMetadata _metadataFor(int trackId) {
    try {
      return widget.repository.getTrackMetadata(trackId);
    } catch (_) {
      return TrackMetadata(
        trackId: trackId,
        title: 'Unavailable track',
        artist: '',
        album: '',
        albumArtist: '',
        composer: '',
        date: '',
        genre: '',
        trackNumber: 0,
        discNumber: 0,
        hasDiscNumber: false,
      );
    }
  }

  ImageProvider? _artworkFor(int trackId) {
    final cached = _artworkCache[trackId];
    if (cached != null) return cached;
    try {
      final artwork = widget.repository.getTrackArtwork(trackId);
      if (artwork == null || artwork.isEmpty) return null;
      final image = ResizeImage(
        MemoryImage(artwork.data),
        width: 88,
        height: 88,
      );
      _artworkCache[trackId] = image;
      return image;
    } catch (_) {
      return null;
    }
  }

  void _selectTrack(int index) {
    try {
      widget.playerController.selectAndPlay(index);
      widget.onTrackSelected();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _reorderSegment(
    List<TrackMetadata> tracks,
    int start,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex--;
    final ids = tracks.map((track) => track.trackId).toList();
    final trackId = ids.removeAt(oldIndex);
    ids.insert(newIndex, trackId);
    try {
      widget.playerController.reorderQueueSegment(start, ids);
      _refreshQueue();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Widget _sectionLabel(String title, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFEDEDED),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: const TextStyle(
                color: Color(0xFF9A9A9A),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFF85818D), fontSize: 12),
    ),
  );

  Widget _trackTile(
    TrackMetadata track, {
    required int queueIndex,
    required int dragIndex,
    required bool isCurrent,
    required bool reorderable,
  }) {
    final artwork = _artworkFor(track.trackId);
    return Material(
      key: ValueKey('queue-${track.trackId}-$queueIndex'),
      color: isCurrent ? const Color(0xFF30263C) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _selectTrack(queueIndex),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox.square(
                  dimension: 44,
                  child: artwork == null
                      ? const ColoredBox(
                          color: Color(0xFF292631),
                          child: Icon(
                            Icons.music_note_rounded,
                            color: Color(0xFF9A9A9A),
                            size: 20,
                          ),
                        )
                      : Image(
                          image: artwork,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title.trim().isEmpty ? 'Unknown title' : track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent
                            ? const Color(0xFFC4A8F0)
                            : const Color(0xFFEDEDED),
                        fontSize: 12,
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
                        color: Color(0xFF9A9A9A),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (reorderable)
                ReorderableDragStartListener(
                  index: dragIndex,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 18,
                      color: Color(0xFF9A9A9A),
                    ),
                  ),
                )
              else if (isCurrent)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.equalizer_rounded,
                    size: 17,
                    color: Color(0xFFB58AF4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrent = _currentIndex >= 0 && _currentIndex < _queueTracks.length;
    final upcomingStart = hasCurrent ? (_currentIndex + 1).toInt() : 0;
    final upcomingTracks = _queueTracks.sublist(upcomingStart);
    final currentTrack = hasCurrent ? _queueTracks[_currentIndex] : null;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(left: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Queue',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEDEDED),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_queueTracks.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9A9A9A),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close queue',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF2A2A2A), height: 1),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _sectionLabel('Now playing'),
                    ),
                    if (currentTrack != null)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        sliver: SliverToBoxAdapter(
                          child: _trackTile(
                            currentTrack,
                            queueIndex: _currentIndex,
                            dragIndex: 0,
                            isCurrent: true,
                            reorderable: false,
                          ),
                        ),
                      )
                    else
                      SliverToBoxAdapter(
                        child: _emptyHint('Nothing is playing.'),
                      ),
                    SliverToBoxAdapter(
                      child: _sectionLabel(
                        'Up next',
                        trailing: _upNextCount == 0
                            ? '${upcomingTracks.length}'
                            : '$_upNextCount added first',
                      ),
                    ),
                    if (upcomingTracks.isEmpty)
                      SliverToBoxAdapter(
                        child: _emptyHint('No more tracks in this queue.'),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        sliver: SliverReorderableList(
                          itemCount: upcomingTracks.length,
                          onReorder: (oldIndex, newIndex) => _reorderSegment(
                            upcomingTracks,
                            upcomingStart,
                            oldIndex,
                            newIndex,
                          ),
                          itemBuilder: (context, index) => _trackTile(
                            upcomingTracks[index],
                            queueIndex: upcomingStart + index,
                            dragIndex: index,
                            isCurrent: false,
                            reorderable: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
