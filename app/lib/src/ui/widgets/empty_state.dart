import 'package:flutter/material.dart';

import '../tokens.dart';

/// Der Platz, an dem noch nichts steht.
///
/// Eine leere Liste soll nicht wie ein Fehler wirken, sondern sagen, was
/// hier hingehört und wie es dahin kommt.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.action,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = accent ?? theme.colorScheme.primary;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Insets.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: Radii.lgAll,
              ),
              child: Icon(icon, size: 26, color: tint),
            ),
            const SizedBox(height: Insets.lg),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: Insets.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: Insets.xl), action!],
          ],
        ),
      ),
    );
  }
}

/// Der kleine Bruder für einen einzelnen Bereich: eine Zeile, kein Bild.
class InlineHint extends StatelessWidget {
  const InlineHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xs),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
