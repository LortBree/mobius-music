import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/mobius_theme.dart';
import '../../core/ffi/offline_player.dart';

/// The compact mobile transport bar, shown above the bottom navigation when a
/// track is loaded.
///
/// Pure presentation (like [MiniPlayer]): every value comes in from the owner
/// (the shell) and every interaction goes back out through a callback, so the
/// shell stays the only owner of player state. Only the thin progress line
/// listens to [position], so the 200 ms position ticks do not rebuild the
/// rest of the bar.
///
/// Mobile controls are deliberately limited to loop · favorite · play/pause.
/// There is NO prev/next, NO seek handle and NO add-to-playlist/queue — those
/// live on the Now Playing screen on mobile. Trade-off (the user's explicit
/// choice): track skipping is only via Now Playing or the track list.
class MobileMiniPlayer extends StatelessWidget {
  const MobileMiniPlayer({
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
    required this.onToggleRepeat,
    required this.onToggleFavorite,
    required this.onPlayPause,
  });

  final double height;
  final TrackMetadata? track;
  final ImageProvider? artwork;
  final ValueListenable<double> position;

  /// Track duration in seconds; `<= 0` means unknown (progress line hidden).
  final double duration;
  final bool isPlaying;
  final bool isFavorite;
  final OfflinePlayerRepeatMode repeatMode;

  final VoidCallback onOpenNowPlaying;
  final VoidCallback onToggleRepeat;
  final VoidCallback onToggleFavorite;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    final colors = MobiusSurfaces.of(context);
    final track = this.track;
    if (track == null) {
      return const SizedBox.shrink();
    }

    final repeatActive = repeatMode != OfflinePlayerRepeatMode.off;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: colors.miniPlayer.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border.withValues(alpha: 0.4)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpenNowPlaying,
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        _MiniPlayerArtwork(
                          artwork: artwork,
                          colors: colors,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title.isEmpty ? 'Unknown title' : track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track.artist.isEmpty
                                    ? 'Unknown artist'
                                    : track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _repeatLabel(),
                  onPressed: onToggleRepeat,
                  icon: Icon(_repeatIcon()),
                  iconSize: 20,
                  color: repeatActive ? colors.accentLight : colors.textSecondary,
                ),
                IconButton(
                  tooltip: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                  ),
                  iconSize: 20,
                  color: isFavorite ? colors.accentLight : colors.textSecondary,
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: FilledButton(
                    onPressed: onPlayPause,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.onAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: position,
              builder: (context, current, _) {
                final progress = (duration > 0)
                    ? (current / duration).clamp(0.0, 1.0)
                    : 0.0;
                return SizedBox(
                  height: 2.5,
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  ),
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

/// Clean album cover without progress ring overlay.
class _MiniPlayerArtwork extends StatelessWidget {
  const _MiniPlayerArtwork({
    required this.artwork,
    required this.colors,
  });

  final ImageProvider? artwork;
  final MobiusSurfaces colors;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: Icon(
        Icons.music_note_rounded,
        size: 20,
        color: colors.textSecondary,
      ),
    );

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: colors.border.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: artwork != null
          ? Image(
              image: artwork!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => placeholder,
            )
          : placeholder,
    );
  }
}
