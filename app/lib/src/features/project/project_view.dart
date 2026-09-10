import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../ui/note_style.dart';
import '../../ui/palette.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/labels.dart';
import '../../ui/widgets/markdown_text.dart';
import '../../ui/widgets/note_card.dart';
import '../../ui/widgets/page_body.dart';
import '../../ui/widgets/paper.dart';
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
    final color = project == null
        ? Theme.of(context).colorScheme.primary
        : Color(project.color);

    final open = board.value?.where((n) => n.status.isOpen).length ?? 0;

    return Scaffold(
      appBar: PageHeader(
        color: color,
        title: project?.name ?? 'Projekt',
        subtitle: switch (open) {
          0 => 'Nichts offen',
          1 => '1 offener Zettel',
          _ => '$open offene Zettel',
        },
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

/// Der Kopf einer Seite: Farbmarke, Name, eine Zeile Kontext, Aktionen.
///
/// Bewusst keine `AppBar`: die setzt ihren Inhalt an den Fensterrand, der
/// Inhalt darunter steht aber in einer begrenzten Spalte. Hier laufen beide
/// an derselben Kante entlang. Den Zurück-Pfeil bringt der Kopf selbst mit,
/// sobald die Seite auf einen Stapel gelegt wurde.
class PageHeader extends StatelessWidget implements PreferredSizeWidget {
  const PageHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.color,
    this.icon,
    this.actions,
    this.maxWidth = pageMaxWidth,
  });

  final String title;
  final String? subtitle;
  final Color? color;
  final IconData? icon;
  final List<Widget>? actions;
  final double maxWidth;

  static const double height = 68;

  @override
  Size get preferredSize => const Size.fromHeight(height + 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          bottom: false,
          child: SizedBox(
            height: height,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    canPop ? Insets.sm : pageGutter(context),
                    0,
                    Insets.sm,
                    0,
                  ),
                  child: Row(
                    children: [
                      if (canPop) ...[
                        const BackButton(),
                        const SizedBox(width: Insets.xs),
                      ],
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.16),
                          borderRadius: Radii.smAll,
                        ),
                        child: icon == null
                            ? Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: tint,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : Icon(icon, size: 17, color: tint),
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge,
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium,
                              ),
                          ],
                        ),
                      ),
                      ...?actions,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: context.paper.hairline),
      ],
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

    final gutter = pageGutter(context);

    return PageBody(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          gutter,
          Insets.sm,
          gutter,
          Insets.listBottom,
        ),
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
      ),
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
    final accent = type.color(theme.colorScheme);

    return Padding(
      padding: const EdgeInsets.only(top: Insets.xl, bottom: Insets.md),
      child: Row(
        children: [
          TypeBadge(type: type, size: 26),
          const SizedBox(width: Insets.md),
          Text(
            type.sectionTitle,
            style: theme.textTheme.titleSmall?.copyWith(letterSpacing: -0.2),
          ),
          if (count > 0) ...[
            const SizedBox(width: Insets.sm),
            CountBadge(count: count, color: accent),
          ],
          const SizedBox(width: Insets.md),
          // Eine Linie bis zum rechten Rand fasst den Bereich zusammen,
          // ohne ihn einzurahmen.
          Expanded(child: Divider(height: 1, color: context.paper.hairline)),
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
    final accent = NoteType.instruction.color(theme.colorScheme);
    final current = instructions.where((n) => n.status.isOpen).firstOrNull;
    final history = instructions.where((n) => !n.status.isOpen).toList();

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
          _NoInstruction(projectId: projectId)
        else
          PaperCard(
            onTap: () => showNoteEditor(context, current),
            accent: accent,
            wash: accent.withValues(alpha: 0.09),
            emphasised: true,
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              Insets.lg,
              Insets.xl,
              Insets.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.push_pin, size: 14, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      'Gilt gerade',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                MarkdownText(
                  current.body,
                  style: theme.textTheme.titleMedium,
                  selectable: false,
                ),
              ],
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
          width: 440,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: history.length,
            separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
            itemBuilder: (_, index) => NoteCard(note: history[index]),
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

/// Der leere Platz für die Anweisung – der Bereich soll auch dann etwas
/// hergeben, wenn nichts gilt.
class _NoInstruction extends StatelessWidget {
  const _NoInstruction({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.paper;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.xl,
        vertical: Insets.lg,
      ),
      decoration: BoxDecoration(
        borderRadius: Radii.mdAll,
        border: Border.all(color: tokens.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              NoteType.instruction.emptyHint,
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => showCaptureSheet(
              context,
              projectId: projectId,
              type: NoteType.instruction,
            ),
            child: const Text('Anweisung setzen'),
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
    final open = steps.where((n) => n.status.isOpen).toList();
    final closed = steps.where((n) => !n.status.isOpen).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          type: NoteType.step,
          count: open.length,
          projectId: projectId,
        ),
        if (open.isEmpty) InlineHint(NoteType.step.emptyHint),
        if (open.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: open.length,
            onReorderItem: (oldIndex, newIndex) =>
                _reorder(ref, open, oldIndex, newIndex),
            proxyDecorator: (child, _, _) =>
                Material(type: MaterialType.transparency, child: child),
            itemBuilder: (context, index) {
              final note = open[index];
              return Padding(
                key: ValueKey(note.id),
                padding: const EdgeInsets.only(bottom: Insets.md),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: const EdgeInsets.only(right: Insets.sm),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 18,
                            color: Theme.of(context).colorScheme.outline
                                .withValues(alpha: 0.7),
                          ),
                        ),
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
    final open = requirements.where((n) => n.status.isOpen).toList();
    final closed = requirements.where((n) => !n.status.isOpen).toList();

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
        if (open.isEmpty) InlineHint(NoteType.requirement.emptyHint),
        for (final (label, notes) in groups)
          if (notes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm, bottom: Insets.sm),
              child: SectionLabel(label),
            ),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.md),
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
    final open = notes.where((n) => n.status.isOpen).toList();
    final closed = notes.where((n) => !n.status.isOpen).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(type: type, count: open.length, projectId: projectId),
        if (open.isEmpty) InlineHint(type.emptyHint),
        for (final note in open)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md),
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
    final theme = Theme.of(context);
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
          InlineHint(NoteType.log.emptyHint)
        else
          PaperPanel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              title: Text(
                '${log.length} Einträge, neueste zuerst',
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                'Zuletzt: ${formatTimestamp(log.first.createdAt)}',
                style: theme.textTheme.bodySmall,
              ),
              children: [
                Divider(height: 1, color: context.paper.hairline),
                for (final note in log)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.md,
                      Insets.md,
                      Insets.md,
                      0,
                    ),
                    child: NoteCard(note: note, dense: true),
                  ),
                const SizedBox(height: Insets.md),
              ],
            ),
          ),
      ],
    );
  }
}

/// Was erledigt ist, liegt zusammengeklappt darunter.
class _CollapsedGroup extends StatelessWidget {
  const _CollapsedGroup({required this.title, required this.notes});

  final String title;
  final List<NoteRow> notes;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: SectionLabel(title, caps: false),
      children: [
        const SizedBox(height: Insets.xs),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md),
            child: NoteCard(note: note, dense: true),
          ),
      ],
    );
  }
}
