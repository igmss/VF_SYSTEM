import 'package:flutter/material.dart';

class AppTheme {
  static const bg = Color(0xFF07111A);
  static const surface = Color(0xFF0D1822);
  static const surfaceRaised = Color(0xFF132230);
  static const lightBg = Color(0xFFF4F0E8);
  static const lightSurface = Color(0xFFFFFCF7);
  static const lightSurfaceRaised = Color(0xFFEDE5D8);
  static const accent = Color(0xFFB47B32);
  static const accentSoft = Color(0xFFD8B273);
  static const gold = Color(0xFFE0C48A);
  static const line = Color(0xFF203445);
  static const lightLine = Color(0xFFD9CCBA);
  static const textPrimary = Color(0xFFF6F1E8);
  static const textMuted = Color(0xFF9DAFBC);
  static const lightTextPrimary = Color(0xFF1A2430);
  static const lightTextMuted = Color(0xFF6B7280);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color scaffoldBg(BuildContext context) =>
      isDark(context) ? bg : lightBg;

  static Color surfaceColor(BuildContext context) =>
      isDark(context) ? surface : lightSurface;

  static Color surfaceRaisedColor(BuildContext context) =>
      isDark(context) ? surfaceRaised : lightSurfaceRaised;

  static Color lineColor(BuildContext context) =>
      isDark(context) ? line : lightLine;

  static Color textPrimaryColor(BuildContext context) =>
      isDark(context) ? textPrimary : lightTextPrimary;

  static Color textMutedColor(BuildContext context) =>
      isDark(context) ? textMuted : lightTextMuted;

  static List<Color> backgroundGradient(BuildContext context) => isDark(context)
      ? const [Color(0xFF07111A), Color(0xFF0A1722), Color(0xFF10202D)]
      : const [Color(0xFFF4F0E8), Color(0xFFF7F2EA), Color(0xFFECE2D3)];

  static List<Color> heroGradient(BuildContext context) => isDark(context)
      ? const [Color(0xFF8F6730), Color(0xFFD8B273)]
      : const [Color(0xFF8E6633), Color(0xFFE7C78B)];

  static List<Color> panelGradient(BuildContext context) => isDark(context)
      ? const [Color(0xFF112130), Color(0xFF0C1925)]
      : const [Color(0xFFFFFCF7), Color(0xFFF2E9DD)];

  static Color glowColor(BuildContext context) =>
      isDark(context) ? accent.withValues(alpha: 0.14) : accent.withValues(alpha: 0.09);

  static Color secondaryGlowColor(BuildContext context) =>
      isDark(context) ? gold.withValues(alpha: 0.08) : accentSoft.withValues(alpha: 0.10);

  static List<BoxShadow> softShadow(BuildContext context) => [
        BoxShadow(
          color: isDark(context)
              ? Colors.black.withValues(alpha: 0.26)
              : const Color(0xFF8A6A3C).withValues(alpha: 0.10),
          blurRadius: isDark(context) ? 28 : 20,
          offset: const Offset(0, 12),
        ),
      ];

  static Color positiveColor(BuildContext context) =>
      isDark(context) ? const Color(0xFF3FD0A8) : const Color(0xFF1E8E72);

  static Color positiveColorSoft(BuildContext context) =>
      isDark(context)
          ? const Color(0xFF3FD0A8).withValues(alpha: 0.12)
          : const Color(0xFF1E8E72).withValues(alpha: 0.10);

  static Color infoColor(BuildContext context) =>
      isDark(context) ? const Color(0xFF73B8F6) : const Color(0xFF2F6B9A);

  static Color infoColorSoft(BuildContext context) =>
      isDark(context)
          ? const Color(0xFF73B8F6).withValues(alpha: 0.12)
          : const Color(0xFF2F6B9A).withValues(alpha: 0.10);

  static Color errorColor(BuildContext context) =>
      isDark(context) ? const Color(0xFFFF6B6B) : const Color(0xFFD84343);

  static Color errorColorSoft(BuildContext context) =>
      isDark(context)
          ? const Color(0xFFFF6B6B).withValues(alpha: 0.12)
          : const Color(0xFFD84343).withValues(alpha: 0.10);

  static Color warningColor(BuildContext context) =>
      isDark(context) ? const Color(0xFFE3B86B) : const Color(0xFFB47B32);

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: accent,
      secondary: accentSoft,
      surface: surface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textPrimary,
      error: Color(0xFFFF6B6B),
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? textPrimary : textMuted,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textMuted),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
        ),
      ),
      dividerColor: line,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.0,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.45,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          color: textMuted,
          height: 1.35,
        ),
      ),
    );
  }

  static ThemeData light() {
    final scheme = const ColorScheme.light(
      primary: accent,
      secondary: accentSoft,
      surface: lightSurface,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: lightTextPrimary,
      error: Color(0xFFD84343),
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: lightBg,
      canvasColor: lightBg,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: const BorderSide(color: lightLine),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSurface,
        indicatorColor: accent.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? lightTextPrimary
                : lightTextMuted,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightTextPrimary,
          side: const BorderSide(color: lightLine),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurfaceRaised,
        hintStyle: const TextStyle(color: lightTextMuted),
        labelStyle: const TextStyle(color: lightTextMuted),
        prefixIconColor: lightTextMuted,
        suffixIconColor: lightTextMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: lightLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: lightLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFD84343)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFD84343)),
        ),
      ),
      dividerColor: lightLine,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: lightTextPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.0,
        ),
        titleLarge: TextStyle(
          color: lightTextPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.45,
        ),
        titleMedium: TextStyle(
          color: lightTextPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: lightTextPrimary,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          color: lightTextMuted,
          height: 1.35,
        ),
      ),
    );
  }
}
