import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// Soft, slowly drifting aurora glows behind the app content.
class AnimatedMobiusBackground extends StatefulWidget {
  const AnimatedMobiusBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AnimatedMobiusBackground> createState() =>
      _AnimatedMobiusBackgroundState();
}

class _AnimatedMobiusBackgroundState extends State<AnimatedMobiusBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 48),
    )..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: MobiusColors.ink),
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AuroraPainter(animation: _controller),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.animation}) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final phase = animation.value * math.pi * 2;
    final w = size.width;
    final h = size.height;

    // Broad radial fields recreate the soft light in the reference. The hue
    // shifts slowly across the purple, magenta, and blue palette.
    _drawGlow(
      canvas,
      size,
      center: Offset(
        w * (0.30 + 0.035 * math.sin(phase)),
        h * (0.18 + 0.035 * math.cos(phase)),
      ),
      radius: Size(w * 0.42, h * 0.66),
      color: _shiftColor(
        const Color(0xFFB34CC6),
        const Color(0xFF7555D9),
        phase,
      ),
      opacity: 0.22,
    );
    _drawGlow(
      canvas,
      size,
      center: Offset(
        w * (0.84 + 0.025 * math.cos(phase + 1.1)),
        h * (0.08 + 0.035 * math.sin(phase + 1.1)),
      ),
      radius: Size(w * 0.35, h * 0.62),
      color: _shiftColor(
        const Color(0xFF7883D5),
        const Color(0xFF9B65D2),
        phase + 1.7,
      ),
      opacity: 0.20,
    );
    _drawGlow(
      canvas,
      size,
      center: Offset(
        w * (0.05 + 0.025 * math.sin(phase + 2.2)),
        h * (0.82 + 0.04 * math.cos(phase + 2.2)),
      ),
      radius: Size(w * 0.46, h * 0.72),
      color: _shiftColor(
        const Color(0xFF5039B0),
        const Color(0xFF814CC8),
        phase + 3.1,
      ),
      opacity: 0.23,
    );
  }

  Color _shiftColor(Color first, Color second, double phase) {
    final amount = 0.5 - 0.5 * math.cos(phase);
    return Color.lerp(first, second, amount)!;
  }

  void _drawGlow(
    Canvas canvas,
    Size size, {
    required Offset center,
    required Size radius,
    required Color color,
    required double opacity,
  }) {
    final rect = Rect.fromCenter(
      center: center,
      width: radius.width * 2,
      height: radius.height * 2,
    );
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: opacity),
        color.withValues(alpha: opacity * 0.52),
        color.withValues(alpha: 0),
      ],
      stops: const [0, 0.42, 1],
    ).createShader(rect);

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.screen,
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
