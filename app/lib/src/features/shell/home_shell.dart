import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/palette.dart';
import '../../ui/tokens.dart';
import '../capture/capture_sheet.dart';
import '../inbox/inbox_view.dart';
import '../overview/overview_view.dart';
import '../project/archived_projects_page.dart';
import '../project/project_view.dart';
import '../search/search_view.dart';
import '../settings/settings_view.dart';
import 'destination.dart';
import 'project_sidebar.dart';

/// Ab dieser Breite passen Liste und Inhalt nebeneinander.
const double twoPaneBreakpoint = 900;

/// Breite der Seitenspalte.
const double sidebarWidth = 268;

/// Das Grundgerüst der App.
///
/// Desktop und Mobil sind gleichwertig: dieselben Ansichten, nur einmal
/// nebeneinander und einmal hintereinander.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends ConsumerState<HomeShell> {
  Destination _selected = const OverviewDestination();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= twoPaneBreakpoint;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            openCapture,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): openCapture,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _open(const SearchDestination()),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _open(const SearchDestination()),
      },
      child: Focus(
        autofocus: true,
        child: wide ? _buildWide(context) : _buildNarrow(context),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: sidebarWidth,
            child: SafeArea(
              right: false,
              child: ProjectSidebar(
                selected: _selected,
                onSelect: _select,
                onCapture: openCapture,
                onOpenArchived: _openArchived,
              ),
            ),
          ),
          VerticalDivider(width: 1, color: context.paper.hairline),
          // Der Wechsel zwischen zwei Projekten blendet über, damit klar
          // ist, dass sich der ganze Bereich austauscht und nicht nur ein
          // paar Zeilen anders stehen.
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.base,
              switchInCurve: Motion.standard,
              child: KeyedSubtree(
                key: ValueKey(_selected),
                child: _detailFor(_selected),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Auf dem Handy ist die Übersicht die Startseite: Projekte als Kacheln,
  /// Suche und Einstellungen im Kopf, der Ablegen-Knopf unten rechts.
  Widget _buildNarrow(BuildContext context) {
    final syncEnabled = ref.watch(syncEnabledProvider).value ?? false;
    return Scaffold(
      body: OverviewView(
        onOpenProject: (id) => _open(ProjectDestination(id)),
        onOpenInbox: () => _open(const ProjectDestination(null)),
        onOpenSearch: () => _open(const SearchDestination()),
        onOpenSettings: () => _open(const SettingsDestination()),
        onOpenArchived: _openArchived,
        headerActions: [
          if (syncEnabled)
            SyncIndicator(outcome: ref.watch(syncControllerProvider)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: openCapture,
        icon: const Icon(Icons.add),
        label: const Text('Zettel ablegen'),
      ),
    );
  }

  Widget _detailFor(Destination destination) {
    return switch (destination) {
      OverviewDestination() => OverviewView(
        onOpenProject: (id) => _select(ProjectDestination(id)),
        onOpenInbox: () => _select(const ProjectDestination(null)),
        onOpenArchived: _openArchived,
      ),
      ProjectDestination(:final projectId) =>
        projectId == null
            ? const InboxView()
            : ProjectView(projectId: projectId, key: ValueKey(projectId)),
      SearchDestination() => const SearchView(),
      SettingsDestination() => const SettingsView(),
    };
  }

  void _openArchived() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ArchivedProjectsPage(
          onOpenProject: (id) {
            Navigator.of(context).pop();
            _open(ProjectDestination(id));
          },
        ),
      ),
    );
  }

  void _select(Destination destination) {
    setState(() => _selected = destination);
    _rememberProject(destination);
  }

  /// Auf schmalen Fenstern wird die Ansicht als eigene Seite geöffnet.
  void _open(Destination destination) {
    final wide = MediaQuery.sizeOf(context).width >= twoPaneBreakpoint;
    if (wide) {
      _select(destination);
      return;
    }
    setState(() => _selected = destination);
    _rememberProject(destination);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => _detailFor(destination)));
  }

  void _rememberProject(Destination destination) {
    if (destination case ProjectDestination(:final projectId)
        when projectId != null) {
      ref.read(lastProjectProvider.notifier).remember(projectId);
    }
  }

  /// Öffnet die Schnelleingabe – auch vom globalen Hotkey aus.
  Future<void> openCapture() async {
    final current = _selected;
    final projectId = current is ProjectDestination ? current.projectId : null;
    await showCaptureSheet(context, projectId: projectId);
  }
}
