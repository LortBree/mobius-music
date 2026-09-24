import 'package:flutter/material.dart';

import '../../../core/ffi/offline_player.dart';
import '../../../playback/player_controller.dart';
import '../data/user_collections.dart';

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
  final String? removeLabel;
  final Future<void> Function()? onRemove;
  final VoidCallback? onChanged;
  final VoidCallback? onGoToArtist;
  final VoidCallback? onGoToAlbum;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapDown: (details) => _showMenu(context, details.globalPosition),
    child: child,
  );

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final bounds = RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
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
          await _showSleepOptions(context, bounds);
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
