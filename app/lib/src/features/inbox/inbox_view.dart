import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/note_card.dart';
import '../../ui/widgets/page_body.dart';
import '../capture/capture_sheet.dart';
import '../project/project_archive_page.dart';
import '../project/project_view.dart' show PageHeader;

/// Die Inbox: alles, was noch keinem Projekt zugeordnet ist.
///
/// Bewusst eine flache Liste statt der sieben Bereiche – hier wird
/// weggeräumt, nicht nachgeschlagen.
class InboxView extends ConsumerWidget {
  const InboxView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final count = inbox.value?.length ?? 0;

    return Scaffold(
      appBar: PageHeader(
        title: 'Inbox',
        icon: Icons.inbox_outlined,
        subtitle: switch (count) {
          0 => 'Nichts liegen geblieben',
          1 => '1 Zettel wartet auf ein Projekt',
          _ => '$count Zettel warten auf ein Projekt',
        },
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
          if (notes.isEmpty) {
            return EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Die Inbox ist leer.',
              message:
                  'Alles, was ohne @projekt abgelegt wird, landet hier – '
                  'und wandert von hier aus weiter.',
              action: FilledButton.icon(
                onPressed: () => showCaptureSheet(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ersten Zettel ablegen'),
              ),
            );
          }
          final gutter = pageGutter(context);
          return PageBody(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(
                gutter,
                Insets.lg,
                gutter,
                Insets.listBottom,
              ),
              itemCount: notes.length,
              separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
              itemBuilder: (context, index) => NoteCard(note: notes[index]),
            ),
          );
        },
      ),
    );
  }
}
