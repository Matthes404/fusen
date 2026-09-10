import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../features/note/note_editor.dart';
import '../note_style.dart';
import 'markdown_text.dart';

final DateFormat _timestampFormat = DateFormat('dd.MM.yyyy, HH:mm');

String formatTimestamp(DateTime value) =>
    _timestampFormat.format(value.toLocal());

/// Ein Zettel in einer Liste.
///
/// Dieselbe Karte für alle sieben Typen: was der Typ kann, entscheidet, was
/// zu sehen ist – Häkchen bei Schritten, Priorität bei Anforderungen,
/// Zeitstempel beim Log.
class NoteCard extends ConsumerWidget {
  const NoteCard({
    required this.note,
    super.key,
    this.showProject = false,
    this.dense = false,
  });

  final NoteRow note;

  /// In der Suche und im Archiv steht der Zettel ohne Projektkontext.
  final bool showProject;

  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final done = note.status != NoteStatus.open;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showNoteEditor(context, note),
        child: Padding(
          padding: EdgeInsets.fromLTRB(dense ? 8 : 12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Leading(note: note),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (note.title != null && note.title!.isNotEmpty)
                      Text(
                        note.title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    if (note.body.isNotEmpty)
                      Opacity(
                        opacity: done ? 0.55 : 1,
                        child: MarkdownText(note.body),
                      ),
                    if (note.answer != null && note.answer!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _AnswerBlock(answer: note.answer!),
                      ),
                    _Meta(note: note, showProject: showProject),
                  ],
                ),
              ),
              _NoteMenu(note: note),
            ],
          ),
        ),
      ),
    );
  }
}

class _Leading extends ConsumerWidget {
  const _Leading({required this.note});

  final NoteRow note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    if (note.type.isCheckable) {
      return SizedBox(
        width: 28,
        height: 28,
        child: Checkbox(
          value: note.status == NoteStatus.done,
          tristate: false,
          onChanged: (checked) => ref
              .read(noteRepositoryProvider)
              .setStatus(
                note.id,
                checked == true ? NoteStatus.done : NoteStatus.open,
              ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Icon(note.type.icon, size: 18, color: note.type.color(scheme)),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.answer});

  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Antwort', style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          MarkdownText(answer),
        ],
      ),
    );
  }
}

class _Meta extends ConsumerWidget {
  const _Meta({required this.note, required this.showProject});

  final NoteRow note;
  final bool showProject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chips = <Widget>[];

    if (note.priority != null) {
      chips.add(
        _MetaChip(label: note.priority!.label, color: note.priority!.color),
      );
    }
    if (note.type == NoteType.log) {
      chips.add(_MetaChip(label: formatTimestamp(note.createdAt)));
    }
    if (showProject) {
      final projects = ref.watch(projectsProvider).value ?? const [];
      final project = projects.where((p) => p.id == note.projectId).firstOrNull;
      chips.add(
        _MetaChip(
          label: project?.name ?? 'Inbox',
          color: project == null ? null : Color(project.color),
        ),
      );
    }
    for (final tag in note.tags) {
      chips.add(_MetaChip(label: '#$tag'));
    }
    if (note.archivedAt != null) {
      chips.add(const _MetaChip(label: 'archiviert'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color == null ? theme.colorScheme.onSurfaceVariant : tint,
        ),
      ),
    );
  }
}

class _NoteMenu extends ConsumerWidget {
  const _NoteMenu({required this.note});

  final NoteRow note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(noteRepositoryProvider);

    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: const Icon(Icons.more_vert, size: 18),
        visualDensity: VisualDensity.compact,
        tooltip: 'Aktionen',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: () => showNoteEditor(context, note),
          child: const Text('Bearbeiten'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.swap_horiz, size: 18),
          menuChildren: [
            for (final type in NoteType.sectionOrder)
              MenuItemButton(
                leadingIcon: Icon(type.icon, size: 18),
                onPressed: type == note.type
                    ? null
                    : () => _changeType(context, ref, type),
                child: Text(type.label),
              ),
          ],
          child: const Text('Typ wechseln'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.drive_file_move_outline, size: 18),
          menuChildren: [
            MenuItemButton(
              onPressed: note.projectId == null
                  ? null
                  : () => repository.moveToProject(note.id, null),
              child: const Text('Inbox'),
            ),
            for (final project in ref.watch(projectsProvider).value ?? const [])
              MenuItemButton(
                onPressed: project.id == note.projectId
                    ? null
                    : () => repository.moveToProject(note.id, project.id),
                child: Text(project.name),
              ),
          ],
          child: const Text('Verschieben'),
        ),
        if (note.body.isNotEmpty)
          MenuItemButton(
            leadingIcon: const Icon(Icons.copy_all_outlined, size: 18),
            onPressed: () => copyToClipboard(context, note.body),
            child: const Text('Text kopieren'),
          ),
        MenuItemButton(
          leadingIcon: Icon(
            note.archivedAt == null
                ? Icons.archive_outlined
                : Icons.unarchive_outlined,
            size: 18,
          ),
          onPressed: () => note.archivedAt == null
              ? repository.archive(note.id)
              : repository.unarchive(note.id),
          child: Text(note.archivedAt == null ? 'Archivieren' : 'Zurückholen'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.delete_outline, size: 18),
          onPressed: () => repository.delete(note.id),
          child: const Text('Löschen'),
        ),
      ],
    );
  }

  Future<void> _changeType(
    BuildContext context,
    WidgetRef ref,
    NoteType type,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(noteRepositoryProvider).changeType(note.id, type);
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
