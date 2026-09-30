import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/mobius_theme.dart';
import '../../core/ffi/offline_player.dart';
import '../playback_time_format.dart';
import 'mini_seek_bar.dart';

/// The bottom transport bar.
///
/// Pure presentation: every value comes in from the owner and every
/// interaction goes back out through a callback, so the shell stays the only
/// owner of player state. Only the seek bar listens to [position], so the
/// 200 ms position ticks do not rebuild the rest of the bar.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.height,
    required this.track,
    required this.artwork,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isFavorite,
    required this.repeatMode,
    required this.onOpenNowPlaying,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    required this.onSeekPreview,
    required this.onSeek,
    required this.onToggleFavorite,
    required this.onAddToPlaylist,
    required this.onToggleRepeat,
    required this.onOpenQueue,
  });

  final double height;
  final TrackMetadata? track;
  final ImageProvider? artwork;
  final ValueListenable<double> position;

  /// Track duration in seconds; `<= 0` means unknown and disables seeking.
  final double duration;
  final bool isPlaying;
  final bool isFavorite;
  final OfflinePlayerRepeatMode repeatMode;

  final VoidCallback onOpenNowPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final ValueChanged<double> onSeekPreview;
  final ValueChanged<double> onSeek;
  final VoidCallback onToggleFavorite;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onToggleRepeat;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final colors = MobiusSurfaces.of(context);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.miniPlayer,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: _buildTrackInfo(colors)),
          const SizedBox(width: 20),
          Expanded(flex: 5, child: _buildTransport(colors)),
          const SizedBox(width: 20),
          Expanded(flex: 3, child: _buildTrailingActions(colors)),
        ],
      ),
    );
  }

  Widget _buildTrackInfo(MobiusSurfaces colors) {
    final track = this.track;

    return InkWell(
      onTap: track == null ? null : onOpenNowPlaying,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          _buildArtwork(colors),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track?.artist ?? 'Select a track',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransport(MobiusSurfaces colors) {
    final hasTrack = track != null;
    final maxDuration = duration > 0 ? duration : 1.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Previous',
              onPressed: hasTrack ? onPrevious : null,
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: 27,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 48,
              height: 48,
              child: FilledButton(
                onPressed: hasTrack ? onPlayPause : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.onAccent,
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Next',
              onPressed: hasTrack ? onNext : null,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 27,
            ),
          ],
        ),
        const SizedBox(height: 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ValueListenableBuilder<double>(
            valueListenable: position,
            builder: (context, value, _) => MiniSeekBar(
              position: value.clamp(0.0, maxDuration).toDouble(),
              duration: maxDuration,
              enabled: duration > 0,
              formatTime: formatPlaybackTime,
              onChanged: onSeekPreview,
              onChangeEnd: onSeek,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrailingActions(MobiusSurfaces colors) {
    final hasTrack = track != null;
    final repeatActive = repeatMode != OfflinePlayerRepeatMode.off;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
          onPressed: hasTrack ? onToggleFavorite : null,
          icon: Icon(
            isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
          iconSize: 21,
          color: isFavorite ? colors.accentLight : colors.textSecondary,
        ),
        IconButton(
          tooltip: 'Add to playlist',
          onPressed: hasTrack ? onAddToPlaylist : null,
          icon: const Icon(Icons.playlist_add_rounded),
          iconSize: 22,
          color: colors.textSecondary,
        ),
        IconButton(
          tooltip: _repeatLabel(),
          onPressed: hasTrack ? onToggleRepeat : null,
          icon: Icon(_repeatIcon()),
          iconSize: 22,
          color: repeatActive ? colors.accentLight : colors.textSecondary,
        ),
        IconButton(
          tooltip: 'Queue',
          onPressed: hasTrack ? onOpenQueue : null,
          icon: const Icon(Icons.queue_music_rounded),
          iconSize: 22,
          color: colors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildArtwork(MobiusSurfaces colors) {
    final placeholder = Center(
      child: Icon(
        Icons.music_note_rounded,
        size: 26,
        color: colors.textSecondary,
      ),
    );
    final artwork = this.artwork;

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: colors.border,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: artwork != null
          ? Image(
              image: artwork,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => placeholder,
            )
          : placeholder,
    );
  }

  String _repeatLabel() {
    switch (repeatMode) {
      case OfflinePlayerRepeatMode.off:
        return 'Repeat off';
      case OfflinePlayerRepeatMode.track:
        return 'Repeat one';
      case OfflinePlayerRepeatMode.queue:
        return 'Repeat queue';
    }
  }

  IconData _repeatIcon() {
    switch (repeatMode) {
      case OfflinePlayerRepeatMode.off:
        return Icons.repeat_rounded;
      case OfflinePlayerRepeatMode.track:
        return Icons.repeat_one_rounded;
      case OfflinePlayerRepeatMode.queue:
        return Icons.repeat_rounded;
    }
  }
}
