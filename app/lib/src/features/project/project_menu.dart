import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/repositories/project_repository.dart';
import '../../ui/tokens.dart';
import '../capture/list_import_dialog.dart';
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
          leadingIcon: const Icon(Icons.playlist_add_rounded, size: 18),
          onPressed: () => showListImportDialog(context, projectId: project.id),
          child: const Text('Aus einer Liste anlegen …'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.drive_file_rename_outline, size: 18),
          onPressed: () => renameProject(context, ref, project),
          child: const Text('Umbenennen'),
        ),
        MenuItemButton(
          leadingIcon: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Color(project.color),
              shape: BoxShape.circle,
            ),
          ),
          onPressed: () => _pickColor(context, ref),
          child: const Text('Farbe …'),
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

  Future<void> _pickColor(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Farbe für „${project.name}“'),
        content: SizedBox(
          width: 264,
          child: Wrap(
            spacing: Insets.md,
            runSpacing: Insets.md,
            children: [
              for (final color in projectPalette)
                _Swatch(
                  color: Color(color),
                  selected: color == project.color,
                  onTap: () => Navigator.of(context).pop(color),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await ref.read(projectRepositoryProvider).setColor(project.id, picked);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    // Vor dem Dialog holen: danach ist das Menü womöglich schon weg.
    final repository = ref.read(projectRepositoryProvider);
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
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.delete(project.id);
  }
}

/// Ein Farbfeld in der Auswahl.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: Radii.pillAll,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// Fragt einen neuen Projektnamen ab und speichert ihn.
Future<void> renameProject(
  BuildContext context,
  WidgetRef ref,
  ProjectRow project,
) async {
  final repository = ref.read(projectRepositoryProvider);
  final name = await promptForProjectName(
    context,
    title: 'Projekt umbenennen',
    initial: project.name,
  );
  if (name == null) return;
  await repository.rename(project.id, name);
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
