import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../data/repositories/note_repository.dart';
import '../../ui/note_style.dart';
import '../../ui/palette.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/labels.dart';
import '../../ui/widgets/markdown_text.dart';
import '../../ui/widgets/note_card.dart';
import '../../ui/widgets/page_body.dart';
import '../../ui/widgets/paper.dart';
import '../capture/capture_plan.dart';
import '../capture/capture_sheet.dart';
import '../capture/list_import_dialog.dart';
import '../note/note_editor.dart';
import 'project_menu.dart';

/// Ab dieser Breite stehen die Bereiche in zwei Spalten.
const double _twoColumnWidth = 1120;

/// Breite der Inhaltsspalte bei zwei Spalten.
const double _twoColumnMaxWidth = 1440;

/// Die Projekt-Ansicht aus dem Konzept: sieben feste Bereiche in fester
/// Reihenfolge, damit man immer weiß, wo etwas steht.
class ProjectView extends ConsumerWidget {
  const ProjectView({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider(projectId)).value;
    final board = ref.watch(boardProvider(projectId));
    final progress =
        ref.watch(progressProvider).value?[projectId] ?? NoteProgress.empty;
    final color = project == null
        ? Theme.of(context).colorScheme.primary
        : Color(project.color);

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= _twoColumnWidth;
        final maxWidth = twoColumns ? _twoColumnMaxWidth : pageMaxWidth;
        return _scaffold(
          context,
          project,
          board,
          progress,
          color,
          twoColumns,
          maxWidth,
        );
      },
    );
  }

  Widget _scaffold(
    BuildContext context,
    ProjectRow? project,
    AsyncValue<List<NoteRow>> board,
    NoteProgress progress,
    Color color,
    bool twoColumns,
    double maxWidth,
  ) {
    return Scaffold(
      appBar: PageHeader(
        color: color,
        title: project?.name ?? 'Projekt',
        subtitle: switch ((progress.open, progress.closed)) {
          (0, 0) => 'Noch nichts zu tun',
          (0, _) => 'Alles erledigt',
          (final open, 0) => open == 1 ? '1 offen' : '$open offen',
          (final open, final closed) => '$open offen · $closed erledigt',
        },
        progress: progress.total == 0 ? null : progress.ratio,
        maxWidth: maxWidth,
        actions: [
          // Auf dem Handy wird es im Kopf eng – dort steht der Import im
          // Projektmenü.
          if (MediaQuery.sizeOf(context).width >= 600)
            IconButton(
              tooltip: 'Aus einer Liste anlegen',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () =>
                  showListImportDialog(context, projectId: projectId),
            ),
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
        data: (notes) => _ProjectBody(
          projectId: projectId,
          notes: notes,
          twoColumns: twoColumns,
        ),
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
    this.progress,
    this.maxWidth = pageMaxWidth,
  });

  final String title;
  final String? subtitle;
  final Color? color;
  final IconData? icon;
  final List<Widget>? actions;

  /// Anteil erledigt, 0 bis 1 – als schmaler Balken neben dem Untertitel.
  final double? progress;
  final double maxWidth;

  static const double height = 68;

  @override
  Size get preferredSize => const Size.fromHeight(height + 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final progress = this.progress;

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
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.16),
                          borderRadius: Radii.smAll,
                        ),
                        child: icon == null
                            ? Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: tint,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : Icon(icon, size: 18, color: tint),
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
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      subtitle!,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelMedium,
                                    ),
                                  ),
                                  if (progress != null) ...[
                                    const SizedBox(width: Insets.sm),
                                    _ProgressBar(value: progress, color: tint),
                                  ],
                                ],
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

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final percent = (value * 100).round();
    return Tooltip(
      message: '$percent % erledigt',
      child: SizedBox(
        width: 72,
        child: ClipRRect(
          borderRadius: Radii.pillAll,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: value),
            duration: Motion.slow,
            curve: Motion.standard,
            builder: (context, animated, _) => LinearProgressIndicator(
              value: animated,
              minHeight: 5,
              color: color,
              backgroundColor: color.withValues(alpha: 0.16),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectBody extends ConsumerWidget {
  const _ProjectBody({
    required this.projectId,
    required this.notes,
    required this.twoColumns,
  });

  final String projectId;
  final List<NoteRow> notes;
  final bool twoColumns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    List<NoteRow> of(NoteType type) =>
        notes.where((n) => n.type == type).toList();

    final instruction = _InstructionSection(
      projectId: projectId,
      instructions: of(NoteType.instruction),
    );
    Widget work(NoteType type) =>
        _WorkSection(projectId: projectId, type: type, notes: of(type));
    final references = _ReferenceSection(
      projectId: projectId,
      notes: of(NoteType.reference),
    );
    final log = _LogSection(projectId: projectId);

    final gutter = pageGutter(context);
    final padding = EdgeInsets.fromLTRB(
      gutter,
      Insets.sm,
      gutter,
      Insets.listBottom,
    );

    if (!twoColumns) {
      return PageBody(
        child: ListView(
          padding: padding,
          children: [
            instruction,
            work(NoteType.step),
            work(NoteType.question),
            work(NoteType.requirement),
            work(NoteType.idea),
            references,
            log,
          ],
        ),
      );
    }

    // Auf dem großen Bildschirm liegen die Zettel wie auf einem Tisch
    // nebeneinander: links, was jetzt zu tun ist, rechts, was bleibt.
    return PageBody(
      maxWidth: _twoColumnMaxWidth,
      child: SingleChildScrollView(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  instruction,
                  work(NoteType.step),
                  work(NoteType.question),
                ],
              ),
            ),
            const SizedBox(width: Insets.xxl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  work(NoteType.requirement),
                  work(NoteType.idea),
                  references,
                  log,
                ],
              ),
            ),
          ],
        ),
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
            tooltip: '${type.label} ablegen',
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
    final history = instructions.where((n) => !n.status.isOpen).toList()
      ..sort(
        (a, b) =>
            (b.closedAt ?? b.updatedAt).compareTo(a.closedAt ?? a.updatedAt),
      );

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
                      'GILT GERADE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'seit ${formatDay(current.createdAt)}',
                      style: theme.textTheme.labelSmall,
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
          width: 460,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: history.length,
            separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
            itemBuilder: (_, index) {
              final note = history[index];
              final until = note.closedAt;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel(
                    until == null
                        ? 'Seit ${formatDay(note.createdAt)}'
                        : '${formatDay(note.createdAt)} bis ${formatDay(until)}',
                    caps: false,
                  ),
                  const SizedBox(height: Insets.xs),
                  NoteCard(note: note, swipeable: false),
                ],
              );
            },
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
              '${NoteType.instruction.emptyHint} Was gilt diese Woche?',
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

/// Die Bereiche, in denen gearbeitet wird: Schritte, Fragen, Anforderungen,
/// Ideen.
///
/// Offenes steht oben, nach Priorität gruppiert, sobald irgendwo eine
/// gesetzt ist – ohne Prioritäten bleibt es eine schlichte Liste. Schritte
/// lassen sich innerhalb ihrer Gruppe verschieben. Abgeschlossenes liegt
/// eingeklappt darunter, zuletzt Erledigtes zuerst.
class _WorkSection extends ConsumerWidget {
  const _WorkSection({
    required this.projectId,
    required this.type,
    required this.notes,
  });

  final String projectId;
  final NoteType type;
  final List<NoteRow> notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = notes.where((n) => n.status.isOpen).toList();
    final closed = notes.where((n) => !n.status.isOpen).toList()
      ..sort(
        (a, b) =>
            (b.closedAt ?? b.updatedAt).compareTo(a.closedAt ?? a.updatedAt),
      );
    final grouped = open.any((n) => n.priority != null);

    final groups = <(NotePriority?, List<NoteRow>)>[
      if (grouped)
        for (final priority in [...NotePriority.displayOrder, null])
          (priority, open.where((n) => n.priority == priority).toList())
      else
        (null, open),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(type: type, count: open.length, projectId: projectId),
        for (final (priority, items) in groups)
          if (items.isNotEmpty) ...[
            if (grouped) _PriorityGroupLabel(type: type, priority: priority),
            if (type.isManuallySortable)
              _ReorderableCards(notes: items, showPriority: !grouped)
            else
              for (final note in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: NoteCard(note: note, showPriority: !grouped),
                ),
          ],
        InlineAdd(projectId: projectId, type: type),
        if (closed.isNotEmpty)
          _ClosedGroup(
            storageKey: 'closed-$projectId-${type.name}',
            title: '${closedGroupLabel(type)} (${closed.length})',
            notes: closed,
          ),
      ],
    );
  }
}

class _PriorityGroupLabel extends StatelessWidget {
  const _PriorityGroupLabel({required this.type, required this.priority});

  final NoteType type;
  final NotePriority? priority;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final priority = this.priority;
    final color = priority?.color(scheme) ?? scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.xs, bottom: Insets.sm),
      child: Row(
        children: [
          Icon(priority?.icon ?? Icons.remove_rounded, size: 14, color: color),
          const SizedBox(width: Insets.xs),
          Text(
            (priority == null
                    ? 'Ohne Priorität'
                    : priorityLabel(type, priority))
                .toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, letterSpacing: 0.9),
          ),
        ],
      ),
    );
  }
}

/// Schritte: per Griff am linken Rand verschiebbar.
class _ReorderableCards extends ConsumerWidget {
  const _ReorderableCards({required this.notes, required this.showPriority});

  final List<NoteRow> notes;
  final bool showPriority;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: notes.length,
      onReorderItem: (oldIndex, newIndex) async {
        // onReorderItem liefert newIndex bereits passend zur entfernten
        // Karte.
        final ids = notes.map((n) => n.id).toList();
        ids.insert(newIndex, ids.removeAt(oldIndex));
        await ref.read(noteRepositoryProvider).reorder(ids);
      },
      proxyDecorator: (child, _, _) =>
          Material(type: MaterialType.transparency, child: child),
      itemBuilder: (context, index) {
        final note = notes[index];
        return Padding(
          key: ValueKey(note.id),
          padding: const EdgeInsets.only(bottom: Insets.md),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Tooltip(
                    message: 'Ziehen zum Sortieren',
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
              ),
              Expanded(
                child: NoteCard(
                  note: note,
                  dense: true,
                  showPriority: showPriority,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Bereich 6 – Referenzen: nachschlagen, nicht abhaken.
class _ReferenceSection extends StatelessWidget {
  const _ReferenceSection({required this.projectId, required this.notes});

  final String projectId;
  final List<NoteRow> notes;

  @override
  Widget build(BuildContext context) {
    const type = NoteType.reference;
    final open = notes.where((n) => n.status.isOpen).toList();
    final closed = notes.where((n) => !n.status.isOpen).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(type: type, count: open.length, projectId: projectId),
        for (final note in open)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md),
            child: NoteCard(note: note),
          ),
        InlineAdd(projectId: projectId, type: type),
        if (closed.isNotEmpty)
          _ClosedGroup(
            storageKey: 'closed-$projectId-${type.name}',
            title: 'Erledigt (${closed.length})',
            notes: closed,
          ),
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
        InlineAdd(projectId: projectId, type: NoteType.log),
        if (log.isNotEmpty)
          PaperPanel(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              key: PageStorageKey('log-$projectId'),
              tilePadding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              title: Text(
                log.length == 1
                    ? '1 Eintrag'
                    : '${log.length} Einträge, neueste zuerst',
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

/// Was abgeschlossen ist, liegt zusammengeklappt darunter.
class _ClosedGroup extends StatelessWidget {
  const _ClosedGroup({
    required this.storageKey,
    required this.title,
    required this.notes,
  });

  final String storageKey;
  final String title;
  final List<NoteRow> notes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: PageStorageKey(storageKey),
      tilePadding: EdgeInsets.zero,
      leading: Icon(
        Icons.check_circle_rounded,
        size: 18,
        color: scheme.tertiary,
      ),
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

/// Direkt im Bereich anlegen: tippen, Enter, weiter.
///
/// Mehrere Zeilen – eingefügt oder mit Umschalt+Enter getippt – werden
/// mehrere Zettel. Das ist der kurze Weg, aus einer Liste Aufgaben zu
/// machen, ohne den Import-Dialog zu öffnen.
class InlineAdd extends ConsumerStatefulWidget {
  const InlineAdd({required this.projectId, required this.type, super.key});

  final String? projectId;
  final NoteType type;

  @override
  ConsumerState<InlineAdd> createState() => _InlineAddState();
}

class _InlineAddState extends ConsumerState<InlineAdd> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  CapturePlan _plan = CapturePlan.empty;
  bool _split = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_replan);
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _replan() {
    setState(() {
      _plan = planCapture(
        _controller.text,
        // Hier ist jede Zeile ein Eintrag, auch ohne Spiegelstrich – so wie
        // man in eine Checkliste tippt.
        split: _split,
        type: widget.type,
        typeFromHeadings: false,
      );
    });
  }

  String get _hint => switch (widget.type) {
    NoteType.step => 'Nächsten Schritt hinzufügen …',
    NoteType.question => 'Frage notieren …',
    NoteType.requirement => 'Anforderung festhalten …',
    NoteType.idea => 'Idee notieren …',
    NoteType.reference => 'Link, Befehl oder Pfad …',
    NoteType.log => 'Was hast du gemacht?',
    NoteType.instruction => 'Anweisung …',
  };

  Future<void> _submit() async {
    if (_saving || _plan.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(captureServiceProvider)
          .createAll(_plan.drafts, projectId: widget.projectId);
      _controller.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
      _focusNode.requestFocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _submit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _controller.text.isNotEmpty) {
      _controller.clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = widget.type.color(scheme);
    final active = _focusNode.hasFocus || _controller.text.isNotEmpty;
    final count = _plan.drafts.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: Motion.fast,
            decoration: BoxDecoration(
              color: active ? context.paper.paper : Colors.transparent,
              borderRadius: Radii.mdAll,
              border: Border.all(
                color: active
                    ? accent.withValues(alpha: 0.5)
                    : context.paper.hairline,
                style: BorderStyle.solid,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Insets.md, 11, 0, 0),
                  child: Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: active ? accent : scheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Focus(
                    onKeyEvent: _onKey,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 6,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(
                          Insets.sm,
                          11,
                          Insets.md,
                          11,
                        ),
                        hintText: _hint,
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.75,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: IconButton(
                      tooltip: count > 1 ? '$count anlegen' : 'Anlegen',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.keyboard_return_rounded, color: accent),
                      onPressed: _plan.isEmpty ? null : _submit,
                    ),
                  ),
              ],
            ),
          ),
          if (_plan.canSplit)
            Padding(
              padding: const EdgeInsets.only(top: Insets.xs, left: Insets.xs),
              child: Row(
                children: [
                  Icon(
                    Icons.format_list_bulleted_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Insets.xs),
                  Expanded(
                    child: Text(
                      _split
                          ? 'Enter legt $count ${_plural(count)} an'
                          : 'Enter legt einen Zettel mit Liste an',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _split = !_split;
                      _replan();
                    },
                    child: Text(_split ? 'Als ein Zettel' : 'Einzeln anlegen'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _plural(int count) => switch (widget.type) {
    NoteType.step => count == 1 ? 'Schritt' : 'Schritte',
    NoteType.question => count == 1 ? 'Frage' : 'Fragen',
    NoteType.requirement => count == 1 ? 'Anforderung' : 'Anforderungen',
    NoteType.idea => count == 1 ? 'Idee' : 'Ideen',
    NoteType.reference => count == 1 ? 'Referenz' : 'Referenzen',
    NoteType.log => count == 1 ? 'Eintrag' : 'Einträge',
    NoteType.instruction => 'Zettel',
  };
}
