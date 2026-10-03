import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/mobius_theme.dart';

/// A compact volume control: a speaker icon that mutes/restores on tap, and a
/// short horizontal slider. Pure presentation — the current level comes in as
/// a [ValueListenable] (so keyboard-driven changes keep the slider in sync),
/// and every interaction goes back out through [onChanged] / [onChangeEnd].
///
/// Styled to match the Now Playing seek bar's [SliderTheme] so the two read as
/// one family.
class VolumeControl extends StatefulWidget {
  const VolumeControl({
    super.key,
    required this.volume,
    required this.onChanged,
    required this.onChangeEnd,
    this.enabled = true,
    this.sliderWidth = 100,
  });

  /// Current volume, 0.0–1.0, as a listenable so the slider follows the
  /// controller even when the keyboard shortcuts change it.
  final ValueListenable<double> volume;

  /// Fired continuously while dragging (live) and on a mute toggle.
  final ValueChanged<double> onChanged;

  /// Fired once when the drag settles — the moment to persist the value.
  final ValueChanged<double> onChangeEnd;

  /// When false the control is greyed out and ignores input (e.g. an output
  /// mode where the engine owns the level).
  final bool enabled;

  final double sliderWidth;

  @override
  State<VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<VolumeControl> {
  /// The level to restore when un-muting. Captured the moment the user mutes.
  double _volumeBeforeMute = 1.0;

  void _toggleMute(double current) {
    if (current > 0) {
      _volumeBeforeMute = current;
      widget.onChanged(0);
      widget.onChangeEnd(0);
    } else {
      final restore = _volumeBeforeMute > 0 ? _volumeBeforeMute : 1.0;
      widget.onChanged(restore);
      widget.onChangeEnd(restore);
    }
  }

  IconData _iconFor(double volume) {
    if (volume <= 0) return Icons.volume_off_rounded;
    if (volume < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colors = MobiusSurfaces.of(context);

    return ValueListenableBuilder<double>(
      valueListenable: widget.volume,
      builder: (context, volume, _) {
        final clamped = volume.clamp(0.0, 1.0).toDouble();
        final muted = clamped <= 0;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: muted ? 'Unmute' : 'Mute',
              onPressed: widget.enabled ? () => _toggleMute(clamped) : null,
              iconSize: 20,
              color: colors.textSecondary,
              icon: Icon(_iconFor(clamped)),
            ),
            SizedBox(
              width: widget.sliderWidth,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: colors.accent,
                  inactiveTrackColor: colors.border,
                  thumbColor: colors.accentLight,
                  overlayColor: colors.accent.withValues(alpha: 0.2),
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: clamped,
                  onChanged: widget.enabled ? widget.onChanged : null,
                  onChangeEnd: widget.enabled ? widget.onChangeEnd : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
