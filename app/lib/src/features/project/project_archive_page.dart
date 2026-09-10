import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/note_card.dart';
import '../../ui/widgets/page_body.dart';
import 'project_view.dart' show PageHeader;

/// Erledigte und verworfene Zettel eines Projekts.
class ProjectArchivePage extends ConsumerWidget {
  const ProjectArchivePage({
    required this.projectId,
    required this.title,
    super.key,
  });

  final String? projectId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archive = ref.watch(archiveProvider(projectId));

    return Scaffold(
      appBar: PageHeader(
        title: 'Archiv',
        subtitle: title,
        icon: Icons.inventory_2_outlined,
      ),
      body: archive.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (notes) {
          if (notes.isEmpty) {
            return const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Das Archiv ist leer.',
              message:
                  'Archivierte Zettel bleiben erhalten, stehen aber nicht '
                  'mehr im Weg.',
            );
          }
          final gutter = pageGutter(context);
          return PageBody(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(
                gutter,
                Insets.lg,
                gutter,
                Insets.xxl,
              ),
              itemCount: notes.length,
              separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
              itemBuilder: (context, index) =>
                  NoteCard(note: notes[index], showProject: projectId == null),
            ),
          );
        },
      ),
    );
  }
}
