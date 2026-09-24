import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../data/repositories/capture_service.dart';
import '../../ui/note_style.dart';
import '../../ui/palette.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/labels.dart';
import '../../ui/widgets/priority_chip.dart';
import '../../ui/widgets/project_menu_items.dart';
import '../../ui/widgets/undo.dart';
import 'capture_plan.dart';

/// Öffnet den Listen-Import: Text einfügen, jede Zeile wird ein Zettel.
///
/// [source] ist ein bestehender Zettel, dessen Liste aufgeteilt wird – er
/// wandert danach auf Wunsch ins Archiv.
Future<void> showListImportDialog(
  BuildContext context, {
  String? projectId,
  NoteType? type,
  String initialText = '',
  NoteRow? source,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showDialog<void>(
    context: context,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.46),
    builder: (_) => ListImportDialog(
      projectId: projectId,
      type: type,
      initialText: initialText,
      source: source,
      messenger: messenger,
    ),
  );
}

class ListImportDialog extends ConsumerStatefulWidget {
  const ListImportDialog({
    super.key,
    this.projectId,
    this.type,
    this.initialText = '',
    this.source,
    this.messenger,
  });

  final String? projectId;
  final NoteType? type;
  final String initialText;
  final NoteRow? source;
  final ScaffoldMessengerState? messenger;

  @override
  ConsumerState<ListImportDialog> createState() => _ListImportDialogState();
}

class _ListImportDialogState extends ConsumerState<ListImportDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );

  late String? _projectId = widget.projectId;
  late NoteType? _type = widget.type;
  NotePriority? _priority;
  bool _archiveSource = true;
  bool _saving = false;

  /// Abgewählte Einträge, nach Position im Plan.
  final Set<int> _skipped = {};

  CapturePlan _plan = CapturePlan.empty;

  /// Der Text beim letzten Planen. Der Controller meldet auch bloße
  /// Cursorbewegungen; die sollen abgewählte Einträge nicht wieder anwählen.
  late String _plannedText = _text.text;

  @override
  void initState() {
    super.initState();
    _replan();
    _text.addListener(() {
      if (_text.text == _plannedText) return;
      _plannedText = _text.text;
      _skipped.clear();
      setState(_replan);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _replan() {
    _plan = planCapture(
      _text.text,
      split: true,
      // Ohne Überschrift und ohne !typ wird eine Zeile ein Schritt – aus
      // einer Liste sollen Aufgaben werden, keine Ideen.
      type: _type ?? NoteType.step,
      typeFromHeadings: _type == null,
      priority: _priority,
    );
  }

  List<NoteDraft> get _selected => [
    for (var i = 0; i < _plan.drafts.length; i++)
      if (!_skipped.contains(i)) _plan.drafts[i],
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;
    final tokens = context.paper;

    // Auf dem Handy nicht gleich die Tastatur: sie verdeckte den halben
    // Dialog, und der Weg ist ohnehin meist „Einfügen“.
    final editor = _Editor(
      controller: _text,
      onPaste: _pasteFromClipboard,
      autofocus: wide && _text.text.isEmpty,
    );
    final preview = _Preview(
      embedded: !wide,
      plan: _plan,
      skipped: _skipped,
      onToggle: (index) => setState(
        () => _skipped.contains(index)
            ? _skipped.remove(index)
            : _skipped.add(index),
      ),
      onAll: (select) => setState(() {
        _skipped.clear();
        if (!select) {
          _skipped.addAll(List.generate(_plan.drafts.length, (i) => i));
        }
      }),
    );

    final header = _Header(source: widget.source, compact: !wide);
    final options = _Options(
      projectId: _projectId,
      type: _type,
      priority: _priority,
      onProject: (id) => setState(() => _projectId = id),
      onType: (type) => setState(() {
        _type = type;
        _replan();
      }),
      onPriority: (priority) => setState(() {
        _priority = priority;
        _replan();
      }),
    );
    final divider = Divider(height: 1, color: tokens.hairline);

    // Während des Speicherns nicht schließen: der Dialog schließt sich danach
    // selbst, und ein zweites Schließen träfe die Seite darunter.
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: EdgeInsets.all(wide ? Insets.xxl : Insets.md),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 980,
            maxHeight: wide ? 680 : size.height,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Breit bleiben Kopf und Optionen stehen. Auf dem Handy
              // scrollen sie mit – fest stehend ließen sie mit offener
              // Tastatur dem Textfeld keinen Platz.
              if (wide) ...[header, divider, options, divider],
              Flexible(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: editor),
                          VerticalDivider(width: 1, color: tokens.hairline),
                          Expanded(child: preview),
                        ],
                      )
                    : ListView(
                        shrinkWrap: true,
                        // Das Textfeld gleich unter den Kopf: Einfügen ist
                        // der erste Schritt, die Optionen braucht man selten.
                        children: [
                          header,
                          divider,
                          SizedBox(height: 220, child: editor),
                          divider,
                          options,
                          divider,
                          preview,
                        ],
                      ),
              ),
              Divider(height: 1, color: tokens.hairline),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.lg,
                  Insets.md,
                  Insets.md,
                  Insets.md,
                ),
                // Schmal wird „Abbrechen“ zum Kreuz und die Beschriftung
                // darf sich kürzen – sonst schöbe sie den Knopf aus dem Bild.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 440;
                    final cancel = compact
                        ? IconButton(
                            tooltip: 'Abbrechen',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(context).pop(),
                          )
                        : TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Abbrechen'),
                          );
                    final save = FilledButton.icon(
                      style: brandButtonStyle(),
                      onPressed: _selected.isEmpty || _saving ? null : _create,
                      icon: const Icon(Icons.playlist_add_check_rounded),
                      label: Text(
                        switch (_selected.length) {
                          0 => 'Anlegen',
                          1 => '1 Zettel anlegen',
                          final n => '$n Zettel anlegen',
                        },
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                    if (widget.source == null) {
                      // Der Knopf gibt nur nach, wenn es wirklich eng wird –
                      // ein Platzhalter daneben nähme ihm sonst die Hälfte.
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          cancel,
                          const SizedBox(width: Insets.sm),
                          Flexible(child: save),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _archiveSource,
                            onChanged: (value) =>
                                setState(() => _archiveSource = value ?? true),
                            title: const Text(
                              'Ursprünglichen Zettel archivieren',
                            ),
                          ),
                        ),
                        cancel,
                        const SizedBox(width: Insets.sm),
                        Flexible(child: save),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _text.text = _text.text.isEmpty ? text : '${_text.text}\n$text';
  }

  Future<void> _create() async {
    setState(() => _saving = true);
    final capture = ref.read(captureServiceProvider);
    final notes = ref.read(noteRepositoryProvider);
    final source = widget.source;
    final navigator = Navigator.of(context);

    final List<NoteRow> created;
    final archive = source != null && _archiveSource;
    try {
      created = await capture.createAll(_selected, projectId: _projectId);
      if (archive) await notes.archive(source.id);
    } on Object catch (error) {
      // Ohne das bliebe der Dialog gesperrt: Schließen ist während des
      // Speicherns abgeschaltet.
      if (mounted) setState(() => _saving = false);
      final messenger = widget.messenger;
      if (messenger != null) {
        showMessage(messenger, 'Anlegen fehlgeschlagen: $error');
      }
      return;
    }

    if (mounted) navigator.pop();
    final messenger = widget.messenger;
    if (messenger == null) return;
    showUndoSnackBar(
      messenger,
      created.length == 1
          ? '1 Zettel angelegt'
          : '${created.length} Zettel angelegt',
      onUndo: () async {
        await capture.undo(created);
        if (archive) await notes.unarchive(source.id);
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.source, required this.compact});

  final NoteRow? source;

  /// Auf dem Handy nur die Überschrift: die Erklärung steht als Beispiel
  /// schon im leeren Textfeld, und Schließen liegt unten im Fuß – der Kopf
  /// scrollt dort mit weg.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.xl,
        Insets.lg,
        Insets.md,
        Insets.lg,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fusenSeed.withValues(alpha: 0.3),
              borderRadius: Radii.smAll,
            ),
            child: const Icon(Icons.playlist_add_rounded, size: 20),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source == null
                      ? 'Aus einer Liste anlegen'
                      : 'In einzelne Zettel aufteilen',
                  style: theme.textTheme.titleMedium,
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Jede Zeile wird ein Zettel. Eingerücktes wird zu Details, '
                    'Überschriften wie „Ideen:“ bestimmen den Typ, '
                    '[x] heißt erledigt.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (!compact)
            IconButton(
              tooltip: 'Schließen',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }
}

class _Options extends ConsumerWidget {
  const _Options({
    required this.projectId,
    required this.type,
    required this.priority,
    required this.onProject,
    required this.onType,
    required this.onPriority,
  });

  final String? projectId;
  final NoteType? type;
  final NotePriority? priority;
  final ValueChanged<String?> onProject;
  final ValueChanged<NoteType?> onType;
  final ValueChanged<NotePriority?> onPriority;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider).value ?? const [];
    final archivedProjects =
        ref.watch(archivedProjectsProvider).value ?? const [];
    final scheme = Theme.of(context).colorScheme;

    Widget field(String label, Widget child) => SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionLabel(label),
          const SizedBox(height: Insets.xs),
          child,
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.xl,
        Insets.md,
        Insets.xl,
        Insets.md,
      ),
      child: Wrap(
        spacing: Insets.lg,
        runSpacing: Insets.md,
        children: [
          field(
            'Wohin',
            DropdownButtonFormField<String?>(
              initialValue: projectId,
              isExpanded: true,
              items: projectMenuItems(
                projects: projects,
                archived: archivedProjects,
                selected: projectId,
                showColor: true,
              ),
              onChanged: onProject,
            ),
          ),
          field(
            'Typ',
            DropdownButtonFormField<NoteType?>(
              initialValue: type,
              isExpanded: true,
              items: [
                const DropdownMenuItem<NoteType?>(child: Text('Automatisch')),
                for (final t in NoteType.sectionOrder)
                  DropdownMenuItem<NoteType?>(
                    value: t,
                    child: Row(
                      children: [
                        Icon(t.icon, size: 16, color: t.color(scheme)),
                        const SizedBox(width: Insets.sm),
                        Flexible(
                          child: Text(t.label, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: onType,
            ),
          ),
          field(
            'Priorität',
            DropdownButtonFormField<NotePriority?>(
              initialValue: priority,
              isExpanded: true,
              items: [
                const DropdownMenuItem<NotePriority?>(child: Text('Keine')),
                for (final p in NotePriority.displayOrder)
                  DropdownMenuItem<NotePriority?>(
                    value: p,
                    child: Row(
                      children: [
                        Icon(p.icon, size: 16, color: p.color(scheme)),
                        const SizedBox(width: Insets.sm),
                        Text(priorityLabel(type ?? NoteType.step, p)),
                      ],
                    ),
                  ),
              ],
              onChanged: onPriority,
            ),
          ),
        ],
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.controller,
    required this.onPaste,
    required this.autofocus,
  });

  final TextEditingController controller;
  final VoidCallback onPaste;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        TextField(
          controller: controller,
          autofocus: autofocus,
          expands: true,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: monoFamily,
            fontSize: 13.5,
            height: 1.55,
          ),
          decoration: InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.fromLTRB(
              Insets.xl,
              Insets.lg,
              Insets.xl,
              Insets.lg,
            ),
            hintText:
                'Nächste Schritte:\n'
                '- NNUE-Export testen !hoch\n'
                '- Perft für Rochade ergänzen\n'
                '  (Details eingerückt)\n'
                '- [x] Transposition Table verdoppeln\n'
                '\n'
                'Ideen:\n'
                '- Eröffnungsbuch aus Lichess-Partien',
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: monoFamily,
              fontSize: 13.5,
              height: 1.55,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        Positioned(
          right: Insets.sm,
          bottom: Insets.sm,
          child: TextButton.icon(
            onPressed: onPaste,
            icon: const Icon(Icons.content_paste_rounded, size: 16),
            label: const Text('Einfügen'),
          ),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.plan,
    required this.skipped,
    required this.onToggle,
    required this.onAll,
    this.embedded = false,
  });

  final CapturePlan plan;
  final Set<int> skipped;
  final ValueChanged<int> onToggle;
  final ValueChanged<bool> onAll;

  /// Steht die Vorschau selbst in einer scrollenden Liste (schmales
  /// Fenster), scrollt sie nicht noch einmal für sich.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drafts = plan.drafts;

    if (drafts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.format_list_bulleted_rounded,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
              const SizedBox(height: Insets.md),
              Text(
                'Hier erscheinen die Zettel,\nsobald links etwas steht.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final selected = drafts.length - skipped.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.sm,
            Insets.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: SectionLabel(
                  '$selected von ${drafts.length} ausgewählt',
                  caps: false,
                ),
              ),
              TextButton(
                onPressed: () => onAll(skipped.isNotEmpty),
                child: Text(skipped.isEmpty ? 'Keine' : 'Alle'),
              ),
            ],
          ),
        ),
        if (embedded)
          for (var index = 0; index < drafts.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
              child: _DraftRow(
                draft: drafts[index],
                selected: !skipped.contains(index),
                onToggle: () => onToggle(index),
              ),
            )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                Insets.sm,
                0,
                Insets.sm,
                Insets.md,
              ),
              itemCount: drafts.length,
              itemBuilder: (context, index) => _DraftRow(
                draft: drafts[index],
                selected: !skipped.contains(index),
                onToggle: () => onToggle(index),
              ),
            ),
          ),
      ],
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.draft,
    required this.selected,
    required this.onToggle,
  });

  final NoteDraft draft;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final heading = draft.title ?? draft.body;
    final details = draft.title == null ? null : draft.body;

    return InkWell(
      borderRadius: Radii.smAll,
      onTap: onToggle,
      child: Opacity(
        opacity: selected ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.xs,
            vertical: 6,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: selected, onChanged: (_) => onToggle()),
              const SizedBox(width: Insets.xs),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: TypeBadge(type: draft.type, size: 22),
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      heading,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: draft.title == null
                            ? FontWeight.w500
                            : FontWeight.w700,
                        decoration: draft.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (details != null)
                      Text(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          MetaChip(
                            label: draft.type.label,
                            color: draft.type.color(scheme),
                          ),
                          if (draft.priority != null &&
                              draft.type.supportsPriority)
                            PriorityBadge(
                              type: draft.type,
                              priority: draft.priority,
                              dense: true,
                            ),
                          if (draft.done)
                            MetaChip(
                              label: statusLabel(draft.type, NoteStatus.done),
                              icon: Icons.check_rounded,
                              color: scheme.tertiary,
                            ),
                          if (draft.projectName != null)
                            MetaChip(
                              label: '@${draft.projectName}',
                              icon: Icons.folder_outlined,
                            ),
                          for (final tag in draft.tags)
                            MetaChip(label: '#$tag'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
