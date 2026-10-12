import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'lrc_parser.dart';

/// Apple Music style synchronized lyrics view with fluid centering and spring typography.
class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.lyrics,
    required this.positionNotifier,
    required this.onSeek,
    this.accentColor,
  });

  final ParsedLyrics? lyrics;
  final ValueListenable<double> positionNotifier;
  final ValueChanged<Duration> onSeek;
  final Color? accentColor;

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};

  int _lastActiveIndex = -1;
  bool _isUserScrolling = false;
  Timer? _resumeAutoScrollTimer;

  @override
  void initState() {
    super.initState();
    widget.positionNotifier.addListener(_onPositionChanged);
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionNotifier != widget.positionNotifier) {
      oldWidget.positionNotifier.removeListener(_onPositionChanged);
      widget.positionNotifier.addListener(_onPositionChanged);
    }
    if (oldWidget.lyrics != widget.lyrics) {
      _lastActiveIndex = -1;
      _lineKeys.clear();
    }
  }

  @override
  void dispose() {
    widget.positionNotifier.removeListener(_onPositionChanged);
    _resumeAutoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onPositionChanged() {
    final lyrics = widget.lyrics;
    if (lyrics == null || !lyrics.isSynced || lyrics.isEmpty) return;

    final currentPos = Duration(
      milliseconds: (widget.positionNotifier.value * 1000).round(),
    );
    final activeIndex = lyrics.findActiveIndex(currentPos);

    if (activeIndex != _lastActiveIndex) {
      setState(() => _lastActiveIndex = activeIndex);
      if (!_isUserScrolling && activeIndex >= 0) {
        _scrollToIndex(activeIndex);
      }
    }
  }

  void _scrollToIndex(int index) {
    final key = _lineKeys[index];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.35, // Apple Music sweet-spot
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _isUserScrolling = true;
        _resumeAutoScrollTimer?.cancel();
      } else {
        _resumeAutoScrollTimer?.cancel();
        _resumeAutoScrollTimer = Timer(const Duration(milliseconds: 3500), () {
          if (mounted) {
            _isUserScrolling = false;
            if (_lastActiveIndex >= 0) {
              _scrollToIndex(_lastActiveIndex);
            }
          }
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;

    if (lyrics == null || lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 14),
            Text(
              'Lyrics not available',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Top and bottom vertical gradient mask for Apple Music depth effect
    return ShaderMask(
      shaderCallback: (rect) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.08, 0.90, 1.0],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight =
              constraints.maxHeight.isFinite && constraints.maxHeight > 100
                  ? constraints.maxHeight
                  : MediaQuery.sizeOf(context).height * 0.5;
          final topPadding = (viewportHeight * 0.28).clamp(40.0, 240.0);
          final bottomPadding = (viewportHeight * 0.45).clamp(80.0, 360.0);

          return NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(24, topPadding, 24, bottomPadding),
              itemCount: lyrics.lines.length,
              itemBuilder: (context, index) {
                final line = lyrics.lines[index];
                final isActive = lyrics.isSynced && index == _lastActiveIndex;
                final isPast = lyrics.isSynced && index < _lastActiveIndex;

                final key = _lineKeys.putIfAbsent(index, () => GlobalKey());

                return KeyedSubtree(
                  key: key,
                  child: _AppleMusicLyricRow(
                    text: line.text,
                    isActive: isActive,
                    isPast: isPast,
                    isSynced: lyrics.isSynced,
                    accentColor: widget.accentColor,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (lyrics.isSynced) {
                        widget.onSeek(line.timestamp);
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AppleMusicLyricRow extends StatelessWidget {
  const _AppleMusicLyricRow({
    required this.text,
    required this.isActive,
    required this.isPast,
    required this.isSynced,
    required this.onTap,
    this.accentColor,
  });

  final String text;
  final bool isActive;
  final bool isPast;
  final bool isSynced;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final activeColor = Colors.white;
    final inactiveColor = Colors.white.withValues(
      alpha: isPast ? 0.35 : 0.25,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: isActive ? 1.04 : 1.0,
          alignment: Alignment.centerLeft,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: isActive ? activeColor : inactiveColor,
              fontSize: isActive ? 26 : 22,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              height: 1.35,
              letterSpacing: -0.2,
              shadows: isActive
                  ? [
                      Shadow(
                        color: (accentColor ?? Colors.white).withValues(alpha: 0.3),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Text(text),
          ),
        ),
      ),
    );
  }
}
