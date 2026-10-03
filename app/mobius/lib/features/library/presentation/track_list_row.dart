import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';

/// A single row in an album/artist detail tracklist.
///
/// Columns: a leading slot (track number, or a play icon on hover, or an
/// accent equalizer glyph when this is the playing track) | the title, with
/// the performing artist beneath it in dim text only when [artistSubtitle]
/// is supplied | the duration, right-aligned in tabular figures.
///
/// All interaction goes out through [onPlay]; the parent is expected to wrap
/// the row in its existing context-menu widget for secondary-tap actions.
/// Double-click or clicking the play glyph triggers [onPlay].
class TrackListRow extends StatefulWidget {
  const TrackListRow({
    super.key,
    required this.trackNumber,
    required this.title,
    required this.isCurrent,
    required this.onPlay,
    this.artistSubtitle,
    this.duration,
  });

  /// The number shown at the left (1-based display value already resolved by
  /// the caller — track number when known, else the row's ordinal).
  final int trackNumber;

  final String title;

  /// Shown beneath the title in dim text. `null`/empty hides the line (the
  /// album page passes it only when the track artist differs from the album
  /// artist; the artist context may always pass it).
  final String? artistSubtitle;

  /// Duration in seconds, if known. `null` renders as `--` (per-track
  /// durations are only known for the currently loaded track).
  final double? duration;

  final bool isCurrent;
  final VoidCallback onPlay;

  @override
  State<TrackListRow> createState() => _TrackListRowState();
}

class _TrackListRowState extends State<TrackListRow> {
  bool _hovered = false;

  Color _rowColor(BuildContext context) {
    if (widget.isCurrent) return MobiusColors.selectionOf(context);
    if (_hovered) return MobiusColors.panelOf(context);
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.artistSubtitle?.trim() ?? '';
    final hasSubtitle = subtitle.isNotEmpty;
    final accent = MobiusColors.accentOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onDoubleTap: widget.onPlay,
        child: Material(
          color: _rowColor(context),
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Center(child: _buildLeading(context, accent)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title.trim().isEmpty
                              ? 'Unknown title'
                              : widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.isCurrent
                                ? accent
                                : MobiusColors.textOf(context),
                            fontSize: 14,
                            fontWeight: widget.isCurrent
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        if (hasSubtitle) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: MobiusColors.textDimOf(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _formatDuration(widget.duration),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: MobiusColors.textDimOf(context),
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context, Color accent) {
    // Playing: accent equalizer glyph, regardless of hover.
    if (widget.isCurrent) {
      return Icon(Icons.graphic_eq_rounded, size: 18, color: accent);
    }
    // Hover: the number becomes a play affordance.
    if (_hovered) {
      return IconButton(
        tooltip: 'Play',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        iconSize: 20,
        color: MobiusColors.accentLightOf(context),
        icon: const Icon(Icons.play_arrow_rounded),
        onPressed: widget.onPlay,
      );
    }
    // Default: the track number.
    return Text(
      '${widget.trackNumber}',
      style: TextStyle(
        color: MobiusColors.textDimOf(context),
        fontSize: 13,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

String _formatDuration(double? seconds) {
  if (seconds == null || !seconds.isFinite || seconds < 0) return '--';
  final total = seconds.floor();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// A small "Disc N" sub-header shown between disc boundaries on the album
/// detail tracklist.
class TrackListDiscHeader extends StatelessWidget {
  const TrackListDiscHeader({super.key, required this.discNumber});

  final int discNumber;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
    child: Row(
      children: [
        Icon(
          Icons.album_outlined,
          size: 15,
          color: MobiusColors.textDimOf(context),
        ),
        const SizedBox(width: 8),
        Text(
          'Disc $discNumber',
          style: TextStyle(
            color: MobiusColors.textDimOf(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ],
    ),
  );
}
