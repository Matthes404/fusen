import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/note_card.dart' show formatDay;
import '../../ui/widgets/page_body.dart';
import '../../ui/widgets/paper.dart';
import '../../ui/widgets/project_avatar.dart';
import '../../ui/widgets/undo.dart';
import 'project_view.dart' show PageHeader;

/// Archivierte Projekte – bisher gab es keinen Weg zurück zu ihnen.
class ArchivedProjectsPage extends ConsumerWidget {
  const ArchivedProjectsPage({required this.onOpenProject, super.key});

  final ValueChanged<String> onOpenProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedProjectsProvider).value ?? const [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const PageHeader(
        title: 'Archivierte Projekte',
        icon: Icons.inventory_2_outlined,
        subtitle: 'Ruhen, bis man sie zurückholt',
      ),
      body: archived.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Kein Projekt im Archiv.',
              message:
                  'Ein Projekt, das fertig ist, wandert über sein Menü hierher '
                  '– samt allen Zetteln.',
            )
          : PageBody(
              child: ListView.separated(
                padding: EdgeInsets.all(pageGutter(context)),
                itemCount: archived.length,
                separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
                itemBuilder: (context, index) {
                  final project = archived[index];
                  return PaperCard(
                    onTap: () => onOpenProject(project.id),
                    child: Row(
                      children: [
                        ProjectAvatar(project: project, size: 28),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                project.name,
                                style: theme.textTheme.titleSmall,
                              ),
                              if (project.archivedAt != null)
                                Text(
                                  'archiviert ${formatDay(project.archivedAt!)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final repository = ref.read(
                              projectRepositoryProvider,
                            );
                            await repository.unarchive(project.id);
                            showUndoSnackBar(
                              messenger,
                              '„${project.name}“ ist zurück',
                              onUndo: () => repository.archive(project.id),
                            );
                          },
                          icon: const Icon(Icons.unarchive_outlined, size: 18),
                          label: const Text('Zurückholen'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
