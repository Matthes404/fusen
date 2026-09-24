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

  /// Ein Bild aus der Zwischenablage – ein Bildschirmfoto oder im
  /// Dateimanager kopierte Bilddateien. `null`, wenn keins drin liegt.
  static Future<List<PreparedImage>> fromClipboard() async {
    if (!hasClipboardImages) return const [];
    try {
      final bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty) {
        return [await prepareImage(bytes)];
      }
      final paths = await Pasteboard.files();
      return await _prepareAll([
        for (final path in paths)
          if (_looksLikeImage(path)) XFile(path),
      ]);
    } on UnsupportedImageException {
      return const [];
    } on Object catch (error) {
      // Ein Plugin, das auf dieser Plattform nicht antwortet, soll das
      // Einfügen von Text nicht verhindern.
      debugPrint('Fusen: Zwischenablage nicht lesbar ($error)');
      return const [];
    }
  }

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

/// Eine verständliche Meldung, wenn ein Bild nicht angenommen wurde.
String describeImageError(Object error) => switch (error) {
  ImageTooLargeException() => error.toString(),
  UnsupportedImageException() => error.toString(),
  _ => 'Das Bild ließ sich nicht laden.',
};
