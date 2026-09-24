import 'package:flutter/material.dart';

import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../note_style.dart';
import '../tokens.dart';

/// Die Priorität als kleine Marke: Pfeil und Wort in ihrer Farbe.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({
    required this.type,
    required this.priority,
    super.key,
    this.onTap,
    this.dense = false,
  });

  final NoteType type;

  /// `null` zeigt einen zurückhaltenden Platzhalter – nur sinnvoll, wenn
  /// man darauf tippen kann ([onTap]).
  final NotePriority? priority;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final priority = this.priority;
    final tint = priority?.color(scheme) ?? scheme.onSurfaceVariant;
    final label = priority == null
        ? 'Priorität'
        : priorityLabel(type, priority);

    final pill = Container(
      padding: EdgeInsets.fromLTRB(dense ? 4 : 5, 2, dense ? 7 : 8, 2),
      decoration: BoxDecoration(
        color: priority == null
            ? Colors.transparent
            : tint.withValues(alpha: priority.isEmphasised ? 0.13 : 0.08),
        borderRadius: Radii.pillAll,
        border: priority == null
            ? Border.all(color: scheme.outline.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            priority?.icon ?? Icons.unfold_more_rounded,
            size: dense ? 13 : 14,
            color: tint,
          ),
          const SizedBox(width: 2),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: tint)),
        ],
      ),
    );

    if (onTap == null) return pill;
    return Tooltip(
      message: 'Priorität ändern',
      child: InkWell(borderRadius: Radii.pillAll, onTap: onTap, child: pill),
    );
  }
}

/// Die Einträge eines Prioritätsmenüs – für ein eigenes Menü oder als
/// Untermenü im Menü eines Zettels.
List<Widget> priorityMenuItems({
  required BuildContext context,
  required NoteType type,
  required NotePriority? current,
  required ValueChanged<NotePriority?> onSelected,
}) {
  final scheme = Theme.of(context).colorScheme;
  return [
    for (final priority in NotePriority.displayOrder)
      MenuItemButton(
        leadingIcon: Icon(
          priority.icon,
          size: 18,
          color: priority.color(scheme),
        ),
        trailingIcon: priority == current
            ? const Icon(Icons.check_rounded, size: 16)
            : null,
        onPressed: () => onSelected(priority),
        child: Text(priorityLabel(type, priority)),
      ),
    MenuItemButton(
      leadingIcon: const Icon(Icons.remove_rounded, size: 18),
      trailingIcon: current == null
          ? const Icon(Icons.check_rounded, size: 16)
          : null,
      onPressed: () => onSelected(null),
      child: const Text('Keine'),
    ),
  ];
}

/// Marke und Menü in einem: antippen, Priorität wählen.
class PriorityPicker extends StatelessWidget {
  const PriorityPicker({
    required this.type,
    required this.priority,
    required this.onChanged,
    super.key,
    this.showEmpty = true,
    this.dense = false,
  });

  final NoteType type;
  final NotePriority? priority;
  final ValueChanged<NotePriority?> onChanged;

  /// Ohne Priorität trotzdem eine Marke zeigen, über die man eine setzt.
  final bool showEmpty;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (priority == null && !showEmpty) return const SizedBox.shrink();
    return MenuAnchor(
      menuChildren: priorityMenuItems(
        context: context,
        type: type,
        current: priority,
        onSelected: onChanged,
      ),
      builder: (context, controller, _) => PriorityBadge(
        type: type,
        priority: priority,
        dense: dense,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
