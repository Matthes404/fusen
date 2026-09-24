import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../ui/note_style.dart';
import '../../ui/palette.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/labels.dart';
import '../../ui/widgets/note_card.dart';
import '../../ui/widgets/page_body.dart';
import '../capture/capture_syntax.dart';
import '../project/project_view.dart' show PageHeader;

/// Volltextsuche über alle Projekte.
///
/// Die Eingabe versteht dieselben Kurzbefehle wie die Schnelleingabe:
/// `@projekt` grenzt auf ein Projekt ein, `!typ` auf einen Zettel-Typ,
/// `#tag` und freie Wörter werden gesucht.
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;

  String _query = '';
  bool _includeArchived = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Kurz warten, statt bei jedem Tastendruck die Datenbank zu fragen.
  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = _controller.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final projects = ref.watch(projectsProvider).value ?? const [];
    final draft = parseCapture(_query);

    final project = draft.projectQuery == null
        ? null
        : projects
              .where(
                (p) => p.name.toLowerCase().startsWith(
                  draft.projectQuery!.toLowerCase(),
                ),
              )
              .firstOrNull;

    final terms = <String>[
      ...draft.body.split(RegExp(r'\s+')).where((t) => t.isNotEmpty),
      ...draft.tags,
    ];

    final filters = <Widget>[
      if (draft.projectQuery != null)
        MetaChip(
          label: project?.name ?? '${draft.projectQuery} (unbekannt)',
          icon: Icons.folder_outlined,
          color: project == null ? scheme.error : Color(project.color),
        ),
      if (draft.type != null)
        MetaChip(
          label: draft.type!.label,
          icon: draft.type!.icon,
          color: draft.type!.color(scheme),
        ),
      if (draft.priority != null)
        MetaChip(
          label: priorityLabel(draft.type ?? NoteType.step, draft.priority!),
          icon: draft.priority!.icon,
          color: draft.priority!.color(scheme),
        ),
    ];

    final idle =
        terms.isEmpty &&
        draft.type == null &&
        draft.priority == null &&
        project == null;
    final gutter = pageGutter(context);

    return Scaffold(
      // Der Kopf trägt auf schmalen Fenstern den Zurück-Pfeil.
      appBar: const PageHeader(title: 'Suche', icon: Icons.search),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                Insets.lg,
                gutter,
                Insets.md,
              ),
              child: TextField(
                controller: _controller,
                autofocus: true,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Insets.lg,
                    vertical: Insets.lg,
                  ),
                  hintText: 'Suchen … @projekt !typ #tag',
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Leeren',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _controller.clear,
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.xl,
                0,
                Insets.xl,
                Insets.md,
              ),
              child: Row(
                children: [
                  for (final filter in filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: filter,
                    ),
                  const Spacer(),
                  _ArchiveToggle(
                    value: _includeArchived,
                    onChanged: (value) =>
                        setState(() => _includeArchived = value),
                  ),
                ],
              ),
            ),
            Expanded(
              child: idle
                  ? const _SearchHint()
                  : _Results(
                      terms: terms,
                      projectId: project?.id,
                      projectFilterActive: draft.projectQuery != null,
                      type: draft.type,
                      priority: draft.priority,
                      includeArchived: _includeArchived,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ob das Archiv mitgesucht wird – ein Schalter, kein Filterchip: er ist
/// immer an derselben Stelle und sagt beides an, Zustand und Wirkung.
class _ArchiveToggle extends StatelessWidget {
  const _ArchiveToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: value ? scheme.primaryContainer : Colors.transparent,
      borderRadius: Radii.pillAll,
      child: InkWell(
        borderRadius: Radii.pillAll,
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            borderRadius: Radii.pillAll,
            border: Border.all(
              color: value ? Colors.transparent : context.paper.paperBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.check : Icons.inventory_2_outlined,
                size: 14,
                color: value
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Archiv',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: value
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({
    required this.terms,
    required this.projectId,
    required this.projectFilterActive,
    required this.type,
    required this.priority,
    required this.includeArchived,
  });

  final List<String> terms;
  final String? projectId;
  final bool projectFilterActive;
  final NoteType? type;
  final NotePriority? priority;
  final bool includeArchived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ein Projektfilter ohne Treffer soll nichts zeigen statt der Inbox:
    // `@unbekannt` bedeutet „in diesem Projekt“, nicht „ohne Projekt“.
    if (projectFilterActive && projectId == null) {
      return const EmptyState(
        icon: Icons.folder_off_outlined,
        title: 'Kein Projekt mit diesem Namen.',
        message: 'Tippe den Anfang eines vorhandenen Projektnamens.',
      );
    }

    return StreamBuilder<List<NoteRow>>(
      stream: ref
          .watch(noteRepositoryProvider)
          .search(
            terms: terms,
            projectId: projectId,
            projectFilterActive: projectFilterActive,
            type: type,
            priority: priority,
            includeArchived: includeArchived,
          ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        final notes = snapshot.data;
        if (notes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (notes.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off,
            title: 'Nichts gefunden.',
            message: 'Andere Wörter probieren, oder weniger davon.',
          );
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            pageGutter(context),
            Insets.xs,
            pageGutter(context),
            Insets.xxl,
          ),
          itemCount: notes.length,
          separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
          itemBuilder: (context, index) =>
              NoteCard(note: notes[index], showProject: true, showType: true),
        );
      },
    );
  }
}

/// Solange nichts getippt ist: zeigen, was die Suche kann.
class _SearchHint extends StatelessWidget {
  const _SearchHint();

  static const _examples = [
    ('nnue export', 'zwei Wörter, beide müssen vorkommen'),
    ('@chess !anf', 'Anforderungen eines Projekts'),
    ('!hoch', 'alles mit hoher Priorität, quer durch die Projekte'),
    ('#deadline', 'alles mit diesem Schlagwort'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Oben links statt mittig: die Hilfe soll dort stehen, wo gleich die
    // Treffer erscheinen.
    return ListView(
      padding: EdgeInsets.fromLTRB(
        pageGutter(context),
        Insets.md,
        pageGutter(context),
        Insets.xxl,
      ),
      children: [
        const SectionLabel('Beispiele'),
        const SizedBox(height: Insets.md),
        for (final (example, meaning) in _examples)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: Radii.xsAll,
                    border: Border.all(color: context.paper.paperBorder),
                  ),
                  child: Text(
                    example,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: monoFamily,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(meaning, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
