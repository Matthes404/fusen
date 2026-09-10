import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_type.dart';
import '../../ui/note_style.dart';
import '../../ui/widgets/note_card.dart';
import '../capture/capture_syntax.dart';

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
    final theme = Theme.of(context);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suche'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Suchen … @projekt !typ #tag',
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: _controller.clear,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (draft.projectQuery != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Chip(
                          avatar: const Icon(Icons.folder_outlined, size: 16),
                          label: Text(
                            project?.name ??
                                '${draft.projectQuery} (unbekannt)',
                          ),
                        ),
                      ),
                    if (draft.type != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Chip(
                          avatar: Icon(draft.type!.icon, size: 16),
                          label: Text(draft.type!.label),
                        ),
                      ),
                    const Spacer(),
                    FilterChip(
                      label: const Text('Archiv'),
                      selected: _includeArchived,
                      onSelected: (value) =>
                          setState(() => _includeArchived = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: terms.isEmpty && draft.type == null && project == null
          ? _SearchHint(style: theme.textTheme.bodySmall)
          : _Results(
              terms: terms,
              projectId: project?.id,
              projectFilterActive: draft.projectQuery != null,
              type: draft.type,
              includeArchived: _includeArchived,
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
    required this.includeArchived,
  });

  final List<String> terms;
  final String? projectId;
  final bool projectFilterActive;
  final NoteType? type;
  final bool includeArchived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ein Projektfilter ohne Treffer soll nichts zeigen statt der Inbox:
    // `@unbekannt` bedeutet „in diesem Projekt“, nicht „ohne Projekt“.
    if (projectFilterActive && projectId == null) {
      return const Center(child: Text('Kein Projekt mit diesem Namen.'));
    }

    return StreamBuilder<List<NoteRow>>(
      stream: ref
          .watch(noteRepositoryProvider)
          .search(
            terms: terms,
            projectId: projectId,
            projectFilterActive: projectFilterActive,
            type: type,
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
          return const Center(child: Text('Nichts gefunden.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          itemCount: notes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) =>
              NoteCard(note: notes[index], showProject: true),
        );
      },
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint({this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // Oben links statt mittig: die Hilfe soll dort stehen, wo gleich die
    // Treffer erscheinen.
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Beispiele', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('nnue export', style: style),
            Text('@chess !anf   – Anforderungen eines Projekts', style: style),
            Text('#deadline     – alles mit diesem Tag', style: style),
          ],
        ),
      ),
    );
  }
}
