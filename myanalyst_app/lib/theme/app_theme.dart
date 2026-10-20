import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Brightness.light,
  ).copyWith(
    primary: Palette.accent,
    onPrimary: Colors.white,
    secondary: Palette.accent,
    surface: Palette.sheet,
    onSurface: Palette.ink,
    error: Palette.brick,
    outline: Palette.rule,
    outlineVariant: Palette.rule,
  );

  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radii.md),
    borderSide: BorderSide(color: Palette.ruleStrong),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.paper,
    fontFamily: 'Plex Sans',
    splashFactory: NoSplash.splashFactory, // quiet interactions; hover/pressed states carry feedback
    dividerTheme: const DividerThemeData(color: Palette.rule, thickness: 1, space: 1),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Palette.accent,
      selectionColor: Palette.accentWash,
    ),
    textTheme: const TextTheme(
      bodyMedium: Txt.body,
      bodyLarge: Txt.body,
      labelLarge: Txt.label,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.sheet,
      hintStyle: Txt.bodyMuted.copyWith(color: Palette.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: Palette.accent, width: 1.5)),
      errorBorder: border.copyWith(borderSide: const BorderSide(color: Palette.brick)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return Palette.ruleStrong;
          if (s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)) return Palette.accentHover;
          return Palette.accent;
        }),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        textStyle: WidgetStatePropertyAll(Txt.label.copyWith(color: Colors.white)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.md))),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(Palette.ink),
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.hovered) ? Palette.sunken : Colors.transparent),
        side: const WidgetStatePropertyAll(BorderSide(color: Palette.ruleStrong)),
        textStyle: const WidgetStatePropertyAll(Txt.label),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 13)),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.md))),
      ),
    ),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(Palette.accent),
        overlayColor: WidgetStatePropertyAll(Palette.accentWash),
        textStyle: WidgetStatePropertyAll(Txt.label),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.sm))),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.all(Radii.sm)),
      textStyle: TextStyle(fontFamily: 'Plex Sans', fontSize: 12.5, color: Colors.white),
      waitDuration: Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.ink,
      contentTextStyle: Txt.body.copyWith(color: Colors.white),
      actionTextColor: const Color(0xFFA9D3C3),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.md)),
      width: 440,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.sheet,
      indicatorColor: Palette.accentWash,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStatePropertyAll(Txt.caption.copyWith(color: Palette.ink, fontWeight: FontWeight.w500)),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(6),
      radius: Radius.circular(3),
    ),
  );
}
