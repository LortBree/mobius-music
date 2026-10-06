import 'package:flutter/material.dart';

/// A sleek, atmospheric loading view featuring the 3D isometric Mobius loop
/// with subtle ambient breathing animation.
class MobiusLoadingView extends StatefulWidget {
  const MobiusLoadingView({
    super.key,
    this.size = 260.0,
    this.backgroundColor = Colors.black,
  });

  final double size;
  final Color backgroundColor;

  @override
  State<MobiusLoadingView> createState() => _MobiusLoadingViewState();
}

class _MobiusLoadingViewState extends State<MobiusLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      alignment: Alignment.center,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            ),
          );
        },
        child: Image.asset(
          'assets/icons/mobius_loop_3d.png',
          width: widget.size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.all_inclusive_rounded,
            size: widget.size * 0.6,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}
