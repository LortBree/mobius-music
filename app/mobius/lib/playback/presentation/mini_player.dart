import 'dart:ui' as ui;
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
    this.onOpenLyrics,
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
  final VoidCallback? onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    final colors = MobiusSurfaces.of(context);

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: colors.miniPlayer.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colors.border.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(flex: 3, child: _buildTrackInfo(colors)),
                const SizedBox(width: 12),
                Expanded(flex: 5, child: _buildTransport(colors)),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: _buildTrailingActions(colors)),
              ],
            ),
          ),
        ),
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
              iconSize: 25,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
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
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Next',
              onPressed: hasTrack ? onNext : null,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 25,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
            onPressed: hasTrack ? onToggleFavorite : null,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
            iconSize: 20,
            color: isFavorite ? colors.accentLight : colors.textSecondary,
          ),
          IconButton(
            tooltip: 'Add to playlist',
            onPressed: hasTrack ? onAddToPlaylist : null,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: const Icon(Icons.playlist_add_rounded),
            iconSize: 21,
            color: colors.textSecondary,
          ),
          IconButton(
            tooltip: _repeatLabel(),
            onPressed: hasTrack ? onToggleRepeat : null,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: Icon(_repeatIcon()),
            iconSize: 20,
            color: repeatActive ? colors.accentLight : colors.textSecondary,
          ),
          IconButton(
            tooltip: 'Queue',
            onPressed: hasTrack ? onOpenQueue : null,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            icon: const Icon(Icons.queue_music_rounded),
            iconSize: 21,
            color: colors.textSecondary,
          ),
          if (onOpenLyrics != null)
            IconButton(
              tooltip: 'Lyrics',
              onPressed: hasTrack ? onOpenLyrics : null,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: const Icon(Icons.lyrics_rounded),
              iconSize: 20,
              color: colors.textSecondary,
            ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(10),
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
