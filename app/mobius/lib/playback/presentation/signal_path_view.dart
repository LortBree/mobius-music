import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../core/audio/signal_path.dart';
import '../player_controller.dart';

/// Formats a sample rate as a compact `kHz` figure: `48000 -> 48`, `44100 ->
/// 44.1`, `0 -> --`. Shared by the strip and the sheet.
String _khz(int rate) {
  if (rate <= 0) return '--';
  if (rate % 1000 == 0) return '${rate ~/ 1000}';
  return (rate / 1000).toStringAsFixed(1);
}

/// Short label for a route when no device name is known.
String routeLabel(OutputRoute route) {
  switch (route) {
    case OutputRoute.speaker:
      return 'Speaker';
    case OutputRoute.wired:
      return 'Wired';
    case OutputRoute.bluetooth:
      return 'Bluetooth';
    case OutputRoute.usb:
      return 'USB';
    case OutputRoute.unknown:
      return 'Output';
  }
}

/// Builds the one-line strip caption, e.g.
/// `FLAC 24/48 → EQ → AAudio 48k → Speaker`.
///
/// Pulled out as a pure function so it can be unit-tested without pumping a
/// widget.
String signalPathSummary(SignalPath path) {
  final source = StringBuffer();
  if (path.sourceFormat.isNotEmpty) source.write('${path.sourceFormat} ');
  source.write('${path.sourceBitsPerSample}/${_khz(path.sourceSampleRate)}');

  final stages = <String>[source.toString().trim()];
  if (path.equalizerActive) stages.add('EQ');
  if (path.resampling) stages.add('Resample');
  final api = path.outputApi.isEmpty ? 'Output' : path.outputApi;
  stages.add('$api ${_khz(path.outputSampleRate)}k');
  final device = path.deviceName.isNotEmpty
      ? path.deviceName
      : routeLabel(path.route);
  stages.add(device);

  return stages.join(' → ');
}

/// The inline signal-path strip shown under the Now Playing title. Tapping it
/// opens the [SignalPathSheet]. The trailing dot is amber for standard output
/// and green only when the engine confirms a bit-perfect path.
///
/// Pure presentation: the owner passes the already-resolved [SignalPath]
/// (from `PlayerController.readSignalPath()`), and refreshes it on its own
/// cadence. [path] may be null — then the strip renders a muted
/// "Nothing playing" line and the tap is disabled.
class SignalPathStrip extends StatelessWidget {
  const SignalPathStrip({super.key, required this.path, this.onTap});

  final SignalPath? path;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    final dim = MobiusColors.textDimOf(context);

    if (path == null) {
      return Semantics(
        label: 'Signal path: nothing playing',
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(Icons.graphic_eq_rounded, size: 14, color: dim),
            const SizedBox(width: 8),
            Text('Nothing playing', style: TextStyle(color: dim, fontSize: 12)),
          ],
        ),
      );
    }

    final dotColor = path.bitPerfect
        ? MobiusColors.nativeOf(context)
        : MobiusColors.compatibleOf(context);

    return Semantics(
      button: onTap != null,
      label: 'Signal path: ${signalPathSummary(path)}',
      excludeSemantics: true,
      child: Material(
        color: MobiusColors.panelOf(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    signalPathSummary(path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: MobiusColors.textOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the signal-path detail bottom sheet. [path] is resolved by the caller
/// (`readSignalPath()`); when null the sheet shows "Nothing playing".
Future<void> showSignalPathSheet(
  BuildContext context, {
  required SignalPath? path,
  PlayerController? controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MobiusColors.backgroundOf(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => SignalPathSheet(path: path, controller: controller),
  );
}

/// The signal-path detail sheet: status header, a vertical timeline of the
/// stages (Source → Decoder → DSP → Resampler → Output → Device), a verdict
/// card, and a telemetry row (buffer / underruns / callbacks).
///
/// Bypassed stages (DSP when !dspActive, Resampler when !resampling) are
/// dimmed rather than hidden, so the full chain is always legible.
class SignalPathSheet extends StatelessWidget {
  const SignalPathSheet({super.key, required this.path, this.controller});

  final SignalPath? path;
  final PlayerController? controller;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: MobiusColors.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (path == null)
              _buildEmpty(context)
            else
              _buildContent(context, path),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 36,
            color: MobiusColors.textDimOf(context),
          ),
          const SizedBox(height: 12),
          Text(
            'Nothing playing',
            style: TextStyle(
              color: MobiusColors.textDimOf(context),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SignalPath path) {
    final isBitPerfect = path.bitPerfect;
    final statusColor = isBitPerfect
        ? MobiusColors.nativeOf(context)
        : MobiusColors.compatibleOf(context);
    final statusText = isBitPerfect ? 'BIT-PERFECT' : 'STANDARD';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              'Signal path',
              style: TextStyle(
                color: MobiusColors.textOf(context),
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withValues(alpha: 0.55)),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        if (controller != null && path.route == OutputRoute.usb) ...[
          const SizedBox(height: 14),
          _UsbModeCard(controller: controller!),
        ],
        const SizedBox(height: 18),
        _Timeline(path: path),
        const SizedBox(height: 18),
        _VerdictCard(
          isBitPerfect: isBitPerfect,
          isUsb: path.route == OutputRoute.usb,
        ),
        const SizedBox(height: 16),
        _TelemetryRow(path: path),
      ],
    );
  }
}

/// A vertical stage timeline with a glowing connector line and a dot per
/// stage. Dimmed stages read as present-but-inactive.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.path});

  final SignalPath path;

  @override
  Widget build(BuildContext context) {
    final channels = switch (path.sourceChannels) {
      1 => 'Mono',
      2 => 'Stereo',
      _ => '${path.sourceChannels} ch',
    };
    final sourceLines = [
      '${path.sourceFormat.isEmpty ? 'PCM' : path.sourceFormat} · '
          '${path.sourceBitsPerSample}-bit · '
          '${_khz(path.sourceSampleRate)} kHz · $channels',
      if (path.lossless) 'Lossless',
    ].join('\n');

    final outBits = path.outputIsFloat
        ? 'float32'
        : '${path.outputBitsPerSample}-bit';
    final api = path.outputApi.isEmpty ? 'Output' : path.outputApi;

    final deviceLabel = path.deviceName.isNotEmpty
        ? path.deviceName
        : routeLabel(path.route);

    final stages = <_Stage>[
      _Stage('Source', sourceLines, active: true),
      _Stage('Decoder', 'Mobius core', active: true),
      _Stage(
        'DSP',
        path.dspActive ? _dspDescription(path) : 'Passthrough',
        active: path.dspActive,
      ),
      _Stage(
        'Resampler',
        path.resampling ? 'Converting rate' : 'Bypassed',
        active: path.resampling,
      ),
      _Stage(
        'Output',
        '$api · $outBits · ${_khz(path.outputSampleRate)} kHz',
        active: true,
      ),
      _Stage('Device', deviceLabel, active: true),
    ];

    return Column(
      children: [
        for (var i = 0; i < stages.length; i++)
          _StageTile(stage: stages[i], isLast: i == stages.length - 1),
      ],
    );
  }

  static String _dspDescription(SignalPath path) {
    final parts = <String>[];
    if (path.equalizerActive) parts.add('EQ ${path.equalizerBands}-band');
    final isUsb = path.deviceName.toLowerCase().contains('usb') ||
        path.deviceName.toLowerCase().contains('uac') ||
        path.outputApi.toLowerCase().contains('uac') ||
        path.deviceName.toLowerCase().contains('jade');
    if (!isUsb && path.volume < 0.999) {
      parts.add('Volume ${(path.volume * 100).round()}%');
    }
    return parts.isEmpty ? 'Passthrough' : parts.join(' · ');
  }
}

class _Stage {
  const _Stage(this.title, this.detail, {required this.active});

  final String title;
  final String detail;
  final bool active;
}

class _StageTile extends StatelessWidget {
  const _StageTile({required this.stage, required this.isLast});

  final _Stage stage;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final accent = MobiusColors.accentLightOf(context);
    final dotColor = stage.active ? accent : MobiusColors.borderOf(context);
    final titleColor = stage.active
        ? MobiusColors.textOf(context)
        : MobiusColors.textDimOf(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: stage.active
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: MobiusColors.borderOf(context),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.title,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stage.detail,
                    style: TextStyle(
                      color: MobiusColors.textDimOf(context),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.isBitPerfect, this.isUsb = false});

  final bool isBitPerfect;
  final bool isUsb;

  @override
  Widget build(BuildContext context) {
    final text = isBitPerfect
        ? 'The engine delivers these samples untouched to the device (Hardware Volume active).'
        : isUsb
            ? 'Direct USB path is active, but EQ or resampling '
                'is changing the samples. Turn EQ and resampling off for bit-perfect.'
            : "Android's mixer owns this route and may resample or mix. "
                'Bit-perfect needs a USB DAC path.';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MobiusColors.panelOf(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MobiusColors.borderOf(context)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: MobiusColors.textDimOf(context),
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}

class _TelemetryRow extends StatelessWidget {
  const _TelemetryRow({required this.path});

  final SignalPath path;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _cell(context, 'Buffer', '${path.bufferMs} ms'),
        _cell(context, 'Underruns', '${path.underrunSamples}'),
        _cell(context, 'Callbacks', '${path.callbackCount}'),
      ],
    );
  }

  Widget _cell(BuildContext context, String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: MobiusColors.panelOf(context).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: MobiusColors.textOf(context),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: MobiusColors.textDimOf(context),
                fontSize: 11,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsbModeCard extends StatelessWidget {
  const _UsbModeCard({required this.controller});

  final PlayerController controller;

  String _formatDb(double v) {
    if (v <= 0.001) return '-50.0 dB';
    final db = -50.0 * (1.0 - math.sqrt(v.clamp(0.001, 1.0)));
    return '${db.toStringAsFixed(1)} dB';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.bitPerfectModeListenable,
      builder: (context, isBitPerfect, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MobiusColors.panelOf(context).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isBitPerfect
                  ? MobiusColors.nativeOf(context).withValues(alpha: 0.5)
                  : MobiusColors.borderOf(context),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Title & Active Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Audio Output Mode',
                    style: TextStyle(
                      color: MobiusColors.textOf(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isBitPerfect
                          ? MobiusColors.nativeOf(context).withValues(alpha: 0.15)
                          : MobiusColors.accentOf(context).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isBitPerfect
                            ? MobiusColors.nativeOf(context).withValues(alpha: 0.3)
                            : MobiusColors.accentOf(context).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      isBitPerfect ? 'Bit-Perfect' : 'Standard',
                      style: TextStyle(
                        color: isBitPerfect
                            ? MobiusColors.nativeOf(context)
                            : MobiusColors.accentOf(context),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Full-width Mode Switcher
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Bit-Perfect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      icon: Icon(Icons.bolt_rounded, size: 16),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Standard', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      icon: Icon(Icons.tune_rounded, size: 16),
                    ),
                  ],
                  selected: {isBitPerfect},
                  onSelectionChanged: (selection) {
                    controller.setBitPerfectMode(selection.first);
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.comfortable,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Hardware Volume (DAC Amp)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: controller.hardwareVolumeListenable,
                    builder: (context, hwVol, _) {
                      final pct = (hwVol * 100).round();
                      final db = _formatDb(hwVol);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Hardware Volume (DAC Amp)',
                                style: TextStyle(
                                  color: MobiusColors.textDimOf(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '$pct% ($db)',
                                style: TextStyle(
                                  color: MobiusColors.textOf(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            ),
                            child: Slider(
                              value: hwVol,
                              activeColor: isBitPerfect
                                  ? MobiusColors.nativeOf(context)
                                  : MobiusColors.accentOf(context),
                              onChanged: (val) => controller.setHardwareVolume(val),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Software Volume or Bit-Perfect Passthrough Badge
              if (!isBitPerfect) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: controller.volumeListenable,
                      builder: (context, swVol, _) {
                        final pct = (swVol * 100).round();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Software Volume (Digital Attenuation)',
                                  style: TextStyle(
                                    color: MobiusColors.textDimOf(context),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '$pct%',
                                  style: TextStyle(
                                    color: MobiusColors.textOf(context),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              ),
                              child: Slider(
                                value: swVol,
                                activeColor: MobiusColors.accentOf(context),
                                onChanged: (val) => controller.setVolume(val),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: MobiusColors.nativeOf(context).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: MobiusColors.nativeOf(context).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: MobiusColors.nativeOf(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Software Volume locked at 100% · Direct Bit-Perfect Passthrough',
                          style: TextStyle(
                            color: MobiusColors.nativeOf(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

