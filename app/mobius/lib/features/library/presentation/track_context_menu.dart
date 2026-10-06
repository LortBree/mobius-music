import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/player_shell_state.dart' show kMobileBreakpoint;
import '../../../app/theme/colors.dart';
import '../../../core/ffi/offline_player.dart';
import '../../../playback/player_controller.dart';
import '../data/ffi_library_repository.dart';
import '../data/user_collections.dart';
import 'group_artwork.dart';

String trackArtistName(TrackMetadata track) {
  final albumArtist = track.albumArtist.trim();
  return albumArtist.isEmpty ? track.artist.trim() : albumArtist;
}

class TrackContextMenu extends StatelessWidget {
  const TrackContextMenu({
    super.key,
    required this.track,
    required this.collections,
    required this.playerController,
    required this.child,
    this.repository,
    this.removeLabel,
    this.onRemove,
    this.onChanged,
    this.onGoToArtist,
    this.onGoToAlbum,
  });

  final TrackMetadata track;
  final UserCollections collections;
  final PlayerController playerController;
  final Widget child;
  final FfiLibraryRepository? repository;
  final String? removeLabel;
  final Future<void> Function()? onRemove;
  final VoidCallback? onChanged;
  final VoidCallback? onGoToArtist;
  final VoidCallback? onGoToAlbum;

  static Future<void> showForTrack({
    required BuildContext context,
    required Offset position,
    required TrackMetadata track,
    required UserCollections collections,
    required PlayerController playerController,
    FfiLibraryRepository? repository,
    String? removeLabel,
    Future<void> Function()? onRemove,
    VoidCallback? onChanged,
    VoidCallback? onGoToArtist,
    VoidCallback? onGoToAlbum,
  }) async {
    final menu = TrackContextMenu(
      track: track,
      collections: collections,
      playerController: playerController,
      repository: repository,
      removeLabel: removeLabel,
      onRemove: onRemove,
      onChanged: onChanged,
      onGoToArtist: onGoToArtist,
      onGoToAlbum: onGoToAlbum,
      child: const SizedBox.shrink(),
    );
    await menu._showMenu(context, position);
  }

  @override
  Widget build(BuildContext context) {
    final gestureChild = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) => _showMenu(context, details.globalPosition),
      child: child,
    );

    return SwipeableQueueTrack(
      track: track,
      playerController: playerController,
      child: gestureChild,
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    final String? action;
    RelativeRect? bounds;

    if (isMobile) {
      action = await _showMobileBottomSheet(context);
    } else {
      final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
      bounds = RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      );
      action = await showMenu<String>(
        context: context,
        position: bounds,
        items: [
          if (removeLabel != null && onRemove != null)
            PopupMenuItem(
              value: 'remove',
              child: _MenuLabel(Icons.remove_circle_outline, removeLabel!),
            ),
          const PopupMenuItem(
            value: 'playlist',
            child: _MenuLabel(Icons.playlist_add_rounded, 'Add to playlist'),
          ),
          const PopupMenuItem(
            value: 'queue',
            child: _MenuLabel(Icons.queue_music_rounded, 'Add to queue'),
          ),
          const PopupMenuItem(
            value: 'sleep',
            child: _MenuLabel(Icons.timer_outlined, 'Sleep timer'),
          ),
          if (onGoToArtist != null)
            const PopupMenuItem(
              value: 'artist',
              child: _MenuLabel(Icons.person_outline_rounded, 'Go to artist'),
            ),
          if (onGoToAlbum != null)
            const PopupMenuItem(
              value: 'album',
              child: _MenuLabel(Icons.album_outlined, 'Go to album'),
            ),
          const PopupMenuItem(
            value: 'metadata',
            child: _MenuLabel(Icons.info_outline_rounded, 'View metadata'),
          ),
        ],
      );
    }
    if (!context.mounted || action == null) return;

    try {
      switch (action) {
        case 'remove':
          await onRemove?.call();
          break;
        case 'playlist':
          await _addToPlaylist(context);
          break;
        case 'queue':
          playerController.addToQueue(track.trackId);
          _showNotice(context, 'Added to queue.');
          break;
        case 'sleep':
          if (isMobile) {
            await _showSleepBottomSheet(context);
          } else if (bounds != null) {
            await _showSleepOptions(context, bounds);
          }
          break;
        case 'artist':
          onGoToArtist?.call();
          break;
        case 'album':
          onGoToAlbum?.call();
          break;
        case 'metadata':
          await _showMetadata(context);
          break;
      }
    } catch (error) {
      if (context.mounted) _showNotice(context, error.toString());
    }
  }

  Future<String?> _showMobileBottomSheet(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: MobiusColors.panelOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: MobiusColors.borderOf(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: repository != null
                          ? GroupArtwork(
                              repository: repository!,
                              source: GroupArtworkSource([track.trackId]),
                              decodeSize: 104,
                              filterQuality: FilterQuality.medium,
                              placeholder: Center(
                                child: Icon(
                                  Icons.music_note_rounded,
                                  color: MobiusColors.textDimOf(context),
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                Icons.music_note_rounded,
                                color: MobiusColors.textDimOf(context),
                              ),
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title.isEmpty ? 'Unknown title' : track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: MobiusColors.textOf(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            trackArtistName(track).isEmpty
                                ? 'Unknown artist'
                                : trackArtistName(track),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: MobiusColors.textDimOf(context),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: MobiusColors.borderOf(context)),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Add to playlist'),
                onTap: () => Navigator.pop(bottomSheetContext, 'playlist'),
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: const Text('Add to queue'),
                onTap: () => Navigator.pop(bottomSheetContext, 'queue'),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Sleep timer'),
                onTap: () => Navigator.pop(bottomSheetContext, 'sleep'),
              ),
              if (onGoToArtist != null)
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Go to artist'),
                  onTap: () => Navigator.pop(bottomSheetContext, 'artist'),
                ),
              if (onGoToAlbum != null)
                ListTile(
                  leading: const Icon(Icons.album_outlined),
                  title: const Text('Go to album'),
                  onTap: () => Navigator.pop(bottomSheetContext, 'album'),
                ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('View metadata'),
                onTap: () => Navigator.pop(bottomSheetContext, 'metadata'),
              ),
              if (removeLabel != null && onRemove != null)
                ListTile(
                  leading: Icon(
                    Icons.remove_circle_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    removeLabel!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  onTap: () => Navigator.pop(bottomSheetContext, 'remove'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSleepBottomSheet(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: MobiusColors.panelOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 14),
            Text(
              'Sleep Timer',
              style: TextStyle(
                color: MobiusColors.textOf(context),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in const [
              ('5', '5 minutes'),
              ('10', '10 minutes'),
              ('15', '15 minutes'),
              ('30', '30 minutes'),
              ('60', '1 hour'),
              ('end', 'End of track'),
              ('cancel', 'Cancel sleep timer'),
            ])
              ListTile(
                title: Text(entry.$2),
                onTap: () => Navigator.pop(ctx, entry.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    _handleSleepChoice(context, choice);
  }

  void _handleSleepChoice(BuildContext context, String choice) {
    if (choice == 'end') {
      playerController.sleepAtEndOfTrack();
      _showNotice(context, 'Playback will stop at the end of this track.');
    } else if (choice == 'cancel') {
      playerController.cancelSleepTimer();
      _showNotice(context, 'Sleep timer cancelled.');
    } else {
      playerController.setSleepTimer(Duration(minutes: int.parse(choice)));
      _showNotice(context, 'Sleep timer set for $choice minutes.');
    }
  }

  Future<void> _addToPlaylist(BuildContext context) async {
    final playlists = await collections.playlists();
    if (!context.mounted) return;
    final search = TextEditingController();
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = search.text.trim().toLowerCase();
          final names = playlists.keys
              .where((name) => name.toLowerCase().contains(query))
              .toList();
          return AlertDialog(
            title: const Text('Add to playlist'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Find a playlist',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.add_rounded),
                          title: const Text('New playlist'),
                          onTap: () => Navigator.pop(dialogContext, '\u0000new'),
                        ),
                        for (final name in names)
                          ListTile(
                            leading: const Icon(Icons.queue_music_rounded),
                            title: Text(name),
                            subtitle: Text('${playlists[name]!.length} songs'),
                            onTap: () => Navigator.pop(dialogContext, name),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    search.dispose();
    if (selected == null || !context.mounted) return;

    var playlistName = selected;
    if (selected == '\u0000new') {
      final nameController = TextEditingController();
      final newPlaylistName = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Create playlist'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Playlist name'),
            onSubmitted: (name) => Navigator.pop(dialogContext, name.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                nameController.text.trim(),
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      nameController.dispose();
      if (newPlaylistName == null || newPlaylistName.trim().isEmpty) return;
      playlistName = newPlaylistName;
      await collections.createPlaylist(playlistName);
    }

    await collections.addToPlaylist(playlistName, track.trackId);
    onChanged?.call();
    if (context.mounted) _showNotice(context, 'Added to $playlistName.');
  }

  Future<void> _showSleepOptions(
    BuildContext context,
    RelativeRect position,
  ) async {
    final choice = await showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(value: '5', child: Text('5 minutes')),
        PopupMenuItem(value: '10', child: Text('10 minutes')),
        PopupMenuItem(value: '15', child: Text('15 minutes')),
        PopupMenuItem(value: '30', child: Text('30 minutes')),
        PopupMenuItem(value: '60', child: Text('1 hour')),
        PopupMenuItem(value: 'end', child: Text('End of track')),
        PopupMenuItem(value: 'cancel', child: Text('Cancel sleep timer')),
      ],
    );
    if (choice == null || !context.mounted) return;
    _handleSleepChoice(context, choice);
  }

  Future<void> _showMetadata(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(track.title.isEmpty ? 'Track metadata' : track.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MetadataLine('Artist', track.artist),
              _MetadataLine('Album', track.album),
              _MetadataLine('Album artist', track.albumArtist),
              _MetadataLine('Composer', track.composer),
              _MetadataLine('Date', track.date),
              _MetadataLine('Genre', track.genre),
              if (track.trackNumber > 0)
                _MetadataLine('Track number', '${track.trackNumber}'),
              if (track.hasDiscNumber)
                _MetadataLine('Disc number', '${track.discNumber}'),
              _MetadataLine('Track ID', '${track.trackId}'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  void _showNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 12),
      Text(label),
    ],
  );
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(child: Text(value.isEmpty ? '—' : value)),
      ],
    ),
  );
}

/// Wraps a track row with an authentic Spotify-like swipe/slide-to-queue gesture.
///
/// Swiping the track from left to right reveals an interactive "Add to queue"
/// accent panel with haptic feedback when the activation threshold is crossed.
/// On release, the track is appended to the playback queue and smoothly springs
/// back into place without dismissing or deleting the row from the list.
class SwipeableQueueTrack extends StatefulWidget {
  const SwipeableQueueTrack({
    super.key,
    required this.track,
    required this.playerController,
    required this.child,
    this.onQueued,
  });

  final TrackMetadata track;
  final PlayerController playerController;
  final Widget child;
  final VoidCallback? onQueued;

  @override
  State<SwipeableQueueTrack> createState() => _SwipeableQueueTrackState();
}

class _SwipeableQueueTrackState extends State<SwipeableQueueTrack> {
  bool _thresholdReached = false;
  double _dragProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    final accent = MobiusColors.accentOf(context);
    final isSwiping = _dragProgress > 0.02;

    return Dismissible(
      key: ValueKey('swipe-queue-${widget.key ?? widget.track.trackId}'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.28,
      },
      onUpdate: (details) {
        final progress = details.progress;
        final reached = details.reached;
        if (progress != _dragProgress || reached != _thresholdReached) {
          setState(() {
            _dragProgress = progress;
            if (reached && !_thresholdReached) {
              _thresholdReached = true;
              HapticFeedback.mediumImpact();
            } else if (!reached && _thresholdReached) {
              _thresholdReached = false;
            }
          });
        }
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          widget.playerController.addToQueue(widget.track.trackId);
          HapticFeedback.lightImpact();
          widget.onQueued?.call();
          if (context.mounted) {
            final title = widget.track.title.trim().isEmpty ? 'Track' : widget.track.title.trim();
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.queue_music_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Added to queue: $title',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          }
        }
        setState(() {
          _thresholdReached = false;
          _dragProgress = 0.0;
        });
        return false; // Crucial: smoothly springs back into the list
      },
      background: isSwiping
          ? Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: _thresholdReached
                    ? accent
                    : accent.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(8),
              ),
              child: AnimatedScale(
                scale: _thresholdReached ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.queue_music_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Add to queue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
      child: Material(
        color: isSwiping ? MobiusColors.backgroundOf(context) : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}
