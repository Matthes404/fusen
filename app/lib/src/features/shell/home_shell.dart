import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../capture/capture_sheet.dart';
import '../inbox/inbox_view.dart';
import '../project/project_view.dart';
import '../search/search_view.dart';
import '../settings/settings_view.dart';
import 'destination.dart';
import 'project_sidebar.dart';

/// Ab dieser Breite passen Liste und Inhalt nebeneinander.
const double twoPaneBreakpoint = 900;

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
  Destination _selected = const ProjectDestination(null);

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
            width: 264,
            child: ProjectSidebar(
              selected: _selected,
              onSelect: _select,
              onCapture: openCapture,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _detailFor(_selected)),
        ],
      ),
    );
  }

  Widget _buildNarrow(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ProjectSidebar(
          selected: _selected,
          onSelect: _open,
          onCapture: openCapture,
          showSelection: false,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Zettel ablegen',
        onPressed: openCapture,
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  Widget _detailFor(Destination destination) {
    return switch (destination) {
      ProjectDestination(:final projectId) =>
        projectId == null
            ? const InboxView()
            : ProjectView(projectId: projectId, key: ValueKey(projectId)),
      SearchDestination() => const SearchView(),
      SettingsDestination() => const SettingsView(),
    };
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
