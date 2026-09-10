import 'package:flutter/material.dart';

import 'palette.dart';
import 'tokens.dart';

/// Die Farbe der Haftnotiz-Metapher: ein warmes Gelb.
const Color fusenSeed = Color(0xFFFFC53D);

/// Die Tinte darauf.
///
/// Beide Farben stehen in hell wie dunkel gleich – der Knopf, der die App
/// ausmacht, soll überall wie ein Haftzettel aussehen und nicht mal braun,
/// mal gelb sein. Für Text und Linien ist `ColorScheme.primary` zuständig,
/// das dafür genug Kontrast hat.
const Color fusenInk = Color(0xFF422C00);

/// Der Anstrich für den Knopf, der einen Zettel ablegt.
ButtonStyle brandButtonStyle() => FilledButton.styleFrom(
  backgroundColor: fusenSeed,
  foregroundColor: fusenInk,
  iconColor: fusenInk,
);

/// Schriften, die die App möglichst gut aussehen lässt – die erste, die auf
/// dem System vorhanden ist, gewinnt. Fehlt alles, bleibt es bei der
/// Systemschrift; ein eigenes Schriftpaket ist der App nicht wert.
const List<String> _fontStack = [
  'Inter',
  'SF Pro Text',
  'Segoe UI Variable Text',
  'Segoe UI',
  'Noto Sans',
  'DejaVu Sans',
];

/// Für Code, Zeitstempel und Tastenkürzel.
const String monoFamily = 'monospace';

ThemeData fusenTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = light ? fusenLightScheme : fusenDarkScheme;
  final paper = light ? FusenColors.light : FusenColors.dark;

  // Erst die Schriftstufen festlegen, dann die Bauteile daraus bedienen.
  //
  // Der Umweg über `base.textTheme` ist wichtig: dort hat Flutter die
  // Schriftart der Plattform schon eingesetzt. Wer stattdessen die rohen
  // Stile in ein Bauteil-Theme steckt, bekommt in der Titelzeile und auf
  // Knöpfen eine andere Schrift als im Fließtext.
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: _textTheme(scheme),
    fontFamilyFallback: _fontStack,
  );
  final text = base.textTheme;

  return base.copyWith(
    extensions: [paper],
    scaffoldBackgroundColor: paper.canvas,
    canvasColor: paper.canvas,
    visualDensity: VisualDensity.standard,

    // Der Material-Standard streut ab Material 3 einen Farbschleier über
    // erhöhte Flächen. Papier soll aber Papier bleiben.
    applyElevationOverlayColor: false,

    // InkSparkle glitzert; für eine Notiz-App ist das zu viel Show.
    splashFactory: InkRipple.splashFactory,

    iconTheme: IconThemeData(size: 20, color: scheme.onSurfaceVariant),
    primaryIconTheme: IconThemeData(size: 20, color: scheme.onSurfaceVariant),

    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const _RiseTransitionBuilder(),
      },
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 60,
      titleSpacing: Insets.lg,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(size: 20, color: scheme.onSurfaceVariant),
      actionsIconTheme: IconThemeData(size: 20, color: scheme.onSurfaceVariant),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: paper.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.mdAll,
        side: BorderSide(color: paper.paperBorder),
      ),
    ),

    dividerTheme: DividerThemeData(
      space: 1,
      thickness: 1,
      color: paper.hairline,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        foregroundColor: scheme.onSurface,
        textStyle: text.labelLarge,
        side: BorderSide(color: paper.paperBorder),
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        foregroundColor: scheme.onSurfaceVariant,
        textStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        highlightColor: scheme.onSurface.withValues(alpha: 0.06),
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: fusenSeed,
      foregroundColor: fusenInk,
      elevation: 3,
      focusElevation: 4,
      hoverElevation: 6,
      highlightElevation: 2,
      extendedTextStyle: text.labelLarge,
      shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainer,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      // Die schwebende Beschriftung nimmt die Akzentfarbe erst an, wenn
      // das Feld den Fokus hat – sonst leuchtet ein ganzes Formular.
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
        final color = states.contains(WidgetState.error)
            ? scheme.error
            : states.contains(WidgetState.focused)
            ? scheme.primary
            : scheme.onSurfaceVariant;
        return text.labelMedium!.copyWith(color: color);
      }),
      helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      prefixIconColor: scheme.onSurfaceVariant,
      suffixIconColor: scheme.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: Radii.smAll,
        borderSide: BorderSide(color: paper.paperBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: Radii.smAll,
        borderSide: BorderSide(color: paper.paperBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: Radii.smAll,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: Radii.smAll,
        borderSide: BorderSide(color: paper.hairline),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: Radii.smAll,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: Radii.smAll,
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
    ),

    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.24),
      selectionHandleColor: scheme.primary,
    ),

    // Grün heißt erledigt – überall, quer durch alle Zettel-Typen.
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: scheme.outline, width: 1.6),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.tertiary
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(scheme.onTertiary),
      shape: const RoundedRectangleBorder(borderRadius: Radii.xsAll),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: light
          ? scheme.surfaceContainer
          : scheme.surfaceContainerHigh,
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.onPrimaryContainer,
      side: BorderSide(color: paper.paperBorder),
      labelStyle: text.labelMedium,
      secondaryLabelStyle: text.labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      shape: const RoundedRectangleBorder(borderRadius: Radii.pillAll),
      showCheckmark: false,
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.transparent,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        foregroundColor: scheme.onSurfaceVariant,
        side: BorderSide(color: paper.paperBorder),
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
    ),

    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: scheme.onSurfaceVariant,
      collapsedIconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      collapsedTextColor: scheme.onSurfaceVariant,
      childrenPadding: EdgeInsets.zero,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: paper.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: text.titleMedium,
      contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.lgAll,
        side: BorderSide(color: paper.paperBorder),
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: paper.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      dragHandleColor: scheme.outline.withValues(alpha: 0.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      ),
    ),

    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(paper.paper),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(scheme.shadow),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: Insets.xs),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: Radii.mdAll,
            side: BorderSide(color: paper.paperBorder),
          ),
        ),
      ),
    ),

    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(
        foregroundColor: scheme.onSurface,
        iconColor: scheme.onSurfaceVariant,
        textStyle: text.bodyMedium,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: Insets.md),
        shape: const RoundedRectangleBorder(borderRadius: Radii.xsAll),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: paper.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      textStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.mdAll,
        side: BorderSide(color: paper.paperBorder),
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: scheme.inversePrimary,
      elevation: 6,
      insetPadding: const EdgeInsets.all(Insets.lg),
      shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
    ),

    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 6),
      margin: const EdgeInsets.all(Insets.xs),
      textStyle: text.labelMedium?.copyWith(color: scheme.onInverseSurface),
      decoration: BoxDecoration(
        color: scheme.inverseSurface.withValues(alpha: 0.94),
        borderRadius: Radii.xsAll,
      ),
    ),

    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(Radii.xs),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => scheme.outline.withValues(
          alpha: states.contains(WidgetState.hovered) ? 0.55 : 0.3,
        ),
      ),
      crossAxisMargin: 2,
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      circularTrackColor: scheme.primary.withValues(alpha: 0.15),
      linearTrackColor: scheme.primary.withValues(alpha: 0.15),
    ),
  );
}

/// Die Schriftstufen.
///
/// Enger als der Material-Standard und mit klaren Sprüngen: Überschriften
/// tragen ihr Gewicht über Fettung und leicht negative Laufweite, Fließtext
/// bleibt luftig genug zum Lesen.
TextTheme _textTheme(ColorScheme scheme) {
  final ink = scheme.onSurface;
  final muted = scheme.onSurfaceVariant;

  // Die Schriftliste hängt an jeder Stufe, nicht nur an `ThemeData`:
  // Stile, die direkt in ein Bauteil-Theme wandern (Titelzeile, Knöpfe),
  // kommen an `ThemeData.fontFamilyFallback` sonst nie vorbei.
  TextStyle style(
    double size,
    FontWeight weight,
    double tracking,
    double height, {
    Color? color,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: tracking,
    height: height,
    color: color ?? ink,
    fontFamilyFallback: _fontStack,
  );

  return TextTheme(
    displayLarge: style(40, FontWeight.w700, -1.0, 1.1),
    displayMedium: style(34, FontWeight.w700, -0.8, 1.12),
    displaySmall: style(28, FontWeight.w700, -0.6, 1.15),
    headlineLarge: style(26, FontWeight.w700, -0.5, 1.18),
    headlineMedium: style(23, FontWeight.w700, -0.4, 1.2),
    headlineSmall: style(20, FontWeight.w700, -0.3, 1.25),
    titleLarge: style(19, FontWeight.w700, -0.3, 1.25),
    titleMedium: style(16, FontWeight.w600, -0.15, 1.35),
    titleSmall: style(15, FontWeight.w600, -0.1, 1.35),
    bodyLarge: style(16, FontWeight.w400, 0, 1.5),
    bodyMedium: style(15, FontWeight.w400, 0, 1.5),
    bodySmall: style(13, FontWeight.w400, 0.1, 1.45, color: muted),
    labelLarge: style(14, FontWeight.w600, 0.1, 1.2),
    labelMedium: style(12, FontWeight.w600, 0.3, 1.2, color: muted),
    labelSmall: style(11, FontWeight.w600, 0.4, 1.2, color: muted),
  );
}

/// Seitenwechsel: aufblenden und einen Hauch nach oben schieben.
///
/// Die eingebauten Übergänge sind entweder platt (Linux, Windows) oder
/// laut (Android). Das hier ist überall dasselbe und stört nie.
class _RiseTransitionBuilder extends PageTransitionsBuilder {
  const _RiseTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Über `drive` statt `CurvedAnimation`: das braucht kein dispose.
    final curve = CurveTween(curve: Motion.emphasized);
    final fade = animation.drive(curve);
    final rise = animation.drive(
      Tween(begin: const Offset(0, 0.02), end: Offset.zero).chain(curve),
    );
    final settle = secondaryAnimation.drive(
      Tween<double>(begin: 1, end: 0.985).chain(curve),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: rise,
        child: ScaleTransition(scale: settle, child: child),
      ),
    );
  }
}
