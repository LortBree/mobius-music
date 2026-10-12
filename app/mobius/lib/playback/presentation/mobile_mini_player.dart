import 'dart:async';
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
/// Mobile controls are deliberately limited to loop · favorite · play/pause;
/// horizontal swipes move to the previous or next track.
class MobileMiniPlayer extends StatefulWidget {
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
    this.onPrevious,
    this.onNext,
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
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<MobileMiniPlayer> createState() => _MobileMiniPlayerState();
}

class _MobileMiniPlayerState extends State<MobileMiniPlayer> {
  double _dragFactor = 0;
  bool _isDragging = false;
  int _lastSwipeDirection = -1;

  void _finishDrag(DragEndDetails details, double width) {
    final threshold = (width * 0.16).clamp(48.0, 72.0);
    final distance = _dragFactor * width;
    final velocity = details.primaryVelocity ?? 0;
    final flick = velocity.abs() >= 480 && distance.abs() >= 12;
    final shouldSkip = distance.abs() >= threshold || flick;
    final direction = distance.abs() >= threshold
        ? distance.sign.toInt()
        : flick
        ? velocity.sign.toInt()
        : 0;

    setState(() {
      _isDragging = false;
      _dragFactor = 0;
      if (shouldSkip && direction != 0) _lastSwipeDirection = direction;
    });

    if (!shouldSkip || direction == 0) return;
    if (direction < 0) {
      widget.onNext?.call();
    } else {
      widget.onPrevious?.call();
    }
  }

  void _cancelDrag() {
    setState(() {
      _isDragging = false;
      _dragFactor = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = MobiusSurfaces.of(context);
    final track = widget.track;
    if (track == null) {
      return const SizedBox.shrink();
    }

    final repeatActive = widget.repeatMode != OfflinePlayerRepeatMode.off;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _isDragging = true),
          onHorizontalDragUpdate: (details) {
            setState(() {
              _dragFactor = (_dragFactor + details.delta.dx / width * 0.78)
                  .clamp(-0.17, 0.17);
            });
          },
          onHorizontalDragEnd: (details) => _finishDrag(details, width),
          onHorizontalDragCancel: _cancelDrag,
          child: AnimatedSlide(
            offset: Offset(_dragFactor, 0),
            duration: _isDragging
                ? Duration.zero
                : const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: colors.miniPlayer.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colors.border.withValues(alpha: 0.4),
                    ),
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
                                onTap: widget.onOpenNowPlaying,
                                borderRadius: BorderRadius.circular(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        transitionBuilder: (child, animation) {
                                          final position =
                                              Tween<Offset>(
                                                begin: Offset(
                                                  -_lastSwipeDirection * 0.12,
                                                  0,
                                                ),
                                                end: Offset.zero,
                                              ).animate(
                                                CurvedAnimation(
                                                  parent: animation,
                                                  curve: Curves.easeOutCubic,
                                                ),
                                              );
                                          return FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position: position,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Row(
                                          key: ValueKey(track.trackId),
                                          children: [
                                            _MiniPlayerArtwork(
                                              artwork: widget.artwork,
                                              colors: colors,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _RunningMiniPlayerTitle(
                                                    text: track.title.isEmpty
                                                        ? 'Unknown title'
                                                        : track.title,
                                                    style: TextStyle(
                                                      color: colors.textPrimary,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    track.artist.isEmpty
                                                        ? 'Unknown artist'
                                                        : track.artist,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color:
                                                          colors.textSecondary,
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
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: _repeatLabel(),
                              onPressed: widget.onToggleRepeat,
                              icon: Icon(_repeatIcon()),
                              iconSize: 20,
                              color: repeatActive
                                  ? colors.accentLight
                                  : colors.textSecondary,
                            ),
                            IconButton(
                              tooltip: widget.isFavorite
                                  ? 'Remove from Favorites'
                                  : 'Add to Favorites',
                              onPressed: widget.onToggleFavorite,
                              icon: Icon(
                                widget.isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                              ),
                              iconSize: 20,
                              color: widget.isFavorite
                                  ? colors.accentLight
                                  : colors.textSecondary,
                            ),
                            const SizedBox(width: 2),
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: FilledButton(
                                onPressed: widget.onPlayPause,
                                style: FilledButton.styleFrom(
                                  backgroundColor: colors.accent,
                                  foregroundColor: colors.onAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Icon(
                                  widget.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
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
                          valueListenable: widget.position,
                          builder: (context, current, _) {
                            final progress = (widget.duration > 0)
                                ? (current / widget.duration).clamp(0.0, 1.0)
                                : 0.0;
                            return SizedBox(
                              height: 2.5,
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.transparent,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colors.accent,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _repeatLabel() {
    switch (widget.repeatMode) {
      case OfflinePlayerRepeatMode.off:
        return 'Repeat off';
      case OfflinePlayerRepeatMode.track:
        return 'Repeat one';
      case OfflinePlayerRepeatMode.queue:
        return 'Repeat queue';
    }
  }

  IconData _repeatIcon() {
    switch (widget.repeatMode) {
      case OfflinePlayerRepeatMode.off:
        return Icons.repeat_rounded;
      case OfflinePlayerRepeatMode.track:
        return Icons.repeat_one_rounded;
      case OfflinePlayerRepeatMode.queue:
        return Icons.repeat_rounded;
    }
  }
}

class _RunningMiniPlayerTitle extends StatelessWidget {
  const _RunningMiniPlayerTitle({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();

        if (painter.width <= constraints.maxWidth) {
          return Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        return _MiniPlayerMarquee(
          key: ValueKey(text),
          text: text,
          style: style,
          period: painter.width + 32,
        );
      },
    );
  }
}

class _MiniPlayerMarquee extends StatefulWidget {
  const _MiniPlayerMarquee({
    super.key,
    required this.text,
    required this.style,
    required this.period,
  });

  final String text;
  final TextStyle style;
  final double period;

  @override
  State<_MiniPlayerMarquee> createState() => _MiniPlayerMarqueeState();
}

class _MiniPlayerMarqueeState extends State<_MiniPlayerMarquee> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_animateLoop());
    });
  }

  Future<void> _animateLoop() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    while (mounted) {
      if (!_controller.hasClients) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      final target = widget.period.clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
      if (target <= 0) return;
      final duration = Duration(
        milliseconds: (target / 26 * 1000).round().clamp(1000, 12000),
      );
      await _controller.animateTo(
        target,
        duration: duration,
        curve: Curves.linear,
      );
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(0);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget titleCopy() =>
        Text(widget.text, maxLines: 1, softWrap: false, style: widget.style);

    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          titleCopy(),
          const SizedBox(width: 32),
          titleCopy(),
          const SizedBox(width: 32),
          titleCopy(),
        ],
      ),
    );
  }
}

/// Clean album cover without progress ring overlay.
class _MiniPlayerArtwork extends StatelessWidget {
  const _MiniPlayerArtwork({required this.artwork, required this.colors});

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
