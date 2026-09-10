import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../ui/note_style.dart';
import '../../ui/widgets/markdown_text.dart';
import '../../ui/widgets/note_card.dart';
import '../capture/capture_sheet.dart';
import '../note/note_editor.dart';
import 'project_menu.dart';

/// Die Projekt-Ansicht aus dem Konzept: sieben feste Bereiche in fester
/// Reihenfolge, damit man immer weiß, wo etwas steht.
class ProjectView extends ConsumerWidget {
  const ProjectView({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider(projectId)).value;
    final board = ref.watch(boardProvider(projectId));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (project != null)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Color(project.color),
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Text(
                project?.name ?? 'Projekt',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Zettel ablegen',
            icon: const Icon(Icons.add),
            onPressed: () => showCaptureSheet(context, projectId: projectId),
          ),
          if (project != null) ProjectMenu(project: project),
        ],
      ),
      body: board.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (notes) => _ProjectBody(projectId: projectId, notes: notes),
      ),
    );
  }
}

class _ProjectBody extends ConsumerWidget {
  const _ProjectBody({required this.projectId, required this.notes});

  final String projectId;
  final List<NoteRow> notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    List<NoteRow> of(NoteType type) =>
        notes.where((n) => n.type == type).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _InstructionSection(
          projectId: projectId,
          instructions: of(NoteType.instruction),
        ),
        _StepSection(projectId: projectId, steps: of(NoteType.step)),
        _SimpleSection(
          projectId: projectId,
          type: NoteType.question,
          notes: of(NoteType.question),
        ),
        _RequirementSection(
          projectId: projectId,
          requirements: of(NoteType.requirement),
        ),
        _SimpleSection(
          projectId: projectId,
          type: NoteType.idea,
          notes: of(NoteType.idea),
        ),
        _SimpleSection(
          projectId: projectId,
          type: NoteType.reference,
          notes: of(NoteType.reference),
        ),
        _LogSection(projectId: projectId),
      ],
    );
  }
}

/// Kopfzeile eines Bereichs: Symbol, Titel, Anzahl und ein „+“.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.type,
    required this.count,
    super.key,
    this.projectId,
    this.trailing,
  });

  final NoteType type;
  final int count;
  final String? projectId;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Icon(type.icon, size: 18, color: type.color(theme.colorScheme)),
          const SizedBox(width: 8),
          Text(
            type.sectionTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text('$count', style: theme.textTheme.labelMedium),
          ],
          const Spacer(),
          ?trailing,
          IconButton(
            tooltip: '${type.label} hinzufügen',
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                showCaptureSheet(context, projectId: projectId, type: type),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

/// Bereich 1 – groß, immer sichtbar. Ältere Anweisungen liegen im Verlauf.
class _InstructionSection extends ConsumerWidget {
  const _InstructionSection({
    required this.projectId,
    required this.instructions,
  });

  final String projectId;
  final List<NoteRow> instructions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = instructions
        .where((n) => n.status == NoteStatus.open)
        .firstOrNull;
    final history = instructions
        .where((n) => n.status != NoteStatus.open)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          type: NoteType.instruction,
          count: 0,
          projectId: projectId,
          trailing: history.isEmpty
              ? null
              : TextButton(
                  onPressed: () => _showHistory(context, history),
                  child: Text('Verlauf (${history.length})'),
                ),
        ),
        if (current == null)
          _EmptyHint(NoteType.instruction.emptyHint)
        else
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => showNoteEditor(context, current),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: NoteType.instruction
                      .color(theme.colorScheme)
                      .withValues(alpha: 0.08),
                ),
                child: MarkdownText(
                  current.body,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showHistory(BuildContext context, List<NoteRow> history) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verlauf der Anweisungen'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final note in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NoteCard(note: note),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }
}

/// Bereich 2 – Checkliste, per Drag-and-drop sortierbar.
class _StepSection extends ConsumerWidget {
  const _StepSection({required this.projectId, required this.steps});

  final String projectId;
  final List<NoteRow> steps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = steps.where((n) => n.status == NoteStatus.open).toList();
    final closed = steps.where((n) => n.status != NoteStatus.open).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          type: NoteType.step,
          count: open.length,
          projectId: projectId,
        ),
        if (open.isEmpty) _EmptyHint(NoteType.step.emptyHint),
        if (open.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: open.length,
            onReorderItem: (oldIndex, newIndex) =>
                _reorder(ref, open, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final note = open[index];
              return Padding(
                key: ValueKey(note.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.drag_indicator, size: 18),
                      ),
                    ),
                    Expanded(child: NoteCard(note: note, dense: true)),
                  ],
                ),
              );
            },
          ),
        if (closed.isNotEmpty)
          _CollapsedGroup(title: 'Erledigt (${closed.length})', notes: closed),
      ],
    );
  }

  Future<void> _reorder(
    WidgetRef ref,
    List<NoteRow> open,
    int oldIndex,
    int newIndex,
  ) async {
    // onReorderItem liefert newIndex bereits passend zur entfernten Karte.
    final ids = open.map((n) => n.id).toList();
    ids.insert(newIndex, ids.removeAt(oldIndex));
    await ref.read(noteRepositoryProvider).reorder(ids);
  }
}

/// Bereich 4 – nach Priorität gruppiert, Muss zuerst.
class _RequirementSection extends StatelessWidget {
  const _RequirementSection({
    required this.projectId,
    required this.requirements,
  });

  final String projectId;
  final List<NoteRow> requirements;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = requirements
        .where((n) => n.status == NoteStatus.open)
        .toList();
    final closed = requirements
        .where((n) => n.status != NoteStatus.open)
        .toList();

    List<NoteRow> withPriority(NotePriority? priority) =>
        open.where((n) => n.priority == priority).toList();

    final groups = <(String, List<NoteRow>)>[
      for (final priority in NotePriority.displayOrder)
        (priority.label, withPriority(priority)),
      ('Ohne Priorität', withPriority(null)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          type: NoteType.requirement,
          count: open.length,
          projectId: projectId,
        ),
        if (open.isEmpty) _EmptyHint(NoteType.requirement.emptyHint),
        for (final (label, notes) in groups)
          if (notes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(label, style: theme.textTheme.labelMedium),
            ),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NoteCard(note: note),
              ),
          ],
        if (closed.isNotEmpty)
          _CollapsedGroup(
            title: 'Umgesetzt oder verworfen (${closed.length})',
            notes: closed,
          ),
      ],
    );
  }
}

/// Bereiche 3, 5 und 6 – schlichte Listen.
class _SimpleSection extends StatelessWidget {
  const _SimpleSection({
    required this.projectId,
    required this.type,
    required this.notes,
  });

  final String projectId;
  final NoteType type;
  final List<NoteRow> notes;

  @override
  Widget build(BuildContext context) {
    final open = notes.where((n) => n.status == NoteStatus.open).toList();
    final closed = notes.where((n) => n.status != NoteStatus.open).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(type: type, count: open.length, projectId: projectId),
        if (open.isEmpty) _EmptyHint(type.emptyHint),
        for (final note in open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: NoteCard(note: note),
          ),
        if (closed.isNotEmpty)
          _CollapsedGroup(title: 'Erledigt (${closed.length})', notes: closed),
      ],
    );
  }
}

/// Bereich 7 – eingeklappt, neueste Einträge zuerst.
class _LogSection extends ConsumerWidget {
  const _LogSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(logProvider(projectId)).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          type: NoteType.log,
          count: log.length,
          projectId: projectId,
        ),
        if (log.isEmpty)
          _EmptyHint(NoteType.log.emptyHint)
        else
          Card(
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text('${log.length} Einträge, neueste zuerst'),
              subtitle: Text(
                'Zuletzt: ${formatTimestamp(log.first.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              children: [
                for (final note in log)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: NoteCard(note: note, dense: true),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CollapsedGroup extends StatelessWidget {
  const _CollapsedGroup({required this.title, required this.notes});

  final String title;
  final List<NoteRow> notes;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: Theme.of(context).textTheme.labelMedium),
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NoteCard(note: note, dense: true),
            ),
        ],
      ),
    );
  }
}
