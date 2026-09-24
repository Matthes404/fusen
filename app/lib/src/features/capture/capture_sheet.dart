import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/attachments/image_prep.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../data/repositories/capture_service.dart';
import '../../ui/note_style.dart';
import '../../ui/palette.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/keycap.dart';
import '../../ui/widgets/labels.dart';
import '../../ui/widgets/priority_chip.dart';
import '../../ui/widgets/undo.dart';
import '../attachments/image_input.dart';
import 'capture_plan.dart';
import 'capture_syntax.dart';
import 'list_import_dialog.dart';

/// Öffnet die Schnelleingabe.
///
/// [projectId] und [type] sind die Vorbelegung, wenn die Eingabe aus einem
/// Bereich heraus geöffnet wird („+“ bei den Nächsten Schritten). Was der
/// Nutzer tippt, sticht die Vorbelegung immer.
Future<String?> showCaptureSheet(
  BuildContext context, {
  String? projectId,
  NoteType? type,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.46),
    builder: (_) => CaptureDialog(projectId: projectId, type: type),
  );
}

class CaptureDialog extends ConsumerStatefulWidget {
  const CaptureDialog({super.key, this.projectId, this.type});

  final String? projectId;
  final NoteType? type;

  @override
  ConsumerState<CaptureDialog> createState() => _CaptureDialogState();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _CaptureDialogState extends ConsumerState<CaptureDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String? _target;
  bool _targetChosen = false;
  bool _saving = false;

  /// Typ und Priorität aus den Marken – gelten, solange die Eingabe nichts
  /// anderes sagt (`!typ`, `!hoch`).
  NoteType? _type;
  NotePriority? _priority;

  /// `null` heißt automatisch: eine erkennbare Liste wird aufgeteilt.
  bool? _split;

  final List<PreparedImage> _images = [];
  int _loadingImages = 0;
  bool _dragging = false;

  CaptureDraft _draft = const CaptureDraft(body: '');
  CapturePlan _plan = CapturePlan.empty;

  @override
  void initState() {
    super.initState();
    _target = widget.projectId;
    _targetChosen = widget.projectId != null;
    _type = widget.type;
    _controller.addListener(_reparse);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _reparse() => setState(_replan);

  void _replan() {
    _draft = parseCapture(_controller.text);
    _plan = planCapture(
      _controller.text,
      split: _split,
      type: _type ?? NoteType.idea,
      priority: _priority,
    );
  }

  /// Das Projekt, das die App vorschlägt, solange nichts gewählt wurde.
  String? get _suggestion => ref.read(lastProjectProvider);

  NoteType get _effectiveType => _draft.type ?? _type ?? NoteType.idea;

  NotePriority? get _effectivePriority => _draft.priority ?? _priority;

  /// Speichern geht, sobald es Text gibt – oder ein Bild. Auch ein Bild mit
  /// nichts als `@projekt #tag` daneben: der Plan ist dann leer, das Feld
  /// aber nicht.
  bool get _canSave =>
      !_saving && _loadingImages == 0 && (!_plan.isEmpty || _images.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.paper;
    final projects = ref.watch(projectsProvider).value ?? const [];

    final sheet = DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.paper,
        borderRadius: Radii.lgAll,
        border: Border.all(
          color: _dragging ? theme.colorScheme.primary : tokens.paperBorder,
          width: _dragging ? 2 : 1,
        ),
        boxShadow: tokens.overlay,
      ),
      child: ClipRRect(
        borderRadius: Radii.lgAll.subtract(
          const BorderRadius.all(Radius.circular(1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Der Klebestreifen oben am Block.
            Container(height: 4, color: fusenSeed),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.xl,
                        Insets.xl,
                        Insets.xl,
                        Insets.lg,
                      ),
                      child: _input(theme),
                    ),
                    _Preview(
                      target: _resolveTargetName(projects),
                      // Beim Aufteilen trägt jede Zeile ihre eigenen
                      // Kurzbefehle – die Marken oben zeigen dann die
                      // Vorgabe für alle übrigen, nicht die einer Zeile.
                      type: _plan.split
                          ? _type ?? NoteType.idea
                          : _effectiveType,
                      typeFromText: !_plan.split && _draft.type != null,
                      priority: _plan.split ? _priority : _effectivePriority,
                      priorityFromText: !_plan.split && _draft.priority != null,
                      tags: _draft.tags,
                      suggestion: _targetChosen || _draft.projectQuery != null
                          ? null
                          : _projectName(projects, _suggestion),
                      onAcceptSuggestion: _acceptSuggestion,
                      onPickTarget: () => _pickTarget(projects),
                      onType: (type) => setState(() {
                        _type = type;
                        _replan();
                      }),
                      onPriority: (priority) => setState(() {
                        _priority = priority;
                        _replan();
                      }),
                    ),
                    if (_images.isNotEmpty || _loadingImages > 0)
                      _ImageTray(
                        images: _images,
                        loading: _loadingImages,
                        hint: _plan.split && _plan.drafts.length > 1
                            ? 'Bilder hängen am ersten Zettel.'
                            : null,
                        onRemove: (index) =>
                            setState(() => _images.removeAt(index)),
                      ),
                    if (_plan.canSplit)
                      _SplitPanel(
                        plan: _plan,
                        onSplit: (split) => setState(() {
                          _split = split;
                          _replan();
                        }),
                        onOpenImport: _openImport,
                      ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: tokens.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.md,
                Insets.sm,
                Insets.md,
                Insets.sm,
              ),
              // Auf dem Handy passen Bildknöpfe, Hilfe, „Abbrechen“ und ein
              // „3 Zettel ablegen“ nicht nebeneinander: dort werden die
              // Knöpfe dichter, „Abbrechen“ wird zum Kreuz und die
              // Beschriftung kürzer.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 440;
                  final count = _plan.split ? _plan.drafts.length : 1;
                  final density = compact ? VisualDensity.compact : null;
                  final cancel = compact
                      ? IconButton(
                          tooltip: 'Abbrechen',
                          visualDensity: density,
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        )
                      : TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Abbrechen'),
                        );
                  final save = FilledButton(
                    style: brandButtonStyle(),
                    onPressed: _canSave ? _save : null,
                    child: Text(
                      switch ((count > 1, compact)) {
                        (false, _) => 'Ablegen',
                        (true, false) => '$count Zettel ablegen',
                        (true, true) => 'Ablegen ($count)',
                      },
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                  return Row(
                    children: [
                      _ImageButtons(
                        onPick: _pickImages,
                        onCamera: _takePhoto,
                        visualDensity: density,
                      ),
                      IconButton(
                        tooltip: 'Kurzbefehle',
                        visualDensity: density,
                        icon: const Icon(Icons.help_outline_rounded, size: 20),
                        onPressed: _showHelp,
                      ),
                      const SizedBox(width: Insets.xs),
                      if (compact)
                        // Der Knopf ist hier das einzige, was nachgeben
                        // darf – und nur, wenn es wirklich eng wird.
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              cancel,
                              const SizedBox(width: Insets.sm),
                              Flexible(child: save),
                            ],
                          ),
                        )
                      else ...[
                        const Expanded(child: _Shortcuts()),
                        cancel,
                        const SizedBox(width: Insets.sm),
                        save,
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    // Während des Speicherns nicht schließen: das Fenster schließt sich
    // danach selbst, und ein zweites Schließen träfe die Seite darunter.
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: 64,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: DropTarget(
            enable: ImageInput.supportsDrop,
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) {
              setState(() => _dragging = false);
              _addImages(() => ImageInput.fromFiles(details.files));
            },
            child: sheet,
          ),
        ),
      ),
    );
  }

  Widget _input(ThemeData theme) {
    return Shortcuts(
      // Strg+V zuerst hier: liegt ein Bild in der Zwischenablage, wird es
      // angehängt statt als leerer Text eingefügt.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyV, control: true): _PasteIntent(),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true): _PasteIntent(),
      },
      child: Actions(
        actions: {
          _PasteIntent: CallbackAction<_PasteIntent>(
            onInvoke: (_) {
              _paste();
              return null;
            },
          ),
        },
        child: Focus(
          onKeyEvent: _onKey,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            minLines: 1,
            maxLines: 10,
            // Größer als sonst: das Feld ist der ganze Zweck dieses Fensters.
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: 'Was ist los? @projekt !typ !hoch #tag',
              hintStyle: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.enter && !shift) {
      if (_canSave) _save();
      return KeyEventResult.handled;
    }
    // Tab übernimmt den Vorschlag, statt den Fokus weiterzuschieben.
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        !_targetChosen &&
        _draft.projectQuery == null &&
        _suggestion != null) {
      _acceptSuggestion();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Strg+V: im Dateimanager kopierte Bilder, sonst Text, sonst ein Bild.
  ///
  /// Text vor Bild, weil Tabellenprogramme zu kopierten Zellen auch ein Bild
  /// der Zellen ablegen – eingefügt werden soll aber die Liste.
  Future<void> _paste() async {
    if (await ImageInput.clipboardHasImageFiles()) {
      // Kopierte Dateien: der Text daneben wäre nur ihr Name. Lassen sie
      // sich nicht lesen, sagt das die Meldung aus _addImages.
      await _addImages(ImageInput.clipboardFiles);
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      final value = _controller.value;
      final selection = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      _controller.value = TextEditingValue(
        text: value.text.replaceRange(selection.start, selection.end, text),
        selection: TextSelection.collapsed(
          offset: selection.start + text.length,
        ),
      );
      return;
    }
    if (ImageInput.hasClipboardImages) {
      await _addImages(ImageInput.clipboardBitmap);
    }
  }

  Future<void> _pickImages() => _addImages(ImageInput.pick);

  Future<void> _takePhoto() =>
      _addImages(() async => [?await ImageInput.camera()]);

  Future<void> _addImages(Future<List<PreparedImage>> Function() load) async {
    setState(() => _loadingImages++);
    try {
      final images = await load();
      if (mounted) setState(() => _images.addAll(images));
    } on Object catch (error) {
      if (mounted) {
        showMessage(ScaffoldMessenger.of(context), describeImageError(error));
      }
    } finally {
      if (mounted) setState(() => _loadingImages--);
      _focusNode.requestFocus();
    }
  }

  void _acceptSuggestion() {
    setState(() {
      _target = _suggestion;
      _targetChosen = true;
    });
  }

  String? _projectName(List<ProjectRow> projects, String? id) {
    if (id == null) return null;
    return projects.where((p) => p.id == id).firstOrNull?.name;
  }

  /// Was oben als Ziel angezeigt wird.
  String _resolveTargetName(List<ProjectRow> projects) {
    final query = _draft.projectQuery;
    if (query != null) {
      final match = projects
          .where((p) => p.name.toLowerCase().startsWith(query.toLowerCase()))
          .toList();
      return match.length == 1 ? match.single.name : '$query (neu)';
    }
    if (_targetChosen) return _projectName(projects, _target) ?? 'Inbox';
    return 'Inbox';
  }

  Future<void> _pickTarget(List<ProjectRow> projects) async {
    final picked = await showDialog<_Target>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Wohin?'),
        contentPadding: const EdgeInsets.fromLTRB(
          Insets.sm,
          Insets.sm,
          Insets.sm,
          Insets.md,
        ),
        children: [
          _TargetOption(
            label: 'Inbox',
            icon: Icons.inbox_outlined,
            onTap: () => Navigator.of(context).pop(const _Target(null)),
          ),
          for (final project in projects)
            _TargetOption(
              label: project.name,
              color: Color(project.color),
              onTap: () => Navigator.of(context).pop(_Target(project.id)),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _target = picked.projectId;
        _targetChosen = true;
      });
    }
    _focusNode.requestFocus();
  }

  Future<void> _openImport() async {
    final text = _controller.text;
    final projectId = _targetChosen ? _target : widget.projectId;
    Navigator.of(context).pop();
    await showListImportDialog(
      context,
      projectId: projectId,
      type: _type,
      initialText: text,
    );
  }

  void _showHelp() {
    showDialog<void>(context: context, builder: (_) => const _SyntaxHelp());
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final navigator = Navigator.of(context);
    final capture = ref.read(captureServiceProvider);
    final attachments = ref.read(attachmentRepositoryProvider);

    var drafts = _plan.drafts;
    // Nur Bilder, kein Text: dann eben ein Zettel mit Bild, benannt nach
    // der Datei – ein Bildschirmfoto heißt nach seinem Zeitpunkt. Was an
    // Kurzbefehlen danebenstand (@projekt, #tag), gilt trotzdem.
    if (drafts.isEmpty && _images.isNotEmpty) {
      final name = _images.first.fileName;
      final dot = name.lastIndexOf('.');
      drafts = [
        NoteDraft(
          body: '',
          title: dot > 0 ? name.substring(0, dot) : name,
          projectName: _draft.projectQuery,
          type: _effectiveType,
          priority: _effectivePriority,
          tags: _draft.tags,
        ),
      ];
    }

    final List<NoteRow> created;
    try {
      created = await capture.createAll(
        drafts,
        projectId: _targetChosen ? _target : null,
      );
      if (created.isNotEmpty) {
        for (final image in _images) {
          await attachments.add(created.first.id, image);
        }
      }
    } on Object catch (error) {
      // Ohne das bliebe das Fenster gesperrt: Schließen ist während des
      // Speicherns abgeschaltet.
      if (mounted) {
        setState(() => _saving = false);
        showMessage(
          ScaffoldMessenger.of(context),
          'Speichern fehlgeschlagen: $error',
        );
      }
      return;
    }

    if (!mounted) return;
    final projectId = created.firstOrNull?.projectId;
    ref.read(lastProjectProvider.notifier).remember(projectId);
    navigator.pop(projectId);
  }
}

class _Target {
  const _Target(this.projectId);

  final String? projectId;
}

/// Was die App aus dem Getippten macht – Ziel, Typ, Priorität, Schlagworte.
///
/// Typ und Priorität lassen sich auch antippen: wer die Kurzbefehle nicht
/// kennt, kommt so ebenfalls ans Ziel.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.target,
    required this.type,
    required this.typeFromText,
    required this.priority,
    required this.priorityFromText,
    required this.tags,
    required this.suggestion,
    required this.onAcceptSuggestion,
    required this.onPickTarget,
    required this.onType,
    required this.onPriority,
  });

  final String target;
  final NoteType type;
  final bool typeFromText;
  final NotePriority? priority;
  final bool priorityFromText;
  final List<String> tags;
  final String? suggestion;
  final VoidCallback onAcceptSuggestion;
  final VoidCallback onPickTarget;
  final ValueChanged<NoteType> onType;
  final ValueChanged<NotePriority?> onPriority;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.lg),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Pill(
            icon: Icons.folder_outlined,
            label: target,
            trailing: Icons.unfold_more,
            onTap: onPickTarget,
          ),
          MenuAnchor(
            menuChildren: [
              for (final t in NoteType.sectionOrder)
                MenuItemButton(
                  leadingIcon: Icon(t.icon, size: 18, color: t.color(scheme)),
                  trailingIcon: t == type
                      ? const Icon(Icons.check_rounded, size: 16)
                      : null,
                  onPressed: typeFromText ? null : () => onType(t),
                  child: Text(t.label),
                ),
            ],
            builder: (context, controller, _) => _Pill(
              icon: type.icon,
              label: type.label,
              color: type.color(scheme),
              trailing: typeFromText ? null : Icons.unfold_more,
              onTap: typeFromText
                  ? null
                  : () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
            ),
          ),
          if (type.supportsPriority)
            priorityFromText
                ? PriorityBadge(type: type, priority: priority)
                : PriorityPicker(
                    type: type,
                    priority: priority,
                    onChanged: onPriority,
                  ),
          for (final tag in tags) _Pill(label: '#$tag'),
          if (suggestion != null)
            _Pill(
              label: suggestion!,
              leading: const Keycap('Tab'),
              onTap: onAcceptSuggestion,
            ),
        ],
      ),
    );
  }
}

/// Mehrere Einträge erkannt: aufteilen oder als ein Zettel behalten.
class _SplitPanel extends StatelessWidget {
  const _SplitPanel({
    required this.plan,
    required this.onSplit,
    required this.onOpenImport,
  });

  final CapturePlan plan;
  final ValueChanged<bool> onSplit;
  final VoidCallback onOpenImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = plan.entryCount;
    final drafts = plan.drafts;
    const visible = 5;

    return Container(
      margin: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
      padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.sm, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: Radii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Auf dem Handy steht die Umschaltung unter der Überschrift statt
          // daneben – nebeneinander ist dort kein Platz.
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                children: [
                  Icon(
                    Icons.format_list_bulleted_rounded,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Text(
                      '$count Einträge erkannt',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              );
              final toggle = SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
                segments: [
                  const ButtonSegment(value: false, label: Text('Ein Zettel')),
                  ButtonSegment(value: true, label: Text('$count Zettel')),
                ],
                selected: {plan.split},
                onSelectionChanged: (value) => onSplit(value.first),
              );
              if (constraints.maxWidth >= 400) {
                return Row(
                  children: [
                    Expanded(child: title),
                    toggle,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(height: Insets.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: toggle,
                  ),
                ],
              );
            },
          ),
          if (plan.split) ...[
            const SizedBox(height: Insets.sm),
            for (final draft in drafts.take(visible))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      draft.done
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 14,
                      color: draft.done
                          ? scheme.tertiary
                          : draft.type.color(scheme),
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        draft.title ?? draft.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (draft.priority != null && draft.type.supportsPriority)
                      Icon(
                        draft.priority!.icon,
                        size: 14,
                        color: draft.priority!.color(scheme),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                if (drafts.length > visible)
                  Expanded(
                    child: Text(
                      'und ${drafts.length - visible} weitere',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                  )
                else
                  const Spacer(),
                // Kurz, damit er auch auf dem Handy ganz dasteht – die
                // Vorschau sieht man ja schon darüber.
                TextButton(
                  onPressed: onOpenImport,
                  child: const Text('Anpassen …'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Angehängte Bilder, bevor sie gespeichert sind.
class _ImageTray extends StatelessWidget {
  const _ImageTray({
    required this.images,
    required this.loading,
    required this.onRemove,
    this.hint,
  });

  final List<PreparedImage> images;
  final int loading;
  final ValueChanged<int> onRemove;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 72.0;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              for (var i = 0; i < images.length; i++)
                SizedBox.square(
                  dimension: size,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: Radii.smAll,
                        child: Image.memory(
                          images[i].bytes,
                          fit: BoxFit.cover,
                          cacheWidth: (size * dpr).round(),
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHigh,
                            child: const Icon(Icons.image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 3,
                        right: 3,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => onRemove(i),
                            child: const Padding(
                              padding: EdgeInsets.all(3),
                              child: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (var i = 0; i < loading; i++)
                Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: Radii.smAll,
                  ),
                  child: const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: Insets.xs),
            Text(hint!, style: theme.textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

/// Bild anhängen: auf dem Handy Galerie oder Kamera, auf dem Desktop die
/// Dateiauswahl – einfügen und hineinziehen gehen dort ohnehin.
class _ImageButtons extends StatelessWidget {
  const _ImageButtons({
    required this.onPick,
    required this.onCamera,
    this.visualDensity,
  });

  final VoidCallback onPick;
  final VoidCallback onCamera;
  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: ImageInput.hasClipboardImages
              ? 'Bild anhängen (oder mit Strg+V einfügen, hineinziehen)'
              : 'Bild aus der Galerie',
          visualDensity: visualDensity,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
          onPressed: onPick,
        ),
        if (ImageInput.hasCamera)
          IconButton(
            tooltip: 'Foto aufnehmen',
            visualDensity: visualDensity,
            icon: const Icon(Icons.photo_camera_outlined, size: 20),
            onPressed: onCamera,
          ),
      ],
    );
  }
}

/// Eine Marke in der Vorschau. Anklickbar, wenn [onTap] gesetzt ist.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    this.icon,
    this.color,
    this.onTap,
    this.leading,
    this.trailing,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  final Widget? leading;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurfaceVariant;
    final tokens = context.paper;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          if (icon != null) ...[
            Icon(icon, size: 14, color: tint),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color == null ? theme.colorScheme.onSurface : tint,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            Icon(trailing, size: 13, color: theme.colorScheme.outline),
          ],
        ],
      ),
    );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Radii.pillAll,
        border: Border.all(
          color: color == null
              ? tokens.paperBorder
              : color!.withValues(alpha: 0.25),
        ),
      ),
      child: content,
    );

    return Material(
      color: color == null
          ? theme.colorScheme.surfaceContainer
          : color!.withValues(alpha: 0.12),
      borderRadius: Radii.pillAll,
      child: onTap == null
          ? decorated
          : InkWell(
              borderRadius: Radii.pillAll,
              onTap: onTap,
              child: decorated,
            ),
    );
  }
}

/// Die Tasten, die die Schnelleingabe ausmachen.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    // Auf schmalen Fenstern ist dafür kein Platz – dort tippt man ohnehin.
    if (MediaQuery.sizeOf(context).width < 560) return const SizedBox.shrink();
    // Lieber etwas kleiner als abgeschnitten, wenn es im Fuß eng wird.
    Widget fit(Widget hint) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: hint,
    );
    return Wrap(
      spacing: Insets.md,
      runSpacing: Insets.xs,
      children: [
        fit(const KeyHint(keys: ['Enter'], text: 'speichert')),
        fit(const KeyHint(keys: ['Shift', 'Enter'], text: 'neue Zeile')),
      ],
    );
  }
}

/// Die Kurzbefehle auf einen Blick.
class _SyntaxHelp extends StatelessWidget {
  const _SyntaxHelp();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(String code, String meaning) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              code,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: monoFamily,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(child: Text(meaning, style: theme.textTheme.bodySmall)),
        ],
      ),
    );

    return AlertDialog(
      title: const Text('Kurzbefehle'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Zuordnen'),
              row('@projekt', 'in dieses Projekt – neu, wenn es fehlt'),
              row('#tag', 'Schlagwort anhängen'),
              const SizedBox(height: Insets.md),
              const SectionLabel('Typ'),
              for (final type in NoteType.sectionOrder)
                row('!${canonicalTypeAlias[type]}', type.label),
              const SizedBox(height: Insets.md),
              const SectionLabel('Priorität'),
              row('!hoch  !muss  !p1', 'hoch – bei Anforderungen „Muss“'),
              row('!mittel  !soll  !p2', 'mittel – „Soll“'),
              row('!niedrig  !kann  !p3', 'niedrig – „Kann“'),
              const SizedBox(height: Insets.md),
              const SectionLabel('Listen'),
              row('- eins\n- zwei', 'jede Zeile ein eigener Zettel'),
              row('- [x] erledigt', 'gleich als erledigt anlegen'),
              row('Ideen:', 'Überschrift – bestimmt den Typ darunter'),
              row('  eingerückt', 'Details zum Eintrag darüber'),
              const SizedBox(height: Insets.md),
              const SectionLabel('Bilder'),
              row(
                'Strg+V',
                'Bild aus der Zwischenablage anhängen – oder hineinziehen',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

/// Eine Zeile im „Wohin?“-Dialog.
class _TargetOption extends StatelessWidget {
  const _TargetOption({
    required this.label,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: Radii.smAll,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.md,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: icon != null
                  ? Icon(icon, size: 18)
                  : Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
