import 'package:flutter/material.dart';

/// Die Farbe der Haftnotiz-Metapher: ein warmes Gelb.
const Color fusenSeed = Color(0xFFFFC53D);

ThemeData fusenTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: fusenSeed,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light
        ? const Color(0xFFFBFAF8)
        : scheme.surface,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    ),
    dividerTheme: DividerThemeData(space: 1, color: scheme.outlineVariant),
  );
}
