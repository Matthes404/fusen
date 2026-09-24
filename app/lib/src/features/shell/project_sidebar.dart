import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../sync/sync_service.dart';
import '../../ui/palette.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/fusen_logo.dart';
import '../../ui/widgets/labels.dart';
import '../../ui/widgets/project_avatar.dart';
import '../project/project_menu.dart';
import 'destination.dart';

/// Die linke Spalte auf dem Schreibtisch: Übersicht, Suche, Inbox,
/// Projekte, Einstellungen.
///
/// Auf dem Handy gibt es sie nicht – dort ist die Übersicht die Startseite
/// und übernimmt ihre Aufgaben.
class ProjectSidebar extends ConsumerWidget {
  const ProjectSidebar({
    required this.selected,
    required this.onSelect,
    required this.onCapture,
    super.key,
    this.onOpenArchived,
  });

  final Destination selected;
  final ValueChanged<Destination> onSelect;
  final VoidCallback onCapture;
  final VoidCallback? onOpenArchived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final projects = ref.watch(projectsProvider).value ?? const [];
    final archived = ref.watch(archivedProjectsProvider).value ?? const [];
    final counts = ref.watch(openCountsProvider).value ?? const {};

    bool isProject(String? id) =>
        selected is ProjectDestination &&
        (selected as ProjectDestination).projectId == id;

    return ColoredBox(
      color: context.paper.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarHeader(onCapture: onCapture),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.sm,
                    Insets.xs,
                    Insets.sm,
                    0,
                  ),
                  sliver: SliverList.list(
                    children: [
                      _SidebarTile(
                        icon: Icons.space_dashboard_outlined,
                        label: 'Übersicht',
                        accent: scheme.primary,
                        selected: selected is OverviewDestination,
                        onTap: () => onSelect(const OverviewDestination()),
                      ),
                      _SidebarTile(
                        icon: Icons.search,
                        label: 'Suche',
                        accent: scheme.primary,
                        selected: selected is SearchDestination,
                        onTap: () => onSelect(const SearchDestination()),
                      ),
                      _SidebarTile(
                        icon: Icons.inbox_outlined,
                        label: 'Inbox',
                        accent: scheme.primary,
                        count: counts[null] ?? 0,
                        selected: isProject(null),
                        onTap: () => onSelect(const ProjectDestination(null)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Insets.md,
                          Insets.xl,
                          Insets.xs,
                          Insets.xs,
                        ),
                        child: Row(
                          children: [
                            const SectionLabel('Projekte'),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Neues Projekt',
                              icon: const Icon(Icons.add, size: 18),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _createProject(context, ref),
                            ),
                          ],
                        ),
                      ),
                      if (projects.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(
                            Insets.md,
                            Insets.xs,
                            Insets.md,
                            Insets.xs,
                          ),
                          child: _NoProjectsHint(),
                        ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                  // Per Ziehen sortierbar – die Reihenfolge gilt auch in der
                  // Übersicht und reist mit dem Sync.
                  sliver: SliverReorderableList(
                    itemCount: projects.length,
                    onReorderItem: (oldIndex, newIndex) {
                      final ids = projects.map((p) => p.id).toList();
                      ids.insert(newIndex, ids.removeAt(oldIndex));
                      ref.read(projectRepositoryProvider).reorder(ids);
                    },
                    proxyDecorator: (child, _, _) =>
                        Material(type: MaterialType.transparency, child: child),
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(project.id),
                        index: index,
                        child: _SidebarTile(
                          leading: ProjectAvatar(project: project, size: 20),
                          accent: Color(project.color),
                          label: project.name,
                          count: counts[project.id] ?? 0,
                          selected: isProject(project.id),
                          onTap: () => onSelect(ProjectDestination(project.id)),
                        ),
                      );
                    },
                  ),
                ),
                if (archived.isNotEmpty && onOpenArchived != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.sm,
                      Insets.xs,
                      Insets.sm,
                      Insets.md,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _SidebarTile(
                        icon: Icons.inventory_2_outlined,
                        label: 'Archiviert',
                        accent: scheme.primary,
                        count: archived.length,
                        quiet: true,
                        selected: false,
                        onTap: onOpenArchived!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: context.paper.hairline),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.sm,
              Insets.sm,
              Insets.sm,
              Insets.md,
            ),
            child: _SidebarTile(
              icon: Icons.settings_outlined,
              label: 'Einstellungen',
              accent: scheme.primary,
              selected: selected is SettingsDestination,
              onTap: () => onSelect(const SettingsDestination()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final name = await promptForProjectName(context, title: 'Neues Projekt');
    if (name == null) return;
    final ProjectRow project = await ref
        .read(projectRepositoryProvider)
        .create(name: name);
    onSelect(ProjectDestination(project.id));
  }
}

class _NoProjectsHint extends StatelessWidget {
  const _NoProjectsHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Noch keine Projekte.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
    );
  }
}

class _SidebarHeader extends ConsumerWidget {
  const _SidebarHeader({required this.onCapture});

  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outcome = ref.watch(syncControllerProvider);
    final enabled = ref.watch(syncEnabledProvider).value ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.lg,
        Insets.md,
        Insets.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const FusenWordmark(),
              const Spacer(),
              if (enabled) SyncIndicator(outcome: outcome),
            ],
          ),
          const SizedBox(height: Insets.lg),
          FilledButton(
            onPressed: onCapture,
            style: brandButtonStyle(),
            child: const Row(
              children: [
                Icon(Icons.add, size: 18),
                SizedBox(width: Insets.sm),
                Expanded(child: Text('Zettel ablegen')),
                _ButtonHint('Strg N'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Das Tastenkürzel im Knopf – gedämpft, damit es die Beschriftung nicht
/// überstimmt.
class _ButtonHint extends StatelessWidget {
  const _ButtonHint(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: Insets.sm),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: fusenInk.withValues(alpha: 0.14),
        borderRadius: Radii.xsAll,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontFamily: monoFamily,
          letterSpacing: 0,
          color: fusenInk.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

/// Der Stand des Abgleichs als kleines Symbol – antippen gleicht sofort ab.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({required this.outcome, super.key});

  final SyncOutcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    if (outcome.status == SyncStatus.running) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final (icon, color, tooltip) = switch (outcome.status) {
      SyncStatus.success when outcome.warning != null => (
        Icons.cloud_done_outlined,
        scheme.onSurfaceVariant,
        outcome.warning!,
      ),
      SyncStatus.success => (
        Icons.cloud_done_outlined,
        scheme.tertiary,
        'Abgeglichen',
      ),
      SyncStatus.authFailed => (
        Icons.lock_outline,
        scheme.error,
        'Zugangscode passt nicht',
      ),
      SyncStatus.error => (
        Icons.cloud_off_outlined,
        scheme.error,
        outcome.message ?? 'Fehler beim Abgleich',
      ),
      _ => (
        Icons.cloud_queue,
        scheme.onSurfaceVariant,
        'Noch nicht abgeglichen',
      ),
    };

    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color),
      visualDensity: VisualDensity.compact,
      onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(),
    );
  }
}

/// Eine Zeile in der Seitenspalte.
///
/// Die markierte Zeile trägt die Farbe dessen, was sie öffnet – bei einem
/// Projekt also dessen eigene. Das bindet Spalte und Inhalt zusammen,
/// besser als ein überall gleicher grauer Balken.
class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    this.icon,
    this.leading,
    this.count = 0,
    this.quiet = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;
  final Widget? leading;
  final int count;

  /// Zurückhaltend gesetzt – für Einträge, die selten gebraucht werden.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: Radii.smAll,
        child: InkWell(
          borderRadius: Radii.smAll,
          hoverColor: scheme.onSurface.withValues(alpha: 0.05),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: 8,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child:
                      leading ??
                      Icon(
                        icon,
                        size: quiet ? 16 : 18,
                        color: selected ? accent : foreground,
                      ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (quiet
                                ? theme.textTheme.bodySmall
                                : theme.textTheme.bodyMedium)
                            ?.copyWith(
                              color: foreground,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                  ),
                ),
                if (count > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: Insets.sm),
                    child: CountBadge(
                      count: count,
                      quiet: !selected,
                      color: selected ? accent : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
