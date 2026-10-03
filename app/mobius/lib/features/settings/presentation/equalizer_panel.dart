import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/colors.dart';
import '../../../playback/equalizer_response.dart';

/// The Settings equalizer: an interactive frequency-response graph with one
/// draggable handle per band, preset chips, and a readout of the automatic
/// preamp the engine applies to keep boosts from clipping.
///
/// Stateless about gains: the owner keeps them, persists them and applies
/// them to the player. [onGainsChanged] fires with `commit: false` while a
/// handle is dragged and `commit: true` when the gesture ends (persist then).
class EqualizerPanel extends StatelessWidget {
  const EqualizerPanel({
    super.key,
    required this.gains,
    required this.enabled,
    required this.onGainsChanged,
    required this.onEnabledChanged,
  });

  final List<double> gains;
  final bool enabled;
  final void Function(List<double> gains, {required bool commit})
  onGainsChanged;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final preset = EqualizerPresets.nameFor(gains);
    final preamp = EqualizerResponse.autoPreampDb(gains);
    final isFlat = preset == 'Flat';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: MobiusColors.panelOf(context),
        border: Border.all(color: MobiusColors.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equalizer',
                      style: TextStyle(
                        color: MobiusColors.textOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      enabled
                          ? 'Drag a point to shape the sound. Double-click a point to reset it.'
                          : 'Off: the equalizer leaves the audio untouched.',
                      style: TextStyle(
                        color: MobiusColors.textDimOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled && !isFlat)
                TextButton.icon(
                  onPressed: () => onGainsChanged(
                    List<double>.from(EqualizerPresets.all['Flat']!),
                    commit: true,
                  ),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Reset'),
                  style: TextButton.styleFrom(
                    foregroundColor: MobiusColors.textDimOf(context),
                  ),
                ),
              const SizedBox(width: 4),
              Switch.adaptive(
                value: enabled,
                activeTrackColor: MobiusColors.accentOf(context),
                onChanged: onEnabledChanged,
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: enabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !enabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in EqualizerPresets.all.keys)
                        _PresetChip(
                          label: name,
                          selected: name == preset,
                          onTap: () => onGainsChanged(
                            List<double>.from(EqualizerPresets.all[name]!),
                            commit: true,
                          ),
                        ),
                      if (preset == EqualizerPresets.custom)
                        const _PresetChip(
                          label: EqualizerPresets.custom,
                          selected: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  EqualizerGraph(gains: gains, onGainsChanged: onGainsChanged),
                  const SizedBox(height: 10),
                  _PreampReadout(preampDb: preamp),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = MobiusColors.accentOf(context);
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.18)
            : MobiusColors.backgroundOf(context).withValues(alpha: 0.4),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? accent : MobiusColors.borderOf(context),
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? MobiusColors.accentLightOf(context)
                    : MobiusColors.textOf(context),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreampReadout extends StatelessWidget {
  const _PreampReadout({required this.preampDb});

  final double preampDb;

  @override
  Widget build(BuildContext context) {
    final active = preampDb < -0.05;
    return Row(
      children: [
        Icon(
          active ? Icons.shield_outlined : Icons.check_circle_outline,
          size: 14,
          color: MobiusColors.textDimOf(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            active
                ? 'Auto preamp ${preampDb.toStringAsFixed(1)} dB: '
                      'lowers the input so boosted bands never clip.'
                : 'No preamp needed: nothing is boosted above 0 dB.',
            style: TextStyle(
              color: MobiusColors.textDimOf(context),
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// The response graph with draggable band handles.
class EqualizerGraph extends StatefulWidget {
  const EqualizerGraph({
    super.key,
    required this.gains,
    required this.onGainsChanged,
    this.height = 220,
  });

  final List<double> gains;
  final void Function(List<double> gains, {required bool commit})
  onGainsChanged;
  final double height;

  @override
  State<EqualizerGraph> createState() => _EqualizerGraphState();
}

class _EqualizerGraphState extends State<EqualizerGraph> {
  static const double _snapDb = 0.5;
  static const double _keyStepDb = 0.5;

  int? _activeBand;
  int? _hoverBand;

  _GraphGeometry _geometry(Size size) => _GraphGeometry(size);

  double _snap(double gain) => ((gain / _snapDb).round() * _snapDb).clamp(
    EqualizerResponse.minGainDb,
    EqualizerResponse.maxGainDb,
  );

  void _setBand(int band, double gain, {required bool commit}) {
    final next = List<double>.from(widget.gains);
    next[band] = _snap(gain);
    widget.onGainsChanged(next, commit: commit);
  }

  int _nearestBand(_GraphGeometry g, Offset position) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var band = 0; band < 10; band++) {
      final distance = (g.xForBand(band) - position.dx).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = band;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final accent = MobiusColors.accentOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        final g = _geometry(size);

        return MouseRegion(
          cursor: _hoverBand != null || _activeBand != null
              ? SystemMouseCursors.resizeUpDown
              : SystemMouseCursors.basic,
          onHover: (event) {
            final band = _nearestBand(g, event.localPosition);
            final near =
                (g.xForBand(band) - event.localPosition.dx).abs() <
                g.bandSpacing / 2;
            final next = near ? band : null;
            if (next != _hoverBand) setState(() => _hoverBand = next);
          },
          onExit: (_) => setState(() => _hoverBand = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (details) {
              final band = _nearestBand(g, details.localPosition);
              setState(() => _activeBand = band);
              _setBand(
                band,
                g.gainForY(details.localPosition.dy),
                commit: false,
              );
            },
            onVerticalDragUpdate: (details) {
              final band = _activeBand;
              if (band == null) return;
              _setBand(
                band,
                g.gainForY(details.localPosition.dy),
                commit: false,
              );
            },
            onVerticalDragEnd: (_) {
              final band = _activeBand;
              setState(() => _activeBand = null);
              if (band != null) {
                widget.onGainsChanged(
                  List<double>.from(widget.gains),
                  commit: true,
                );
              }
            },
            onTapDown: (details) {
              final band = _nearestBand(g, details.localPosition);
              _setBand(
                band,
                g.gainForY(details.localPosition.dy),
                commit: true,
              );
            },
            onDoubleTapDown: (details) {
              final band = _nearestBand(g, details.localPosition);
              _setBand(band, 0, commit: true);
            },
            onDoubleTap: () {},
            child: Stack(
              children: [
                CustomPaint(
                  size: size,
                  painter: _EqualizerPainter(
                    gains: widget.gains,
                    geometry: g,
                    activeBand: _activeBand ?? _hoverBand,
                    accent: accent,
                    accentLight: MobiusColors.accentLightOf(context),
                    grid: MobiusColors.borderOf(context),
                    label: MobiusColors.textDimOf(context),
                    handleFill: MobiusColors.panelOf(context),
                  ),
                ),
                // Invisible per-band semantics so the graph is usable with
                // VoiceOver (increase/decrease like a slider).
                for (var band = 0; band < 10; band++)
                  Positioned(
                    left: g.xForBand(band) - g.bandSpacing / 2,
                    width: g.bandSpacing,
                    top: 0,
                    height: size.height,
                    child: Semantics(
                      label:
                          '${_frequencyLabel(EqualizerResponse.bandsHz[band])} Hz band',
                      value: _gainLabel(widget.gains[band]),
                      increasedValue: _gainLabel(
                        _snap(widget.gains[band] + _keyStepDb),
                      ),
                      decreasedValue: _gainLabel(
                        _snap(widget.gains[band] - _keyStepDb),
                      ),
                      onIncrease: () => _setBand(
                        band,
                        widget.gains[band] + _keyStepDb,
                        commit: true,
                      ),
                      onDecrease: () => _setBand(
                        band,
                        widget.gains[band] - _keyStepDb,
                        commit: true,
                      ),
                      textDirection: TextDirection.ltr,
                      child: const SizedBox.expand(),
                    ),
                  ),
                if (_activeBand != null)
                  _ValueBubble(
                    geometry: g,
                    band: _activeBand!,
                    gain: widget.gains[_activeBand!],
                    color: accent,
                    textColor: MobiusColors.onAccentOf(context),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _frequencyLabel(double hz) => hz >= 1000
    ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k'
    : hz.toStringAsFixed(0);

String _gainLabel(double gain) =>
    '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB';

/// Maps frequency/gain to pixels. Bands are octave-spaced, so on a log axis
/// they sit evenly; the axis spans half a band beyond each end.
class _GraphGeometry {
  _GraphGeometry(this.size);

  final Size size;

  static const double leftGutter = 34;
  static const double bottomGutter = 20;
  static const double topPad = 12;
  static const double rightPad = 8;
  static const double displayRangeDb = 15; // a little headroom past ±12

  double get plotLeft => leftGutter;
  double get plotRight => size.width - rightPad;
  double get plotTop => topPad;
  double get plotBottom => size.height - bottomGutter;
  double get plotWidth => math.max(1, plotRight - plotLeft);
  double get plotHeight => math.max(1, plotBottom - plotTop);

  // log2 domain: band 0 is 31 Hz, band 9 is 16 kHz (about 9 octaves).
  static final double _lowLog = _log2(EqualizerResponse.bandsHz.first) - 0.5;
  static final double _highLog = _log2(EqualizerResponse.bandsHz.last) + 0.5;

  static double _log2(double v) => math.log(v) / math.ln2;

  double xForFrequency(double hz) =>
      plotLeft + (_log2(hz) - _lowLog) / (_highLog - _lowLog) * plotWidth;

  double frequencyForX(double x) {
    final t = ((x - plotLeft) / plotWidth).clamp(0.0, 1.0);
    return math.pow(2, _lowLog + t * (_highLog - _lowLog)).toDouble();
  }

  double xForBand(int band) => xForFrequency(EqualizerResponse.bandsHz[band]);

  double get bandSpacing => plotWidth / (_highLog - _lowLog);

  double yForGain(double db) {
    final t =
        (db.clamp(-displayRangeDb, displayRangeDb) + displayRangeDb) /
        (2 * displayRangeDb);
    return plotBottom - t * plotHeight;
  }

  double gainForY(double y) {
    final t = ((plotBottom - y) / plotHeight).clamp(0.0, 1.0);
    return (t * 2 * displayRangeDb - displayRangeDb).clamp(
      EqualizerResponse.minGainDb,
      EqualizerResponse.maxGainDb,
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  _EqualizerPainter({
    required this.gains,
    required this.geometry,
    required this.activeBand,
    required this.accent,
    required this.accentLight,
    required this.grid,
    required this.label,
    required this.handleFill,
  });

  final List<double> gains;
  final _GraphGeometry geometry;
  final int? activeBand;
  final Color accent;
  final Color accentLight;
  final Color grid;
  final Color label;
  final Color handleFill;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = label.withValues(alpha: 0.55)
      ..strokeWidth = 1;

    // Horizontal dB grid.
    for (final db in const [12.0, 6.0, 0.0, -6.0, -12.0]) {
      final y = g.yForGain(db);
      canvas.drawLine(
        Offset(g.plotLeft, y),
        Offset(g.plotRight, y),
        db == 0 ? zeroPaint : gridPaint,
      );
      _text(
        canvas,
        db == 0 ? '0' : '${db > 0 ? '+' : ''}${db.toStringAsFixed(0)}',
        Offset(g.plotLeft - 6, y),
        align: _Align.rightMiddle,
      );
    }

    // Vertical band lines and frequency labels.
    for (var band = 0; band < 10; band++) {
      final x = g.xForBand(band);
      canvas.drawLine(
        Offset(x, g.plotTop),
        Offset(x, g.plotBottom),
        gridPaint..color = grid.withValues(alpha: band == activeBand ? 1 : 0.5),
      );
      _text(
        canvas,
        _frequencyLabel(EqualizerResponse.bandsHz[band]),
        Offset(x, g.plotBottom + 4),
        align: _Align.topCenter,
        emphasized: band == activeBand,
      );
    }

    // Combined response curve, sampled per ~2 px.
    final samples = math.max(2, (g.plotWidth / 2).round());
    final curve = Path();
    for (var i = 0; i <= samples; i++) {
      final x = g.plotLeft + g.plotWidth * i / samples;
      final db = EqualizerResponse.responseDb(gains, g.frequencyForX(x));
      final y = g.yForGain(db);
      i == 0 ? curve.moveTo(x, y) : curve.lineTo(x, y);
    }

    final zeroY = g.yForGain(0);
    final fill = Path.from(curve)
      ..lineTo(g.plotRight, zeroY)
      ..lineTo(g.plotLeft, zeroY)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withValues(alpha: 0.32),
                accent.withValues(alpha: 0.04),
                accent.withValues(alpha: 0.32),
              ],
              stops: const [0, 0.5, 1],
            ).createShader(
              Rect.fromLTRB(g.plotLeft, g.plotTop, g.plotRight, g.plotBottom),
            ),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Band handles: at each band's own gain (the curve shows the sum).
    for (var band = 0; band < 10; band++) {
      final center = Offset(g.xForBand(band), g.yForGain(gains[band]));
      final active = band == activeBand;
      if (active) {
        canvas.drawCircle(
          center,
          13,
          Paint()..color = accent.withValues(alpha: 0.18),
        );
      }
      canvas.drawCircle(center, active ? 7 : 5.5, Paint()..color = handleFill);
      canvas.drawCircle(
        center,
        active ? 7 : 5.5,
        Paint()
          ..color = active ? accentLight : accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor, {
    required _Align align,
    bool emphasized = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: emphasized ? accentLight : label,
          fontSize: 10,
          fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = switch (align) {
      _Align.rightMiddle => anchor - Offset(painter.width, painter.height / 2),
      _Align.topCenter => anchor - Offset(painter.width / 2, 0),
    };
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_EqualizerPainter old) =>
      !_sameGains(old.gains, gains) ||
      old.activeBand != activeBand ||
      old.accent != accent ||
      old.grid != grid ||
      old.label != label ||
      old.handleFill != handleFill ||
      old.geometry.size != geometry.size;

  static bool _sameGains(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

enum _Align { rightMiddle, topCenter }

class _ValueBubble extends StatelessWidget {
  const _ValueBubble({
    required this.geometry,
    required this.band,
    required this.gain,
    required this.color,
    required this.textColor,
  });

  final _GraphGeometry geometry;
  final int band;
  final double gain;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    const width = 108.0;
    final x = geometry.xForBand(band);
    final handleY = geometry.yForGain(gain);
    // Above the handle, or below it when the handle is near the top.
    final top = handleY - 38 < 0 ? handleY + 14 : handleY - 38;
    final left = (x - width / 2).clamp(0.0, geometry.size.width - width);

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            '${_gainLabel(gain)} · ${_frequencyLabel(EqualizerResponse.bandsHz[band])} Hz',
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
