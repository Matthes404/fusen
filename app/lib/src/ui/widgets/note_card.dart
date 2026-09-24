import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../features/capture/list_import_dialog.dart';
import '../../features/capture/list_syntax.dart';
import '../../features/note/note_actions.dart';
import '../../features/note/note_editor.dart';
import '../note_style.dart';
import '../tokens.dart';
import 'attachments.dart';
import 'completion_check.dart';
import 'labels.dart';
import 'markdown_text.dart';
import 'paper.dart';
import 'priority_chip.dart';

final DateFormat _timestampFormat = DateFormat('dd.MM.yyyy, HH:mm');

// Rein numerisch: Monatsnamen bräuchten die deutschen Datumsdaten von intl,
// und die müssten vor dem ersten Aufruf geladen sein.
final DateFormat _dayFormat = DateFormat('d.M.');
final DateFormat _dayYearFormat = DateFormat('d.M.yy');

String formatTimestamp(DateTime value) =>
    _timestampFormat.format(value.toLocal());

/// Ein Tag, so wie man ihn sagt: „heute“, „gestern“, „3.9.“.
String formatDay(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final today = DateUtils.dateOnly(reference);
  final day = DateUtils.dateOnly(local);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'heute';
  if (difference == 1) return 'gestern';
  return day.year == today.year
      ? _dayFormat.format(local)
      : _dayYearFormat.format(local);
}

/// Ob die Oberfläche auf einem Touch-Gerät läuft – dort gibt es Wischgesten.
bool isTouchPlatform(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };

/// Ein Zettel in einer Liste.
///
/// Dieselbe Karte für alle sieben Typen: was der Typ kann, entscheidet, was
/// zu sehen ist – der runde Haken bei allem, was man abarbeitet, die
/// Priorität als Pfeil, Zeitstempel beim Log, Bilder als Vorschau. Die
/// Kennfarbe steht als Streifen an der Kante und als Hauch auf dem Papier,
/// damit ein Stapel schon aus dem Augenwinkel sortiert aussieht.
class NoteCard extends ConsumerWidget {
  const NoteCard({
    required this.note,
    super.key,
    this.showProject = false,
    this.showType = false,
    this.triage = false,
    this.showPriority = true,
    this.dense = false,
    this.swipeable = true,
  });

  final NoteRow note;

  /// In der Suche und im Archiv steht der Zettel ohne Projektkontext.
  final bool showProject;

  /// Wo verschiedene Typen gemischt stehen (Inbox, Suche, Übersicht), sagt
  /// eine Marke, was der Zettel ist.
  final bool showType;

  /// In der Inbox: eine Marke, mit der man den Zettel einem Projekt gibt.
  final bool triage;

  /// Steht die Karte schon unter einer Prioritäts-Überschrift, wäre die
  /// Marke doppelt. Ändern lässt sie sich dann über das Menü.
  final bool showPriority;

  final bool dense;

  /// Auf dem Handy: nach rechts wischen hakt ab, nach links archiviert.
  final bool swipeable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final closed = !note.status.isOpen;

    final card = PaperCard(
      onTap: () => showNoteEditor(context, note),
      accent: note.type.color(scheme),
      // Abgehakte Zettel treten zurück: keine Einfärbung mehr.
      wash: closed ? null : note.type.wash(scheme),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: closed ? 0.6 : 1,
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
                              decoration: closed
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (note.body.isNotEmpty)
                        MarkdownText(
                          note.body,
                          selectable: false,
                          struck: closed && (note.title?.isEmpty ?? true),
                        ),
                      if (note.answer != null && note.answer!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: Insets.sm),
                          child: _AnswerBlock(answer: note.answer!),
                        ),
                    ],
                  ),
                ),
                AttachmentStrip(noteId: note.id, size: dense ? 48 : 56),
                _Meta(
                  note: note,
                  showProject: showProject,
                  showType: showType,
                  showPriority: showPriority,
                  triage: triage,
                ),
              ],
            ),
          ),
          _NoteMenu(note: note),
        ],
      ),
    );

    if (!swipeable || !isTouchPlatform(context)) return card;
    return _SwipeActions(note: note, child: card);
  }
}

class _Leading extends ConsumerWidget {
  const _Leading({required this.note, required this.dense});

  final NoteRow note;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (note.type.isCheckable) {
      return CompletionCheck(
        done: note.status == NoteStatus.done,
        discarded: note.status == NoteStatus.discarded,
        accent: note.type.color(Theme.of(context).colorScheme),
        size: dense ? 20 : 21,
        tooltip: note.status.isOpen
            ? 'Als ${statusLabel(note.type, NoteStatus.done)} markieren'
            : 'Wieder öffnen',
        onChanged: (done) =>
            NoteActions.setDone(context, ref, note, done: done),
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
  const _Meta({
    required this.note,
    required this.showProject,
    required this.showType,
    required this.showPriority,
    required this.triage,
  });

  final NoteRow note;
  final bool showProject;
  final bool showType;
  final bool showPriority;
  final bool triage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final chips = <Widget>[];

    if (showPriority && note.priority != null && note.type.supportsPriority) {
      chips.add(
        PriorityPicker(
          type: note.type,
          priority: note.priority,
          dense: true,
          showEmpty: false,
          onChanged: (priority) =>
              ref.read(noteRepositoryProvider).setPriority(note.id, priority),
        ),
      );
    }
    if (showType) {
      chips.add(
        MetaChip(
          label: note.type.label,
          icon: note.type.icon,
          color: note.type.color(scheme),
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
    final closedAt = note.closedAt;
    if (closedAt != null &&
        !note.status.isOpen &&
        note.type != NoteType.instruction) {
      final done = note.status == NoteStatus.done;
      chips.add(
        MetaChip(
          label:
              '${_capitalized(statusLabel(note.type, note.status))} '
              '${formatDay(closedAt)}',
          icon: done ? Icons.check_rounded : Icons.block_rounded,
          color: done ? scheme.tertiary : null,
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
    if (triage) {
      chips.add(_SortInto(note: note));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm),
      child: Wrap(
        spacing: 6,
        runSpacing: Insets.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: chips,
      ),
    );
  }

  static String _capitalized(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}

/// „Einsortieren“: der kürzeste Weg aus der Inbox in ein Projekt.
class _SortInto extends ConsumerWidget {
  const _SortInto({required this.note});

  final NoteRow note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider).value ?? const [];
    final theme = Theme.of(context);

    return MenuAnchor(
      menuChildren: [
        for (final project in projects)
          MenuItemButton(
            leadingIcon: _ProjectDot(color: Color(project.color)),
            onPressed: () => NoteActions.moveTo(context, ref, note, project.id),
            child: Text(project.name),
          ),
        if (projects.isEmpty)
          const MenuItemButton(child: Text('Noch keine Projekte')),
      ],
      builder: (context, controller, _) => InkWell(
        borderRadius: Radii.pillAll,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
          decoration: BoxDecoration(
            borderRadius: Radii.pillAll,
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.drive_file_move_outline,
                size: 13,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                'Einsortieren',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
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
    final scheme = Theme.of(context).colorScheme;
    final repository = ref.read(noteRepositoryProvider);
    final splittable = parseList(note.body).entries.length > 1;

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
        if (note.type.isCheckable)
          MenuItemButton(
            leadingIcon: Icon(
              note.status.isOpen
                  ? Icons.check_circle_outline
                  : Icons.radio_button_unchecked,
              size: 18,
            ),
            onPressed: () => NoteActions.setDone(
              context,
              ref,
              note,
              done: note.status.isOpen,
            ),
            child: Text(
              note.status.isOpen
                  ? 'Als ${statusLabel(note.type, NoteStatus.done)} markieren'
                  : 'Wieder öffnen',
            ),
          ),
        if (note.type.supportsPriority)
          SubmenuButton(
            leadingIcon: Icon(
              note.priority?.icon ?? Icons.low_priority_rounded,
              size: 18,
            ),
            menuChildren: priorityMenuItems(
              context: context,
              type: note.type,
              current: note.priority,
              onSelected: (priority) =>
                  repository.setPriority(note.id, priority),
            ),
            child: const Text('Priorität'),
          ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.swap_horiz, size: 18),
          menuChildren: [
            for (final type in NoteType.sectionOrder)
              MenuItemButton(
                leadingIcon: Icon(
                  type.icon,
                  size: 18,
                  color: type.color(scheme),
                ),
                onPressed: type == note.type
                    ? null
                    : () => NoteActions.changeType(context, ref, note, type),
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
                  : () => NoteActions.moveTo(context, ref, note, null),
              child: const Text('Inbox'),
            ),
            for (final project in ref.watch(projectsProvider).value ?? const [])
              MenuItemButton(
                leadingIcon: _ProjectDot(color: Color(project.color)),
                onPressed: project.id == note.projectId
                    ? null
                    : () => NoteActions.moveTo(context, ref, note, project.id),
                child: Text(project.name),
              ),
          ],
          child: const Text('Verschieben'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          onPressed: () => NoteActions.addImages(context, ref, note),
          child: const Text('Bild anhängen …'),
        ),
        if (splittable)
          MenuItemButton(
            leadingIcon: const Icon(Icons.call_split_rounded, size: 18),
            onPressed: () => showListImportDialog(
              context,
              projectId: note.projectId,
              initialText: note.body,
              source: note,
            ),
            child: const Text('In einzelne Zettel aufteilen …'),
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
              ? NoteActions.archive(context, ref, note)
              : repository.unarchive(note.id),
          child: Text(note.archivedAt == null ? 'Archivieren' : 'Zurückholen'),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            Icons.delete_outline,
            size: 18,
            color: scheme.error,
          ),
          onPressed: () => NoteActions.delete(context, ref, note),
          child: Text('Löschen', style: TextStyle(color: scheme.error)),
        ),
      ],
    );
  }
}

/// Wischgesten auf dem Handy: nach rechts abhaken, nach links archivieren.
///
/// Die Karte verschwindet nicht durch die Geste selbst, sondern weil sich
/// die Liste ändert – deshalb liefert `confirmDismiss` immer `false`. Sonst
/// entfernte `Dismissible` die Karte, bevor die Datenbank es tut, und käme
/// mit dem neuen Stand der Liste durcheinander.
class _SwipeActions extends ConsumerWidget {
  const _SwipeActions({required this.note, required this.child});

  final NoteRow note;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final canCheck = note.type.isCheckable;
    final archived = note.archivedAt != null;

    Widget background(
      Alignment alignment,
      Color color,
      IconData icon,
      String label,
    ) => Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: Radii.mdAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: Insets.sm),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: color),
          ),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('swipe-${note.id}'),
      direction: canCheck
          ? DismissDirection.horizontal
          : DismissDirection.endToStart,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.3,
      },
      background: canCheck
          ? background(
              Alignment.centerLeft,
              scheme.tertiary,
              note.status.isOpen ? Icons.check_rounded : Icons.undo_rounded,
              note.status.isOpen ? 'Erledigt' : 'Wieder offen',
            )
          : const SizedBox.shrink(),
      // Im Archiv (und in Suchtreffern von dort) holt dieselbe Geste den
      // Zettel zurück, statt ihn ein zweites Mal zu archivieren.
      secondaryBackground: archived
          ? background(
              Alignment.centerRight,
              scheme.onSurfaceVariant,
              Icons.unarchive_outlined,
              'Zurückholen',
            )
          : background(
              Alignment.centerRight,
              scheme.onSurfaceVariant,
              Icons.archive_outlined,
              'Archivieren',
            ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await NoteActions.setDone(
            context,
            ref,
            note,
            done: note.status.isOpen,
          );
        } else if (archived) {
          await NoteActions.unarchive(context, ref, note);
        } else {
          await NoteActions.archive(context, ref, note);
        }
        return false;
      },
      child: child,
    );
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
