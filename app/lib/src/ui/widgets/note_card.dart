import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../features/note/note_editor.dart';
import '../note_style.dart';
import '../tokens.dart';
import 'labels.dart';
import 'markdown_text.dart';
import 'paper.dart';

final DateFormat _timestampFormat = DateFormat('dd.MM.yyyy, HH:mm');

String formatTimestamp(DateTime value) =>
    _timestampFormat.format(value.toLocal());

/// Ein Zettel in einer Liste.
///
/// Dieselbe Karte für alle sieben Typen: was der Typ kann, entscheidet, was
/// zu sehen ist – Häkchen bei Schritten, Priorität bei Anforderungen,
/// Zeitstempel beim Log. Die Kennfarbe steht als Streifen an der Kante und
/// als Hauch auf dem Papier, damit ein Stapel schon aus dem Augenwinkel
/// sortiert aussieht.
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
    final scheme = theme.colorScheme;
    final done = note.status != NoteStatus.open;

    return PaperCard(
      onTap: () => showNoteEditor(context, note),
      accent: note.type.color(scheme),
      // Abgehakte Zettel treten zurück: keine Einfärbung mehr.
      wash: done ? null : note.type.wash(scheme),
      padding: EdgeInsets.fromLTRB(
        dense ? Insets.sm : Insets.md,
        dense ? Insets.sm : Insets.md,
        Insets.xs,
        dense ? Insets.sm : Insets.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Leading(note: note, dense: dense),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Opacity(
              opacity: done ? 0.6 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (note.title != null && note.title!.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: note.body.isEmpty ? 0 : Insets.xs,
                      ),
                      child: Text(
                        note.title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (note.body.isNotEmpty)
                    MarkdownText(note.body, selectable: false),
                  if (note.answer != null && note.answer!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: Insets.sm),
                      child: _AnswerBlock(answer: note.answer!),
                    ),
                  _Meta(note: note, showProject: showProject),
                ],
              ),
            ),
          ),
          _NoteMenu(note: note),
        ],
      ),
    );
  }
}

class _Leading extends ConsumerWidget {
  const _Leading({required this.note, required this.dense});

  final NoteRow note;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (note.type.isCheckable) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Center(
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
        ),
      );
    }

    return TypeBadge(type: note.type, size: dense ? 24 : 28);
  }
}

/// Die Antwort auf eine Frage – abgesetzt, aber am Zettel dran.
class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.answer});

  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = NoteType.question.color(theme.colorScheme);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.md, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: Radii.smAll,
        border: Border(left: BorderSide(color: accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.subdirectory_arrow_right, size: 13, color: accent),
              const SizedBox(width: Insets.xs),
              Text(
                'Antwort',
                style: theme.textTheme.labelSmall?.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: Insets.xs),
          MarkdownText(answer, selectable: false),
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
    final scheme = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    if (note.priority != null) {
      final priority = note.priority!;
      chips.add(
        MetaChip(
          label: priority.label,
          icon: Icons.flag_outlined,
          color: priority.isEmphasised ? priority.color(scheme) : null,
        ),
      );
    }
    if (note.type == NoteType.log) {
      chips.add(
        MetaChip(
          label: formatTimestamp(note.createdAt),
          icon: Icons.schedule,
          mono: true,
        ),
      );
    }
    if (showProject) {
      final projects = ref.watch(projectsProvider).value ?? const [];
      final project = projects.where((p) => p.id == note.projectId).firstOrNull;
      chips.add(
        MetaChip(
          label: project?.name ?? 'Inbox',
          icon: project == null ? Icons.inbox_outlined : Icons.circle,
          color: project == null ? null : Color(project.color),
        ),
      );
    }
    for (final tag in note.tags) {
      chips.add(MetaChip(label: '#$tag'));
    }
    if (note.archivedAt != null) {
      chips.add(
        const MetaChip(label: 'archiviert', icon: Icons.inventory_2_outlined),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm),
      child: Wrap(spacing: 6, runSpacing: Insets.xs, children: chips),
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
      alignmentOffset: const Offset(-140, 0),
      builder: (context, controller, child) => IconButton(
        icon: const Icon(Icons.more_horiz, size: 18),
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
                leadingIcon: Icon(
                  type.icon,
                  size: 18,
                  color: type.color(Theme.of(context).colorScheme),
                ),
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
              leadingIcon: const Icon(Icons.inbox_outlined, size: 18),
              onPressed: note.projectId == null
                  ? null
                  : () => repository.moveToProject(note.id, null),
              child: const Text('Inbox'),
            ),
            for (final project in ref.watch(projectsProvider).value ?? const [])
              MenuItemButton(
                leadingIcon: _ProjectDot(color: Color(project.color)),
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

/// Der Farbpunkt eines Projekts – im Menü an der Stelle des Symbols.
class _ProjectDot extends StatelessWidget {
  const _ProjectDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}
