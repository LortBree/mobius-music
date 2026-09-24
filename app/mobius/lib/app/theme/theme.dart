import 'package:flutter/material.dart';

import 'colors.dart';
import 'typography.dart';

abstract final class MobiusTheme {
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: MobiusTypography.sans,

      scaffoldBackgroundColor: MobiusColors.ink,

      colorScheme: const ColorScheme.dark(
        primary: MobiusColors.purple,
        onPrimary: Colors.white,
        secondary: MobiusColors.purpleLight,
        onSecondary: MobiusColors.ink,
        surface: MobiusColors.panel,
        onSurface: MobiusColors.text,
        outline: MobiusColors.border,
      ),

      textTheme: const TextTheme(
        displaySmall: MobiusTypography.display,
        headlineSmall: MobiusTypography.title,
        bodyMedium: MobiusTypography.body,
        labelLarge: MobiusTypography.label,
      ),

      dividerTheme: const DividerThemeData(
        color: MobiusColors.border,
        thickness: 1,
        space: 1,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          MobiusColors.textDim.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      fontFamily: MobiusTypography.sans,

      scaffoldBackgroundColor: MobiusColors.paper,

      colorScheme: const ColorScheme.light(
        primary: MobiusColors.purpleDark,
        onPrimary: Colors.white,
        secondary: MobiusColors.purple,
        onSecondary: Colors.white,
        surface: MobiusColors.paper,
        onSurface: MobiusColors.ink,
        outline: Color(0xFFD6D6D6),
      ),

      textTheme: const TextTheme(
        displaySmall: MobiusTypography.display,
        headlineSmall: MobiusTypography.title,
        bodyMedium: MobiusTypography.body,
        labelLarge: MobiusTypography.label,
      ),
    );
  }
}