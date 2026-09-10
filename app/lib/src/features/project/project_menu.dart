import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/repositories/project_repository.dart';
import 'project_archive_page.dart';

/// Projekt umbenennen, einfärben, archivieren, löschen.
class ProjectMenu extends ConsumerWidget {
  const ProjectMenu({required this.project, super.key});

  final ProjectRow project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(projectRepositoryProvider);

    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Projekt',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.drive_file_rename_outline, size: 18),
          onPressed: () => renameProject(context, ref, project),
          child: const Text('Umbenennen'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.palette_outlined, size: 18),
          menuChildren: [
            for (final color in projectPalette)
              MenuItemButton(
                leadingIcon: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                  ),
                ),
                onPressed: () => repository.setColor(project.id, color),
                child: Text(color == project.color ? 'Aktuell' : ' '),
              ),
          ],
          child: const Text('Farbe'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.inventory_2_outlined, size: 18),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProjectArchivePage(
                projectId: project.id,
                title: project.name,
              ),
            ),
          ),
          child: const Text('Archiv'),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            project.archivedAt == null
                ? Icons.archive_outlined
                : Icons.unarchive_outlined,
            size: 18,
          ),
          onPressed: () => project.archivedAt == null
              ? repository.archive(project.id)
              : repository.unarchive(project.id),
          child: Text(
            project.archivedAt == null
                ? 'Projekt archivieren'
                : 'Projekt zurückholen',
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => _confirmDelete(context, ref),
          child: const Text('Projekt löschen'),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('„${project.name}“ löschen?'),
        content: const Text(
          'Alle Zettel des Projekts verschwinden mit – auf allen Geräten. '
          'Zum Aufheben lieber archivieren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(projectRepositoryProvider).delete(project.id);
  }
}

/// Fragt einen neuen Projektnamen ab und speichert ihn.
Future<void> renameProject(
  BuildContext context,
  WidgetRef ref,
  ProjectRow project,
) async {
  final name = await promptForProjectName(
    context,
    title: 'Projekt umbenennen',
    initial: project.name,
  );
  if (name == null) return;
  await ref.read(projectRepositoryProvider).rename(project.id, name);
}

/// Kleiner Dialog für „Name eingeben“ – beim Anlegen wie beim Umbenennen.
Future<String?> promptForProjectName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) {
          final name = value.trim();
          if (name.isNotEmpty) Navigator.of(context).pop(name);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          },
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
}
