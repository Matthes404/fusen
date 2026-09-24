import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../tokens.dart';

/// Die Einträge einer Projektauswahl: Inbox, die aktiven Projekte – und das
/// gewählte, wenn es archiviert oder (noch) nicht angekommen ist.
///
/// Ohne diesen letzten Eintrag gäbe es zum Wert kein passendes Element: im
/// Debug-Build eine Assertion, im Release ein leeres Feld. Das passiert, wenn
/// man einen Zettel aus einem archivierten Projekt öffnet.
List<DropdownMenuItem<String?>> projectMenuItems({
  required List<ProjectRow> projects,
  required List<ProjectRow> archived,
  required String? selected,
  bool showColor = false,
}) {
  Widget label(String text, {Color? color}) => Row(
    children: [
      if (showColor && color != null) ...[
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: Insets.sm),
      ],
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
    ],
  );

  final known = projects.any((p) => p.id == selected);
  final hidden = selected == null || known
      ? null
      : archived.where((p) => p.id == selected).firstOrNull;

  return [
    const DropdownMenuItem<String?>(child: Text('Inbox')),
    for (final project in projects)
      DropdownMenuItem<String?>(
        value: project.id,
        child: label(project.name, color: Color(project.color)),
      ),
    if (selected != null && !known)
      DropdownMenuItem<String?>(
        value: selected,
        child: label(
          hidden == null
              ? 'Unbekanntes Projekt'
              : '${hidden.name} (archiviert)',
          color: hidden == null ? null : Color(hidden.color),
        ),
      ),
  ];
}
