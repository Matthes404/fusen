import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/widgets/note_card.dart';

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
      appBar: AppBar(title: Text('Archiv – $title')),
      body: archive.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (notes) {
          if (notes.isEmpty) {
            return const Center(child: Text('Das Archiv ist leer.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => NoteCard(note: notes[index]),
          );
        },
      ),
    );
  }
}
