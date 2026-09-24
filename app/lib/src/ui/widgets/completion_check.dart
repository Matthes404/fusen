import 'package:flutter/material.dart';

import '../tokens.dart';

/// Der runde Haken, mit dem ein Zettel erledigt wird.
///
/// Rund statt eckig: ein Kästchen sieht nach Formular aus, ein Kreis nach
/// Aufgabe. Offen trägt er die Farbe des Zettel-Typs, erledigt wird er grün
/// – quer durch alle Typen dasselbe Grün, damit „fertig“ überall gleich
/// aussieht. Unter dem Zeiger deutet sich der Haken schon an.
class CompletionCheck extends StatefulWidget {
  const CompletionCheck({
    required this.done,
    required this.onChanged,
    super.key,
    this.discarded = false,
    this.accent,
    this.size = 22,
    this.tooltip,
  });

  final bool done;

  /// Verworfen ist auch abgeschlossen, aber nicht erledigt – grau statt grün.
  final bool discarded;

  final ValueChanged<bool>? onChanged;
  final Color? accent;
  final double size;
  final String? tooltip;

  @override
  State<CompletionCheck> createState() => _CompletionCheckState();
}

class _CompletionCheckState extends State<CompletionCheck> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final closed = widget.done || widget.discarded;
    final ring = widget.accent ?? scheme.outline;
    final fill = widget.discarded ? scheme.outline : scheme.tertiary;
    final size = widget.size;

    final Widget mark = closed
        ? Icon(
            widget.discarded ? Icons.remove_rounded : Icons.check_rounded,
            key: const ValueKey('closed'),
            size: size * 0.7,
            color: widget.discarded ? scheme.surface : scheme.onTertiary,
          )
        : AnimatedOpacity(
            key: const ValueKey('open'),
            duration: Motion.fast,
            opacity: _hovered ? 0.55 : 0,
            child: Icon(Icons.check_rounded, size: size * 0.66, color: ring),
          );

    final circle = AnimatedContainer(
      duration: Motion.base,
      curve: Motion.standard,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: closed
            ? fill
            : (_hovered ? ring.withValues(alpha: 0.1) : Colors.transparent),
        border: Border.all(
          color: closed ? fill : ring.withValues(alpha: _hovered ? 1 : 0.7),
          width: 1.8,
        ),
      ),
      child: Center(
        child: AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Curves.easeOutBack,
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: mark,
        ),
      ),
    );

    final onChanged = widget.onChanged;
    final label =
        widget.tooltip ?? (closed ? 'Wieder öffnen' : 'Als erledigt markieren');

    return Semantics(
      button: true,
      checked: widget.done,
      label: label,
      child: Tooltip(
        message: label,
        child: MouseRegion(
          cursor: onChanged == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onChanged == null ? null : () => onChanged(!closed),
            // Etwas Luft um den Kreis, damit der Finger ihn trifft.
            child: Padding(padding: const EdgeInsets.all(3), child: circle),
          ),
        ),
      ),
    );
  }
}
