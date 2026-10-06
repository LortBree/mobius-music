import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/mobius_theme.dart';
import '../../core/audio/signal_path.dart';

/// Layout presets for the 1:1 square Mobius shareable music card.
enum ShareCardLayout {
  /// Minimalist modern square card with dynamic cover art accent gradient,
  /// centered artwork, clean resolution subtitle, hairline divider, and Mobius branding.
  minimal,

  /// Archival vinyl slipcase with registration corner brackets, catalog stamps,
  /// and tabular audiophile specs rail.
  archivalVinyl,

  /// Asymmetric Swiss modular grid with 0.5px hairline architectural rules,
  /// tabular metadata columns, and perimeter crosshairs.
  swissModular,

  /// Precision mastering lab instrument faceplate with dual micro-bezels,
  /// 4-quadrant telemetry grid, and hardware route status.
  audioLab;

  String get displayName {
    switch (this) {
      case ShareCardLayout.minimal:
        return 'Minimalist';
      case ShareCardLayout.archivalVinyl:
        return 'Archival Vinyl';
      case ShareCardLayout.swissModular:
        return 'Swiss Modular';
      case ShareCardLayout.audioLab:
        return 'Audio Lab';
    }
  }

  String get shortName {
    switch (this) {
      case ShareCardLayout.minimal:
        return 'Minimal';
      case ShareCardLayout.archivalVinyl:
        return 'Vinyl';
      case ShareCardLayout.swissModular:
        return 'Swiss';
      case ShareCardLayout.audioLab:
        return 'Lab';
    }
  }

  String get label => shortName;
}

/// Renders an authentic 1:1 square shareable aesthetic card for the currently playing track.
///
/// In [ShareCardLayout.minimal] mode, renders a clean modern card with cover art accent
/// gradient blending down to pure black, centered artwork, resolution subtitle,
/// bold track title and artist, hairline divider, and Mobius branding.
class ShareableMusicCard extends StatefulWidget {
  const ShareableMusicCard({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    this.artworkBytes,
    this.formatLabel,
    this.isBitPerfect = false,
    this.width = 340,
    this.height,
    this.layout = ShareCardLayout.minimal,
  });

  final String title;
  final String artist;
  final String album;
  final Uint8List? artworkBytes;
  final String? formatLabel;
  final bool isBitPerfect;
  final double width;
  final double? height;
  final ShareCardLayout layout;

  @override
  State<ShareableMusicCard> createState() => _ShareableMusicCardState();
}

class _ShareableMusicCardState extends State<ShareableMusicCard> {
  Color? _extractedAccent;

  @override
  void initState() {
    super.initState();
    _extractColor();
  }

  @override
  void didUpdateWidget(covariant ShareableMusicCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkBytes != widget.artworkBytes) {
      _extractColor();
    }
  }

  Future<void> _extractColor() async {
    final bytes = widget.artworkBytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted && _extractedAccent != null) {
        setState(() => _extractedAccent = null);
      }
      return;
    }

    try {
      final scheme = await ColorScheme.fromImageProvider(
        provider: MemoryImage(bytes),
        brightness: Brightness.dark,
      );
      if (mounted) {
        setState(() => _extractedAccent = scheme.primary);
      }
    } catch (_) {
      // Fallback cleanly to default slate-navy accent if image decoding fails
    }
  }

  Color _getTopGradientColor(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    // Keep hue, calibrate lightness to deep atmospheric tone for maximum contrast
    final tunedHsl = hsl.withLightness(hsl.lightness.clamp(0.20, 0.36));
    return tunedHsl.toColor();
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = widget.title.isEmpty ? 'Untitled Track' : widget.title;
    final displayArtist = widget.artist.isEmpty ? 'Unknown Artist' : widget.artist;
    final displayAlbum = widget.album.isEmpty ? 'Unknown Album' : widget.album;
    final isMinimal = widget.layout == ShareCardLayout.minimal;
    final cardRadius = isMinimal ? 0.0 : 4.0;
    const defaultAccent = Color(0xFF28367F);
    final topColor = _getTopGradientColor(_extractedAccent ?? defaultAccent);
    final effectiveHeight = widget.height ?? (isMinimal ? null : widget.width);

    return Container(
      width: widget.width,
      height: effectiveHeight,
      decoration: BoxDecoration(
        color: isMinimal ? null : MobiusColors.ambientBase,
        borderRadius: isMinimal ? null : BorderRadius.circular(cardRadius),
        border: isMinimal
            ? null
            : Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 0.5,
              ),
        gradient: isMinimal
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.45, 1.0],
                colors: [
                  topColor,
                  Color.lerp(topColor, Colors.black, 0.60)!,
                  const Color(0xFF000000), // Pure black bottom as requested
                ],
              )
            : null,
        boxShadow: isMinimal
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.65),
                  blurRadius: 28,
                  spreadRadius: 2,
                  offset: const Offset(0, 14),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: isMinimal ? BorderRadius.zero : BorderRadius.circular(cardRadius),
        child: isMinimal
            ? _buildMinimalLayout(
                widget.width,
                displayTitle,
                displayArtist,
              )
            : Stack(
                children: [
                  // Ambient shell fields (only for legacy archival/modular/lab layouts)
                  _buildAmbientShellFields(),

                  // Registration marks / crosshairs overlay (legacy layouts only)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RegistrationMarksPainter(layout: widget.layout),
                    ),
                  ),

                  // Card composition layout
                  Positioned.fill(
                    child: switch (widget.layout) {
                      ShareCardLayout.minimal => _buildMinimalLayout(
                          widget.width,
                          displayTitle,
                          displayArtist,
                        ),
                      ShareCardLayout.archivalVinyl => _buildArchivalVinylLayout(
                          displayTitle,
                          displayArtist,
                          displayAlbum,
                        ),
                      ShareCardLayout.swissModular => _buildSwissModularLayout(
                          displayTitle,
                          displayArtist,
                          displayAlbum,
                        ),
                      ShareCardLayout.audioLab => _buildAudioLabLayout(
                          displayTitle,
                          displayArtist,
                          displayAlbum,
                        ),
                    },
                  ),
                ],
              ),
      ),
    );
  }

  Uint8List? get artworkBytes => widget.artworkBytes;
  String? get formatLabel => widget.formatLabel;
  bool get isBitPerfect => widget.isBitPerfect;
  double get width => widget.width;
  double get height => widget.height ?? widget.width;

  static String resolveResolution(String? label) {
    if (label == null || label.trim().isEmpty) {
      return '16-bit / 44.1 kHz';
    }
    final trimmed = label.trim();
    final normalized = trimmed.replaceAll(RegExp(r'\s*·\s*'), ' / ');

    final regex = RegExp(r'(\d+-bit\s*/\s*[\d\.]+\s*(?:kHz|MHz))', caseSensitive: false);
    final match = regex.firstMatch(normalized);
    if (match != null) {
      return match.group(1)!;
    }

    final bitsMatch = RegExp(r'(\d+)-bit').firstMatch(normalized);
    final rateMatch = RegExp(r'([\d\.]+)\s*(kHz|MHz)', caseSensitive: false).firstMatch(normalized);
    if (bitsMatch != null && rateMatch != null) {
      return '${bitsMatch.group(1)}-bit / ${rateMatch.group(1)} ${rateMatch.group(2)}';
    }

    if (normalized.toUpperCase().contains('DSD')) {
      if (rateMatch != null) {
        return 'DSD / ${rateMatch.group(1)} ${rateMatch.group(2)}';
      }
      return 'DSD Direct';
    }

    return normalized;
  }

  // ---- Layout 0: Minimalist Clean Adaptive Card ------------------------------
  Widget _buildMinimalLayout(
    double cardWidth,
    String displayTitle,
    String displayArtist,
  ) {
    final resolution = resolveResolution(widget.formatLabel);
    final artDimension = (cardWidth * 0.58).clamp(140.0, 480.0);
    final titleSize = (cardWidth * 0.058).clamp(16.0, 32.0);
    final artistSize = (cardWidth * 0.040).clamp(12.0, 22.0);
    final resSize = (cardWidth * 0.033).clamp(10.5, 18.0);
    final logoSize = (cardWidth * 0.052).clamp(16.0, 32.0);
    final brandSize = (cardWidth * 0.038).clamp(12.0, 24.0);
    final hPadding = (cardWidth * 0.075).clamp(20.0, 48.0);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: hPadding,
        vertical: (cardWidth * 0.075).clamp(22.0, 42.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Centered Artwork with subtle rounded corners (album sleeve aesthetic)
          Center(
            child: Container(
              width: artDimension,
              height: artDimension,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.50),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: widget.artworkBytes != null && widget.artworkBytes!.isNotEmpty
                    ? Image.memory(
                        widget.artworkBytes!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackArt(),
                      )
                    : _buildFallbackArt(),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // 2. Centered Resolution Badge (e.g. 16-bit / 44.1 kHz)
          Center(
            child: Text(
              resolution,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: resSize,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.4,
              ),
            ),
          ),

          const SizedBox(height: 22),

          // 3. Track Title (Full title, adaptive height, wraps naturally down)
          Text(
            displayTitle,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: Colors.white,
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 6),

          // 4. Artist Name
          Text(
            displayArtist,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: artistSize,
              fontWeight: FontWeight.w400,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 20),

          // 5. Subtle Hairline Divider
          Container(
            height: 0.8,
            color: Colors.white.withValues(alpha: 0.16),
          ),

          const SizedBox(height: 18),

          // 6. Brand Footer: [Mobius Logo] Mobius Music
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/icons/mobius_logo_white.png',
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.all_inclusive_rounded,
                  size: logoSize,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Mobius Music',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: brandSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Mobius Ambient Shell Fields ------------------------------------------
  Widget _buildAmbientShellFields() {
    return Stack(
      children: [
        // 1. Dominant Violet Field (upper-left/center)
        Positioned(
          top: -60,
          left: -50,
          width: width * 1.1,
          height: height * 0.65,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.4),
                radius: 0.95,
                colors: [
                  MobiusColors.ambientViolet.withValues(alpha: 0.48),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // 2. Magenta Secondary Field (upper-center)
        Positioned(
          top: -40,
          left: 20,
          right: 20,
          height: height * 0.5,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.1, -0.6),
                radius: 0.85,
                colors: [
                  MobiusColors.ambientMagenta.withValues(alpha: 0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // 3. Violet-to-Blue Field (upper-right)
        Positioned(
          top: -50,
          right: -40,
          width: width * 0.9,
          height: height * 0.55,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.65, -0.5),
                radius: 0.90,
                colors: [
                  MobiusColors.ambientBlue.withValues(alpha: 0.38),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // 4. Subtle Cool Cyan Accent Field
        Positioned(
          top: 30,
          right: -10,
          width: width * 0.7,
          height: height * 0.4,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.45, 0.0),
                radius: 0.80,
                colors: [
                  MobiusColors.ambientCyan.withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // 5. Subtle Emerald Native Field (#7FD99A)
        Positioned(
          bottom: -20,
          left: -20,
          width: width * 0.6,
          height: height * 0.35,
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.5, 0.5),
                radius: 0.75,
                colors: [
                  MobiusColors.native.withValues(alpha: 0.09),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // 6. Vertical vignette / falloff mask to ambientBase (#09090D)
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.45, 0.82, 1.0],
                colors: [
                  Colors.transparent,
                  Color(0x2809090D),
                  Color(0xB009090D),
                  MobiusColors.ambientBase,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Layout 1: Archival Vinyl Sleeve (1:1) --------------------------------
  Widget _buildArchivalVinylLayout(
    String displayTitle,
    String displayArtist,
    String displayAlbum,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header Strip: Catalog stamp & bit-perfect verification
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'CAT. MBS-0909 // ARCHIVAL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (isBitPerfect) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: MobiusColors.native,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'BIT-PERFECT',
                      style: TextStyle(
                        color: MobiusColors.native,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // Center Artwork Frame with 0.5px hairline border & registration relief
          Expanded(
            child: Row(
              children: [
                // Artwork Container (Square)
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: artworkBytes != null && artworkBytes!.isNotEmpty
                          ? Image.memory(
                              artworkBytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildFallbackArt(),
                            )
                          : _buildFallbackArt(),
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // Right rail: Matrix runout stamp & technical metadata column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'MATRIX RUNOUT',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'MBS-UAC2-DIR-MASTER',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 9.0,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildHairlineDivider(),
                      const SizedBox(height: 10),
                      Text(
                        'RESOLUTION',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatLabel ?? 'LOSSLESS ARCHIVE',
                        style: const TextStyle(
                          color: Color(0xFF60A5FA),
                          fontSize: 10.0,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (isBitPerfect) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Bit-Perfect UAC2',
                          style: TextStyle(
                            color: MobiusColors.native,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          _buildHairlineDivider(),
          const SizedBox(height: 10),

          // Track Title & Artist Metadata
          Text(
            displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$displayArtist  ·  $displayAlbum',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 12),
          _buildHairlineDivider(),
          const SizedBox(height: 10),

          // Bottom Bar: [Icon Mobius] Mobius Music in bottom-left
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildBottomLeftBranding(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'ED. 2026 // HI-FI',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 8.0,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Layout 2: Swiss Modular Grid (1:1) -----------------------------------
  Widget _buildSwissModularLayout(
    String displayTitle,
    String displayArtist,
    String displayAlbum,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header telemetry bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '+ SWISS MODULAR // SPEC 01',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (isBitPerfect) ...[
                const SizedBox(width: 8),
                const Text(
                  'BIT-PERFECT',
                  style: TextStyle(
                    color: MobiusColors.native,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _buildHairlineDivider(),
          const SizedBox(height: 10),

          // Modular Body: Left Artwork, Right Specs & Track info
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Column: Artwork & Technical Label
                SizedBox(
                  width: (width - 48) * 0.46,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: artworkBytes != null &&
                                    artworkBytes!.isNotEmpty
                                ? Image.memory(
                                    artworkBytes!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _buildFallbackArt(),
                                  )
                                : _buildFallbackArt(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'AUDIO SOURCE FILE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 7.0,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),

                // Vertical 0.5px hairline divider
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Container(
                    width: 0.5,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),

                // Right Column: Track & Tabular Matrix
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRACK TITLE',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ARTIST // ALBUM',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$displayArtist  ·  $displayAlbum',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 11.0,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                      const Spacer(),
                      _buildHairlineDivider(),
                      const SizedBox(height: 6),

                      // Tabular metadata rows
                      _buildSwissDataRow('CODEC', formatLabel ?? 'LOSSLESS'),
                      const SizedBox(height: 4),
                      _buildSwissDataRow(
                        'ROUTE',
                        isBitPerfect ? 'Bit-Perfect UAC2' : 'SYSTEM MIXER',
                        isHighlighted: isBitPerfect,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          _buildHairlineDivider(),
          const SizedBox(height: 10),

          // Bottom Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildBottomLeftBranding(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'MODULAR LAB',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 8.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwissDataRow(String label, String value, {bool isHighlighted = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 8.0,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: isHighlighted ? MobiusColors.native : Colors.white.withValues(alpha: 0.85),
              fontSize: 9.0,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  // ---- Layout 3: Precision Audio Lab (1:1) -----------------------------------
  Widget _buildAudioLabLayout(
    String displayTitle,
    String displayArtist,
    String displayAlbum,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Lab status telemetry
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'LAB-SPEC // MASTER VERIFIED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: isBitPerfect
                        ? MobiusColors.native.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                  color: isBitPerfect
                      ? MobiusColors.native.withValues(alpha: 0.12)
                      : Colors.transparent,
                ),
                child: Text(
                  isBitPerfect ? 'BIT-PERFECT' : 'CALIBRATED',
                  style: TextStyle(
                    color: isBitPerfect ? MobiusColors.native : Colors.white70,
                    fontSize: 8.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          _buildHairlineDivider(),
          const SizedBox(height: 10),

          // Center Section: Artwork + 4-Quadrant Telemetry Matrix
          Expanded(
            child: Row(
              children: [
                // Compact Lab Artwork Frame
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 0.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: artworkBytes != null && artworkBytes!.isNotEmpty
                          ? Image.memory(
                              artworkBytes!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildFallbackArt(),
                            )
                          : _buildFallbackArt(),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // 4-Quadrant Telemetry Grid
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTelemetryQuadrant(
                                'SPEC',
                                formatLabel ?? 'PCM / LOSSLESS',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTelemetryQuadrant(
                                'RATE',
                                formatLabel?.contains('·') == true
                                    ? formatLabel!.split('·').last.trim()
                                    : '96.0 kHz',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTelemetryQuadrant(
                                'TRANSFER',
                                isBitPerfect ? 'Bit-Perfect UAC2' : 'DIRECT PCM',
                                isHighlighted: isBitPerfect,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildTelemetryQuadrant(
                                'OUTPUT ROUTE',
                                isBitPerfect ? 'UAC2 DIRECT' : 'SYSTEM DAC',
                                isHighlighted: isBitPerfect,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          _buildHairlineDivider(),
          const SizedBox(height: 8),

          // Track Information
          Text(
            displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$displayArtist  ·  $displayAlbum',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 10),
          _buildHairlineDivider(),
          const SizedBox(height: 8),

          // Bottom Rail
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildBottomLeftBranding(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'UAC2 LAB',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryQuadrant(
    String label,
    String value, {
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 7.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isHighlighted ? MobiusColors.native : Colors.white.withValues(alpha: 0.9),
              fontSize: 9.0,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ---- Micro Components & Anti-AI Elements -----------------------------------
  Widget _buildHairlineDivider() {
    return Container(
      height: 0.5,
      color: Colors.white.withValues(alpha: 0.14),
    );
  }

  Widget _buildBottomLeftBranding() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/icons/mobius_logo_white.png',
          width: 18,
          height: 18,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.all_inclusive_rounded,
            size: 18,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Mobius Music',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackArt() {
    return Container(
      color: const Color(0xFF141418),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 48,
          color: Colors.white.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

/// Custom painter rendering architectural hairline registration brackets and crosshairs.
class _RegistrationMarksPainter extends CustomPainter {
  const _RegistrationMarksPainter({required this.layout});

  final ShareCardLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const offset = 8.0;
    const armLength = 7.0;

    switch (layout) {
      case ShareCardLayout.minimal:
        // Minimal layout does not render registration brackets or crosshairs
        break;

      case ShareCardLayout.archivalVinyl:
        // Corner brackets: ┌ ┐ └ ┘
        // Top-left ┌
        canvas.drawLine(const Offset(offset, offset), const Offset(offset + armLength, offset), paint);
        canvas.drawLine(const Offset(offset, offset), const Offset(offset, offset + armLength), paint);

        // Top-right ┐
        canvas.drawLine(Offset(size.width - offset, offset), Offset(size.width - offset - armLength, offset), paint);
        canvas.drawLine(Offset(size.width - offset, offset), Offset(size.width - offset, offset + armLength), paint);

        // Bottom-left └
        canvas.drawLine(Offset(offset, size.height - offset), Offset(offset + armLength, size.height - offset), paint);
        canvas.drawLine(Offset(offset, size.height - offset), Offset(offset, size.height - offset - armLength), paint);

        // Bottom-right ┘
        canvas.drawLine(Offset(size.width - offset, size.height - offset), Offset(size.width - offset - armLength, size.height - offset), paint);
        canvas.drawLine(Offset(size.width - offset, size.height - offset), Offset(size.width - offset, size.height - offset - armLength), paint);
        break;

      case ShareCardLayout.swissModular:
      case ShareCardLayout.audioLab:
        // Perimeter crosshairs (+)
        _drawCrosshair(canvas, paint, const Offset(offset, offset), 4.0);
        _drawCrosshair(canvas, paint, Offset(size.width - offset, offset), 4.0);
        _drawCrosshair(canvas, paint, Offset(offset, size.height - offset), 4.0);
        _drawCrosshair(canvas, paint, Offset(size.width - offset, size.height - offset), 4.0);

        // Midpoint crosshairs
        _drawCrosshair(canvas, paint, Offset(size.width / 2, offset), 3.5);
        _drawCrosshair(canvas, paint, Offset(size.width / 2, size.height - offset), 3.5);
        break;
    }
  }

  void _drawCrosshair(Canvas canvas, Paint paint, Offset center, double arm) {
    canvas.drawLine(Offset(center.dx - arm, center.dy), Offset(center.dx + arm, center.dy), paint);
    canvas.drawLine(Offset(center.dx, center.dy - arm), Offset(center.dx, center.dy + arm), paint);
  }

  @override
  bool shouldRepaint(covariant _RegistrationMarksPainter oldDelegate) =>
      oldDelegate.layout != layout;
}

/// Modal bottom sheet to preview, select layout styles, and share the 1:1 music card.
const String _prefKeyShareCardLayout = 'mobius_share_card_layout';

/// Modal bottom sheet to preview, select layout styles, and share the 1:1 music card.
Future<void> showShareableCardModal({
  required BuildContext context,
  required String title,
  required String artist,
  required String album,
  Uint8List? artworkBytes,
  SignalPath? signalPath,
  ShareCardLayout? initialLayout,
}) async {
  final GlobalKey boundaryKey = GlobalKey();

  String formatLabel = '';
  bool isBitPerfect = false;
  if (signalPath != null) {
    isBitPerfect = signalPath.bitPerfect;
    final rateKHz = (signalPath.sourceSampleRate / 1000.0).toStringAsFixed(1);
    final bits = signalPath.sourceBitsPerSample;
    final fmt = signalPath.sourceFormat.toUpperCase();
    formatLabel = '$fmt $bits-bit · $rateKHz kHz';
  }

  ShareCardLayout layoutToUse = initialLayout ?? ShareCardLayout.minimal;
  if (initialLayout == null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKeyShareCardLayout);
      if (saved != null) {
        layoutToUse = ShareCardLayout.values.firstWhere(
          (e) => e.name == saved,
          orElse: () => ShareCardLayout.minimal,
        );
      }
    } catch (e) {
      debugPrint('[ShareCard] SharedPreferences read error: $e');
    }
  }

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalContext) {
      return _ShareCardModalContent(
        boundaryKey: boundaryKey,
        title: title,
        artist: artist,
        album: album,
        artworkBytes: artworkBytes,
        formatLabel: formatLabel,
        isBitPerfect: isBitPerfect,
        initialLayout: layoutToUse,
      );
    },
  );
}

/// Backwards-compatible alias for [showShareableCardModal].
Future<void> showShareableMusicCardModal({
  required BuildContext context,
  required String title,
  required String artist,
  required String album,
  Uint8List? artworkBytes,
  SignalPath? signalPath,
  ShareCardLayout? initialLayout,
}) => showShareableCardModal(
  context: context,
  title: title,
  artist: artist,
  album: album,
  artworkBytes: artworkBytes,
  signalPath: signalPath,
  initialLayout: initialLayout,
);

class _ShareCardModalContent extends StatefulWidget {
  const _ShareCardModalContent({
    required this.boundaryKey,
    required this.title,
    required this.artist,
    required this.album,
    this.artworkBytes,
    required this.formatLabel,
    required this.isBitPerfect,
    this.initialLayout = ShareCardLayout.minimal,
  });

  final GlobalKey boundaryKey;
  final String title;
  final String artist;
  final String album;
  final Uint8List? artworkBytes;
  final String formatLabel;
  final bool isBitPerfect;
  final ShareCardLayout initialLayout;

  @override
  State<_ShareCardModalContent> createState() => _ShareCardModalContentState();
}

class _ShareCardModalContentState extends State<_ShareCardModalContent> {
  static const MethodChannel _shareChannel = MethodChannel('mobius/share');
  bool _isProcessing = false;

  Future<Uint8List?> _captureCardBytes() async {
    try {
      final boundary = widget.boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[ShareCard] capture error: $e');
      return null;
    }
  }

  Future<void> _shareCard() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final bytes = await _captureCardBytes();
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate image')),
          );
        }
        return;
      }

      await _shareChannel.invokeMethod('shareImage', {
        'bytes': bytes,
        'title': 'Share ${widget.title}',
      });
    } on PlatformException catch (e) {
      debugPrint('[ShareCard] Share error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveCard() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final bytes = await _captureCardBytes();
      if (bytes == null) return;

      final safeTitle = widget.title.replaceAll(RegExp(r'[^\w\s]+'), '_');
      final fileName = 'mobius_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.png';

      final res = await _shareChannel.invokeMethod('saveImage', {
        'bytes': bytes,
        'fileName': fileName,
      });

      if (mounted && res == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to Pictures/Mobius'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on PlatformException catch (e) {
      debugPrint('[ShareCard] Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final cardWidth = (media.size.width - 56).clamp(240.0, 340.0);
    final surfaces = Theme.of(context).extension<MobiusSurfaces>();
    final panelColor = surfaces?.background ?? MobiusColors.ambientBase;
    final textColor = surfaces?.textPrimary ?? Colors.white;
    final textDimColor = surfaces?.textSecondary ?? Colors.white60;

    return Container(
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, media.padding.bottom + 16),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Share Music Card',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: textDimColor,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Adaptive Minimalist Card preview wrapped in RepaintBoundary
            Center(
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: RepaintBoundary(
                  key: widget.boundaryKey,
                  child: ShareableMusicCard(
                    title: widget.title,
                    artist: widget.artist,
                    album: widget.album,
                    artworkBytes: widget.artworkBytes,
                    formatLabel: widget.formatLabel,
                    isBitPerfect: widget.isBitPerfect,
                    width: cardWidth,
                    height: null, // Fully adaptive to title length!
                    layout: ShareCardLayout.minimal,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 22),

            // Actions: Save & Share buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _saveCard,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Save Image'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isProcessing ? null : _shareCard,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.share_rounded, size: 18),
                    label: Text(_isProcessing ? 'Generating...' : 'Share'),
                    style: FilledButton.styleFrom(
                      backgroundColor: surfaces?.accent ?? MobiusColors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

