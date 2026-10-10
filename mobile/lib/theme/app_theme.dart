import 'package:flutter/material.dart';

/// Thyantra brand colours (thyantra.com).
class Brand {
  static const navy = Color(0xFF0D47A1);
  static const navyLight = Color(0xFF1565C0);

  /// Decorative only: too light for text on white (contrast below 4.5:1).
  static const green = Color(0xFF39D353);
  static const slate = Color(0xFF0F172A);
}

/// Design tokens. Text colours meet WCAG AA (4.5:1) on their backgrounds.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.foreground,
    required this.card,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.success,
    required this.warning,
    required this.destructive,
    required this.border,
    required this.gradientPrimary,
    required this.gradientAccent,
    required this.gradientSuccess,
    required this.gradientHero,
    required this.shadowSoft,
    required this.shadowMedium,
    required this.shadowElevated,
    required this.shadowGlow,
    required this.shadowAccent,
    required this.isDark,
  });

  final Color background;
  final Color foreground;
  final Color card;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color muted;
  final Color mutedForeground;
  final Color accent;
  final Color success;
  final Color warning;
  final Color destructive;
  final Color border;
  final LinearGradient gradientPrimary;
  final LinearGradient gradientAccent;
  final LinearGradient gradientSuccess;
  final LinearGradient gradientHero;
  final List<BoxShadow> shadowSoft;
  final List<BoxShadow> shadowMedium;
  final List<BoxShadow> shadowElevated;
  final List<BoxShadow> shadowGlow;
  final List<BoxShadow> shadowAccent;
  final bool isDark;

  static const light = AppPalette(
    background: Color(0xFFF8FAFC),
    foreground: Brand.slate,
    card: Color(0xFFFFFFFF),
    primary: Brand.navy,
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFFE8EDF4),
    secondaryForeground: Color(0xFF334155),
    muted: Color(0xFFE2E8F0),
    mutedForeground: Color(0xFF5B6B82),
    accent: Color(0xFFC2410C), // credit / dues
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    destructive: Color(0xFFDC2626),
    border: Color(0xFFE2E8F0),
    gradientPrimary: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.navy, Brand.navyLight]),
    gradientAccent: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC2410C), Color(0xFFEA580C)]),
    gradientSuccess: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF15803D), Color(0xFF1F9D4C)]),
    gradientHero: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.navy, Brand.green]),
    shadowSoft: [BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x0D0D47A1))],
    shadowMedium: [BoxShadow(offset: Offset(0, 4), blurRadius: 12, spreadRadius: -2, color: Color(0x260D47A1))],
    shadowElevated: [BoxShadow(offset: Offset(0, 12), blurRadius: 24, spreadRadius: -4, color: Color(0x330D47A1))],
    shadowGlow: [BoxShadow(blurRadius: 30, color: Color(0x4D0D47A1))],
    shadowAccent: [BoxShadow(offset: Offset(0, 4), blurRadius: 12, spreadRadius: -2, color: Color(0x40C2410C))],
    isDark: false,
  );

  static const dark = AppPalette(
    background: Color(0xFF0B1220),
    foreground: Color(0xFFF1F5F9),
    card: Color(0xFF111A2E),
    primary: Color(0xFF6E9BF2),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFF1A2438),
    secondaryForeground: Color(0xFFE2E8F0),
    muted: Color(0xFF1F2A40),
    mutedForeground: Color(0xFF94A3B8),
    accent: Color(0xFFFB923C),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    destructive: Color(0xFFEF4444),
    border: Color(0xFF243049),
    gradientPrimary: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E5BC6), Color(0xFF2F7BEA)]),
    gradientAccent: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC2410C), Color(0xFFEA580C)]),
    gradientSuccess: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF15803D), Color(0xFF1F9D4C)]),
    gradientHero: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E5BC6), Brand.green]),
    shadowSoft: [BoxShadow(offset: Offset(0, 1), blurRadius: 2, color: Color(0x33000000))],
    shadowMedium: [BoxShadow(offset: Offset(0, 4), blurRadius: 12, spreadRadius: -2, color: Color(0x4D000000))],
    shadowElevated: [BoxShadow(offset: Offset(0, 12), blurRadius: 24, spreadRadius: -4, color: Color(0x66000000))],
    shadowGlow: [BoxShadow(blurRadius: 30, color: Color(0x401E5BC6))],
    shadowAccent: [BoxShadow(offset: Offset(0, 4), blurRadius: 12, spreadRadius: -2, color: Color(0x40FB923C))],
    isDark: true,
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) =>
      t < 0.5 ? this : (other as AppPalette? ?? this);
}

/// Rank badge colours for "Top Selling Products"; white text passes AA on each.
const chartColors = [
  Brand.navy,
  Color(0xFF15803D),
  Color(0xFFC2410C),
  Color(0xFF6D28D9),
  Color(0xFF0E7490),
];

/// Radii from tailwind.config.ts (`--radius: 1rem`).
class AppRadius {
  static const lg = 16.0; // cards, buttons, dialogs, rounded-2xl
  static const md = 14.0; // inputs, selects
  static const xl = 12.0; // icon boxes, cart items
}

extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// Sora (Thyantra's heading font). Sora has no ₹ glyph, so Inter fills in.
TextStyle display(double size, {FontWeight weight = FontWeight.w600, Color? color}) => TextStyle(
      fontFamily: 'Sora',
      fontFamilyFallback: const ['Inter'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: -0.02 * size,
    );

ThemeData buildTheme(AppPalette p) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.isDark ? Brightness.dark : Brightness.light,
    fontFamily: 'Inter',
  );
  final text = base.textTheme.apply(
    bodyColor: p.foreground,
    displayColor: p.foreground,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: BorderSide(color: p.border),
  );
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    colorScheme: ColorScheme(
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      primary: p.primary,
      onPrimary: p.primaryForeground,
      secondary: p.accent,
      onSecondary: Colors.white,
      error: p.destructive,
      onError: Colors.white,
      surface: p.card,
      onSurface: p.foreground,
      outline: p.border,
    ),
    textTheme: text,
    dividerColor: p.border,
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.primary),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: p.background,
      hintStyle: TextStyle(color: p.mutedForeground),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      disabledBorder: inputBorder.copyWith(borderSide: BorderSide(color: p.border.withValues(alpha: 0.5))),
      focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: p.primary, width: 2)),
      errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: p.destructive)),
      focusedErrorBorder: inputBorder.copyWith(borderSide: BorderSide(color: p.destructive, width: 2)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: p.border),
      ),
    ),
    extensions: [p],
  );
}
