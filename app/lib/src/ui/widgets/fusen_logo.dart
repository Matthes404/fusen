import 'dart:math' as math;
import 'dart:ui' as ui;

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

/// Hintergrund des App-Symbols: Petrol. Gegen das Gelb des Zettels ist das
/// der stärkste Kontrast, der noch warm wirkt – und auf einem Startbildschirm
/// voller blauer und weißer Symbole fällt es auf.
const List<Color> fusenIconBackground = [Color(0xFF1F6F66), Color(0xFF0E3F3A)];

/// Das App-Symbol: ein gelber Zettel mit Klebestreifen, leicht schräg
/// aufgeklebt.
///
/// Dieselbe Idee wie [FusenLogo], nur mit mehr Ausstattung – das Symbol
/// steht groß auf dem Startbildschirm, das Logo klein in der Seitenspalte.
/// `tool/app_icons.dart` rendert daraus die Symbole aller Plattformen.
class FusenIconPainter extends CustomPainter {
  const FusenIconPainter({
    this.background = true,
    this.monochrome = false,
    this.scale = 1,
  });

  /// Ohne Hintergrund bleibt nur der Zettel – für die Vordergrund-Ebene
  /// adaptiver Android-Symbole.
  final bool background;

  /// Nur die Form, einfarbig weiß, die Zeilen ausgestanzt – für Androids
  /// eingefärbte Symbole.
  final bool monochrome;

  /// Größe des Zettels relativ zur Fläche. Adaptive Symbole brauchen Rand,
  /// weil das System sie beschneidet.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (background && !monochrome) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(s, s),
            fusenIconBackground,
          ),
      );
    }

    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.rotate(-6 * math.pi / 180);

    final w = s * 0.56 * scale;
    final h = w;
    final fold = w * 0.26;
    final r = w * 0.05;
    final left = -w / 2;
    final top = -h / 2 + s * 0.02 * scale;
    final note = Path()
      ..moveTo(left + r, top)
      ..lineTo(left + w - r, top)
      ..quadraticBezierTo(left + w, top, left + w, top + r)
      ..lineTo(left + w, top + h - fold)
      ..lineTo(left + w - fold, top + h)
      ..lineTo(left + r, top + h)
      ..quadraticBezierTo(left, top + h, left, top + h - r)
      ..lineTo(left, top + r)
      ..quadraticBezierTo(left, top, left + r, top)
      ..close();
    final flap = Path()
      ..moveTo(left + w - fold, top + h - fold)
      ..lineTo(left + w, top + h - fold)
      ..lineTo(left + w - fold, top + h)
      ..close();
    final lineHeight = h * 0.075;
    final lines = [
      for (final (y, width) in const [(0.36, 0.62), (0.52, 0.5), (0.68, 0.34)])
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left + w * 0.16, top + h * y, w * width, lineHeight),
          Radius.circular(lineHeight / 2),
        ),
    ];

    if (monochrome) {
      canvas.saveLayer(Offset(-s, -s) & Size(2 * s, 2 * s), Paint());
      canvas.drawPath(note, Paint()..color = Colors.white);
      final punch = Paint()..blendMode = BlendMode.clear;
      for (final line in lines) {
        canvas.drawRRect(line, punch);
      }
      canvas.drawPath(
        flap,
        Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.02,
      );
      canvas.restore();
      canvas.restore();
      return;
    }

    canvas.drawPath(
      note.shift(Offset(s * 0.012 * scale, s * 0.03 * scale)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03 * scale),
    );
    canvas.drawPath(
      note,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, top),
          Offset(0, top + h),
          const [Color(0xFFFFD35C), Color(0xFFFFBE2E)],
        ),
    );
    canvas.drawPath(
      flap.shift(Offset(-s * 0.004 * scale, -s * 0.004 * scale)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.008 * scale),
    );
    canvas.drawPath(flap, Paint()..color = const Color(0xFFE09A12));

    final ink = Paint()..color = const Color(0x806B4508);
    for (final line in lines) {
      canvas.drawRRect(line, ink);
    }

    // Der Klebestreifen, wie oben an der Schnelleingabe.
    canvas.translate(0, top + s * 0.005 * scale);
    canvas.rotate(4 * math.pi / 180);
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: w * 0.42,
        height: s * 0.075 * scale,
      ),
      Paint()..color = const Color(0xB8FFF4DA),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(FusenIconPainter old) =>
      old.background != background ||
      old.monochrome != monochrome ||
      old.scale != scale;
}
