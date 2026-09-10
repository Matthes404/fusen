import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../palette.dart';
import '../theme.dart';
import '../tokens.dart';

/// Zeigt den Zetteltext als Markdown – Code, Listen und Links.
class MarkdownText extends StatelessWidget {
  const MarkdownText(
    this.data, {
    super.key,
    this.style,
    this.selectable = true,
  });

  final String data;
  final TextStyle? style;

  /// Auf einem Zettel in der Liste steht die Auswahl im Weg: sie schluckt
  /// den Tipp, mit dem man den Zettel öffnet. Zum Kopieren gibt es den
  /// Eintrag im Menü, und im Editor ist der Text ohnehin auswählbar.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.paper;
    final base = style ?? theme.textTheme.bodyMedium;
    final codeSurface = scheme.onSurface.withValues(
      alpha: theme.brightness == Brightness.light ? 0.05 : 0.09,
    );

    return MarkdownBody(
      data: data,
      selectable: selectable,
      onTapLink: (text, href, title) => _open(href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        h1: theme.textTheme.titleLarge,
        h2: theme.textTheme.titleMedium,
        h3: theme.textTheme.titleSmall,
        h4: theme.textTheme.titleSmall,
        h5: theme.textTheme.labelLarge,
        h6: theme.textTheme.labelLarge,
        strong: base?.copyWith(fontWeight: FontWeight.w700),
        em: base?.copyWith(fontStyle: FontStyle.italic),
        a: base?.copyWith(
          color: scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary.withValues(alpha: 0.4),
        ),
        code: base?.copyWith(
          fontFamily: monoFamily,
          fontSize: (base.fontSize ?? 15) - 1.5,
          letterSpacing: 0,
          backgroundColor: Colors.transparent,
        ),
        codeblockPadding: const EdgeInsets.all(Insets.md),
        codeblockDecoration: BoxDecoration(
          color: codeSurface,
          borderRadius: Radii.smAll,
          border: Border.all(color: tokens.hairline),
        ),
        // Zitate bekommen einen Rand statt einer Fläche – das liest sich
        // ruhiger, wenn mehrere davon untereinander stehen.
        blockquotePadding: const EdgeInsets.fromLTRB(Insets.md, 2, 0, 2),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: scheme.primary.withValues(alpha: 0.45),
              width: 3,
            ),
          ),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.hairline)),
        ),
        // Der Zettel ist die Einheit, nicht das Dokument: kein Platz
        // oberhalb des ersten Absatzes.
        blockSpacing: Insets.sm,
        listIndent: 20,
        listBulletPadding: const EdgeInsets.only(right: Insets.sm),
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
