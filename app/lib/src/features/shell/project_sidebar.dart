import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../sync/sync_service.dart';
import '../../ui/palette.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/fusen_logo.dart';
import '../../ui/widgets/labels.dart';
import '../project/project_menu.dart';
import 'destination.dart';

/// Die linke Spalte: Inbox, Projekte, Suche, Einstellungen.
class ProjectSidebar extends ConsumerWidget {
  const ProjectSidebar({
    required this.selected,
    required this.onSelect,
    required this.onCapture,
    super.key,
    this.wide = true,
  });

  final Destination selected;
  final ValueChanged<Destination> onSelect;
  final VoidCallback onCapture;

  /// Auf breiten Fenstern steht die Spalte neben dem Inhalt: dann darf sie
  /// markieren, was gerade rechts steht, und Tastenkürzel zeigen.
  ///
  /// Auf schmalen ist sie die Startseite – eine dauerhaft markierte Zeile
  /// wäre dort irreführend, und den Ablegen-Knopf trägt der Schwebeknopf.
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final projects = ref.watch(projectsProvider).value ?? const [];
    final counts = ref.watch(openCountsProvider).value ?? const {};

    final inboxSelected =
        wide &&
        selected is ProjectDestination &&
        (selected as ProjectDestination).projectId == null;

    return ColoredBox(
      color: context.paper.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarHeader(
            onCapture: onCapture,
            wide: wide,
            settings: wide
                ? null
                : IconButton(
                    tooltip: 'Einstellungen',
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: () => onSelect(const SettingsDestination()),
                  ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Insets.sm,
                Insets.xs,
                Insets.sm,
                Insets.md,
              ),
              children: [
                _SidebarTile(
                  icon: Icons.search,
                  label: 'Suche',
                  accent: scheme.primary,
                  selected: wide && selected is SearchDestination,
                  onTap: () => onSelect(const SearchDestination()),
                ),
                _SidebarTile(
                  icon: Icons.inbox_outlined,
                  label: 'Inbox',
                  accent: scheme.primary,
                  count: counts[null] ?? 0,
                  selected: inboxSelected,
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
                for (final project in projects)
                  _SidebarTile(
                    accent: Color(project.color),
                    label: project.name,
                    count: counts[project.id] ?? 0,
                    selected:
                        wide &&
                        selected is ProjectDestination &&
                        (selected as ProjectDestination).projectId ==
                            project.id,
                    onTap: () => onSelect(ProjectDestination(project.id)),
                  ),
              ],
            ),
          ),
          if (wide) ...[
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
        ],
      ),
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
  const _SidebarHeader({
    required this.onCapture,
    required this.wide,
    this.settings,
  });

  final VoidCallback onCapture;
  final bool wide;

  /// Schmal steht der Weg zu den Einstellungen hier oben – unten hätte er
  /// sich mit dem Schwebeknopf gestapelt.
  final Widget? settings;

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
              if (enabled) _SyncIndicator(outcome: outcome),
              ?settings,
            ],
          ),
          // Schmal übernimmt der Schwebeknopf unten rechts – dort ist er
          // mit dem Daumen zu erreichen.
          if (wide) ...[
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

class _SyncIndicator extends ConsumerWidget {
  const _SyncIndicator({required this.outcome});

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
    this.count = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;
  final int count;

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
              vertical: 9,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: icon != null
                      ? Icon(
                          icon,
                          size: 18,
                          color: selected ? accent : foreground,
                        )
                      : Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
