import 'package:flutter/material.dart';

import '../../data/models/note_type.dart';
import '../note_style.dart';
import '../theme.dart';
import '../tokens.dart';

/// Überschrift einer Gruppe, die keine eigene Zeile verdient hat:
/// klein, gesperrt, in Versalien.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.caps = true});

  final String text;

  /// Ganze Sätze bleiben in gemischter Schreibweise – Versalien sind für
  /// ein, zwei Wörter gedacht, länger liest sie niemand gern.
  final bool caps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      caps ? text.toUpperCase() : text,
      style: theme.textTheme.labelSmall?.copyWith(
        letterSpacing: caps ? 0.9 : 0.3,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Die Zahl neben einer Bereichsüberschrift oder einem Projekt.
class CountBadge extends StatelessWidget {
  const CountBadge({
    required this.count,
    super.key,
    this.color,
    this.quiet = false,
  });

  final int count;
  final Color? color;

  /// Zurückhaltende Form ohne Fläche – für Zeilen, die schon Farbe tragen.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurfaceVariant;

    if (quiet) {
      return Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(color: tint),
      );
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: Radii.pillAll,
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(color: tint),
      ),
    );
  }
}

/// Kleine Marke am Fuß eines Zettels: Priorität, Projekt, Tag, Zeitstempel.
class MetaChip extends StatelessWidget {
  const MetaChip({
    required this.label,
    super.key,
    this.color,
    this.icon,
    this.mono = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;

  /// Zeitstempel stehen in einer festen Breite, damit sie untereinander
  /// nicht tanzen.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tinted = color != null;
    final tint = color ?? theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 8 : 6, 3, 8, 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: tinted ? 0.13 : 0.08),
        borderRadius: Radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tint,
              fontFamily: mono ? monoFamily : null,
              letterSpacing: mono ? 0 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Das Symbol eines Zettel-Typs auf getönter Fläche.
class TypeBadge extends StatelessWidget {
  const TypeBadge({required this.type, super.key, this.size = 28});

  final NoteType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = type.color(scheme);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(type.icon, size: size * 0.56, color: accent),
    );
  }
}
