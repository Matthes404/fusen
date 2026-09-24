import 'package:flutter/material.dart';

import '../palette.dart';
import '../tokens.dart';

/// Ein Blatt Papier.
///
/// Alles, was in der App wie ein Zettel aussehen soll, kommt hier durch:
/// eigene Fläche, feine Kante, weicher Schatten und – wo ein Typ dahinter
/// steht – ein farbiger Streifen an der linken Kante. Unter dem Zeiger hebt
/// sich das Blatt einen Millimeter an.
///
/// Das ersetzt `Card`: die Material-Karte färbt sich mit steigender Höhe
/// grau ein, hier bleibt Papier Papier und nur der Schatten wächst.
class PaperCard extends StatefulWidget {
  const PaperCard({
    required this.child,
    super.key,
    this.onTap,
    this.accent,
    this.wash,
    this.padding = const EdgeInsets.all(Insets.md),
    this.borderRadius = Radii.mdAll,
    this.emphasised = false,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Kennfarbe des Zettel-Typs – wird zum Streifen an der Kante.
  final Color? accent;

  /// Hauch Farbe auf dem Papier selbst.
  final Color? wash;

  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// Für den einen Zettel, der heraussticht: kräftigerer Streifen und
  /// eingefärbte Kante.
  final bool emphasised;

  @override
  State<PaperCard> createState() => _PaperCardState();
}

class _PaperCardState extends State<PaperCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paper;
    final accent = widget.accent;
    final wash = widget.wash;
    final lifted = _hovered && widget.onTap != null;

    // Die Einfärbung wird eingerechnet statt übereinandergelegt: eine
    // deckende Fläche zeichnet sauberer und der Schatten bleibt klar.
    final surface = wash == null || wash.a == 0
        ? tokens.paper
        : Color.alphaBlend(wash, tokens.paper);

    final border = widget.emphasised && accent != null
        ? accent.withValues(alpha: 0.35)
        : lifted
        // Angehoben zeichnet die Kante eine Spur deutlicher nach.
        ? Color.alphaBlend(
            tokens.hairline.withValues(alpha: 0.6),
            tokens.paperBorder,
          )
        : tokens.paperBorder;

    final spine = widget.emphasised ? 4.0 : 3.0;

    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.standard,
        transform: Matrix4.translationValues(0, lifted ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: widget.borderRadius,
          border: Border.all(color: border),
          boxShadow: lifted ? tokens.raised : tokens.rest,
        ),
        child: ClipRRect(
          // Der Rahmen ist einen Pixel dick – innen entsprechend enger.
          borderRadius: widget.borderRadius.subtract(
            const BorderRadius.all(Radius.circular(1)),
          ),
          child: Stack(
            children: [
              if (accent != null)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    width: lifted ? spine + 1 : spine,
                    color: accent,
                  ),
                ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onTap,
                  child: Padding(
                    padding: widget.padding.add(
                      EdgeInsetsDirectional.only(start: accent == null ? 0 : 3),
                    ),
                    child: widget.child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eine ruhige Fläche ohne Zettel-Charakter: Einstellungs-Blöcke,
/// Hinweiskästen, alles, was gruppiert statt betont.
class PaperPanel extends StatelessWidget {
  const PaperPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Optionale Einfärbung, etwa Rot für einen Fehler.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.paper;
    final surface = tint == null
        ? tokens.paper
        : Color.alphaBlend(tint!.withValues(alpha: 0.09), tokens.paper);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: Radii.mdAll,
        border: Border.all(
          color: tint == null
              ? tokens.paperBorder
              : tint!.withValues(alpha: 0.28),
        ),
      ),
      child: child,
    );
  }
}
