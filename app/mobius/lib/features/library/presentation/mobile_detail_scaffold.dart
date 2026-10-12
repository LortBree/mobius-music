import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../../../app/theme/mobius_theme.dart';
import '../../../app/widgets/animated_mobius_background.dart';
import '../data/ffi_library_repository.dart';
import '../../../core/ffi/offline_player.dart';
import 'track_list_row.dart' show currentTrackRowColor;

PageRoute<T> mobileDetailRoute<T>({required WidgetBuilder builder}) =>
    PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slide = animation.drive(
          Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
        );
        final fade = animation.drive(
          Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeOut)),
        );
        return SlideTransition(
          position: slide,
          child: FadeTransition(
            opacity: fade,
            child: child,
          ),
        );
      },
    );

/// Resolves metadata in small groups so opening a detail route can paint its
/// first frame before touching every track through the synchronous FFI API.
Future<void> loadTrackMetadataInBatches({
  required LibraryRepository repository,
  required List<int> trackIds,
  required void Function(List<TrackMetadata> batch, bool isComplete) onBatch,
  required bool Function() isActive,
  int batchSize = 16,
}) async {
  if (!isActive()) return;
  for (var start = 0; start < trackIds.length; start += batchSize) {
    if (!isActive()) return;
    final end = (start + batchSize).clamp(0, trackIds.length);
    final batch = <TrackMetadata>[];
    for (var index = start; index < end; index++) {
      try {
        batch.add(repository.getTrackMetadata(trackIds[index]));
      } catch (_) {}
    }
    onBatch(batch, end == trackIds.length);
    if (end < trackIds.length) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }
  if (trackIds.isEmpty && isActive()) onBatch(const [], true);
}

/// Detail-page top bar with a title that appears once its track list scrolls.
class MobileDetailScaffold extends StatefulWidget {
  const MobileDetailScaffold({
    super.key,
    required this.title,
    required this.bodyBuilder,
    this.onBack,
  });

  final String title;
  final Widget Function(ValueListenable<bool> isCollapsed) bodyBuilder;
  final VoidCallback? onBack;

  @override
  State<MobileDetailScaffold> createState() => _MobileDetailScaffoldState();
}

class _MobileDetailScaffoldState extends State<MobileDetailScaffold> {
  final ValueNotifier<bool> _isCollapsed = ValueNotifier(false);

  @override
  void dispose() {
    _isCollapsed.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    final shouldShow = notification.metrics.pixels > 40;
    if (shouldShow != _isCollapsed.value) {
      _isCollapsed.value = shouldShow;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final baseAmbient = MobiusTheme.ambientFor(Theme.of(context).brightness);
    final mobileAmbient = AmbientConfig(
      base: baseAmbient.base,
      violet: baseAmbient.violet,
      magenta: baseAmbient.magenta,
      blue: baseAmbient.blue,
      cyan: baseAmbient.cyan,
      intensity: 0.72,
      falloffTop: 0.02,
      falloffBottom: 0.96,
      animationSpeed: baseAmbient.animationSpeed,
      warmMode: baseAmbient.warmMode,
      enabled: baseAmbient.enabled,
      maxFrameRate: baseAmbient.maxFrameRate,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedMobiusBackground(
        config: mobileAmbient,
        child: Column(
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: () {
                        if (widget.onBack != null) {
                          widget.onBack!();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                      color: MobiusColors.textOf(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isCollapsed,
                        builder: (context, collapsed, _) => AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: collapsed ? 1 : 0,
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MobiusColors.textOf(context)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: widget.bodyBuilder(_isCollapsed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CollapsibleDetailHeader extends StatelessWidget {
  const CollapsibleDetailHeader({
    super.key,
    required this.isCollapsed,
    required this.child,
  });

  final ValueListenable<bool>? isCollapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final listenable = isCollapsed;
    if (listenable == null) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      child: child,
      builder: (context, collapsed, child) => AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: collapsed ? const SizedBox.shrink() : child!,
      ),
    );
  }
}

/// Shared mobile detail layout for albums, artists, playlists, and favorites.
/// The owning page supplies its domain-specific track list and actions.
class MobileDetailPage extends StatelessWidget {
  const MobileDetailPage({
    super.key,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.trackCount,
    required this.artwork,
    required this.isCollapsed,
    required this.onPlay,
    required this.trackListBuilder,
  });

  final String kind;
  final String title;
  final String subtitle;
  final int trackCount;
  final Widget artwork;
  final ValueListenable<bool>? isCollapsed;
  final VoidCallback? onPlay;
  final WidgetBuilder trackListBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollapsibleDetailHeader(
          isCollapsed: isCollapsed,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                SizedBox(width: 110, height: 110, child: artwork),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        kind.toUpperCase(),
                        style: TextStyle(
                          color: MobiusColors.accentLightOf(context),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MobiusColors.textOf(context),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
                style: FilledButton.styleFrom(
                  backgroundColor: MobiusColors.accentOf(context),
                  foregroundColor: MobiusColors.onAccentOf(context),
                  minimumSize: const Size(104, 44),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$trackCount ${trackCount == 1 ? 'song' : 'songs'}',
                style: TextStyle(
                  color: MobiusColors.textDimOf(context),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: Builder(builder: trackListBuilder)),
      ],
    );
  }
}

/// Compact track row shared by mobile album, artist, and playlist details.
class MobileDetailTrackRow extends StatelessWidget {
  const MobileDetailTrackRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.artwork,
    this.trackNumber,
    required this.isCurrent,
    required this.onPlay,
    this.leading,
    this.onMore,
  });

  final String title;
  final String subtitle;
  final Widget? artwork;
  final int? trackNumber;
  final bool isCurrent;
  final VoidCallback onPlay;
  final Widget? leading;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isCurrent ? currentTrackRowColor(context) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPlay,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  if (artwork != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            artwork!,
                            if (isCurrent)
                              ColoredBox(
                                color: MobiusColors.accentOf(
                                  context,
                                ).withValues(alpha: 0.35),
                                child: Icon(
                                  Icons.equalizer_rounded,
                                  color: MobiusColors.accentLightOf(context),
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ] else ...[
                    SizedBox(
                      width: 32,
                      child: Center(
                        child: isCurrent
                            ? Icon(
                                Icons.equalizer_rounded,
                                color: MobiusColors.accentLightOf(context),
                                size: 18,
                              )
                            : Text(
                                trackNumber != null && trackNumber! > 0
                                    ? '$trackNumber'
                                    : '',
                                style: TextStyle(
                                  color: MobiusColors.textDimOf(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.trim().isEmpty ? 'Unknown title' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent
                                ? MobiusColors.accentOf(context)
                                : MobiusColors.textOf(context),
                            fontSize: 14,
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle.trim().isEmpty ? 'Unknown artist' : subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onMore != null)
                    IconButton(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 18,
                        color: MobiusColors.textDimOf(context),
                      ),
                      onPressed: onMore,
                      splashRadius: 18,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
