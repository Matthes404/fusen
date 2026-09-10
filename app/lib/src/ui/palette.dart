import 'package:flutter/material.dart';

/// Die Farbwelt der App: Papier, Tinte und ein Haftnotiz-Gelb.
///
/// Die Werte stehen von Hand da, statt aus einem Saatkorn errechnet zu sein.
/// `ColorScheme.fromSeed` macht aus Gelb einen kühlen, leicht grünlichen
/// Satz – gewollt ist aber ein warmer Schreibtisch: gebrochenes Weiß,
/// braunschwarze Tinte, Honig als Akzent.

/// Hell – Papier auf einem hellen Schreibtisch.
const ColorScheme fusenLightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFA85F0A),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFE7B4),
  onPrimaryContainer: Color(0xFF462A00),
  secondary: Color(0xFF5C5348),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF1EADC),
  onSecondaryContainer: Color(0xFF39332B),
  tertiary: Color(0xFF1E7A4C),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFCFEBDC),
  onTertiaryContainer: Color(0xFF0B3524),
  error: Color(0xFFB3261E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Color(0xFFFBF8F2),
  onSurface: Color(0xFF241F1A),
  surfaceDim: Color(0xFFEDE6D9),
  surfaceBright: Color(0xFFFFFDF8),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFAF6EE),
  surfaceContainer: Color(0xFFF4EEE2),
  surfaceContainerHigh: Color(0xFFEEE7D9),
  surfaceContainerHighest: Color(0xFFE8E0D0),
  onSurfaceVariant: Color(0xFF6B6157),
  outline: Color(0xFF8C816F),
  outlineVariant: Color(0xFFE3DACA),
  inverseSurface: Color(0xFF37312A),
  onInverseSurface: Color(0xFFF7F1E7),
  inversePrimary: Color(0xFFFFC53D),
  surfaceTint: Color(0xFFA85F0A),
  shadow: Color(0xFF2A1F10),
  scrim: Color(0xFF1A140C),
);

/// Dunkel – derselbe Schreibtisch bei Lampenlicht, nicht das übliche
/// blaustichige Grau.
const ColorScheme fusenDarkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFFC53D),
  onPrimary: Color(0xFF422C00),
  primaryContainer: Color(0xFF5E4200),
  onPrimaryContainer: Color(0xFFFFE1A0),
  secondary: Color(0xFFD6C9B6),
  onSecondary: Color(0xFF392F22),
  secondaryContainer: Color(0xFF4A4033),
  onSecondaryContainer: Color(0xFFF2E5D1),
  tertiary: Color(0xFF5FD196),
  onTertiary: Color(0xFF003824),
  tertiaryContainer: Color(0xFF17523C),
  onTertiaryContainer: Color(0xFF9BF2C4),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF17150F),
  onSurface: Color(0xFFEAE3D6),
  surfaceDim: Color(0xFF17150F),
  surfaceBright: Color(0xFF3D3931),
  surfaceContainerLowest: Color(0xFF100E09),
  surfaceContainerLow: Color(0xFF1D1B14),
  surfaceContainer: Color(0xFF232019),
  surfaceContainerHigh: Color(0xFF2E2A22),
  surfaceContainerHighest: Color(0xFF39352C),
  onSurfaceVariant: Color(0xFFC8BCA6),
  outline: Color(0xFF948A78),
  outlineVariant: Color(0xFF463F35),
  inverseSurface: Color(0xFFEAE3D6),
  onInverseSurface: Color(0xFF332F27),
  inversePrimary: Color(0xFFA85F0A),
  surfaceTint: Color(0xFFFFC53D),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// Was `ColorScheme` nicht kennt, die Haftnotiz-Metapher aber braucht:
/// die Unterlage, das Papier darauf und der Schatten dazwischen.
@immutable
class FusenColors extends ThemeExtension<FusenColors> {
  const FusenColors({
    required this.canvas,
    required this.sidebar,
    required this.paper,
    required this.paperBorder,
    required this.hairline,
    required this.rest,
    required this.raised,
    required this.overlay,
  });

  /// Die Unterlage, auf der die Zettel liegen.
  final Color canvas;

  /// Die Seitenspalte – eine Spur tiefer als die Unterlage.
  final Color sidebar;

  /// Der Zettel selbst.
  final Color paper;

  /// Die Kante des Zettels: sichtbar, aber nur gerade eben.
  final Color paperBorder;

  /// Trennlinien, die nichts betonen sollen.
  final Color hairline;

  /// Zettel in Ruhe.
  final List<BoxShadow> rest;

  /// Zettel unter dem Zeiger – einen Millimeter angehoben.
  final List<BoxShadow> raised;

  /// Was über allem liegt: Dialoge, Menüs, die Schnelleingabe.
  final List<BoxShadow> overlay;

  static const FusenColors light = FusenColors(
    canvas: Color(0xFFF5F1E7),
    sidebar: Color(0xFFF1ECE0),
    paper: Color(0xFFFFFDF8),
    paperBorder: Color(0xFFEBE3D3),
    hairline: Color(0xFFE7DFCF),
    rest: [
      BoxShadow(color: Color(0x0D2A1F10), blurRadius: 3, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x0A2A1F10), blurRadius: 12, offset: Offset(0, 6)),
    ],
    raised: [
      BoxShadow(color: Color(0x142A1F10), blurRadius: 6, offset: Offset(0, 2)),
      BoxShadow(
        color: Color(0x1A2A1F10),
        blurRadius: 24,
        offset: Offset(0, 12),
      ),
    ],
    overlay: [
      BoxShadow(color: Color(0x142A1F10), blurRadius: 10, offset: Offset(0, 3)),
      BoxShadow(
        color: Color(0x232A1F10),
        blurRadius: 36,
        offset: Offset(0, 16),
      ),
    ],
  );

  static const FusenColors dark = FusenColors(
    canvas: Color(0xFF14120D),
    sidebar: Color(0xFF100E09),
    paper: Color(0xFF232019),
    paperBorder: Color(0xFF37322A),
    hairline: Color(0xFF2C2820),
    rest: [
      BoxShadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 6)),
    ],
    raised: [
      BoxShadow(color: Color(0x59000000), blurRadius: 8, offset: Offset(0, 3)),
      BoxShadow(
        color: Color(0x4D000000),
        blurRadius: 26,
        offset: Offset(0, 14),
      ),
    ],
    overlay: [
      BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 4)),
      BoxShadow(
        color: Color(0x80000000),
        blurRadius: 40,
        offset: Offset(0, 18),
      ),
    ],
  );

  @override
  FusenColors copyWith({
    Color? canvas,
    Color? sidebar,
    Color? paper,
    Color? paperBorder,
    Color? hairline,
    List<BoxShadow>? rest,
    List<BoxShadow>? raised,
    List<BoxShadow>? overlay,
  }) {
    return FusenColors(
      canvas: canvas ?? this.canvas,
      sidebar: sidebar ?? this.sidebar,
      paper: paper ?? this.paper,
      paperBorder: paperBorder ?? this.paperBorder,
      hairline: hairline ?? this.hairline,
      rest: rest ?? this.rest,
      raised: raised ?? this.raised,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  FusenColors lerp(FusenColors? other, double t) {
    if (other == null) return this;
    return FusenColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      paperBorder: Color.lerp(paperBorder, other.paperBorder, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      rest: BoxShadow.lerpList(rest, other.rest, t)!,
      raised: BoxShadow.lerpList(raised, other.raised, t)!,
      overlay: BoxShadow.lerpList(overlay, other.overlay, t)!,
    );
  }
}

/// Kurzform für den Zugriff auf die Papierfarben.
extension FusenColorsOf on BuildContext {
  FusenColors get paper => Theme.of(this).extension<FusenColors>()!;
}
