import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/repositories/note_repository.dart';
import '../../ui/note_style.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/fusen_logo.dart';
import '../../ui/widgets/note_card.dart';
import '../../ui/widgets/paper.dart';
import '../../ui/widgets/project_avatar.dart';
import '../project/project_menu.dart' show promptForProjectName;

/// Breite der Übersicht – etwas mehr als eine Projektseite, damit die
/// Kacheln nebeneinander Platz haben.
const double _overviewMaxWidth = 1180;

/// Die Startseite: was ansteht, alle Projekte, zuletzt Erledigtes.
///
/// Auf dem Schreibtisch steht sie rechts neben der Seitenspalte, auf dem
/// Handy ist sie die erste Seite – dort trägt sie deshalb Suche und
/// Einstellungen selbst im Kopf.
class OverviewView extends ConsumerWidget {
  const OverviewView({
    required this.onOpenProject,
    required this.onOpenInbox,
    super.key,
    this.onOpenSearch,
    this.onOpenSettings,
    this.onOpenArchived,
    this.headerActions = const [],
  });

  final ValueChanged<String> onOpenProject;
  final VoidCallback onOpenInbox;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenArchived;

  /// Zusätzliches im Kopf, etwa die Sync-Anzeige auf dem Handy.
  final List<Widget> headerActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider).value ?? const [];
    final progress = ref.watch(progressProvider).value ?? const {};
    final instructions =
        ref.watch(currentInstructionsProvider).value ?? const {};
    final nextSteps = ref.watch(nextStepsProvider).value ?? const {};
    final prioritized = ref.watch(prioritizedProvider).value ?? const [];
    final closed = ref.watch(recentlyClosedProvider).value ?? const [];
    final inbox = ref.watch(inboxProvider).value ?? const [];
    final archived = ref.watch(archivedProjectsProvider).value ?? const [];

    final gutter = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 32.0;
    // Nur die Projekte, die hier auch stehen – sonst zählte der Satz „3
    // offene Zettel in 2 Projekten“ die Inbox und archivierte Projekte mit.
    final open = projects.fold<int>(
      0,
      (sum, project) => sum + (progress[project.id]?.open ?? 0),
    );

    final narrow = MediaQuery.sizeOf(context).width < 600;
    // Auf dem Handy ist die Übersicht die Startseite – dort kommen zuerst
    // die Projekte, damit man ohne Scrollen hineinkommt.
    final important = <Widget>[
      if (prioritized.isNotEmpty) ...[
        _SectionTitle(
          gutter: gutter,
          icon: Icons.keyboard_double_arrow_up_rounded,
          title: 'Wichtig',
          subtitle: 'Offen und priorisiert, aus allen Projekten',
        ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverToBoxAdapter(
            child: _Columns(
              children: [
                for (final note in prioritized.take(narrow ? 4 : 6))
                  NoteCard(
                    note: note,
                    showProject: true,
                    showType: true,
                    dense: true,
                  ),
              ],
            ),
          ),
        ),
      ],
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _overviewMaxWidth),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter, Insets.xl, gutter, 0),
                  sliver: SliverToBoxAdapter(
                    child: _Greeting(
                      open: open,
                      projects: projects.length,
                      onOpenSearch: onOpenSearch,
                      onOpenSettings: onOpenSettings,
                      actions: headerActions,
                    ),
                  ),
                ),
                if (!narrow) ...important,
                _SectionTitle(
                  gutter: gutter,
                  icon: Icons.dashboard_outlined,
                  title: 'Projekte',
                  trailing: archived.isEmpty || onOpenArchived == null
                      ? null
                      : TextButton.icon(
                          onPressed: onOpenArchived,
                          icon: const Icon(
                            Icons.inventory_2_outlined,
                            size: 16,
                          ),
                          label: Text('Archiviert (${archived.length})'),
                        ),
                ),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          mainAxisExtent: 172,
                          crossAxisSpacing: Insets.lg,
                          mainAxisSpacing: Insets.lg,
                        ),
                    delegate: SliverChildListDelegate([
                      _InboxTile(count: inbox.length, onTap: onOpenInbox),
                      for (final project in projects)
                        ProjectTile(
                          project: project,
                          progress: progress[project.id] ?? NoteProgress.empty,
                          instruction: instructions[project.id],
                          nextStep: nextSteps[project.id],
                          onTap: () => onOpenProject(project.id),
                        ),
                      _NewProjectTile(onCreated: onOpenProject),
                    ]),
                  ),
                ),
                if (narrow) ...important,
                if (closed.isNotEmpty) ...[
                  _SectionTitle(
                    gutter: gutter,
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Zuletzt erledigt',
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    sliver: SliverToBoxAdapter(
                      child: PaperPanel(
                        padding: const EdgeInsets.symmetric(
                          vertical: Insets.xs,
                        ),
                        child: Column(
                          children: [
                            for (final note in closed)
                              _ClosedRow(
                                note: note,
                                project: projects
                                    .where((p) => p.id == note.projectId)
                                    .firstOrNull,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(
                  child: SizedBox(height: Insets.listBottom),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.open,
    required this.projects,
    required this.actions,
    this.onOpenSearch,
    this.onOpenSettings,
  });

  final int open;
  final int projects;
  final List<Widget> actions;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final greeting = switch (now.hour) {
      < 11 => 'Guten Morgen',
      < 17 => 'Guten Tag',
      _ => 'Guten Abend',
    };
    final summary = switch ((open, projects)) {
      (_, 0) =>
        'Noch kein Projekt – leg eins an oder wirf Zettel in die Inbox.',
      (0, _) => 'Nichts offen. Zeit für etwas Neues.',
      (1, 1) => '1 offener Zettel in einem Projekt',
      (final o, 1) => '$o offene Zettel in einem Projekt',
      (1, final p) => '1 offener Zettel in $p Projekten',
      (final o, final p) => '$o offene Zettel in $p Projekten',
    };

    // Ohne Seitenspalte (Handy) steht die Marke hier oben.
    final showBrand = onOpenSettings != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBrand) ...[
                const FusenWordmark(),
                const SizedBox(height: Insets.lg),
              ],
              Text(
                formatLongDate(now).toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1),
              ),
              const SizedBox(height: Insets.xs),
              Text(greeting, style: theme.textTheme.headlineMedium),
              const SizedBox(height: Insets.xs),
              Text(
                summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        ...actions,
        if (onOpenSearch != null)
          IconButton(
            tooltip: 'Suche',
            icon: const Icon(Icons.search),
            onPressed: onOpenSearch,
          ),
        if (onOpenSettings != null)
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings_outlined),
            onPressed: onOpenSettings,
          ),
      ],
    );
  }
}

/// Ein Datum, wie es oben auf einem Kalenderblatt steht.
///
/// Von Hand statt mit `intl`: dessen deutsche Monatsnamen müssten vorher
/// geladen werden, und für zwei Wörter lohnt das nicht.
String formatLongDate(DateTime date) {
  const weekdays = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];
  const months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day}. ${months[date.month - 1]}';
}

/// Die Inbox als erster Zettel im Raster – gelb, wie ein frischer Block.
class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waiting = count > 0;

    return Semantics(
      button: true,
      label: 'Inbox',
      child: PaperCard(
        onTap: onTap,
        wash: fusenSeed.withValues(alpha: waiting ? 0.26 : 0.1),
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned(
              top: -6,
              left: 22,
              child: Transform.rotate(
                angle: 0.04,
                child: Container(
                  width: 64,
                  height: 18,
                  color: fusenSeed.withValues(alpha: 0.8),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.xl,
                Insets.lg,
                Insets.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: fusenInk.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.inbox_outlined, size: 17),
                      ),
                      const SizedBox(width: Insets.sm),
                      Text('Inbox', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: Insets.sm),
                  Expanded(
                    child: Text(
                      waiting
                          ? 'Was ohne @projekt abgelegt wurde, wartet hier '
                                'aufs Einsortieren.'
                          : 'Leer – alles hat seinen Platz.',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          waiting
                              ? (count == 1 ? '1 Zettel' : '$count Zettel')
                              : 'nichts offen',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      if (waiting)
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.gutter,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final double gutter;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(gutter, Insets.xxl, gutter, Insets.md),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: Insets.sm),
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(width: Insets.md),
              Flexible(
                child: Text(
                  subtitle!,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            const Spacer(),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Karten in zwei Spalten, sobald Platz ist – auf dem Handy eine.
class _Columns extends StatelessWidget {
  const _Columns({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: child,
                ),
            ],
          );
        }
        final left = [for (var i = 0; i < children.length; i += 2) children[i]];
        final right = [
          for (var i = 1; i < children.length; i += 2) children[i],
        ];
        Widget column(List<Widget> items) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: child,
                ),
            ],
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            column(left),
            const SizedBox(width: Insets.lg),
            column(right),
          ],
        );
      },
    );
  }
}

/// Ein Projekt als Haftzettel: oben ein Klebestreifen in seiner Farbe,
/// darauf Name, Fortschritt und was gerade gilt.
class ProjectTile extends StatelessWidget {
  const ProjectTile({
    required this.project,
    required this.progress,
    required this.onTap,
    super.key,
    this.instruction,
    this.nextStep,
  });

  final ProjectRow project;
  final NoteProgress progress;
  final NoteRow? instruction;
  final NoteRow? nextStep;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(project.color);
    final light = theme.brightness == Brightness.light;
    final percent = (progress.ratio * 100).round();

    return Semantics(
      button: true,
      label: 'Projekt ${project.name}',
      child: PaperCard(
        onTap: onTap,
        wash: color.withValues(alpha: light ? 0.1 : 0.14),
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            // Der Klebestreifen – schräg, wie schnell aufgeklebt.
            Positioned(
              top: -6,
              left: 22,
              child: Transform.rotate(
                angle: -0.05,
                child: Container(
                  width: 64,
                  height: 18,
                  color: color.withValues(alpha: light ? 0.55 : 0.7),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.xl,
                Insets.lg,
                Insets.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ProjectAvatar(project: project, size: 26),
                      const SizedBox(width: Insets.sm),
                      Expanded(
                        child: Text(
                          project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.sm),
                  Expanded(child: _tileBody(theme)),
                  if (progress.total > 0) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: Radii.pillAll,
                            child: LinearProgressIndicator(
                              value: progress.ratio,
                              minHeight: 6,
                              color: color,
                              backgroundColor: color.withValues(alpha: 0.18),
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        Text(
                          '$percent %',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: monoFamily,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.xs),
                    Text(switch ((progress.open, progress.closed)) {
                      (final o, 0) => '$o offen',
                      (0, final c) => 'alles erledigt · $c',
                      (final o, final c) => '$o offen · $c erledigt',
                    }, style: theme.textTheme.labelSmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Was auf dem Zettel steht: die geltende Anweisung, sonst der nächste
  /// Schritt, sonst ein Satz zum Stand.
  Widget _tileBody(ThemeData theme) {
    final instruction = this.instruction;
    final nextStep = this.nextStep;
    if (instruction != null) {
      return Text(
        '„${_plain(instruction.body)}“',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (nextStep != null) {
      final text = (nextStep.title?.isNotEmpty ?? false)
          ? nextStep.title!
          : nextStep.body;
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'Als Nächstes: ', style: theme.textTheme.labelSmall),
            TextSpan(text: _plain(text)),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      );
    }
    return Text(
      progress.total == 0
          ? 'Noch leer – tippen und die ersten Zettel ablegen.'
          : 'Nichts offen.',
      style: theme.textTheme.bodySmall,
    );
  }

  /// Markdown für eine Zeile Vorschau: ohne Sternchen und Backticks.
  static String _plain(String markdown) => markdown
      .replaceAll(RegExp(r'[*_`#>]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _NewProjectTile extends ConsumerWidget {
  const _NewProjectTile({required this.onCreated});

  final ValueChanged<String> onCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: Radii.mdAll,
      onTap: () async {
        // Vor dem Warten holen: dreht man das Handy, während der Dialog
        // offen ist, kann die Kachel danach schon verschwunden sein.
        final repository = ref.read(projectRepositoryProvider);
        final name = await promptForProjectName(
          context,
          title: 'Neues Projekt',
        );
        if (name == null) return;
        final project = await repository.create(name: name);
        onCreated(project.id);
      },
      child: DottedBox(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FusenLogo(size: 28),
              const SizedBox(height: Insets.sm),
              Text('Neues Projekt', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein gestrichelter Rahmen – „hier kommt etwas hin“.
class DottedBox extends StatelessWidget {
  const DottedBox({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorder(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
      ),
      child: child,
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(Radii.md),
        ).deflate(0.7),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// Eine Zeile „erledigt“: Haken, Text, Projekt, Tag.
class _ClosedRow extends StatelessWidget {
  const _ClosedRow({required this.note, required this.project});

  final NoteRow note;
  final ProjectRow? project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = (note.title?.isNotEmpty ?? false) ? note.title! : note.body;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              text.split('\n').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: Insets.md),
          if (project != null) ...[
            ProjectAvatar(project: project!, size: 16),
            const SizedBox(width: Insets.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                project!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ),
            const SizedBox(width: Insets.md),
          ],
          SizedBox(
            width: 64,
            child: Text(
              note.closedAt == null
                  ? statusLabel(note.type, NoteStatus.done)
                  : formatDay(note.closedAt!),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
