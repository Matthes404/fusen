import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../data/attachments/image_prep.dart';

/// Woher Bilder kommen: Galerie oder Dateiauswahl, Kamera, Zwischenablage,
/// hineingezogene Dateien. Alles endet in [PreparedImage] – verkleinert und
/// bereit für [AttachmentRepository.add].
abstract final class ImageInput {
  static final ImagePicker _picker = ImagePicker();

  /// Kamera gibt es nur auf dem Handy; auf dem Desktop bräuchte
  /// `image_picker` dafür ein eigenes Kamera-Plugin.
  static bool get hasCamera =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Einfügen aus der Zwischenablage lohnt sich vor allem auf dem Desktop –
  /// dort entstehen Bildschirmfotos. Auf dem Handy ist die Galerie der Weg.
  static bool get hasClipboardImages =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  /// Hineinziehen aus dem Dateimanager, nur auf dem Desktop.
  static bool get supportsDrop => hasClipboardImages;

  /// Galerie (Handy) bzw. Dateiauswahl (Desktop), mehrere auf einmal.
  ///
  /// Auf dem Handy verkleinert das System schon beim Auswählen – das spart
  /// den Umweg über den Dart-Decoder. Auf dem Desktop ignoriert
  /// `image_picker` die Angaben, dort übernimmt [prepareImage].
  static Future<List<PreparedImage>> pick() async {
    final files = await _picker.pickMultiImage(
      maxWidth: imageMaxEdge.toDouble(),
      maxHeight: imageMaxEdge.toDouble(),
      imageQuality: 85,
    );
    return _prepareAll(files);
  }

  /// Ein Foto mit der Kamera.
  static Future<PreparedImage?> camera() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: imageMaxEdge.toDouble(),
      maxHeight: imageMaxEdge.toDouble(),
      imageQuality: 85,
    );
    if (file == null) return null;
    return (await _prepareAll([file])).firstOrNull;
  }

  /// Für „Aus der Zwischenablage“: erst im Dateimanager kopierte
  /// Bilddateien, dann ein Bild als Pixel (ein Bildschirmfoto).
  static Future<List<PreparedImage>> fromClipboard() async {
    final files = await clipboardFiles();
    if (files.isNotEmpty) return files;
    return clipboardBitmap();
  }

  /// Ob im Dateimanager kopierte Bilddateien bereitliegen – ohne sie zu
  /// lesen. Für Strg+V, das bei Text sonst kurz eine Bildleiste aufblitzen
  /// ließe.
  static Future<bool> clipboardHasImageFiles() async {
    if (!hasClipboardImages) return false;
    try {
      return (await Pasteboard.files()).any(_looksLikeImage);
    } on Object catch (error) {
      _unreadable(error);
      return false;
    }
  }

  /// Im Dateimanager kopierte Bilddateien.
  ///
  /// Vor dem Bild abgefragt, weil der Finder zu einer kopierten Datei auch
  /// ihr Symbol als Bild in die Zwischenablage legt. Leer, wenn keine da
  /// sind; [ClipboardFilesUnreadableException], wenn sie sich nicht lesen
  /// lassen – im macOS-Sandkasten darf die App nur, was man hineinzieht oder
  /// im Dialog wählt.
  static Future<List<PreparedImage>> clipboardFiles() async {
    if (!hasClipboardImages) return const [];
    final List<XFile> files;
    try {
      files = [
        for (final path in await Pasteboard.files())
          if (_looksLikeImage(path)) XFile(path),
      ];
    } on Object catch (error) {
      _unreadable(error);
      return const [];
    }
    try {
      return await _prepareAll(files);
    } on FileSystemException catch (error) {
      _unreadable(error);
      throw const ClipboardFilesUnreadableException();
    }
  }

  /// Ein Bild als Pixel – ein Bildschirmfoto. `[]`, wenn keins da ist.
  ///
  /// Ist das Bild zu groß oder kein lesbares Format, kommt der Fehler durch:
  /// stillschweigend nichts einzufügen, sähe aus wie ein kaputtes Strg+V.
  static Future<List<PreparedImage>> clipboardBitmap() async {
    if (!hasClipboardImages) return const [];
    final Uint8List? bytes;
    try {
      bytes = await Pasteboard.image;
    } on Object catch (error) {
      _unreadable(error);
      return const [];
    }
    if (bytes == null || bytes.isEmpty) return const [];
    return [await prepareImage(bytes)];
  }

  /// Ein Plugin, das auf dieser Plattform nicht antwortet, soll das Einfügen
  /// von Text nicht verhindern.
  static void _unreadable(Object error) =>
      debugPrint('Fusen: Zwischenablage nicht lesbar ($error)');

  /// Hineingezogene Dateien – was kein Bild ist, fällt still heraus.
  static Future<List<PreparedImage>> fromFiles(List<XFile> files) =>
      _prepareAll(files.where((f) => _looksLikeImage(f.name)).toList());

  static Future<List<PreparedImage>> _prepareAll(List<XFile> files) async {
    final prepared = <PreparedImage>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      prepared.add(await prepareImage(bytes, fileName: file.name));
    }
    return prepared;
  }

  static bool _looksLikeImage(String name) {
    final lower = name.toLowerCase();
    return const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.heic',
      '.heif',
    ].any(lower.endsWith);
  }
}

/// Kopierte Dateien, die die App nicht lesen darf.
class ClipboardFilesUnreadableException implements Exception {
  const ClipboardFilesUnreadableException();

  @override
  String toString() =>
      'Die kopierte Datei lässt sich nicht öffnen – zieh sie stattdessen '
      'hinein.';
}

/// Eine verständliche Meldung, wenn ein Bild nicht angenommen wurde.
String describeImageError(Object error) => switch (error) {
  ImageTooLargeException() => error.toString(),
  UnsupportedImageException() => error.toString(),
  ClipboardFilesUnreadableException() => error.toString(),
  _ => 'Das Bild ließ sich nicht laden.',
};
