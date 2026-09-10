import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_type.dart';
import '../../ui/note_style.dart';
import 'capture_syntax.dart';

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
    barrierColor: Colors.black.withValues(alpha: 0.35),
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

class _CaptureDialogState extends ConsumerState<CaptureDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  CaptureDraft _draft = const CaptureDraft(body: '');
  String? _target;
  bool _targetChosen = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _target = widget.projectId;
    _targetChosen = widget.projectId != null;
    _controller.addListener(_reparse);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _reparse() {
    final next = parseCapture(_controller.text);
    setState(() => _draft = next);
  }

  /// Das Projekt, das die App vorschlägt, solange nichts gewählt wurde.
  String? get _suggestion => ref.read(lastProjectProvider);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects = ref.watch(projectsProvider).value ?? const [];
    final effectiveType = _draft.type ?? widget.type ?? NoteType.idea;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 80),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  minLines: 1,
                  maxLines: 8,
                  style: theme.textTheme.titleMedium,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Was ist los? @projekt !typ #tag',
                  ),
                ),
              ),
            ),
            _Preview(
              draft: _draft,
              type: effectiveType,
              target: _resolveTargetName(projects),
              suggestion: _targetChosen || _draft.projectQuery != null
                  ? null
                  : _projectName(projects, _suggestion),
              onAcceptSuggestion: _acceptSuggestion,
              onPickTarget: () => _pickTarget(projects),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Enter speichert · Shift+Enter neue Zeile · Esc bricht ab',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _draft.isEmpty || _saving ? null : _save,
                    child: const Text('Ablegen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.enter && !shift) {
      if (!_draft.isEmpty) _save();
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
    final picked = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Wohin?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Inbox'),
          ),
          for (final project in projects)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(project.id),
              child: Text(project.name),
            ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _target = picked;
      _targetChosen = true;
    });
    _focusNode.requestFocus();
  }

  Future<void> _save() async {
    if (_saving || _draft.isEmpty) return;
    setState(() => _saving = true);

    final navigator = Navigator.of(context);
    final projects = ref.read(projectRepositoryProvider);
    final notes = ref.read(noteRepositoryProvider);

    // Ein getipptes @projekt sticht alles andere; existiert es noch nicht,
    // wird es angelegt – lieber unsauber gespeichert als gar nicht.
    String? projectId;
    final query = _draft.projectQuery;
    if (query != null) {
      projectId = (await projects.findOrCreate(query)).id;
    } else if (_targetChosen) {
      projectId = _target;
    }

    await notes.create(
      projectId: projectId,
      type: _draft.type ?? widget.type ?? NoteType.idea,
      body: _draft.body,
      tags: _draft.tags,
    );

    ref.read(lastProjectProvider.notifier).remember(projectId);
    navigator.pop(projectId);
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.draft,
    required this.type,
    required this.target,
    required this.suggestion,
    required this.onAcceptSuggestion,
    required this.onPickTarget,
  });

  final CaptureDraft draft;
  final NoteType type;
  final String target;
  final String? suggestion;
  final VoidCallback onAcceptSuggestion;
  final VoidCallback onPickTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ActionChip(
            avatar: const Icon(Icons.folder_outlined, size: 16),
            label: Text(target),
            onPressed: onPickTarget,
          ),
          Chip(
            avatar: Icon(
              type.icon,
              size: 16,
              color: type.color(theme.colorScheme),
            ),
            label: Text(type.label),
          ),
          for (final tag in draft.tags) Chip(label: Text('#$tag')),
          if (suggestion != null)
            ActionChip(
              avatar: const Icon(Icons.keyboard_tab, size: 16),
              label: Text('Tab → $suggestion'),
              onPressed: onAcceptSuggestion,
            ),
        ],
      ),
    );
  }
}
