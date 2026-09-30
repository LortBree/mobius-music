import 'package:flutter/material.dart';

import 'mobius_theme.dart';

/// Semantic colours for Mobius.
///
/// Two layers:
///  * The `static const` values below are the ORIGINAL dark palette. They stay
///    for brightness-independent uses (status colours, gradients that are the
///    same in both themes) and as the dark reference.
///  * The `static Color …(BuildContext)` resolvers map each semantic role to
///    the ACTIVE theme via [MobiusSurfaces], so any widget that switches from a
///    raw literal to `MobiusColors.<role>(context)` automatically flips between
///    dark and the warm light theme.
abstract final class MobiusColors {
  // Interactive / accent (dark reference)
  static const purple = Color(0xFF8A63D2);
  static const purpleLight = Color(0xFFC4A8F0);
  static const purpleDark = Color(0xFF6A3FC0);
  static const violetMuted = Color(0xFF3A2A52);

  // Neutral (dark reference)
  static const ink = Color(0xFF121212);
  static const paper = Color(0xFFFAFAFA);
  static const panel = Color(0xFF1A1A1A);
  static const border = Color(0xFF2A2A2A);
  static const text = Color(0xFFEDEDED);
  static const textDim = Color(0xFF9A9A9A);

  // Audio verification status (same in both themes)
  static const native = Color(0xFF7FD99A);
  static const compatible = Color(0xFFE8B74A);
  static const unsupported = Color(0xFFE05A5A);

  // ---- Theme-aware resolvers ---------------------------------------------
  // Use these in widgets instead of the raw constants so colours flip with
  // the active theme. Each reads the registered MobiusSurfaces extension.

  /// Primary readable text.
  static Color textOf(BuildContext c) => MobiusSurfaces.of(c).textPrimary;

  /// Dimmed / secondary text.
  static Color textDimOf(BuildContext c) => MobiusSurfaces.of(c).textSecondary;

  /// Panel / card surface (a step off the background).
  static Color panelOf(BuildContext c) =>
      Theme.of(c).colorScheme.surface;

  /// Base background.
  static Color backgroundOf(BuildContext c) =>
      MobiusSurfaces.of(c).background;

  /// Header / top-bar surface.
  static Color headerOf(BuildContext c) => MobiusSurfaces.of(c).header;

  /// Hairline borders / dividers.
  static Color borderOf(BuildContext c) => MobiusSurfaces.of(c).border;

  /// Accent (interactive) colour.
  static Color accentOf(BuildContext c) => MobiusSurfaces.of(c).accent;

  /// Lighter accent, for selected/active glyphs.
  static Color accentLightOf(BuildContext c) =>
      MobiusSurfaces.of(c).accentLight;

  /// Text/glyph colour that sits on top of the accent.
  static Color onAccentOf(BuildContext c) => MobiusSurfaces.of(c).onAccent;

  /// Bottom playback-bar surface.
  static Color miniPlayerOf(BuildContext c) => MobiusSurfaces.of(c).miniPlayer;

  /// Selected / current-row highlight surface.
  static Color selectionOf(BuildContext c) => MobiusSurfaces.of(c).selection;

  /// Floating tooltip / scrim surface.
  static Color scrimOf(BuildContext c) => MobiusSurfaces.of(c).scrim;

  /// Text/glyph on top of a scrim.
  static Color onScrimOf(BuildContext c) => MobiusSurfaces.of(c).onScrim;

  // ---- Fixed decorative gradients ----------------------------------------
  // The playlist/favorites hero uses a theme-independent purple gradient in
  // both themes. Named here so no raw hex literals live in widget code.
  static const heroGradientTop = Color(0xFF57417E);
  static const heroGradientBottom = Color(0xFF201C2A);
  static const heroCoverTop = Color(0xFF493273);
  static const heroCoverMid = Color(0xFF302344);
  static const heroCoverFade = Color(0x001A1A1A);
  static const favoritesGradientTop = Color(0xFF8055C7);
  static const favoritesGradientBottom = Color(0xFF33234E);
  static const onHeroPrimary = Color(0xFFEDEDED);
  static const onHeroLabel = Color(0xFFE4D7FF);
  static const onHeroMuted = Color(0xFFD0C8D9);

  // ---- Ambient background dark-palette defaults --------------------------
  // Default cool field for AmbientConfig (dark theme). The light theme
  // overrides these via MobiusTheme.ambientFor().
  static const ambientBase = Color(0xFF09090D);
  static const ambientViolet = Color(0xFF6D3BB5);
  static const ambientMagenta = Color(0xFFB044A5);
  static const ambientBlue = Color(0xFF6A4BC0);
  static const ambientCyan = Color(0xFF3B6F9E);
}
