import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/theme/mobius_theme.dart';

/// Thin custom-painted seek bar used by the mini player: hover shows a time
/// tooltip, drag previews through [onChanged], release commits through
/// [onChangeEnd].
class MiniSeekBar extends StatefulWidget {
  const MiniSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.formatTime,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double position;
  final double duration;
  final bool enabled;
  final String Function(double) formatTime;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<MiniSeekBar> createState() => _MiniSeekBarState();
}

class _MiniSeekBarState extends State<MiniSeekBar> {
  double? _hoverValue;
  bool _dragging = false;

  double _valueFromX(double x, double width) {
    if (width <= 0 || widget.duration <= 0) {
      return 0;
    }

    final fraction = (x / width).clamp(0.0, 1.0);
    return fraction * widget.duration;
  }

  void _updateHover(PointerHoverEvent event, double width) {
    if (!widget.enabled || _dragging) {
      return;
    }

    setState(() {
      _hoverValue = _valueFromX(event.localPosition.dx, width);
    });
  }

  void _startDrag(DragStartDetails details, double width) {
    if (!widget.enabled) {
      return;
    }

    final value = _valueFromX(details.localPosition.dx, width);

    setState(() {
      _dragging = true;
      _hoverValue = value;
    });

    widget.onChanged(value);
  }

  void _updateDrag(DragUpdateDetails details, double width) {
    if (!widget.enabled) {
      return;
    }

    final value = _valueFromX(details.localPosition.dx, width);

    setState(() {
      _hoverValue = value;
    });

    widget.onChanged(value);
  }

  void _endDrag(DragEndDetails details, double width) {
    if (!widget.enabled || _hoverValue == null) {
      return;
    }

    final value = _hoverValue!.clamp(0.0, widget.duration);

    widget.onChangeEnd(value);

    if (!mounted) {
      return;
    }

    setState(() {
      _dragging = false;
    });
  }

  void _clearHover(PointerExitEvent event) {
    if (_dragging) {
      return;
    }

    setState(() {
      _hoverValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayedValue =
        (_dragging && _hoverValue != null ? _hoverValue! : widget.position)
            .clamp(0.0, widget.duration);

    final showTooltip = widget.enabled && _hoverValue != null;

    final colors = MobiusSurfaces.of(context);

    return SizedBox(
      height: 42,
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              widget.formatTime(widget.position),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                final fraction = widget.duration > 0
                    ? (displayedValue / widget.duration).clamp(0.0, 1.0)
                    : 0.0;

                final hoverFraction = _hoverValue != null && widget.duration > 0
                    ? (_hoverValue! / widget.duration).clamp(0.0, 1.0)
                    : fraction;

                const tooltipWidth = 58.0;
                final tooltipLeft = (hoverFraction * width - tooltipWidth / 2)
                    .clamp(
                      0.0,
                      (width - tooltipWidth).clamp(0.0, double.infinity),
                    );

                return MouseRegion(
                  onHover: (event) => _updateHover(event, width),
                  onExit: _clearHover,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (showTooltip)
                        Positioned(
                          left: tooltipLeft,
                          top: -14,
                          child: IgnorePointer(
                            child: Container(
                              width: tooltipWidth,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.border,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.formatTime(_hoverValue!),
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 7,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: (details) =>
                              _startDrag(details, width),
                          onHorizontalDragUpdate: (details) =>
                              _updateDrag(details, width),
                          onHorizontalDragEnd: (details) =>
                              _endDrag(details, width),
                          onTapDown: (details) {
                            final value = _valueFromX(
                              details.localPosition.dx,
                              width,
                            );
                            widget.onChanged(value);
                            widget.onChangeEnd(value);
                          },
                          child: SizedBox(
                            height: 28,
                            child: CustomPaint(
                              painter: _MiniSeekBarPainter(
                                fraction: fraction,
                                trackColor: colors.border,
                                activeColor: colors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.enabled)
                        Positioned(
                          left: (fraction * width - 5).clamp(0.0, width - 10),
                          top: 16,
                          child: const IgnorePointer(child: _SeekBarThumb()),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Text(
              widget.formatTime(widget.duration),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeekBarThumb extends StatelessWidget {
  const _SeekBarThumb();

  @override
  Widget build(BuildContext context) {
    final colors = MobiusSurfaces.of(context);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.accentLight,
      ),
    );
  }
}

class _MiniSeekBarPainter extends CustomPainter {
  const _MiniSeekBarPainter({
    required this.fraction,
    required this.trackColor,
    required this.activeColor,
  });

  final double fraction;
  final Color trackColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final y = size.height / 2;
    final endX = size.width * fraction;

    canvas.drawLine(Offset(0, y), Offset(size.width, y), trackPaint);

    if (endX > 0) {
      canvas.drawLine(Offset(0, y), Offset(endX, y), activePaint);
    }
  }

  @override
  bool shouldRepaint(_MiniSeekBarPainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.activeColor != activeColor;
  }
}
