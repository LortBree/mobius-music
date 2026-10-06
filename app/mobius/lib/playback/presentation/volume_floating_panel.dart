import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../player_controller.dart';

/// An authentic Android native-inspired vertical pill volume floating panel that appears
/// on the right edge of the screen whenever volume changes (hardware keys, slider, or media events)
/// and automatically dismisses after inactivity.
///
/// Features conforming to Android 13-15 Material You / SystemUI:
/// - Thick vertical pill capsule slider (width ~44-48dp, height ~190dp).
/// - No gradients: flat solid theme tokens throughout.
///   - Standard mode: violet-blue (`MobiusColors.violetBlueOf` / `theme.colorScheme.primary`).
///   - USB DAC mode: magenta (`MobiusColors.magentaOf` / `theme.colorScheme.secondary`).
/// - Seamless Android-native UX:
///   - Tapping anywhere along the vertical pill instantly seeks/jumps to that level
///     and smoothly continues dragging with zero latency.
///   - Smooth spring/cubic glide animation when stepping through hardware volume keys.
///   - Instant 1:1 direct finger tracking with 0 delay during manual drag.
///   - Haptic feedback tick on touch down and step adjustments.
///   - Pill track background with muted container surface and subtle glassmorphic blur.
///   - Dynamic active fill rising from bottom to top with stadium-rounded corners.
///   - Dynamic speaker/headphones icon.
///   - Auto-dismiss countdown paused during touch/drag.
///   - Authentic Android motion physics (`Curves.fastOutSlowIn`).
class VolumeFloatingPanel extends StatefulWidget {
  const VolumeFloatingPanel({
    super.key,
    required this.controller,
    this.dismissDuration = const Duration(milliseconds: 2800),
    this.topOffsetFraction = 0.28,
  });

  final PlayerController controller;
  final Duration dismissDuration;
  final double topOffsetFraction;

  @override
  State<VolumeFloatingPanel> createState() => VolumeFloatingPanelState();
}

class VolumeFloatingPanelState extends State<VolumeFloatingPanel> {
  static const double _normalWidth = 44.0;
  static const double _expandedWidth = 48.0;
  static const double _pillHeight = 190.0;

  bool _isVisible = false;
  bool _isDragging = false;
  double _dragVolume = 0.5;
  Timer? _dismissTimer;

  double _lastVolume = 1.0;
  double _lastHardwareVolume = 0.36;
  bool _lastBitPerfect = false;
  double _preMuteVolume = 0.5;

  bool get isVisible => _isVisible;

  @override
  void initState() {
    super.initState();
    _lastVolume = widget.controller.volume;
    _lastHardwareVolume = widget.controller.hardwareVolume;
    _lastBitPerfect = widget.controller.isBitPerfectMode;
    _dragVolume = widget.controller.isUsbDacActive ? _lastHardwareVolume : _lastVolume;

    widget.controller.volumeListenable.addListener(_onVolumeChanged);
    widget.controller.hardwareVolumeListenable.addListener(_onHardwareVolumeChanged);
    widget.controller.bitPerfectModeListenable.addListener(_onBitPerfectChanged);
    widget.controller.volumePanelTrigger.addListener(show);
  }

  @override
  void dispose() {
    widget.controller.volumeListenable.removeListener(_onVolumeChanged);
    widget.controller.hardwareVolumeListenable.removeListener(_onHardwareVolumeChanged);
    widget.controller.bitPerfectModeListenable.removeListener(_onBitPerfectChanged);
    widget.controller.volumePanelTrigger.removeListener(show);
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _onVolumeChanged() {
    final newVol = widget.controller.volume;
    if ((newVol - _lastVolume).abs() > 0.001) {
      _lastVolume = newVol;
      if (_isVisible && mounted && !_isDragging) {
        setState(() {});
      }
    }
  }

  void _onHardwareVolumeChanged() {
    final newVol = widget.controller.hardwareVolume;
    if ((newVol - _lastHardwareVolume).abs() > 0.001) {
      _lastHardwareVolume = newVol;
      if (_isVisible && mounted && !_isDragging) {
        setState(() {});
      }
    }
  }

  void _onBitPerfectChanged() {
    final newMode = widget.controller.isBitPerfectMode;
    if (newMode != _lastBitPerfect) {
      _lastBitPerfect = newMode;
      if (_isVisible && mounted) {
        setState(() {});
      }
    }
  }

  /// Manually shows the volume panel and resets the dismissal timer.
  void show() {
    _dismissTimer?.cancel();
    if (!mounted) return;
    if (!_isVisible) {
      setState(() => _isVisible = true);
    } else {
      setState(() {});
    }
    if (!_isDragging) {
      _dismissTimer = Timer(widget.dismissDuration, hide);
    }
  }

  /// Dismisses the volume panel with an animation.
  void hide() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    if (mounted && _isVisible) {
      setState(() {
        _isVisible = false;
        _isDragging = false;
      });
    }
  }

  void _handleTouch(Offset localPosition) {
    show();
    final clampedY = localPosition.dy.clamp(0.0, _pillHeight);
    final ratio = (1.0 - (clampedY / _pillHeight)).clamp(0.0, 1.0);

    final isDac = widget.controller.isUsbDacActive;
    final currentVal = isDac ? widget.controller.hardwareVolume : widget.controller.volume;

    final oldStep = (currentVal * 20).round();
    final newStep = (ratio * 20).round();
    if (oldStep != newStep) {
      unawaited(HapticFeedback.selectionClick());
    }

    _dragVolume = ratio;
    if (isDac) {
      widget.controller.setHardwareVolume(ratio, triggerPanel: false);
    } else {
      widget.controller.setVolume(ratio, triggerPanel: false);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _endTouch() {
    if (mounted) {
      setState(() => _isDragging = false);
    }
    _dismissTimer?.cancel();
    _dismissTimer = Timer(widget.dismissDuration, hide);
  }

  IconData _iconFor(double level, bool isDac) {
    if (isDac) {
      return Icons.headphones_rounded;
    }
    if (level <= 0.001) return Icons.volume_off_rounded;
    if (level < 0.40) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  void toggleMute() {
    final isDac = widget.controller.isUsbDacActive;
    final cur = isDac ? widget.controller.hardwareVolume : widget.controller.volume;

    unawaited(HapticFeedback.mediumImpact());

    if (cur > 0.001) {
      _preMuteVolume = cur;
      if (isDac) {
        widget.controller.setHardwareVolume(0.0, triggerPanel: false);
      } else {
        widget.controller.setVolume(0.0, triggerPanel: false);
      }
    } else {
      final restoreVal = _preMuteVolume > 0.01 ? _preMuteVolume : 0.5;
      if (isDac) {
        widget.controller.setHardwareVolume(restoreVal, triggerPanel: false);
      } else {
        widget.controller.setVolume(restoreVal, triggerPanel: false);
      }
    }
    show();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topPosition = media.size.height * widget.topOffsetFraction;

    final theme = Theme.of(context);
    final isDac = widget.controller.isUsbDacActive;
    final currentVolume = isDac
        ? widget.controller.hardwareVolume
        : widget.controller.volume;

    // Volume slider color preserved as requested
    const baseViolet = Color(0xFF8A63D2);
    final activeColor = baseViolet.withValues(alpha: 0.82);

    // Muted frosted track surface conforming to Android Material You container
    final trackColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.50);
    final currentPillWidth = _isDragging ? _expandedWidth : _normalWidth;
    final targetFill = _isDragging ? _dragVolume : currentVolume.clamp(0.0, 1.0);

    return Positioned(
      top: topPosition,
      right: 12,
      child: IgnorePointer(
        ignoring: !_isVisible,
        child: AnimatedSlide(
          offset: _isVisible ? Offset.zero : const Offset(1.5, 0),
          duration: const Duration(milliseconds: 240),
          curve: Curves.fastOutSlowIn,
          child: AnimatedOpacity(
            opacity: _isVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Semantics(
              label: isDac ? 'Hardware DAC Volume Control' : 'Media Volume Control',
              value: '${(currentVolume * 100).round()}%',
              slider: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Instant seek/jump on tap anywhere along the vertical pill
                onTapDown: (details) {
                  setState(() => _isDragging = true);
                  _dismissTimer?.cancel();
                  _handleTouch(details.localPosition);
                },
                onTapUp: (_) => _endTouch(),
                onTapCancel: () => _endTouch(),
                onVerticalDragDown: (details) {
                  setState(() => _isDragging = true);
                  _dismissTimer?.cancel();
                  _handleTouch(details.localPosition);
                },
                onVerticalDragStart: (details) {
                  setState(() => _isDragging = true);
                  _dismissTimer?.cancel();
                  _handleTouch(details.localPosition);
                },
                onVerticalDragUpdate: (details) {
                  _handleTouch(details.localPosition);
                },
                onVerticalDragEnd: (_) => _endTouch(),
                onVerticalDragCancel: () => _endTouch(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  width: currentPillWidth,
                  height: _pillHeight,
                  decoration: BoxDecoration(
                    color: trackColor,
                    borderRadius: BorderRadius.circular(currentPillWidth / 2),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.38),
                        blurRadius: 18,
                        offset: const Offset(-2, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(currentPillWidth / 2),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // Flat solid active volume fill (NO gradients, rises bottom to top)
                          // Smooth tween glide for hardware keys, instant 1:1 direct tracking for drag
                          if (_isDragging)
                            FractionallySizedBox(
                              heightFactor: targetFill,
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                color: activeColor,
                              ),
                            )
                          else
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(end: targetFill),
                              duration: const Duration(milliseconds: 140),
                              curve: Curves.easeOutCubic,
                              builder: (context, animatedFill, child) {
                                return FractionallySizedBox(
                                  heightFactor: animatedFill.clamp(0.0, 1.0),
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    color: activeColor,
                                  ),
                                );
                              },
                            ),

                          // Unobstructed Overlay: percentage / clean DAC badge at top, dynamic icon at bottom
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // Top Value / Mode Badge (Clean, centered typography)
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isDac) ...[
                                          Container(
                                            margin: const EdgeInsets.only(bottom: 2),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.35),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha: 0.25),
                                                width: 0.6,
                                              ),
                                            ),
                                            child: const Text(
                                              'DAC',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 8.0,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ),
                                        ],
                                        Text(
                                          '${(currentVolume * 100).round()}%',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                            shadows: [
                                              Shadow(color: Colors.black54, blurRadius: 4),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Bottom Dynamic Icon
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black.withValues(alpha: 0.20),
                                      ),
                                      child: Icon(
                                        _iconFor(currentVolume, isDac),
                                        size: 18,
                                        color: Colors.white.withValues(alpha: 0.95),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
