import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../sync/sync_service.dart';
import '../project/project_menu.dart';
import 'destination.dart';

/// Die linke Spalte: Inbox, Projekte, Suche, Einstellungen.
class ProjectSidebar extends ConsumerWidget {
  const ProjectSidebar({
    required this.selected,
    required this.onSelect,
    required this.onCapture,
    super.key,
    this.showSelection = true,
  });

  final Destination selected;
  final ValueChanged<Destination> onSelect;
  final VoidCallback onCapture;

  /// Auf schmalen Fenstern ist die Liste die Startseite – dort wäre eine
  /// dauerhaft markierte Zeile irreführend.
  final bool showSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final projects = ref.watch(projectsProvider).value ?? const [];
    final counts = ref.watch(openCountsProvider).value ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SidebarHeader(onCapture: onCapture),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _SidebarTile(
                icon: Icons.search,
                label: 'Suche',
                selected: showSelection && selected is SearchDestination,
                onTap: () => onSelect(const SearchDestination()),
              ),
              _SidebarTile(
                icon: Icons.inbox_outlined,
                label: 'Inbox',
                count: counts[null] ?? 0,
                selected:
                    showSelection &&
                    selected is ProjectDestination &&
                    (selected as ProjectDestination).projectId == null,
                onTap: () => onSelect(const ProjectDestination(null)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Text('Projekte', style: theme.textTheme.labelMedium),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Text(
                    'Noch keine Projekte.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              for (final project in projects)
                _SidebarTile(
                  color: Color(project.color),
                  label: project.name,
                  count: counts[project.id] ?? 0,
                  selected:
                      showSelection &&
                      selected is ProjectDestination &&
                      (selected as ProjectDestination).projectId == project.id,
                  onTap: () => onSelect(ProjectDestination(project.id)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        _SidebarTile(
          icon: Icons.settings_outlined,
          label: 'Einstellungen',
          selected: showSelection && selected is SettingsDestination,
          onTap: () => onSelect(const SettingsDestination()),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final name = await promptForProjectName(context, title: 'Neues Projekt');
    if (name == null) return;
    final project = await ref
        .read(projectRepositoryProvider)
        .create(name: name);
    onSelect(ProjectDestination(project.id));
  }
}

class _SidebarHeader extends ConsumerWidget {
  const _SidebarHeader({required this.onCapture});

  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final outcome = ref.watch(syncControllerProvider);
    final enabled = ref.watch(syncEnabledProvider).value ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Fusen',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (enabled) _SyncIndicator(outcome: outcome),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onCapture,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Zettel ablegen'),
          ),
        ],
      ),
    );
  }
}

class _SyncIndicator extends ConsumerWidget {
  const _SyncIndicator({required this.outcome});

  final SyncOutcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    if (outcome.status == SyncStatus.running) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final (icon, color, tooltip) = switch (outcome.status) {
      SyncStatus.success => (
        Icons.cloud_done_outlined,
        scheme.primary,
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
      _ => (Icons.cloud_queue, scheme.outline, 'Noch nicht abgeglichen'),
    };

    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color),
      visualDensity: VisualDensity.compact,
      onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
    this.count = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                if (icon != null)
                  Icon(icon, size: 18)
                else
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: color ?? theme.colorScheme.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
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
