import 'package:flutter/material.dart';

/// Cohesive design tokens and theme for FindIt.
///
/// Engineered specifically for high-contrast accessibility (WCAG AAA),
/// low visual fatigue on OLED displays, and large tactile touch affordances
/// for visually impaired and low-vision users.
class AppTheme {
  AppTheme._();

  // Core Color Palette
  static const Color background = Color(0xFF0A0F1D); // Deep Obsidian Slate
  static const Color surface = Color(0xFF11192C); // Card Surface
  static const Color surfaceElevated = Color(0xFF1B253D); // Interactive Card
  static const Color surfaceHighlight = Color(
    0xFF263554,
  ); // Focus & Border Highlight

  // Semantic Accents
  static const Color primary = Color(
    0xFFF59E0B,
  ); // Radiant Amber (Reticles, Key Actions)
  static const Color primaryLight = Color(0xFFFDE68A); // Soft Amber Text
  static const Color primaryDark = Color(0xFFB45309);

  static const Color success = Color(
    0xFF10B981,
  ); // Emerald (Target Locked, Found)
  static const Color successLight = Color(0xFFA7F3D0);

  static const Color telemetry = Color(
    0xFF38BDF8,
  ); // Electric Cyan (Sensors, Distances)
  static const Color error = Color(0xFFEF4444); // Urgent Stop / Error
  static const Color listening = Color(
    0xFFDC2626,
  ); // Active Mic Listening Pulse

  // High Contrast Text & Neutrals
  static const Color textPrimary = Color(0xFFF8FAFC); // Maximum Contrast White
  static const Color textSecondary = Color(0xFFCBD5E1); // Slate Tinted Grey
  static const Color textMuted = Color(0xFF94A3B8); // Subtle Helper Text
  static const Color borderSubtle = Color(0x3394A3B8); // 20% Alpha Divider
  static const Color borderActive = Color(
    0xFFF59E0B,
  ); // Amber Reticle Focus Ring

  // Radii
  static const double radiusSm = 12.0;
  static const double radiusMd = 18.0;
  static const double radiusLg = 24.0;
  static const double radiusFull = 999.0;

  // Minimum Touch Sizes (Accessibility Standard: min 48dp, preferred 56dp)
  static const double minTouchTarget = 48.0;
  static const double primaryButtonHeight = 60.0;
  static const double secondaryButtonHeight = 52.0;

  /// Material 3 Dark ThemeData configured for FindIt
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Color(0xFF000000),
        primaryContainer: surfaceElevated,
        onPrimaryContainer: textPrimary,
        secondary: success,
        onSecondary: Color(0xFF000000),
        tertiary: telemetry,
        surface: surface,
        onSurface: textPrimary,
        error: error,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: textPrimary, size: 26),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: borderSubtle, width: 1.2),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: const Color(0xFF000000),
          minimumSize: const Size(double.infinity, primaryButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
          elevation: 3,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surfaceElevated.withValues(alpha: 0.4),
          minimumSize: const Size(double.infinity, secondaryButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: const BorderSide(color: borderSubtle, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: textMuted, fontSize: 16),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: borderSubtle, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: borderSubtle, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: primary, width: 2.0),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: borderSubtle, width: 1.5),
        ),
        titleTextStyle: const TextStyle(
          color: primary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(
          color: textSecondary,
          fontSize: 16,
          height: 1.5,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary,
        labelStyle: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          side: const BorderSide(color: borderSubtle),
        ),
      ),
    );
  }
}
