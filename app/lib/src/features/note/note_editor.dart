import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/attachments/image_prep.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../data/repositories/note_repository.dart';
import '../../ui/note_style.dart';
import '../../ui/palette.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/attachments.dart';
import '../../ui/widgets/labels.dart';
import '../../ui/widgets/markdown_text.dart';
import '../../ui/widgets/note_card.dart' show formatTimestamp;
import '../../ui/widgets/undo.dart';
import '../attachments/image_input.dart';
import 'note_actions.dart';
import '../../ui/widgets/project_menu_items.dart';

/// Öffnet den Zettel zum Bearbeiten – auf breiten Fenstern als Dialog,
/// auf dem Handy als Blatt von unten.
Future<void> showNoteEditor(BuildContext context, NoteRow note) {
  final wide = MediaQuery.sizeOf(context).width >= compactWidth;
  if (wide) {
    return showDialog<void>(
      context: context,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.46),
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
          child: NoteEditor(noteId: note.id),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: NoteEditor(noteId: note.id),
    ),
  );
}

class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({required this.noteId, super.key});

  final String noteId;

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _tagsController = TextEditingController();
  final _answerController = TextEditingController();

  NoteType _type = NoteType.idea;
  NotePriority? _priority;
  String? _projectId;
  bool _loaded = false;

  /// Markdown-Vorschau statt Eingabefeld.
  bool _preview = false;
  bool _dragging = false;
  int _loadingImages = 0;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagsController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  void _load(NoteRow note) {
    _titleController.text = note.title ?? '';
    _bodyController.text = note.body;
    _tagsController.text = note.tags.map((t) => '#$t').join(' ');
    _answerController.text = note.answer ?? '';
    _type = note.type;
    _priority = note.priority;
    _projectId = note.projectId;
    _loaded = true;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(noteProvider(widget.noteId));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (note) {
        if (note == null) return const Center(child: Text('Zettel ist weg.'));
        if (!_loaded) _load(note);
        return _buildForm(context, note);
      },
    );
  }

  Widget _buildForm(BuildContext context, NoteRow note) {
    final locked = !isContentEditable(note, DateTime.now().toUtc());
    final projects = ref.watch(projectsProvider).value ?? const [];

    return DropTarget(
      // Liegt die Schnelleingabe darüber, gehört ein hineingezogenes Bild
      // ihr – nicht zusätzlich dem Zettel dahinter.
      enable:
          ImageInput.supportsDrop &&
          (ModalRoute.of(context)?.isCurrent ?? true),
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        _addImages(() => ImageInput.fromFiles(details.files));
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: _dragging
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: _form(context, note, locked, projects),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    NoteRow note,
    bool locked,
    List<ProjectRow> projects,
  ) {
    final archivedProjects =
        ref.watch(archivedProjectsProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorHeader(
          note: note,
          type: _type,
          onClose: () => Navigator.of(context).maybePop(),
        ),
        Divider(height: 1, color: context.paper.hairline),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              Insets.lg,
              Insets.xl,
              Insets.xl,
            ),
            children: [
              if (locked)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.lg),
                  child: _LockedBanner(createdAt: note.createdAt),
                ),
              const _FieldLabel('Typ'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final type in NoteType.sectionOrder)
                    _TypeChoice(
                      type: type,
                      selected: _type == type,
                      onTap: locked ? null : () => setState(() => _type = type),
                    ),
                ],
              ),
              if (_type.supportsPriority) ...[
                const SizedBox(height: Insets.xl),
                const _FieldLabel('Priorität'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final priority in NotePriority.displayOrder)
                      _PriorityChoice(
                        type: _type,
                        priority: priority,
                        selected: _priority == priority,
                        onTap: locked
                            ? null
                            : () => setState(
                                () => _priority = _priority == priority
                                    ? null
                                    : priority,
                              ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Insets.xl),
              const _FieldLabel('Status'),
              SegmentedButton<NoteStatus>(
                showSelectedIcon: false,
                segments: [
                  for (final status in NoteStatus.values)
                    ButtonSegment(
                      value: status,
                      icon: Icon(switch (status) {
                        NoteStatus.open => Icons.radio_button_unchecked,
                        NoteStatus.done => Icons.check_circle_outline,
                        NoteStatus.discarded => Icons.block_rounded,
                      }, size: 16),
                      label: Text(statusLabel(_type, status)),
                    ),
                ],
                selected: {note.status},
                onSelectionChanged: (value) => _setStatus(value.first),
              ),
              if (note.closedAt != null && !note.status.isOpen)
                Padding(
                  padding: const EdgeInsets.only(top: Insets.sm),
                  child: Text(
                    '${_capitalized(statusLabel(note.type, note.status))} '
                    'am ${formatTimestamp(note.closedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: Insets.xl),
              const _FieldLabel('Projekt'),
              DropdownButtonFormField<String?>(
                initialValue: _projectId,
                isExpanded: true,
                items: projectMenuItems(
                  projects: projects,
                  archived: archivedProjects,
                  selected: _projectId,
                ),
                onChanged: (value) => setState(() => _projectId = value),
              ),
              const SizedBox(height: Insets.xl),
              TextField(
                controller: _titleController,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Titel (optional)',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Insets.md),
              Row(
                children: [
                  const Expanded(child: _FieldLabel('Text')),
                  _PreviewToggle(
                    preview: _preview,
                    onChanged: (value) => setState(() => _preview = value),
                  ),
                ],
              ),
              if (_preview)
                Container(
                  constraints: const BoxConstraints(minHeight: 120),
                  padding: const EdgeInsets.all(Insets.md),
                  decoration: BoxDecoration(
                    borderRadius: Radii.smAll,
                    border: Border.all(color: context.paper.paperBorder),
                  ),
                  child: _bodyController.text.trim().isEmpty
                      ? Text(
                          'Noch kein Text.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : MarkdownText(_bodyController.text),
                )
              else
                TextField(
                  controller: _bodyController,
                  enabled: !locked,
                  minLines: 5,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    hintText: 'Markdown: **fett**, `code`, - Listen, [Link](…)',
                    alignLabelWithHint: true,
                  ),
                ),
              const SizedBox(height: Insets.xl),
              _ImagesField(
                noteId: note.id,
                loading: _loadingImages,
                onAdd: _addImages,
              ),
              const SizedBox(height: Insets.md),
              TextField(
                controller: _tagsController,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: '#nnue #performance',
                ),
              ),
              if (_type.hasAnswer) ...[
                const SizedBox(height: Insets.md),
                TextField(
                  controller: _answerController,
                  enabled: !locked,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Antwort',
                    helperText: 'Beantwortete Fragen wandern ins Archiv.',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: context.paper.hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.md,
            Insets.md,
            Insets.md,
            Insets.md,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: note.archivedAt == null
                    ? 'Archivieren'
                    : 'Aus dem Archiv holen',
                icon: Icon(
                  note.archivedAt == null
                      ? Icons.archive_outlined
                      : Icons.unarchive_outlined,
                ),
                onPressed: () => _toggleArchive(note),
              ),
              IconButton(
                tooltip: 'Löschen',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(note),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Abbrechen'),
              ),
              const SizedBox(width: Insets.sm),
              FilledButton(
                onPressed: locked ? null : () => _save(note),
                child: const Text('Speichern'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _setStatus(NoteStatus status) async {
    await ref.read(noteRepositoryProvider).setStatus(widget.noteId, status);
  }

  Future<void> _toggleArchive(NoteRow note) async {
    final navigator = Navigator.of(context);
    if (note.archivedAt == null) {
      await NoteActions.archive(context, ref, note);
    } else {
      await ref.read(noteRepositoryProvider).unarchive(note.id);
    }
    navigator.maybePop();
  }

  /// Löschen ohne Rückfrage – dafür mit „Rückgängig“ in der Meldung.
  Future<void> _delete(NoteRow note) async {
    final navigator = Navigator.of(context);
    await NoteActions.delete(context, ref, note);
    navigator.maybePop();
  }

  Future<void> _addImages(Future<List<PreparedImage>> Function() load) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(attachmentRepositoryProvider);
    setState(() => _loadingImages++);
    try {
      for (final image in await load()) {
        await repository.add(widget.noteId, image);
      }
    } on Object catch (error) {
      if (messenger != null) showMessage(messenger, describeImageError(error));
    } finally {
      if (mounted) setState(() => _loadingImages--);
    }
  }

  static String _capitalized(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  Future<void> _save(NoteRow note) async {
    final repository = ref.read(noteRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await repository.updateContent(
        note.id,
        title: _titleController.text.trim(),
        body: _bodyController.text,
        tags: _tagsController.text.split(RegExp(r'[\s,]+')),
      );
      if (_type != note.type) {
        await repository.changeType(note.id, _type);
      }
      if (_projectId != note.projectId) {
        await repository.moveToProject(note.id, _projectId);
      }
      if (_type.supportsPriority) {
        await repository.setPriority(note.id, _priority);
      }
      final answer = _answerController.text.trim();
      if (_type.hasAnswer && answer.isNotEmpty && answer != note.answer) {
        await repository.answerQuestion(note.id, answer);
      }
      navigator.maybePop();
    } on NoteEditLockedException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

/// Überschrift über einem Feld – klein und gesperrt, damit sie das Feld
/// ankündigt statt mit ihm zu konkurrieren.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Insets.sm),
    child: SectionLabel(text),
  );
}

/// Ein Typ zur Auswahl – in seiner eigenen Farbe, wenn er gewählt ist.
class _TypeChoice extends StatelessWidget {
  const _TypeChoice({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final NoteType type;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = type.color(theme.colorScheme);
    final enabled = onTap != null;

    return Material(
      color: selected
          ? accent.withValues(alpha: 0.14)
          : theme.colorScheme.surfaceContainer,
      borderRadius: Radii.pillAll,
      child: InkWell(
        borderRadius: Radii.pillAll,
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: Radii.pillAll,
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.45)
                    : context.paper.paperBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  type.icon,
                  size: 15,
                  color: selected ? accent : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  type.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected ? accent : theme.colorScheme.onSurface,
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

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.note,
    required this.type,
    required this.onClose,
  });

  final NoteRow note;
  final NoteType type;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.xl,
        Insets.md,
        Insets.md,
        Insets.md,
      ),
      child: Row(
        children: [
          TypeBadge(type: type, size: 30),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Zettel bearbeiten', style: theme.textTheme.titleSmall),
                const SizedBox(height: 1),
                Text(
                  statusLabel(type, note.status),
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Schließen',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.createdAt});

  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = NoteType.log.color(theme.colorScheme);

    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: Radii.smAll,
        border: Border.all(color: context.paper.paperBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock, size: 18, color: accent),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              'Log-Einträge sind nach 24 Stunden festgeschrieben. '
              'Archivieren und Löschen gehen weiterhin.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Priorität zur Auswahl – mit Pfeil, in ihrer Farbe, wenn gewählt.
class _PriorityChoice extends StatelessWidget {
  const _PriorityChoice({
    required this.type,
    required this.priority,
    required this.selected,
    required this.onTap,
  });

  final NoteType type;
  final NotePriority priority;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = priority.color(theme.colorScheme);
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.14)
          : theme.colorScheme.surfaceContainer,
      borderRadius: Radii.pillAll,
      child: InkWell(
        borderRadius: Radii.pillAll,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: Radii.pillAll,
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.45)
                  : context.paper.paperBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                priority.icon,
                size: 16,
                color: selected ? accent : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                priorityLabel(type, priority),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? accent : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewToggle extends StatelessWidget {
  const _PreviewToggle({required this.preview, required this.onChanged});

  final bool preview;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => onChanged(!preview),
      icon: Icon(
        preview ? Icons.edit_outlined : Icons.visibility_outlined,
        size: 16,
      ),
      label: Text(preview ? 'Bearbeiten' : 'Vorschau'),
    );
  }
}

/// Die Bilder des Zettels: ansehen, entfernen, dazulegen.
///
/// Anders als der Text werden Bilder sofort gespeichert – ein Bild ist kein
/// Entwurf, und „Abbrechen“ soll nicht heißen, dass es wieder verschwindet.
class _ImagesField extends ConsumerWidget {
  const _ImagesField({
    required this.noteId,
    required this.loading,
    required this.onAdd,
  });

  final String noteId;
  final int loading;
  final Future<void> Function(Future<List<PreparedImage>> Function() load)
  onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attachments =
        ref.watch(noteAttachmentsProvider(noteId)).value ?? const [];
    final repository = ref.read(attachmentRepositoryProvider);
    const size = 84.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(
          attachments.isEmpty ? 'Bilder' : 'Bilder (${attachments.length})',
        ),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (var i = 0; i < attachments.length; i++)
              AttachmentThumb(
                attachment: attachments[i],
                size: size,
                onTap: () => showImageViewer(context, attachments, i),
                onRemove: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  final id = attachments[i].id;
                  await repository.delete(id);
                  if (messenger != null) {
                    showUndoSnackBar(
                      messenger,
                      'Bild entfernt',
                      onUndo: () => repository.restore(id),
                    );
                  }
                },
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
            _AddImageTile(
              size: size,
              onPick: () => onAdd(ImageInput.pick),
              onCamera: ImageInput.hasCamera
                  ? () => onAdd(() async => [?await ImageInput.camera()])
                  : null,
              onPaste: ImageInput.hasClipboardImages
                  ? () => onAdd(ImageInput.fromClipboard)
                  : null,
            ),
          ],
        ),
        if (ImageInput.supportsDrop)
          Padding(
            padding: const EdgeInsets.only(top: Insets.xs),
            child: Text(
              'Auch per Hineinziehen oder aus der Zwischenablage.',
              style: theme.textTheme.labelSmall,
            ),
          ),
      ],
    );
  }
}

class _AddImageTile extends StatelessWidget {
  const _AddImageTile({
    required this.size,
    required this.onPick,
    this.onCamera,
    this.onPaste,
  });

  final double size;
  final VoidCallback onPick;
  final VoidCallback? onCamera;
  final VoidCallback? onPaste;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = [
      if (onCamera != null)
        MenuItemButton(
          leadingIcon: const Icon(Icons.photo_camera_outlined, size: 18),
          onPressed: onCamera,
          child: const Text('Foto aufnehmen'),
        ),
      if (onPaste != null)
        MenuItemButton(
          leadingIcon: const Icon(Icons.content_paste_rounded, size: 18),
          onPressed: onPaste,
          child: const Text('Aus der Zwischenablage'),
        ),
    ];

    Widget tile(VoidCallback onTap) => Tooltip(
      message: 'Bild hinzufügen',
      child: InkWell(
        borderRadius: Radii.smAll,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: Radii.smAll,
            border: Border.all(color: scheme.outline.withValues(alpha: 0.5)),
          ),
          child: Icon(
            Icons.add_photo_alternate_outlined,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    if (extra.isEmpty) return tile(onPick);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.photo_library_outlined, size: 18),
          onPressed: onPick,
          child: const Text('Bild auswählen'),
        ),
        ...extra,
      ],
      builder: (context, controller, _) => tile(
        () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// Kopiert Text in die Zwischenablage und sagt kurz Bescheid.
Future<void> copyToClipboard(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger.showSnackBar(
    const SnackBar(content: Text('Kopiert'), duration: Duration(seconds: 1)),
  );
}
