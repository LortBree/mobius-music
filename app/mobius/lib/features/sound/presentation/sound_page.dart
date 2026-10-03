import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/colors.dart';
import '../../../core/ffi/offline_player.dart';
import '../../../playback/playback_settings.dart';
import '../../../playback/player_controller.dart';
import '../../../playback/presentation/volume_control.dart';
import '../../settings/presentation/equalizer_panel.dart';
import '../../settings/presentation/settings_widgets.dart';

/// Everything that shapes what reaches the DAC: the output-mode selector and
/// the equalizer. Split out of Settings because these are adjusted while
/// listening, whereas Settings holds set-once controls.
///
/// State ownership is unchanged from when this lived in Settings: the page
/// reads the output mode from [PlayerController], loads/saves EQ through
/// [SharedPreferences] with the [PlaybackSettings] keys, and pushes changes
/// straight to the controller. Startup restore still happens in
/// [PlaybackSettings.restore], independent of this page.
class SoundPage extends StatefulWidget {
  const SoundPage({super.key, required this.playerController});

  final PlayerController playerController;

  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> {
  static const String _equalizerGainsKey = PlaybackSettings.equalizerGainsKey;
  static const String _equalizerEnabledKey =
      PlaybackSettings.equalizerEnabledKey;
  static const List<double> _flatGains = PlaybackSettings.flatGains;

  static const List<OfflinePlayerOutputMode> _outputModes = [
    OfflinePlayerOutputMode.auto,
    OfflinePlayerOutputMode.khz44_1,
    OfflinePlayerOutputMode.khz48,
  ];

  late OfflinePlayerOutputMode _outputMode;
  List<double> _equalizerGains = List<double>.from(_flatGains);
  bool _equalizerEnabled = false;

  @override
  void initState() {
    super.initState();
    _outputMode = widget.playerController.outputMode;
    _loadEqualizerSettings();
  }

  // ---- Equalizer ---------------------------------------------------------

  Future<void> _loadEqualizerSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final storedGains = preferences.getStringList(_equalizerGainsKey);
    final gains = PlaybackSettings.parseGains(storedGains);
    final enabled = preferences.getBool(_equalizerEnabledKey) ?? false;
    if (!mounted) return;
    setState(() {
      _equalizerGains = gains;
      _equalizerEnabled = enabled;
    });
    _applyEqualizer();
  }

  Future<void> _saveEqualizerSettings() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _equalizerGainsKey,
      _equalizerGains.map((gain) => gain.toString()).toList(),
    );
    await preferences.setBool(_equalizerEnabledKey, _equalizerEnabled);
  }

  void _applyEqualizer() {
    widget.playerController.setEqualizerGains(
      _equalizerEnabled ? _equalizerGains : _flatGains,
    );
  }

  void _updateEqualizer({
    List<double>? gains,
    bool? enabled,
    bool persist = true,
  }) {
    setState(() {
      if (gains != null) _equalizerGains = gains;
      if (enabled != null) _equalizerEnabled = enabled;
    });
    _applyEqualizer();
    if (persist) _saveEqualizerSettings();
  }

  // ---- Output mode -------------------------------------------------------

  void _setOutputMode(OfflinePlayerOutputMode mode) {
    if (mode == _outputMode) return;

    try {
      widget.playerController.setOutputMode(mode);
      unawaited(PlaybackSettings.saveOutputMode(mode));
      if (!mounted) return;
      setState(() => _outputMode = mode);
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  // ---- Volume ------------------------------------------------------------

  /// Live change while dragging (and on a mute toggle): push straight to the
  /// engine. The controller's own [PlayerController.onVolumeChanged] hook
  /// (wired to [PlaybackSettings.saveVolumeSoon]) debounces the write, so the
  /// drag collapses to a single save.
  void _setVolume(double value) {
    try {
      widget.playerController.setVolume(value);
    } catch (error) {
      _showError(error);
    }
  }

  /// Drag settled: persist the final value now rather than only via the
  /// debounce, so a quick drag-and-release is never lost.
  void _commitVolume(double value) {
    try {
      widget.playerController.setVolume(value);
      unawaited(PlaybackSettings.saveVolumeNow(value));
    } catch (error) {
      _showError(error);
    }
  }

  static String _outputModeLabel(OfflinePlayerOutputMode mode) {
    switch (mode) {
      case OfflinePlayerOutputMode.auto:
        return 'Auto';
      case OfflinePlayerOutputMode.khz44_1:
        return '44.1 kHz';
      case OfflinePlayerOutputMode.khz48:
        return '48 kHz';
      case OfflinePlayerOutputMode.khz96:
        return '96 kHz';
    }
  }

  static String _outputModeDescriptionFor(OfflinePlayerOutputMode mode) {
    switch (mode) {
      case OfflinePlayerOutputMode.auto:
        return 'Play every track at its own sample rate (bit-perfect). The '
            'device switches rate between tracks with different rates.';
      case OfflinePlayerOutputMode.khz44_1:
        return 'Use 44.1 kHz as the maximum output rate. Higher-rate sources are resampled.';
      case OfflinePlayerOutputMode.khz48:
        return 'Use 48 kHz as the maximum output rate. Higher-rate sources are resampled.';
      case OfflinePlayerOutputMode.khz96:
        return 'Use 96 kHz as the maximum output rate when the device supports it.';
    }
  }

  Widget _buildOutputModeDescription() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 20, right: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: MobiusColors.textDimOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _outputModeDescriptionFor(_outputMode),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 12, 36, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsPageHeader(
                title: 'Sound',
                subtitle: 'Shape what reaches your DAC.',
              ),
              const SizedBox(height: 32),
              const SettingsSectionTitle('Output'),
              const SizedBox(height: 16),
              SettingsRow(
                title: 'Output mode',
                description:
                    'Controls the maximum output sample rate used by Mobius.',
                trailing: SettingsDropdown<OfflinePlayerOutputMode>(
                  value: _outputMode,
                  items: _outputModes,
                  labelFor: _outputModeLabel,
                  onChanged: _setOutputMode,
                ),
              ),
              _buildOutputModeDescription(),
              const SizedBox(height: 32),
              const SettingsSectionTitle('Volume'),
              const SizedBox(height: 16),
              SettingsRow(
                title: 'Output volume',
                description:
                    'Sets the playback level. The speaker icon mutes; the '
                    'up/down arrow keys adjust it too.',
                trailing: VolumeControl(
                  volume: widget.playerController.volumeListenable,
                  onChanged: _setVolume,
                  onChangeEnd: _commitVolume,
                  sliderWidth: 180,
                ),
              ),
              const SizedBox(height: 32),
              // EqualizerPanel carries its own "Equalizer" heading and switch.
              EqualizerPanel(
                gains: _equalizerGains,
                enabled: _equalizerEnabled,
                onGainsChanged: (gains, {required commit}) =>
                    _updateEqualizer(gains: gains, persist: commit),
                onEnabledChanged: (enabled) =>
                    _updateEqualizer(enabled: enabled),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
