import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Zeigt den Zetteltext als Markdown – Code, Listen und Links.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = style ?? theme.textTheme.bodyMedium;

    return MarkdownBody(
      data: data,
      selectable: true,
      onTapLink: (text, href, title) => _open(href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        a: base?.copyWith(
          color: scheme.primary,
          decoration: TextDecoration.underline,
        ),
        code: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        // Der Zettel ist die Einheit, nicht das Dokument: kein Platz
        // oberhalb des ersten Absatzes.
        blockSpacing: 6,
        listIndent: 18,
      ),
    );
  }

  Future<void> _open(String? href) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
