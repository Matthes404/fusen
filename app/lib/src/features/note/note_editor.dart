import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../data/repositories/note_repository.dart';
import '../../ui/note_style.dart';
import '../../ui/palette.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/labels.dart';

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
              const SizedBox(height: Insets.xl),
              const _FieldLabel('Projekt'),
              DropdownButtonFormField<String?>(
                initialValue: _projectId,
                items: [
                  const DropdownMenuItem<String?>(child: Text('Inbox')),
                  for (final project in projects)
                    DropdownMenuItem<String?>(
                      value: project.id,
                      child: Text(project.name),
                    ),
                ],
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
              TextField(
                controller: _bodyController,
                enabled: !locked,
                minLines: 5,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'Text (Markdown)',
                  alignLabelWithHint: true,
                ),
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
              if (_type.supportsPriority) ...[
                const SizedBox(height: Insets.xl),
                const _FieldLabel('Priorität'),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final priority in NotePriority.displayOrder)
                      ChoiceChip(
                        label: Text(priority.label),
                        selected: _priority == priority,
                        onSelected: locked
                            ? null
                            : (selected) => setState(
                                () => _priority = selected ? priority : null,
                              ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: Insets.xl),
              const _FieldLabel('Status'),
              Wrap(
                spacing: 6,
                children: [
                  for (final status in NoteStatus.values)
                    ChoiceChip(
                      label: Text(statusLabel(_type, status)),
                      selected: note.status == status,
                      onSelected: (_) => _setStatus(status),
                    ),
                ],
              ),
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
    final repository = ref.read(noteRepositoryProvider);
    if (note.archivedAt == null) {
      await repository.archive(note.id);
    } else {
      await repository.unarchive(note.id);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _delete(NoteRow note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zettel löschen?'),
        content: const Text(
          'Der Zettel verschwindet auf allen Geräten. '
          'Zum Aufheben lieber archivieren.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(noteRepositoryProvider).delete(note.id);
    if (mounted) Navigator.of(context).maybePop();
  }

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

/// Kopiert Text in die Zwischenablage und sagt kurz Bescheid.
Future<void> copyToClipboard(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger.showSnackBar(
    const SnackBar(content: Text('Kopiert'), duration: Duration(seconds: 1)),
  );
}
