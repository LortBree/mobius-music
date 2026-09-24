import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/colors.dart';
import '../../../core/ffi/offline_player.dart';
import '../../../playback/player_controller.dart';
import '../../library/data/ffi_library_repository.dart';
import '../../../core/macos/macos_folder_access.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.playerController,
    required this.repository,
    required this.onLibraryChanged,
  });

  final PlayerController playerController;
  final FfiLibraryRepository repository;
  final VoidCallback onLibraryChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String _musicFoldersKey = 'music_folders';
  static const String _equalizerGainsKey = 'equalizer_gains_v1';
  static const String _equalizerEnabledKey = 'equalizer_enabled_v1';

  static const List<double> _flatGains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  static const List<double> _equalizerFrequencies = [
    31,
    62,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];
  static const Map<String, List<double>> _equalizerPresets = {
    'Flat': _flatGains,
    'Bass boost': [-2, 3, 4, 2, 0, 0, 0, 0, 1, 1],
    'Treble boost': [0, 0, 0, 0, 0, 0, 1, 2, 3, 3],
    'Vocal': [-2, -1, 0, 1, 2, 2, 1, 0, -1, -2],
  };

  late OfflinePlayerOutputMode _outputMode;
  List<double> _equalizerGains = List<double>.from(_flatGains);
  bool _equalizerEnabled = false;
  String _selectedEqualizerPreset = 'Flat';

  List<String> _musicFolders = [];
  bool _loadingFolders = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();

    _outputMode = widget.playerController.outputMode;
    _loadMusicFolders();
    _loadEqualizerSettings();
  }

  Future<void> _loadEqualizerSettings() async {
    final preferences = await SharedPreferences.getInstance();
    final storedGains = preferences.getStringList(_equalizerGainsKey);
    final gains = storedGains == null || storedGains.length != 10
        ? List<double>.from(_flatGains)
        : storedGains.map<double>((value) {
            final parsed = double.tryParse(value) ?? 0;
            return parsed.isFinite
                ? parsed.clamp(-12.0, 12.0).toDouble()
                : 0.0;
          }).toList();
    final enabled = preferences.getBool(_equalizerEnabledKey) ?? false;
    if (!mounted) return;
    setState(() {
      _equalizerGains = gains;
      _equalizerEnabled = enabled;
      _selectedEqualizerPreset = _presetFor(gains);
    });
    _applyEqualizer();
  }

  String _presetFor(List<double> gains) {
    for (final entry in _equalizerPresets.entries) {
      if (List.generate(10, (index) => (entry.value[index] - gains[index]).abs())
          .every((difference) => difference < 0.01)) {
        return entry.key;
      }
    }
    return 'Custom';
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
    String? preset,
    bool persist = true,
  }) {
    setState(() {
      if (gains != null) _equalizerGains = gains;
      if (enabled != null) _equalizerEnabled = enabled;
      _selectedEqualizerPreset = preset ?? _presetFor(_equalizerGains);
    });
    _applyEqualizer();
    if (persist) _saveEqualizerSettings();
  }

  Widget _buildEqualizer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MobiusColors.panel,
        border: Border.all(color: MobiusColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equalizer',
                      style: TextStyle(
                        color: MobiusColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Adjust ten frequency bands while listening.',
                      style: TextStyle(color: MobiusColors.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              DropdownButton<String>(
                value: _selectedEqualizerPreset == 'Custom'
                    ? 'Custom'
                    : _selectedEqualizerPreset,
                dropdownColor: MobiusColors.panel,
                underline: const SizedBox.shrink(),
                items: [
                  ..._equalizerPresets.keys.map(
                    (preset) => DropdownMenuItem(
                      value: preset,
                      child: Text(preset),
                    ),
                  ),
                  if (_selectedEqualizerPreset == 'Custom')
                    const DropdownMenuItem(
                      value: 'Custom',
                      child: Text('Custom'),
                    ),
                ],
                onChanged: (preset) {
                  if (preset == null || preset == 'Custom') return;
                  _updateEqualizer(
                    gains: List<double>.from(_equalizerPresets[preset]!),
                    preset: preset,
                  );
                },
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: _equalizerEnabled,
                activeTrackColor: MobiusColors.purple,
                onChanged: (enabled) => _updateEqualizer(enabled: enabled),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Opacity(
            opacity: _equalizerEnabled ? 1 : 0.48,
            child: IgnorePointer(
              ignoring: !_equalizerEnabled,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 12,
                children: List.generate(_equalizerFrequencies.length, (index) {
                  final frequency = _equalizerFrequencies[index];
                  return SizedBox(
                    width: 56,
                    child: Column(
                      children: [
                        Text(
                          '${_equalizerGains[index].toStringAsFixed(1)} dB',
                          style: const TextStyle(
                            color: MobiusColors.textDim,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 38,
                          height: 148,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SizedBox(
                              width: 148,
                              child: Slider(
                                value: _equalizerGains[index],
                                min: -12,
                                max: 12,
                                divisions: 48,
                                activeColor: MobiusColors.purple,
                                onChanged: (value) {
                                  final gains = List<double>.from(_equalizerGains);
                                  gains[index] = value;
                                  _updateEqualizer(gains: gains, persist: false);
                                },
                                onChangeEnd: (value) {
                                  final gains = List<double>.from(_equalizerGains);
                                  gains[index] = value;
                                  _updateEqualizer(gains: gains);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          frequency >= 1000
                              ? '${(frequency / 1000).toStringAsFixed(frequency % 1000 == 0 ? 0 : 1)}k'
                              : '${frequency.toInt()}',
                          style: const TextStyle(
                            color: MobiusColors.textDim,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMusicFolders() async {
    final preferences = await SharedPreferences.getInstance();

    final folders = preferences.getStringList(_musicFoldersKey) ?? [];

    final restoredFolders = <String>[];

    for (final folder in folders) {
      try {
        final restoredPath = await MacOSFolderAccess.restoreBookmark(folder);

        if (restoredPath != null && restoredPath.isNotEmpty) {
          restoredFolders.add(restoredPath);
        }
      } catch (_) {
        // Existing folders created before security-scoped bookmarks
        // were implemented need to be selected again once.
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _musicFolders = restoredFolders;
      _loadingFolders = false;
    });

    if (restoredFolders.length != folders.length) {
      await preferences.setStringList(_musicFoldersKey, restoredFolders);
    }
  }

  Future<void> _saveMusicFolders() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setStringList(_musicFoldersKey, _musicFolders);
  }

  Future<void> _addMusicFolder() async {
    final directory = await getDirectoryPath(
      confirmButtonText: 'Choose Folder',
    );

    if (directory == null || directory.isEmpty) {
      return;
    }

    if (_musicFolders.contains(directory)) {
      _showMessage('Folder is already in your library.');
      return;
    }

    try {
      final bookmarkSaved = await MacOSFolderAccess.saveBookmark(directory);

      if (!bookmarkSaved) {
        throw StateError(
          'Mobius could not save access permission for this folder.',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _musicFolders = [..._musicFolders, directory];
      });

      await _saveMusicFolders();

      if (!mounted) {
        return;
      }

      _showMessage('Music folder added.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _musicFolders = List<String>.from(_musicFolders)..remove(directory);
      });

      await MacOSFolderAccess.removeBookmark(directory);
      _showError(error);
    }
  }

  Future<void> _removeMusicFolder(String folder) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('Remove music folder?'),
          content: Text(
            'Remove this folder from Mobius library sources?\n\n$folder',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8A63D2),
                foregroundColor: const Color(0xFFFAFAFA),
                elevation: 0,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (shouldRemove != true || !mounted) {
      return;
    }

    final previousFolders = List<String>.from(_musicFolders);

    setState(() {
      _musicFolders = List<String>.from(_musicFolders)..remove(folder);
    });

    try {
      await MacOSFolderAccess.removeBookmark(folder);
      await _saveMusicFolders();

      if (!mounted) {
        return;
      }

      _showMessage('Music folder removed.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _musicFolders = previousFolders;
      });

      _showError(error);
    }
  }

  Future<void> _scanLibrary() async {
    if (_scanning) {
      return;
    }

    if (_musicFolders.isEmpty) {
      _showMessage('Add at least one music folder first.');
      return;
    }

    setState(() {
      _scanning = true;
    });

    try {
      var added = 0;
      var updated = 0;
      var removed = 0;
      var total = 0;

      for (final folder in _musicFolders) {
        final result = widget.repository.scan(folder);

        added += result.added;
        updated += result.updated;
        removed += result.removed;
        total = result.total;
      }

      widget.onLibraryChanged();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Library scan completed: '
            '$total tracks, '
            '$added added, '
            '$updated updated, '
            '$removed removed.',
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  void _setOutputMode(OfflinePlayerOutputMode mode) {
    if (mode == _outputMode) {
      return;
    }

    try {
      widget.playerController.setOutputMode(mode);

      if (!mounted) {
        return;
      }

      setState(() {
        _outputMode = mode;
      });
    } catch (error) {
      _showError(error);
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(Object error) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  String _outputModeLabel(OfflinePlayerOutputMode mode) {
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

  String _outputModeDescriptionFor(OfflinePlayerOutputMode mode) {
    switch (mode) {
      case OfflinePlayerOutputMode.auto:
        return 'Follow the source sample rate when the device supports it.';
      case OfflinePlayerOutputMode.khz44_1:
        return 'Use 44.1 kHz as the maximum output rate. Higher-rate sources are resampled.';
      case OfflinePlayerOutputMode.khz48:
        return 'Use 48 kHz as the maximum output rate. Higher-rate sources are resampled.';
      case OfflinePlayerOutputMode.khz96:
        return 'Use 96 kHz as the maximum output rate when the device supports it.';
    }
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _settingRow({
    required String title,
    required String description,
    required Widget trailing,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: MobiusColors.panel,
        border: Border.all(color: MobiusColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),
          trailing,
        ],
      ),
    );
  }

  Widget _outputModeSelector() {
    const modes = <OfflinePlayerOutputMode>[
      OfflinePlayerOutputMode.auto,
      OfflinePlayerOutputMode.khz44_1,
      OfflinePlayerOutputMode.khz48,
      OfflinePlayerOutputMode.khz96,
    ];

    return SizedBox(
      width: 170,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<OfflinePlayerOutputMode>(
          value: _outputMode,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF9A9A9A),
          ),
          style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 14),
          items: [
            for (final mode in modes)
              DropdownMenuItem<OfflinePlayerOutputMode>(
                value: mode,
                child: Text(_outputModeLabel(mode)),
              ),
          ],
          onChanged: (mode) {
            if (mode != null) {
              _setOutputMode(mode);
            }
          },
        ),
      ),
    );
  }

  Widget _buildOutputModeDescription() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, left: 20, right: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: Color(0xFF9A9A9A),
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

  Widget _buildMusicFolders() {
    if (_loadingFolders) {
      return Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MobiusColors.panel,
          border: Border.all(color: MobiusColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF8A63D2),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_musicFolders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: const Color(0xFF2A2A2A)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'No music folders configured.',
              style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
            ),
          )
        else
          for (final folder in _musicFolders) ...[
            _musicFolderRow(folder),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addMusicFolder,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Music Folder'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEDEDED),
              side: const BorderSide(color: Color(0xFF3A3A3A)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _musicFolderRow(String folder) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 19, color: Color(0xFF9A9A9A)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              folder,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFEDEDED),
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Remove folder',
            onPressed: _scanning ? null : () => _removeMusicFolder(folder),
            icon: const Icon(Icons.close_rounded, size: 18),
            color: const Color(0xFF9A9A9A),
          ),
        ],
      ),
    );
  }

  Widget _buildScanRow() {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan library',
                  style: TextStyle(
                    color: Color(0xFFEDEDED),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Scan all configured music folders for new and changed tracks.',
                  style: TextStyle(
                    color: Color(0xFF9A9A9A),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          FilledButton(
            onPressed: _scanning ? null : _scanLibrary,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8A63D2),
              foregroundColor: const Color(0xFFFAFAFA),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _scanning
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFAFAFA),
                    ),
                  )
                : const Text('Scan Library'),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: const Color(0xFF2A2A2A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mobius',
                  style: TextStyle(
                    color: Color(0xFFEDEDED),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Offline hi-res music player',
                  style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
                ),
              ],
            ),
          ),
          Text(
            '1.0.0',
            style: TextStyle(
              color: Color(0xFF9A9A9A),
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 36, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 42,
                  fontWeight: FontWeight.w600,
                  color: MobiusColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage your library and audio output.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              _sectionTitle('Library'),
              const SizedBox(height: 16),
              _buildMusicFolders(),
              const SizedBox(height: 16),
              _buildScanRow(),
              const SizedBox(height: 40),
              _sectionTitle('Audio'),
              const SizedBox(height: 16),
              _settingRow(
                title: 'Output mode',
                description:
                    'Controls the maximum output sample rate used by Mobius.',
                trailing: _outputModeSelector(),
              ),
              _buildOutputModeDescription(),
              const SizedBox(height: 16),
              _buildEqualizer(),
              const SizedBox(height: 40),
              _sectionTitle('About'),
              const SizedBox(height: 16),
              _aboutRow(),
            ],
          ),
        ),
      ),
    );
  }
}
