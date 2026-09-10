import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_type.dart';
import '../../ui/note_style.dart';
import '../../ui/palette.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/keycap.dart';
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
    final tokens = context.paper;
    final projects = ref.watch(projectsProvider).value ?? const [];
    final effectiveType = _draft.type ?? widget.type ?? NoteType.idea;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: 72,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.paper,
            borderRadius: Radii.lgAll,
            border: Border.all(color: tokens.paperBorder),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.xl,
                    Insets.xl,
                    Insets.xl,
                    Insets.lg,
                  ),
                  child: Focus(
                    onKeyEvent: _onKey,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 8,
                      // Größer als sonst: das Feld ist der ganze Zweck
                      // dieses Fensters.
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
                        hintText: 'Was ist los? @projekt !typ #tag',
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
                Divider(height: 1, color: tokens.hairline),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.lg,
                    Insets.md,
                    Insets.md,
                    Insets.md,
                  ),
                  child: Row(
                    children: [
                      const Expanded(child: _Shortcuts()),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Abbrechen'),
                      ),
                      const SizedBox(width: Insets.sm),
                      FilledButton(
                        style: brandButtonStyle(),
                        onPressed: _draft.isEmpty || _saving ? null : _save,
                        child: const Text('Ablegen'),
                      ),
                    ],
                  ),
                ),
              ],
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
            onTap: () => Navigator.of(context).pop(null),
          ),
          for (final project in projects)
            _TargetOption(
              label: project.name,
              color: Color(project.color),
              onTap: () => Navigator.of(context).pop(project.id),
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

/// Was die App aus dem Getippten gemacht hat – Ziel, Typ, Schlagworte.
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
          _Pill(icon: type.icon, label: type.label, color: type.color(scheme)),
          for (final tag in draft.tags) _Pill(label: '#$tag'),
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

/// Die drei Tasten, die die Schnelleingabe ausmachen.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: Insets.md,
      runSpacing: Insets.xs,
      children: [
        KeyHint(keys: ['Enter'], text: 'speichert'),
        KeyHint(keys: ['Shift', 'Enter'], text: 'neue Zeile'),
        KeyHint(keys: ['Esc'], text: 'bricht ab'),
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
