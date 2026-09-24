// Erzeugt die App-Symbole aller Plattformen aus `FusenIconPainter`.
//
//   cd app && flutter test tool/app_icons.dart
//
// Läuft als Widget-Test, weil Flutter dann selbst zeichnet – jede Größe wird
// aus der Vektorvorlage neu gerendert statt aus einem großen Bild verkleinert.
// Die Ergebnisse liegen im Repository; neu erzeugen muss sie nur, wer das
// Symbol ändert.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fusen/src/ui/widgets/fusen_logo.dart';
import 'package:image/image.dart' as img;

/// Wie das Symbol auf einer Plattform eingefasst wird.
enum _Frame {
  /// Randlos und quadratisch – iOS legt seine eigene Maske darüber.
  square,

  /// Abgerundetes Quadrat mit etwas Rand: Android (alt), Windows, Linux.
  rounded,

  /// Die Kachel nach Apples Raster für macOS: 824 von 1024 Pixeln, mit
  /// Schatten.
  macos,
}

class _Framed extends CustomPainter {
  const _Framed(this.frame, this.art);

  final _Frame frame;
  final CustomPainter art;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    switch (frame) {
      case _Frame.square:
        art.paint(canvas, size);
      case _Frame.rounded:
        final inset = s * 0.04;
        final tile = RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, inset, s - 2 * inset, s - 2 * inset),
          Radius.circular(s * 0.2),
        );
        _drawTile(canvas, tile);
      case _Frame.macos:
        final inset = s * 100 / 1024;
        final tile = RRect.fromRectAndRadius(
          Rect.fromLTWH(inset, inset, s - 2 * inset, s - 2 * inset),
          Radius.circular(s * 185 / 1024),
        );
        canvas.drawRRect(
          tile.shift(Offset(0, s * 10 / 1024)),
          Paint()
            ..color = const Color(0x4D000000)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 12 / 1024),
        );
        _drawTile(canvas, tile);
    }
  }

  void _drawTile(Canvas canvas, RRect tile) {
    canvas.save();
    canvas.clipRRect(tile);
    canvas.translate(tile.left, tile.top);
    art.paint(canvas, Size(tile.width, tile.height));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Framed old) => true;
}

Future<img.Image> _render(
  WidgetTester tester,
  int px, {
  _Frame frame = _Frame.rounded,
  CustomPainter art = const FusenIconPainter(),
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: key,
        child: SizedBox.square(
          dimension: px.toDouble(),
          child: CustomPaint(painter: _Framed(frame, art)),
        ),
      ),
    ),
  );
  late img.Image result;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    result = img.decodePng(png!.buffer.asUint8List())!;
  });
  return result;
}

void _write(String path, List<int> bytes) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

void main() {
  testWidgets('App-Symbole erzeugen', (tester) async {
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // --- Android ---------------------------------------------------------
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    const res = 'android/app/src/main/res';
    for (final MapEntry(key: density, value: factor) in densities.entries) {
      _write(
        '$res/mipmap-$density/ic_launcher.png',
        img.encodePng(await _render(tester, (48 * factor).round())),
      );
      // Adaptive Symbole: 108 dp, davon sind nur die inneren 66 dp sicher
      // sichtbar – der Zettel wird entsprechend kleiner.
      final adaptive = (108 * factor).round();
      _write(
        '$res/mipmap-$density/ic_launcher_foreground.png',
        img.encodePng(
          await _render(
            tester,
            adaptive,
            frame: _Frame.square,
            art: const FusenIconPainter(background: false, scale: 0.72),
          ),
        ),
      );
      _write(
        '$res/mipmap-$density/ic_launcher_monochrome.png',
        img.encodePng(
          await _render(
            tester,
            adaptive,
            frame: _Frame.square,
            art: const FusenIconPainter(
              background: false,
              monochrome: true,
              scale: 0.72,
            ),
          ),
        ),
      );
    }

    // --- iOS ---------------------------------------------------------------
    // Ohne Alphakanal: der App Store lehnt durchsichtige Symbole ab.
    const iosSet = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final (points, scale) in const [
      (20.0, 1),
      (20.0, 2),
      (20.0, 3),
      (29.0, 1),
      (29.0, 2),
      (29.0, 3),
      (40.0, 1),
      (40.0, 2),
      (40.0, 3),
      (60.0, 2),
      (60.0, 3),
      (76.0, 1),
      (76.0, 2),
      (83.5, 2),
      (1024.0, 1),
    ]) {
      final name = points == points.roundToDouble()
          ? points.toInt().toString()
          : points.toString();
      final image = await _render(
        tester,
        (points * scale).round(),
        frame: _Frame.square,
      );
      _write(
        '$iosSet/Icon-App-${name}x$name@${scale}x.png',
        img.encodePng(image.convert(numChannels: 3)),
      );
    }

    // --- macOS -------------------------------------------------------------
    const macSet = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
    for (final px in const [16, 32, 64, 128, 256, 512, 1024]) {
      _write(
        '$macSet/app_icon_$px.png',
        img.encodePng(await _render(tester, px, frame: _Frame.macos)),
      );
    }

    // --- Windows -----------------------------------------------------------
    _write(
      'windows/runner/resources/app_icon.ico',
      img.IcoEncoder().encodeImages([
        for (final px in const [16, 20, 24, 32, 40, 48, 64, 96, 128, 256])
          await _render(tester, px),
      ]),
    );

    // --- Linux -------------------------------------------------------------
    // Nach der Anwendungskennung benannt, damit Desktop und Fenster
    // zusammenfinden (siehe linux/packaging).
    for (final px in const [32, 48, 64, 128, 256, 512]) {
      _write(
        'linux/packaging/icons/hicolor/${px}x$px/apps/dev.fusen.fusen.png',
        img.encodePng(await _render(tester, px)),
      );
    }
  });
}
