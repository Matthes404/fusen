import 'package:flutter/material.dart';

import '../palette.dart';
import '../theme.dart';
import '../tokens.dart';

/// Eine Taste, wie sie auf der Tastatur steht.
class Keycap extends StatelessWidget {
  const Keycap(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.paper;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: Radii.xsAll,
        border: Border.all(color: tokens.paperBorder),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontFamily: monoFamily,
          letterSpacing: 0,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Tastenkürzel plus Erklärung: `Enter` speichert.
class KeyHint extends StatelessWidget {
  const KeyHint({required this.keys, required this.text, super.key});

  final List<String> keys;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text('+', style: theme.textTheme.labelSmall),
            ),
          Keycap(keys[i]),
        ],
        const SizedBox(width: 6),
        Text(text, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
