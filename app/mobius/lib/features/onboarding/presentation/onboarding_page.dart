import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/player_shell_state.dart' show kMobileBreakpoint;
import '../../../app/theme/colors.dart';
import '../../../core/platform/folder_access.dart';
import '../../library/data/ffi_library_repository.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.repository,
    required this.onComplete,
  });

  final FfiLibraryRepository repository;
  final VoidCallback onComplete;

  static const String onboardingCompletedKey = 'mobius_onboarding_completed_v1';
  static const String musicFoldersKey = 'music_folders';

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _isProcessing = false;
  String? _statusMessage;
  String? _selectedFolderPath;
  int _scannedTrackCount = 0;

  Future<void> _handleUseLocalStorage() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Selecting folder...';
    });

    try {
      final directory = await FolderAccess.pickFolder(
        confirmButtonText: 'Choose Music Folder',
      );

      if (directory == null || directory.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = null;
        });
        return;
      }

      setState(() {
        _statusMessage = 'Saving permission & scanning music...';
      });

      await FolderAccess.persist(directory);

      final prefs = await SharedPreferences.getInstance();
      final existingFolders = prefs.getStringList(OnboardingPage.musicFoldersKey) ?? [];
      if (!existingFolders.contains(directory)) {
        await prefs.setStringList(
          OnboardingPage.musicFoldersKey,
          [...existingFolders, directory],
        );
      }

      final scanResult = widget.repository.scan(directory);

      await prefs.setBool(OnboardingPage.onboardingCompletedKey, true);

      if (!mounted) return;

      setState(() {
        _selectedFolderPath = directory;
        _scannedTrackCount = scanResult.total;
        _statusMessage = 'Scan completed: $_scannedTrackCount tracks found!';
      });

      await Future<void>.delayed(const Duration(milliseconds: 600));

      if (mounted) {
        widget.onComplete();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Failed to load folder: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _showPairingModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MobiusColors.panelOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MobiusColors.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 48,
                  color: MobiusColors.accentOf(context),
                ),
                const SizedBox(height: 16),
                Text(
                  'Scan Desktop QR Code',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Open Mobius Music on your Mac or PC.\n'
                  '2. Go to Settings or Onboarding to view your Pairing QR Code.\n'
                  '3. Point this phone’s camera at the computer screen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MobiusColors.textDimOf(context),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                // Simulated Scanner Viewfinder
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: MobiusColors.accentOf(context),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          size: 36,
                          color: MobiusColors.textDimOf(context),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Viewfinder Ready',
                          style: TextStyle(
                            color: MobiusColors.textDimOf(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool(OnboardingPage.onboardingCompletedKey, true);
                      if (mounted) {
                        widget.onComplete();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: MobiusColors.accentOf(context),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Connect & Continue'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingPage.onboardingCompletedKey, true);
    if (mounted) {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < kMobileBreakpoint;

    return Scaffold(
      backgroundColor: MobiusColors.backgroundOf(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // App Logo Icon
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MobiusColors.accentOf(context),
                  MobiusColors.accentOf(context).withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: MobiusColors.accentOf(context).withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.all_inclusive_rounded,
              size: 42,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Headline
        Text(
          'Welcome to Mobius',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your bit-perfect, offline-first personal audio player.\nHow would you like to start?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: MobiusColors.textDimOf(context),
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 36),

        // Option 1: Connect to Computer
        _SelectionCard(
          icon: Icons.computer_rounded,
          title: 'Connect to Computer',
          subtitle:
              'Stream or sync from your PC/Mac music library. Pair instantly using a QR code.',
          badge: 'CROSS-DEVICE',
          onTap: _isProcessing ? null : _showPairingModal,
        ),
        const SizedBox(height: 16),

        // Option 2: Use Local Storage
        _SelectionCard(
          icon: Icons.folder_open_rounded,
          title: 'Use Local Storage',
          subtitle:
              'Play audio files directly from this phone’s internal storage or SD card.',
          badge: 'OFFLINE',
          highlight: true,
          onTap: _isProcessing ? null : _handleUseLocalStorage,
        ),
        const SizedBox(height: 28),

        if (_statusMessage != null) ...[
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isProcessing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_isProcessing) const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: MobiusColors.accentOf(context),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Skip / configure later link
        Center(
          child: TextButton(
            onPressed: _isProcessing ? null : _completeOnboarding,
            child: Text(
              'Skip for now (configure in Settings)',
              style: TextStyle(
                color: MobiusColors.textDimOf(context),
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    MobiusColors.accentOf(context),
                    MobiusColors.accentOf(context).withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.all_inclusive_rounded,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MOBIUS MUSIC',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                  ),
                  Text(
                    'Master Library & Cross-Device Hub',
                    style: TextStyle(
                      color: MobiusColors.textDimOf(context),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),

        // Step 1: Select master music folder
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: MobiusColors.panelOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MobiusColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder_special_rounded,
                    color: MobiusColors.accentOf(context),
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Step 1: Choose Master Music Folder',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Point Mobius to where your music collection lives (e.g. ~/Music). We will scan your files directly without modifying them.',
                style: TextStyle(
                  color: MobiusColors.textDimOf(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _isProcessing ? null : _handleUseLocalStorage,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(
                      _selectedFolderPath != null
                          ? 'Change Folder'
                          : 'Choose Music Folder',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: MobiusColors.accentOf(context),
                      foregroundColor: MobiusColors.onAccentOf(context),
                    ),
                  ),
                  if (_scannedTrackCount > 0) ...[
                    const SizedBox(width: 16),
                    Chip(
                      avatar: const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text('$_scannedTrackCount tracks indexed'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Step 2: Mobile Pairing preview
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: MobiusColors.panelOf(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MobiusColors.borderOf(context)),
          ),
          child: Row(
            children: [
              // QR code mockup graphic
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  size: 80,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step 2: Listen on Your Phone',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Install Mobius Music on your mobile device. Scan this code to sync your collection over local Wi-Fi.',
                      style: TextStyle(
                        color: MobiusColors.textDimOf(context),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Local network ready • Port 43210',
                      style: TextStyle(
                        color: MobiusColors.nativeOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _completeOnboarding,
              child: const Text('Skip for now'),
            ),
            const SizedBox(width: 16),
            FilledButton(
              onPressed: _completeOnboarding,
              style: FilledButton.styleFrom(
                backgroundColor: MobiusColors.accentOf(context),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
              child: const Text('Enter Mobius'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    this.highlight = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = highlight
        ? MobiusColors.accentOf(context).withValues(alpha: 0.7)
        : MobiusColors.borderOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: MobiusColors.panelOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: highlight ? 1.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (highlight
                        ? MobiusColors.accentOf(context)
                        : MobiusColors.borderOf(context))
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: highlight
                    ? MobiusColors.accentOf(context)
                    : MobiusColors.textOf(context),
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: MobiusColors.borderOf(context),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: MobiusColors.textDimOf(context),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: MobiusColors.textDimOf(context),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: MobiusColors.textDimOf(context),
            ),
          ],
        ),
      ),
    );
  }
}
