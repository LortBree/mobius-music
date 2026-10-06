import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/theme/colors.dart';
import '../../../app/mobius_app.dart' show ThemeModeController;
import '../../../core/platform/folder_access.dart';
import '../../../playback/player_controller.dart';
import '../../library/data/ffi_library_repository.dart';
import 'settings_widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.playerController,
    required this.repository,
    required this.onLibraryChanged,
    required this.themeController,
    this.onOpenSound,
  });

  final PlayerController playerController;
  final FfiLibraryRepository repository;
  final VoidCallback onLibraryChanged;
  final ThemeModeController themeController;

  /// When non-null, a "Sound" row is rendered that invokes this to push the
  /// Sound page as its own route. Supplied by the mobile shell (where Sound
  /// is not a bottom-nav tab); the desktop shell passes nothing, so its
  /// Settings page is unchanged.
  final VoidCallback? onOpenSound;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String _musicFoldersKey = 'music_folders';

  List<String> _musicFolders = [];
  bool _loadingFolders = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();

    _loadMusicFolders();
  }

  Future<void> _loadMusicFolders() async {
    final preferences = await SharedPreferences.getInstance();

    final folders = preferences.getStringList(_musicFoldersKey) ?? [];

    final restoredFolders = <String>[];

    for (final folder in folders) {
      try {
        final restoredPath = await FolderAccess.restore(folder);

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
    final directory = await FolderAccess.pickFolder(
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
      final bookmarkSaved = await FolderAccess.persist(directory);

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

      await FolderAccess.remove(directory);
      _showError(error);
    }
  }

  Future<void> _removeMusicFolder(String folder) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: MobiusColors.panelOf(context),
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
                backgroundColor: MobiusColors.accentOf(context),
                foregroundColor: MobiusColors.onAccentOf(context),
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
      await FolderAccess.remove(folder);
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

  Widget _themeSelector() {
    String label(ThemeMode mode) => switch (mode) {
      ThemeMode.dark => 'Deep Sea (Dark)',
      ThemeMode.light => 'Sungaze (Light)',
      ThemeMode.system => 'System',
    };

    return SettingsDropdown<ThemeMode>(
      value: widget.themeController.mode,
      items: const [ThemeMode.dark, ThemeMode.light, ThemeMode.system],
      labelFor: label,
      onChanged: widget.themeController.setMode,
    );
  }

  Widget _buildMusicFolders() {
    if (_loadingFolders) {
      return Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MobiusColors.panelOf(context),
          border: Border.all(color: MobiusColors.borderOf(context)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: MobiusColors.accentOf(context),
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
              color: MobiusColors.panelOf(context),
              border: Border.all(color: MobiusColors.borderOf(context)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'No music folders configured.',
              style: TextStyle(
                color: MobiusColors.textDimOf(context),
                fontSize: 13,
              ),
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
            icon: Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Music Folder'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MobiusColors.textOf(context),
              side: BorderSide(color: MobiusColors.borderOf(context)),
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
        color: MobiusColors.panelOf(context),
        border: Border.all(color: MobiusColors.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 19,
            color: MobiusColors.textDimOf(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              folder,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: MobiusColors.textOf(context),
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Remove folder',
            onPressed: _scanning ? null : () => _removeMusicFolder(folder),
            icon: Icon(Icons.close_rounded, size: 18),
            color: MobiusColors.textDimOf(context),
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
        color: MobiusColors.panelOf(context),
        border: Border.all(color: MobiusColors.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan library',
                  style: TextStyle(
                    color: MobiusColors.textOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Scan all configured music folders for new and changed tracks.',
                  style: TextStyle(
                    color: MobiusColors.textDimOf(context),
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
              backgroundColor: MobiusColors.accentOf(context),
              foregroundColor: MobiusColors.onAccentOf(context),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _scanning
                ? SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MobiusColors.onAccentOf(context),
                    ),
                  )
                : const Text('Scan Library'),
          ),
        ],
      ),
    );
  }

  /// Mobile-only entry that opens the Sound page as its own route. Styled as
  /// a tappable [SettingsRow]-shaped card with a leading icon and a chevron.
  Widget _soundEntryRow() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onOpenSound,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: MobiusColors.panelOf(context),
            border: Border.all(color: MobiusColors.borderOf(context)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 22,
                color: MobiusColors.accentOf(context),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sound',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Output, volume & equalizer',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: MobiusColors.textDimOf(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _volumeNormalizationRow() {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.playerController.volumeNormalizationListenable,
      builder: (context, enabled, _) {
        return SettingsRow(
          title: 'Volume Normalization',
          description:
              'Equalizes perceived loudness across all tracks to prevent sudden loudness jumps. Automatically bypassed in Bit-Perfect mode.',
          trailing: Switch.adaptive(
            value: enabled,
            onChanged: (val) {
              widget.playerController.setVolumeNormalization(val);
            },
          ),
        );
      },
    );
  }

  Widget _buildUsbDacSection() {
    final usb = widget.playerController.usbDacService;
    return ListenableBuilder(
      listenable: usb,
      builder: (context, _) {
        final status = usb.status;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: MobiusColors.panelOf(context),
            border: Border.all(color: MobiusColors.borderOf(context)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: status.attached
                          ? (status.hasPermission
                              ? MobiusColors.nativeOf(context).withValues(alpha: 0.15)
                              : MobiusColors.accentOf(context).withValues(alpha: 0.15))
                          : MobiusColors.textDimOf(context).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.usb_rounded,
                      size: 22,
                      color: status.attached
                          ? (status.hasPermission
                              ? MobiusColors.nativeOf(context)
                              : MobiusColors.accentOf(context))
                          : MobiusColors.textDimOf(context),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                status.attached
                                    ? (status.name.isNotEmpty ? status.name : 'FiiO JadeAudio JA11')
                                    : 'No USB DAC Attached',
                                style: TextStyle(
                                  color: MobiusColors.textOf(context),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (status.attached && status.hasPermission)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: MobiusColors.nativeOf(context).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: MobiusColors.nativeOf(context).withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  'Bit-Perfect',
                                  style: TextStyle(
                                    color: MobiusColors.nativeOf(context),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status.attached
                              ? (status.hasPermission
                                  ? 'Direct UAC2 • Kernel Bypass • VID: 0x${status.vid.toRadixString(16)}, PID: 0x${status.pid.toRadixString(16)}'
                                  : 'Permission required for bit-perfect hardware access')
                              : 'Connect a USB-C Audio DAC (e.g. FiiO JA11)',
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!status.attached) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => usb.checkDevice(),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Scan Devices'),
                  ),
                ),
              ] else if (!status.hasPermission) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => usb.requestPermission(),
                    icon: const Icon(Icons.lock_open_rounded, size: 16),
                    label: const Text('Grant Exclusive USB Access'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MobiusColors.accentOf(context),
                      foregroundColor: MobiusColors.onAccentOf(context),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                ValueListenableBuilder<bool>(
                  valueListenable: widget.playerController.bitPerfectModeListenable,
                  builder: (context, isBitPerfect, _) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Output Audio Mode',
                              style: TextStyle(
                                color: MobiusColors.textOf(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
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
                              widget.playerController.setBitPerfectMode(selection.first);
                            },
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.comfortable,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isBitPerfect
                              ? 'Direct UAC2 passthrough (0 dBFS digital). Volume controlled via DAC hardware amplifier.'
                              : 'Software digital attenuation and DSP equalizer enabled.',
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                // Driver status description
                Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 16, color: MobiusColors.nativeOf(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Direct Isochronous UAC2 streaming active. AudioFlinger mixer bypassed.',
                        style: TextStyle(
                          color: MobiusColors.textDimOf(context),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }


  Widget _aboutRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: MobiusColors.panelOf(context),
        border: Border.all(color: MobiusColors.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mobius Music',
                  style: TextStyle(
                    color: MobiusColors.textOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Offline hi-res music player',
                  style: TextStyle(
                    color: MobiusColors.textDimOf(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '1.2.0',
            style: TextStyle(
              color: MobiusColors.textDimOf(context),
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
      padding: const EdgeInsets.fromLTRB(32, 12, 36, 24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SettingsPageHeader(
                title: 'Settings',
                subtitle: 'Manage your library and appearance.',
              ),
              const SizedBox(height: 32),
              const SettingsSectionTitle('Library'),
              const SizedBox(height: 16),
              _buildMusicFolders(),
              const SizedBox(height: 16),
              _buildScanRow(),
              const SizedBox(height: 40),
              const SettingsSectionTitle('Appearance'),
              const SizedBox(height: 16),
              SettingsRow(
                title: 'Theme',
                description:
                    'Deep Sea dark, Sungaze light, or match the system setting.',
                trailing: _themeSelector(),
              ),
              const SizedBox(height: 40),
              const SettingsSectionTitle('Playback'),
              const SizedBox(height: 16),
              if (widget.onOpenSound != null) ...[
                _soundEntryRow(),
                const SizedBox(height: 16),
              ],
              _volumeNormalizationRow(),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 40),
                const SettingsSectionTitle('USB DAC (Bit-Perfect)'),
                const SizedBox(height: 16),
                _buildUsbDacSection(),
              ],
              const SizedBox(height: 40),
              const SettingsSectionTitle('About'),
              const SizedBox(height: 16),
              _aboutRow(),
            ],
          ),
        ),
      ),
    );
  }
}
