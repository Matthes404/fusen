import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/widgets/note_card.dart';
import '../capture/capture_sheet.dart';
import '../project/project_archive_page.dart';

/// Die Inbox: alles, was noch keinem Projekt zugeordnet ist.
///
/// Bewusst eine flache Liste statt der sieben Bereiche – hier wird
/// weggeräumt, nicht nachgeschlagen.
class InboxView extends ConsumerWidget {
  const InboxView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          IconButton(
            tooltip: 'Zettel ablegen',
            icon: const Icon(Icons.add),
            onPressed: () => showCaptureSheet(context),
          ),
          IconButton(
            tooltip: 'Archiv',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const ProjectArchivePage(projectId: null, title: 'Inbox'),
              ),
            ),
          ),
        ],
      ),
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (notes) {
          if (notes.isEmpty) return const _EmptyInbox();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => NoteCard(note: notes[index]),
          );
        },
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('Die Inbox ist leer.', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Alles, was ohne @projekt abgelegt wird, landet hier.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
