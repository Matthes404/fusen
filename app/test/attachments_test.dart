import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fusen/src/core/clock.dart';
import 'package:fusen/src/data/attachments/image_prep.dart';
import 'package:fusen/src/data/db/database.dart';
import 'package:fusen/src/data/repositories/attachment_repository.dart';
import 'package:image/image.dart' as img;

Uint8List _png(int width, int height, {int alpha = 255}) {
  final image = img.Image(width: width, height: height, numChannels: 4)
    ..clear(img.ColorRgba8(200, 180, 40, alpha));
  return img.encodePng(image);
}

/// Rauschen lässt sich nicht komprimieren – so entsteht eine große Datei,
/// ohne dass das Bild riesig sein muss.
Uint8List _noisyPng(int size) {
  final random = Random(7);
  final image = img.Image(width: size, height: size);
  for (final pixel in image) {
    pixel
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  return img.encodePng(image, level: 1);
}

void main() {
  group('Format erkennen', () {
    test('an den ersten Bytes', () {
      expect(sniffImage(_png(2, 2)), ImageKind.png);
      expect(
        sniffImage(img.encodeJpg(img.Image(width: 2, height: 2))),
        ImageKind.jpeg,
      );
      expect(
        sniffImage(img.encodeGif(img.Image(width: 2, height: 2))),
        ImageKind.gif,
      );
      expect(
        sniffImage(img.encodeBmp(img.Image(width: 2, height: 2))),
        ImageKind.bmp,
      );
      expect(
        sniffImage(
          Uint8List.fromList([
            ...'RIFF'.codeUnits,
            0,
            0,
            0,
            0,
            ...'WEBP'.codeUnits,
          ]),
        ),
        ImageKind.webp,
      );
      expect(
        sniffImage(
          Uint8List.fromList([0, 0, 0, 24, ...'ftypheic'.codeUnits, 0, 0]),
        ),
        ImageKind.heic,
      );
    });

    test('Text ist kein Bild', () {
      expect(sniffImage(Uint8List.fromList('Hallo'.codeUnits)), isNull);
      expect(
        () => prepareImageSync(Uint8List.fromList('Hallo'.codeUnits)),
        throwsA(isA<UnsupportedImageException>()),
      );
    });
  });

  group('Aufbereiten', () {
    test('ein kleines Bild bleibt, wie es ist', () {
      final input = _png(640, 480);

      final prepared = prepareImageSync(input, fileName: 'Skizze.png');

      expect(prepared.bytes, same(input));
      expect(prepared.mimeType, 'image/png');
      expect(prepared.fileName, 'Skizze.png');
      expect((prepared.width, prepared.height), (640, 480));
    });

    test('ein sehr breites Bild wird auf 2048 Pixel verkleinert', () {
      final prepared = prepareImageSync(_png(4000, 1000), fileName: 'weit.png');

      expect((prepared.width, prepared.height), (imageMaxEdge, 512));
      // Eine flache Fläche bleibt als PNG klein genug.
      expect(prepared.mimeType, 'image/png');
      final decoded = img.decodePng(prepared.bytes)!;
      expect((decoded.width, decoded.height), (imageMaxEdge, 512));
    });

    test('hochkant wird an der Höhe gemessen', () {
      final prepared = prepareImageSync(_png(1000, 3000));

      expect((prepared.width, prepared.height), (683, imageMaxEdge));
    });

    test('ein riesiges Foto ohne Transparenz wird JPEG', () {
      final input = _noisyPng(1300);
      expect(input.length, greaterThan(imageShrinkBytes));

      final prepared = prepareImageSync(input, fileName: 'Foto.png');

      expect(prepared.mimeType, 'image/jpeg');
      expect(prepared.fileName, 'Foto.jpg');
      expect(prepared.bytes.length, lessThan(input.length));
      expect(sniffImage(prepared.bytes), ImageKind.jpeg);
    });

    test('Durchsichtiges bleibt PNG', () {
      final prepared = prepareImageSync(_png(3000, 20, alpha: 0));

      expect(prepared.mimeType, 'image/png');
      expect(prepared.width, imageMaxEdge);
    });

    test('ein gedrehtes Handyfoto meldet die angezeigten Maße', () {
      final photo = img.Image(width: 40, height: 20)
        ..exif.imageIfd.orientation = 6;
      final prepared = prepareImageSync(img.encodeJpg(photo));

      expect((prepared.width, prepared.height), (20, 40));
    });

    test('eingefügte Bilder heißen nach dem Zeitpunkt', () {
      final prepared = prepareImageSync(
        _png(10, 10),
        now: DateTime(2026, 9, 24, 8, 5, 3),
      );

      expect(prepared.fileName, 'Bild 2026-09-24 08.05.03.png');
    });

    test('was zu groß ist, wird abgelehnt', () {
      final huge = Uint8List(imageMaxInputBytes + 1)
        ..setAll(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

      expect(
        () => prepareImageSync(huge),
        throwsA(isA<ImageTooLargeException>()),
      );
    });

    test('ein Bildschirmfoto aus der Windows-Zwischenablage wird PNG', () {
      // Windows liefert Bildschirmfotos als BMP. Gespeichert werden sollen
      // sie wie jedes Bildschirmfoto: als PNG, damit Schrift scharf bleibt.
      final bmp = Uint8List.fromList(
        img.encodeBmp(
          img.Image(width: 640, height: 400)
            ..clear(img.ColorRgb8(250, 250, 250)),
        ),
      );

      final prepared = prepareImageSync(bmp);

      expect(prepared.mimeType, 'image/png');
      expect(prepared.width, 640);
      expect(prepared.bytes.length, lessThan(bmp.length));
    });

    test('für Bitmaps gilt eine höhere Grenze', () {
      // Unkomprimiert hat schon ein Foto zweier 4K-Bildschirme über 60 MB.
      final big = Uint8List(imageMaxInputBytes + 1)..setAll(0, 'BM'.codeUnits);
      final tooBig = Uint8List(imageMaxBitmapBytes + 1)
        ..setAll(0, 'BM'.codeUnits);

      expect(
        () => prepareImageSync(big),
        throwsA(isNot(isA<ImageTooLargeException>())),
      );
      expect(
        () => prepareImageSync(tooBig),
        throwsA(isA<ImageTooLargeException>()),
      );
    });

    test('läuft auch im eigenen Isolate', () async {
      final prepared = await prepareImage(_png(3000, 100));

      expect(prepared.width, imageMaxEdge);
    });
  });

  group('AttachmentRepository', () {
    late FusenDatabase db;
    late FixedClock clock;
    late AttachmentRepository repository;

    PreparedImage image([List<int> bytes = const [1, 2, 3]]) => PreparedImage(
      bytes: Uint8List.fromList(bytes),
      mimeType: 'image/png',
      fileName: 'a.png',
      width: 3,
      height: 1,
    );

    setUp(() {
      db = FusenDatabase.memory();
      clock = FixedClock(DateTime.utc(2026, 9, 1, 12));
      repository = AttachmentRepository(db, deviceId: 'gerät', clock: clock);
    });

    tearDown(() => db.close());

    test('hängt ein Bild an und liefert die Daten', () async {
      final added = await repository.add('zettel', image());

      final listed = await repository.forNote('zettel');
      expect(listed.map((a) => a.id), [added.id]);
      expect(listed.single.hasData, isTrue);
      expect(listed.single.uploaded, isFalse);
      expect(listed.single.pendingSync, isTrue);
      expect(listed.single.byteSize, 3);
      expect(await repository.readBytes(added.id), [1, 2, 3]);
      expect(await repository.watchBytes(added.id).first, [1, 2, 3]);
    });

    test('behält die Reihenfolge des Anhängens', () async {
      final first = await repository.add('zettel', image());
      final second = await repository.add('zettel', image());

      expect((await repository.forNote('zettel')).map((a) => a.id), [
        first.id,
        second.id,
      ]);
    });

    test('Entfernen ist ein Tombstone und lässt sich zurücknehmen', () async {
      final added = await repository.add('zettel', image());

      await repository.delete(added.id);
      expect(await repository.forNote('zettel'), isEmpty);
      // Die Daten bleiben, damit „Rückgängig“ funktioniert.
      expect(await repository.readBytes(added.id), [1, 2, 3]);

      await repository.restore(added.id);
      expect((await repository.forNote('zettel')).single.id, added.id);
    });

    test('räumt Daten erst nach einer Weile weg', () async {
      final kept = await repository.add('zettel', image());
      final removed = await repository.add('zettel', image([4, 5]));
      final recent = await repository.add('zettel', image([6]));
      await repository.delete(removed.id);
      clock.advance(const Duration(days: 8));
      await repository.delete(recent.id);

      final purged = await repository.purgeDeletedData();

      expect(purged, 1);
      expect(await repository.readBytes(removed.id), isNull);
      expect((await repository.findById(removed.id))!.hasData, isFalse);
      expect(await repository.readBytes(recent.id), [6]);
      expect(await repository.readBytes(kept.id), [1, 2, 3]);
    });
  });
}
