import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../palette.dart';
import '../tokens.dart';
import 'undo.dart';

/// Ein Bild als Vorschau.
///
/// Lädt seine Daten selbst. Solange sie fehlen – nach einem Abgleich kennt
/// das Gerät das Bild oft schon, hat es aber noch nicht heruntergeladen –,
/// steht ein Platzhalter da.
class AttachmentThumb extends ConsumerWidget {
  const AttachmentThumb({
    required this.attachment,
    super.key,
    this.size = 64,
    this.onTap,
    this.onRemove,
  });

  final AttachmentRow attachment;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = ref.watch(attachmentBytesProvider(attachment.id)).value;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final target = (size * dpr).round();

    Widget placeholder(IconData icon) => ColoredBox(
      color: scheme.surfaceContainerHigh,
      child: Center(
        child: Icon(icon, size: size * 0.34, color: scheme.onSurfaceVariant),
      ),
    );

    // Für „cover“ die kürzere Seite auf die Kachelgröße dekodieren – sonst
    // wird ein Querformat erst klein dekodiert und dann unscharf gestreckt.
    final landscape = (attachment.width ?? 1) >= (attachment.height ?? 1);
    final image = bytes == null
        ? placeholder(Icons.cloud_download_outlined)
        : Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: landscape ? null : target,
            cacheHeight: landscape ? target : null,
            errorBuilder: (_, _, _) => placeholder(Icons.broken_image_outlined),
          );

    return Semantics(
      image: true,
      label: attachment.fileName,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: Radii.smAll,
                border: Border.all(color: context.paper.paperBorder),
              ),
              position: DecorationPosition.foreground,
              child: ClipRRect(
                borderRadius: Radii.smAll,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    // Die Welle beim Antippen liegt über dem Bild, nicht
                    // unsichtbar dahinter.
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(onTap: onTap),
                    ),
                  ],
                ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 3,
                right: 3,
                child: _RemoveButton(onPressed: onRemove!),
              ),
          ],
        ),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Bild entfernen',
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Die Bilder eines Zettels als Reihe kleiner Vorschauen – auf der Karte.
class AttachmentStrip extends ConsumerWidget {
  const AttachmentStrip({
    required this.noteId,
    super.key,
    this.size = 56,
    this.maxVisible = 4,
  });

  final String noteId;
  final double size;
  final int maxVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments =
        ref.watch(noteAttachmentsProvider(noteId)).value ?? const [];
    if (attachments.isEmpty) return const SizedBox.shrink();

    final visible = attachments.take(maxVisible).toList();
    final hidden = attachments.length - visible.length;

    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < visible.length; i++)
            Stack(
              children: [
                AttachmentThumb(
                  attachment: visible[i],
                  size: size,
                  onTap: () => showImageViewer(context, attachments, i),
                ),
                if (hidden > 0 && i == visible.length - 1)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: Radii.smAll,
                        ),
                        child: Text(
                          '+$hidden',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Zeigt Bilder groß: wischen oder Pfeiltasten zum Blättern, ziehen und
/// spreizen zum Zoomen.
Future<void> showImageViewer(
  BuildContext context,
  List<AttachmentRow> attachments,
  int initialIndex, {
  bool allowDelete = true,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => _ImageViewer(
      attachments: attachments,
      initialIndex: initialIndex,
      allowDelete: allowDelete,
      messenger: messenger,
    ),
  );
}

class _ImageViewer extends ConsumerStatefulWidget {
  const _ImageViewer({
    required this.attachments,
    required this.initialIndex,
    required this.allowDelete,
    required this.messenger,
  });

  final List<AttachmentRow> attachments;
  final int initialIndex;
  final bool allowDelete;
  final ScaffoldMessengerState? messenger;

  @override
  ConsumerState<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends ConsumerState<_ImageViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.attachments.length) return;
    _pages.animateToPage(next, duration: Motion.base, curve: Motion.standard);
  }

  Future<void> _delete() async {
    final attachment = widget.attachments[_index];
    final repository = ref.read(attachmentRepositoryProvider);
    await repository.delete(attachment.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    final messenger = widget.messenger;
    if (messenger != null) {
      showUndoSnackBar(
        messenger,
        'Bild entfernt',
        onUndo: () => repository.restore(attachment.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachments[_index];
    final count = widget.attachments.length;
    const light = Colors.white;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pages,
              itemCount: count,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) =>
                  _ViewerPage(attachment: widget.attachments[index]),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Insets.sm),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Schließen',
                      color: light,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Text(
                        count > 1
                            ? '${attachment.fileName}  ·  ${_index + 1} / $count'
                            : attachment.fileName,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: light),
                      ),
                    ),
                    if (widget.allowDelete)
                      IconButton(
                        tooltip: 'Bild entfernen',
                        color: light,
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: _delete,
                      ),
                  ],
                ),
              ),
            ),
            if (count > 1) ...[
              _Arrow(
                alignment: Alignment.centerLeft,
                icon: Icons.chevron_left_rounded,
                onPressed: _index > 0 ? () => _go(-1) : null,
              ),
              _Arrow(
                alignment: Alignment.centerRight,
                icon: Icons.chevron_right_rounded,
                onPressed: _index < count - 1 ? () => _go(1) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ViewerPage extends ConsumerWidget {
  const _ViewerPage({required this.attachment});

  final AttachmentRow attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(attachmentBytesProvider(attachment.id)).value;
    if (bytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return InteractiveViewer(
      maxScale: 6,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            64,
            Insets.lg,
            Insets.lg,
          ),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.alignment,
    required this.icon,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(Insets.sm),
        child: IconButton.filledTonal(
          iconSize: 28,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
