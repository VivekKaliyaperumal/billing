import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Builds a colour from CSS-style HSL values (as written in the web app's
/// `src/index.css`), so tokens stay exact rather than rounded hex.
Color hsl(double h, double s, double l, [double a = 1]) =>
    HSLColor.fromAHSL(a, h, s / 100, l / 100).toColor();

/// Design tokens ported from `src/index.css` (`:root` and `.dark`).
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

  // CSS 135deg runs from top-left to bottom-right.
  static LinearGradient _g135(Color a, Color b) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [a, b],
      );

  static final light = AppPalette(
    background: hsl(240, 20, 97),
    foreground: hsl(240, 10, 10),
    card: hsl(0, 0, 100),
    primary: hsl(262, 83, 58),
    primaryForeground: hsl(0, 0, 100),
    secondary: hsl(240, 20, 94),
    secondaryForeground: hsl(240, 10, 20),
    muted: hsl(240, 15, 90),
    mutedForeground: hsl(240, 8, 46),
    accent: hsl(340, 82, 52),
    success: hsl(160, 84, 39),
    warning: hsl(38, 92, 50),
    destructive: hsl(0, 72, 51),
    border: hsl(240, 15, 88),
    gradientPrimary: _g135(hsl(262, 83, 58), hsl(280, 83, 58)),
    gradientAccent: _g135(hsl(340, 82, 52), hsl(20, 92, 55)),
    gradientSuccess: _g135(hsl(160, 84, 39), hsl(175, 84, 45)),
    gradientHero: _g135(hsl(262, 83, 58), hsl(340, 82, 52)),
    shadowSoft: [BoxShadow(offset: const Offset(0, 1), blurRadius: 2, color: hsl(262, 83, 58, 0.05))],
    shadowMedium: [BoxShadow(offset: const Offset(0, 4), blurRadius: 12, spreadRadius: -2, color: hsl(262, 83, 58, 0.15))],
    shadowElevated: [BoxShadow(offset: const Offset(0, 12), blurRadius: 24, spreadRadius: -4, color: hsl(262, 83, 58, 0.2))],
    shadowGlow: [BoxShadow(blurRadius: 30, color: hsl(262, 83, 58, 0.3))],
    shadowAccent: [BoxShadow(offset: const Offset(0, 4), blurRadius: 12, spreadRadius: -2, color: hsl(340, 82, 52, 0.25))],
    isDark: false,
  );

  static final dark = AppPalette(
    background: hsl(240, 15, 8),
    foreground: hsl(0, 0, 98),
    card: hsl(240, 15, 12),
    primary: hsl(262, 83, 62),
    primaryForeground: hsl(0, 0, 100),
    secondary: hsl(240, 15, 18),
    secondaryForeground: hsl(0, 0, 90),
    muted: hsl(240, 15, 22),
    mutedForeground: hsl(240, 10, 60),
    accent: hsl(340, 82, 55),
    success: hsl(160, 84, 45),
    warning: hsl(38, 92, 55),
    destructive: hsl(0, 72, 50),
    border: hsl(240, 15, 22),
    gradientPrimary: _g135(hsl(262, 83, 62), hsl(280, 83, 62)),
    gradientAccent: _g135(hsl(340, 82, 55), hsl(20, 92, 58)),
    // No dark override for gradient-success in the web app.
    gradientSuccess: _g135(hsl(160, 84, 39), hsl(175, 84, 45)),
    gradientHero: _g135(hsl(262, 83, 62), hsl(340, 82, 55)),
    shadowSoft: [BoxShadow(offset: const Offset(0, 1), blurRadius: 2, color: hsl(0, 0, 0, 0.2))],
    shadowMedium: [BoxShadow(offset: const Offset(0, 4), blurRadius: 12, spreadRadius: -2, color: hsl(0, 0, 0, 0.3))],
    shadowElevated: [BoxShadow(offset: const Offset(0, 12), blurRadius: 24, spreadRadius: -4, color: hsl(0, 0, 0, 0.4))],
    shadowGlow: [BoxShadow(blurRadius: 30, color: hsl(262, 83, 62, 0.25))],
    shadowAccent: [BoxShadow(offset: const Offset(0, 4), blurRadius: 12, spreadRadius: -2, color: hsl(340, 82, 55, 0.25))],
    isDark: true,
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) =>
      t < 0.5 ? this : (other as AppPalette? ?? this);
}

/// Chart colours used for the "Top Selling Products" rank badges.
final chartColors = [
  hsl(262, 83, 58),
  hsl(340, 82, 52),
  hsl(160, 84, 39),
  hsl(38, 92, 50),
  hsl(200, 80, 50),
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

/// Space Grotesk, used for h1–h6 and `.font-display`.
TextStyle display(double size, {FontWeight weight = FontWeight.w600, Color? color}) =>
    GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: weight, color: color, letterSpacing: -0.025 * size);

ThemeData buildTheme(AppPalette p) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.isDark ? Brightness.dark : Brightness.light,
  );
  final text = GoogleFonts.interTextTheme(base.textTheme).apply(
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
