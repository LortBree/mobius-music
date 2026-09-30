import 'package:flutter/material.dart';

import '../widgets/animated_mobius_background.dart';

/// App-wide theming for Mobius. Provides both a dark theme (the original deep
/// violet/near-black look) and a light theme (a warm "sunrise" palette --
/// orange / soft red / yellow over a cream & sand base). Surface colours for
/// the shell are resolved from the active [Brightness] via [MobiusSurfaces],
/// and the ambient background palette is chosen by [MobiusTheme.ambientFor].
abstract final class MobiusTheme {
  // ---- Dark palette -------------------------------------------------------
  static const _darkBackground = Color(0xFF121212);
  static const _darkHeader = Color(0xFF19181F);
  static const _darkSurface = Color(0xFF1A1A1A);
  static const _darkElevated = Color(0xFF2A2A2A);
  static const _darkBorder = Color(0xFF2A2A2A);
  static const _darkText = Color(0xFFEDEDED);
  static const _darkTextDim = Color(0xFF9A9A9A);
  static const _darkAccent = Color(0xFF8A63D2);

  // ---- Light palette (warm sunrise) --------------------------------------
  // Cream/sand rather than stark white -- keeps warm glow vivid and text
  // contrast comfortable.
  static const _lightBackground = Color(0xFFF6EFE6); // warm cream
  static const _lightHeader = Color(0xFFF1E7D8); // sand
  static const _lightSurface = Color(0xFFFBF5EC);
  static const _lightElevated = Color(0xFFEADFCB);
  static const _lightBorder = Color(0xFFE0D3BE);
  static const _lightText = Color(0xFF2A2018); // warm near-black
  static const _lightTextDim = Color(0xFF7A6A55);
  static const _lightAccent = Color(0xFFE0602A); // warm orange

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: _darkBackground,
        surface: _darkSurface,
        elevated: _darkElevated,
        border: _darkBorder,
        primary: _darkAccent,
        text: _darkText,
        secondaryText: _darkTextDim,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: _lightBackground,
        surface: _lightSurface,
        elevated: _lightElevated,
        border: _lightBorder,
        primary: _lightAccent,
        text: _lightText,
        secondaryText: _lightTextDim,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color elevated,
    required Color border,
    required Color primary,
    required Color text,
    required Color secondaryText,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? const Color(0xFFFAFAFA) : const Color(0xFFFFF6EE),
      secondary: primary,
      onSecondary: text,
      surface: surface,
      onSurface: text,
      error: const Color(0xFFE05A5A),
      onError: const Color(0xFFFFFFFF),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: text, fontSize: 15),
        bodyMedium: TextStyle(color: secondaryText, fontSize: 14),
        titleLarge: TextStyle(
          color: text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(color: surface, elevation: 0),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: text),
      extensions: [
        MobiusSurfaces(
          background: background,
          header: isDark ? _darkHeader : _lightHeader,
          border: border,
          textPrimary: text,
          textSecondary: secondaryText,
          accent: primary,
          accentLight:
              isDark ? const Color(0xFFC4A8F0) : const Color(0xFFF2A05A),
          onAccent: colorScheme.onPrimary,
          miniPlayer: isDark ? const Color(0xFF1D1B24) : _lightHeader,
          selection: isDark
              ? const Color(0xFF292631)
              : const Color(0xFFEADFCB),
          scrim: isDark ? const Color(0xFF2A2A2A) : const Color(0xFF2A2018),
          onScrim: const Color(0xFFFAFAFA),
        ),
      ],
    );
  }

  /// The ambient background palette for a given brightness. Dark = the cool
  /// violet/cyan field; light = a warm orange/red/yellow "sunrise" field on a
  /// soft cream base.
  static AmbientConfig ambientFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return const AmbientConfig(
        base: Color(0xFFF3EADC), // warm cream, matches the light background
        violet: Color(0xFFE8873A), // primary: warm orange
        magenta: Color(0xFFD9503B), // secondary: soft red
        blue: Color(0xFFF0B23C), // "upper right": golden yellow
        cyan: Color(0xFFF6D26B), // subtle warm accent (was cool)
        intensity: 0.42, // gentler on a light base so text stays readable
        falloffTop: 0.02,
        falloffBottom: 0.72,
        warmMode: true,
      );
    }
    return const AmbientConfig(); // dark defaults (cool violet field)
  }
}

/// Shell surface colours resolved from the active theme. Registered as a
/// [ThemeExtension] so widgets read them with [MobiusSurfaces.of] and they flip
/// with the theme automatically.
@immutable
class MobiusSurfaces extends ThemeExtension<MobiusSurfaces> {
  const MobiusSurfaces({
    required this.background,
    required this.header,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentLight,
    required this.onAccent,
    required this.miniPlayer,
    required this.selection,
    required this.scrim,
    required this.onScrim,
  });

  final Color background;
  final Color header;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color accentLight;
  final Color onAccent;

  /// The bottom playback-bar surface (a distinct step off the background).
  final Color miniPlayer;

  /// Selected / current-row highlight surface.
  final Color selection;

  /// A floating tooltip / scrim surface drawn over arbitrary content.
  final Color scrim;

  /// Text/glyph colour on top of [scrim].
  final Color onScrim;

  static MobiusSurfaces of(BuildContext context) =>
      Theme.of(context).extension<MobiusSurfaces>()!;

  @override
  MobiusSurfaces copyWith({
    Color? background,
    Color? header,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? accentLight,
    Color? onAccent,
    Color? miniPlayer,
    Color? selection,
    Color? scrim,
    Color? onScrim,
  }) {
    return MobiusSurfaces(
      background: background ?? this.background,
      header: header ?? this.header,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      accentLight: accentLight ?? this.accentLight,
      onAccent: onAccent ?? this.onAccent,
      miniPlayer: miniPlayer ?? this.miniPlayer,
      selection: selection ?? this.selection,
      scrim: scrim ?? this.scrim,
      onScrim: onScrim ?? this.onScrim,
    );
  }

  @override
  MobiusSurfaces lerp(ThemeExtension<MobiusSurfaces>? other, double t) {
    if (other is! MobiusSurfaces) return this;
    return MobiusSurfaces(
      background: Color.lerp(background, other.background, t)!,
      header: Color.lerp(header, other.header, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      miniPlayer: Color.lerp(miniPlayer, other.miniPlayer, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      onScrim: Color.lerp(onScrim, other.onScrim, t)!,
    );
  }
}
