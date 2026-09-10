import 'package:flutter/material.dart';

import '../tokens.dart';

/// Die Bildmarke: ein Zettel mit umgeknickter Ecke.
///
/// Gezeichnet statt als Bild eingebunden – so trägt sie keine Datei mit sich
/// herum und passt sich der Größe und dem Farbschema an.
class FusenLogo extends StatelessWidget {
  const FusenLogo({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _FusenLogoPainter(
          color: color ?? scheme.primary,
          ink: scheme.onSurface,
        ),
      ),
    );
  }
}

class _FusenLogoPainter extends CustomPainter {
  const _FusenLogoPainter({required this.color, required this.ink});

  final Color color;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fold = w * 0.34;
    final r = w * 0.16;

    // Der Zettel: rechteckig, unten rechts ist die Ecke weg.
    final body = Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, h - fold)
      ..lineTo(w - fold, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
    canvas.drawPath(body, Paint()..color = color);

    // Die Rückseite des umgeknickten Zipfels – etwas dunkler.
    final flap = Path()
      ..moveTo(w - fold, h - fold)
      ..lineTo(w, h - fold)
      ..lineTo(w - fold, h)
      ..close();
    canvas.drawPath(
      flap,
      Paint()..color = Color.alphaBlend(ink.withValues(alpha: 0.32), color),
    );

    // Zwei Zeilen „Schrift“, damit die Marke auch groß etwas zeigt.
    final line = Paint()..color = ink.withValues(alpha: 0.36);
    final lineHeight = h * 0.08;
    for (final (top, width) in [(0.3, 0.52), (0.5, 0.34)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.2, h * top, w * width, lineHeight),
          Radius.circular(lineHeight / 2),
        ),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_FusenLogoPainter old) =>
      old.color != color || old.ink != ink;
}

/// Bildmarke plus Schriftzug – steht einmal im Kopf der Seitenspalte.
class FusenWordmark extends StatelessWidget {
  const FusenWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const FusenLogo(size: 22),
        const SizedBox(width: Insets.sm),
        Text(
          'Fusen',
          style: theme.textTheme.titleLarge?.copyWith(letterSpacing: -0.4),
        ),
      ],
    );
  }
}
