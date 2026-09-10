import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../data/repositories/note_repository.dart';
import '../../ui/note_style.dart';

/// Öffnet den Zettel zum Bearbeiten – auf breiten Fenstern als Dialog,
/// auf dem Handy als Blatt von unten.
Future<void> showNoteEditor(BuildContext context, NoteRow note) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: NoteEditor(noteId: note.id),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
    final theme = Theme.of(context);
    final locked = !isContentEditable(note, DateTime.now().toUtc());
    final projects = ref.watch(projectsProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorHeader(
          note: note,
          onClose: () => Navigator.of(context).maybePop(),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (locked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _LockedBanner(createdAt: note.createdAt),
                ),
              Text('Typ', style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final type in NoteType.sectionOrder)
                    ChoiceChip(
                      label: Text(type.label),
                      avatar: Icon(type.icon, size: 16),
                      selected: _type == type,
                      onSelected: locked
                          ? null
                          : (_) => setState(() => _type = type),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Projekt', style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
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
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Titel (optional)',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              TextField(
                controller: _tagsController,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: '#nnue #performance',
                ),
              ),
              if (_type.hasAnswer) ...[
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),
                Text('Priorität', style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
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
              const SizedBox(height: 16),
              Text('Status', style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
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
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
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
              const SizedBox(width: 8),
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

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({required this.note, required this.onClose});

  final NoteRow note;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            note.type.icon,
            size: 20,
            color: note.type.color(theme.colorScheme),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Zettel bearbeiten',
              style: theme.textTheme.titleMedium,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, size: 18),
          const SizedBox(width: 10),
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
