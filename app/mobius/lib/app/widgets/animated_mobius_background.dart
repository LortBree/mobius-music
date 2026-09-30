import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/mobius_theme.dart';
import '../theme/colors.dart';

/// Developer-level tuning for the ambient background. These are not exposed to
/// the end user; they exist so the effect is easy to adjust against the design
/// reference. Colours are the ONLY source of hue -- never album artwork, never
/// the current song.
@immutable
class AmbientConfig {
  const AmbientConfig({
    this.base = MobiusColors.ambientBase,
    this.violet = MobiusColors.ambientViolet,
    this.magenta = MobiusColors.ambientMagenta,
    this.blue = MobiusColors.ambientBlue,
    this.cyan = MobiusColors.ambientCyan,
    this.intensity = 0.58,
    this.falloffTop = 0.02,
    this.falloffBottom = 0.72,
    this.animationSpeed = 1.0,
    this.warmMode = false,
    this.enabled = true,
    this.maxFrameRate = 30,
  });

  /// Near-black canvas the light fields sit on.
  final Color base;

  /// Primary violet (dominant).
  final Color violet;

  /// Secondary muted magenta.
  final Color magenta;

  /// Violet-transitioning-to-blue, upper right.
  final Color blue;

  /// Very subtle cool accent. Kept faint by design.
  final Color cyan;

  /// Overall brightness multiplier.
  final double intensity;

  /// Vertical mask: y (0=top) where the fade begins.
  final double falloffTop;

  /// Vertical mask: y where the field has effectively faded to the base.
  final double falloffBottom;

  /// Multiplies the drift speed (1.0 = the tuned slow default).
  final double animationSpeed;

  /// When true, the hue-drift and directional bias stay in the WARM half of the
  /// wheel (orange<->red<->yellow) instead of drifting cool toward cyan. Used
  /// by the light theme's sunrise palette.
  final bool warmMode;

  /// When false the layer renders the static base with no ticking.
  final bool enabled;

  /// Upper bound on shader repaints per second while animating. The drift is
  /// slow (tens of seconds per cycle), so display rate (60/120 Hz) buys no
  /// visible smoothness but costs a full-window fragment pass every vsync.
  final int maxFrameRate;
}

/// A lightweight, GPU-rendered atmospheric light field concentrated near the
/// top of the window, fading to near-black below. Decoration only: it sits
/// behind the UI, never intercepts input, and never competes with content.
///
/// Cheap by construction: one fragment shader created once and reused; per
/// frame only a handful of `setFloat`s and a single `drawRect` (no bitmaps, no
/// CPU blur, no per-frame allocation). A [RepaintBoundary] isolates the layer,
/// repaints are capped at [AmbientConfig.maxFrameRate], and the drift stops
/// under [TickerMode] (covered route) or while the app is hidden, with its
/// elapsed time preserved so resuming never jumps.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    this.config = const AmbientConfig(),
    this.animate = true,
    this.child,
  });

  final AmbientConfig config;

  /// Runtime gate (e.g. "audio is playing"). When false the drift freezes on
  /// its current frame instead of repainting at display rate. Combined with
  /// [AmbientConfig.enabled] and the platform reduce-motion setting.
  final bool animate;
  final Widget? child;

  @override
  State<AmbientBackground> createState() => AmbientBackgroundState();
}

class AmbientBackgroundState extends State<AmbientBackground>
    with WidgetsBindingObserver {
  // Elapsed animation time fed to the shader. Driven by a timer at
  // [AmbientConfig.maxFrameRate] rather than a vsync ticker: a ticker
  // schedules a frame every vsync, and each frame re-renders the retained
  // shader picture even when nothing changed, so throttling the repaint alone
  // would not reduce GPU work. Timer ticks request exactly one frame each.
  final ValueNotifier<Duration> _time = ValueNotifier<Duration>(Duration.zero);
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _frameTimer;
  ui.FragmentShader? _shader;
  bool _appVisible = true;

  /// Whether the drift is currently advancing.
  @visibleForTesting
  bool get isAnimating => _frameTimer != null;

  /// Notifies once per shader frame; exposed so tests can count frames.
  @visibleForTesting
  ValueListenable<Duration> get frameClock => _time;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appVisible = _isVisible(WidgetsBinding.instance.lifecycleState);
    _loadShader();
  }

  static bool _isVisible(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      state == AppLifecycleState.inactive;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Minimised / hidden: nobody can see the drift, so stop repainting it.
    // `inactive` (window visible but unfocused) keeps animating.
    _appVisible = _isVisible(state);
    _syncTicker();
  }

  bool get _shouldRun =>
      widget.config.enabled &&
      widget.animate &&
      _appVisible &&
      TickerMode.of(context) &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  // Start/stop without resetting the elapsed time, so resuming never jumps.
  void _syncTicker() {
    if (!mounted) return;
    if (_shouldRun) {
      if (_frameTimer != null) return;
      final fps = widget.config.maxFrameRate.clamp(1, 120);
      _stopwatch.start();
      _frameTimer = Timer.periodic(
        Duration(microseconds: 1000000 ~/ fps),
        (_) => _time.value = _stopwatch.elapsed,
      );
    } else if (_frameTimer != null) {
      _frameTimer!.cancel();
      _frameTimer = null;
      _stopwatch.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/ambient_glow.frag',
      );
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (_) {
      if (mounted) setState(() => _shader = null);
    }
  }

  @override
  void didUpdateWidget(AmbientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.maxFrameRate != widget.config.maxFrameRate) {
      _frameTimer?.cancel();
      _frameTimer = null;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;

    final Widget background = shader == null
        ? ColoredBox(color: widget.config.base)
        : RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: isAnimating,
              painter: _AmbientRenderer(
                shader: shader,
                time: _time,
                config: widget.config,
              ),
              child: const SizedBox.expand(),
            ),
          );

    if (widget.child == null) return background;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: background),
        widget.child!,
      ],
    );
  }
}

/// Feeds the shader uniforms. Holds no mutable state beyond the shared shader;
/// all animation comes from [time], the continuously-accumulating elapsed
/// time -- see [paint].
class _AmbientRenderer extends CustomPainter {
  _AmbientRenderer({
    required this.shader,
    required this.time,
    required this.config,
  }) : super(repaint: time);

  final ui.FragmentShader shader;
  final ValueListenable<Duration> time;
  final AmbientConfig config;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // FREE-RUNNING time: the shader's per-field sines have periods that do not
    // divide any fixed loop length, so wrapping t back to 0 would snap every
    // field mid-cycle (a hard cut). Instead we feed the accumulated elapsed
    // seconds, which never wrap -- the motion is one continuous flow with no
    // loop boundary to cut. The stopwatch freezes while stopped and resumes
    // from the same value, so pausing never jumps.
    final elapsed = time.value;
    final t = elapsed.inMicroseconds / 1e6 * config.animationSpeed;

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, t)
      // base
      ..setFloat(3, config.base.r)
      ..setFloat(4, config.base.g)
      ..setFloat(5, config.base.b)
      // violet
      ..setFloat(6, config.violet.r)
      ..setFloat(7, config.violet.g)
      ..setFloat(8, config.violet.b)
      // magenta
      ..setFloat(9, config.magenta.r)
      ..setFloat(10, config.magenta.g)
      ..setFloat(11, config.magenta.b)
      // blue
      ..setFloat(12, config.blue.r)
      ..setFloat(13, config.blue.g)
      ..setFloat(14, config.blue.b)
      // cyan
      ..setFloat(15, config.cyan.r)
      ..setFloat(16, config.cyan.g)
      ..setFloat(17, config.cyan.b)
      // tuning
      ..setFloat(18, config.intensity)
      ..setFloat(19, config.falloffTop)
      ..setFloat(20, config.falloffBottom)
      ..setFloat(21, config.warmMode ? 1.0 : 0.0);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_AmbientRenderer oldDelegate) =>
      oldDelegate.shader != shader || oldDelegate.config != config;
}

/// Backwards-compatible wrapper: the shell wraps its content in
/// [AnimatedMobiusBackground]. Delegates to [AmbientBackground] so the shell
/// needs no change.
class AnimatedMobiusBackground extends StatelessWidget {
  const AnimatedMobiusBackground({
    super.key,
    this.animate = true,
    this.config,
    required this.child,
  });

  final bool animate;

  /// Optional explicit palette. When null, the palette is chosen from the
  /// active theme brightness (cool violet field in dark mode, warm sunrise
  /// field in light mode).
  final AmbientConfig? config;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final resolved = config ?? MobiusTheme.ambientFor(Theme.of(context).brightness);
    return AmbientBackground(animate: animate, config: resolved, child: child);
  }
}
