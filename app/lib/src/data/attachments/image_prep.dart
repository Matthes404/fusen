/// Bilder, die an einem Zettel hängen sollen, werden vor dem Speichern
/// hierdurch geschickt: Format erkennen, Maße lesen, zu Großes verkleinern.
///
/// Der Grund ist der Sync. Ein Handyfoto hat schnell zwölf Megapixel und
/// fünf Megabyte, ein Bildschirmfoto vom 4K-Monitor ähnlich viel. Auf einem
/// Zettel reichen 2048 Pixel an der langen Kante; alles darüber kostet nur
/// Speicher und Zeit beim Abgleich.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Längste Kante nach dem Verkleinern.
const int imageMaxEdge = 2048;

/// Ab hier wird verkleinert, auch wenn die Datei klein genug wäre – etwa ein
/// gut komprimiertes Panorama.
const int imageShrinkEdge = 2560;

/// Ab dieser Dateigröße wird neu kodiert, auch wenn die Maße passen.
const int imageShrinkBytes = 2500 * 1024;

/// Mehr nimmt die App gar nicht erst an.
const int imageMaxInputBytes = 40 * 1024 * 1024;

/// Dasselbe für unkomprimierte Bitmaps. Unter Windows kommt ein
/// Bildschirmfoto aus der Zwischenablage als BMP – vier Bytes pro Pixel,
/// ein Foto zweier 4K-Bildschirme hat da schon 66 MB. Beim Entpacken braucht
/// es nicht mehr Speicher, als es groß ist; die strengere Grenze oben gilt
/// komprimierten Formaten, die sich um ein Vielfaches aufblähen.
const int imageMaxBitmapBytes = 160 * 1024 * 1024;

/// Obergrenze für das, was gespeichert und abgeglichen wird. Der Server
/// erlaubt etwas mehr, damit die Grenze hier die maßgebliche ist.
const int imageMaxStoredBytes = 20 * 1024 * 1024;

/// Bilddaten, fertig zum Speichern.
class PreparedImage {
  const PreparedImage({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  final int? width;
  final int? height;
}

/// Das Bild ist zu groß, auch nach dem Verkleinern.
class ImageTooLargeException implements Exception {
  const ImageTooLargeException(this.bytes);

  final int bytes;

  @override
  String toString() =>
      'Das Bild ist zu groß (${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB).';
}

/// Die Datei ist kein Bild, das die App anzeigen kann.
class UnsupportedImageException implements Exception {
  const UnsupportedImageException();

  @override
  String toString() => 'Das ist kein Bild, das Fusen anzeigen kann.';
}

/// Ein Bildformat, wie es an den ersten Bytes zu erkennen ist.
class ImageKind {
  const ImageKind(this.mimeType, this.extension, {this.decodable = true});

  final String mimeType;
  final String extension;

  /// Ob das `image`-Paket es lesen kann – nur dann lässt es sich verkleinern.
  final bool decodable;

  static const jpeg = ImageKind('image/jpeg', 'jpg');
  static const png = ImageKind('image/png', 'png');
  static const gif = ImageKind('image/gif', 'gif');
  static const webp = ImageKind('image/webp', 'webp');
  static const bmp = ImageKind('image/bmp', 'bmp');
  static const heic = ImageKind('image/heic', 'heic', decodable: false);
}

/// Erkennt das Format an den ersten Bytes statt an der Dateiendung – beim
/// Einfügen aus der Zwischenablage gibt es gar keine.
ImageKind? sniffImage(Uint8List bytes) {
  bool startsWith(List<int> magic, [int offset = 0]) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0xFF, 0xD8, 0xFF])) return ImageKind.jpeg;
  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return ImageKind.png;
  }
  if (startsWith('GIF8'.codeUnits)) return ImageKind.gif;
  if (startsWith('RIFF'.codeUnits) && startsWith('WEBP'.codeUnits, 8)) {
    return ImageKind.webp;
  }
  if (startsWith('BM'.codeUnits)) return ImageKind.bmp;
  // HEIC/HEIF: ISO-Container mit „ftyp“ und einer der HEIF-Marken.
  if (startsWith('ftyp'.codeUnits, 4) && bytes.length >= 12) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    if (const {
      'heic',
      'heix',
      'hevc',
      'heim',
      'heis',
      'mif1',
      'msf1',
    }.contains(brand)) {
      return ImageKind.heic;
    }
  }
  return null;
}

/// Bereitet ein Bild in einem eigenen Isolate auf, damit die Oberfläche
/// beim Verkleinern eines großen Fotos nicht stockt.
Future<PreparedImage> prepareImage(
  Uint8List input, {
  String? fileName,
  DateTime? now,
}) {
  final stamp = now ?? DateTime.now();
  return Isolate.run(
    () => prepareImageSync(input, fileName: fileName, now: stamp),
  );
}

/// Wie [prepareImage], aber im aufrufenden Isolate.
PreparedImage prepareImageSync(
  Uint8List input, {
  String? fileName,
  DateTime? now,
}) {
  final kind = sniffImage(input);
  final limit = kind == ImageKind.bmp
      ? imageMaxBitmapBytes
      : imageMaxInputBytes;
  if (input.length > limit) throw ImageTooLargeException(input.length);
  if (kind == null) throw const UnsupportedImageException();

  final (width, height) = _dimensions(input, kind);
  final edge = width == null || height == null
      ? 0
      : (width > height ? width : height);
  // Eine BMP wird immer umgerechnet: unkomprimiert ist sie ein Vielfaches
  // so groß wie dasselbe Bild als PNG.
  final wantsShrink =
      kind.decodable &&
      kind != ImageKind.gif &&
      (kind == ImageKind.bmp ||
          edge > imageShrinkEdge ||
          input.length > imageShrinkBytes);

  if (!wantsShrink) {
    if (input.length > imageMaxStoredBytes) {
      throw ImageTooLargeException(input.length);
    }
    return PreparedImage(
      bytes: input,
      mimeType: kind.mimeType,
      fileName: _fileName(fileName, kind.extension, now),
      width: width,
      height: height,
    );
  }

  final decoded = img.decodeImage(input);
  if (decoded == null) throw const UnsupportedImageException();

  // Handyfotos stehen oft nur laut EXIF aufrecht. Beim Neukodieren ginge
  // die Angabe verloren, also wird die Drehung in die Pixel übernommen.
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > imageMaxEdge) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: imageMaxEdge,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: imageMaxEdge,
            interpolation: img.Interpolation.average,
          );
  }

  // Bildschirmfotos bleiben PNG: Schrift und scharfe Kanten sehen als JPEG
  // verwaschen aus, und flache Flächen packt PNG ohnehin kleiner. Unter
  // Windows kommen sie als BMP aus der Zwischenablage. Nur wenn das Ergebnis
  // trotzdem riesig ist und nichts durchsichtig ist, wird es doch JPEG.
  if (kind == ImageKind.png || kind == ImageKind.bmp) {
    final png = img.encodePng(image, level: 6);
    if (png.length <= imageShrinkBytes || _hasTransparency(image)) {
      return _finish(png, ImageKind.png, fileName, now, image);
    }
  }

  final jpeg = img.encodeJpg(_withoutAlpha(image), quality: 85);
  return _finish(jpeg, ImageKind.jpeg, fileName, now, image);
}

PreparedImage _finish(
  Uint8List bytes,
  ImageKind kind,
  String? fileName,
  DateTime? now,
  img.Image image,
) {
  if (bytes.length > imageMaxStoredBytes) {
    throw ImageTooLargeException(bytes.length);
  }
  return PreparedImage(
    bytes: bytes,
    mimeType: kind.mimeType,
    fileName: _fileName(fileName, kind.extension, now),
    width: image.width,
    height: image.height,
  );
}

/// Maße aus dem Dateikopf, ohne das ganze Bild zu dekodieren.
(int?, int?) _dimensions(Uint8List bytes, ImageKind kind) {
  if (!kind.decodable) return (null, null);
  try {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) {
      return (null, null);
    }
    var width = info.width;
    var height = info.height;
    if (kind == ImageKind.jpeg) {
      // EXIF-Drehung um 90° oder 270° vertauscht die angezeigten Maße.
      final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
      if (orientation != null && orientation >= 5 && orientation <= 8) {
        (width, height) = (height, width);
      }
    }
    return (width, height);
  } on Object {
    return (null, null);
  }
}

bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  final opaque = image.maxChannelValue;
  for (final pixel in image) {
    if (pixel.a < opaque) return true;
  }
  return false;
}

/// JPEG kennt keine Transparenz – durchsichtige Stellen werden weiß statt
/// schwarz.
img.Image _withoutAlpha(img.Image image) {
  if (!image.hasAlpha) return image;
  final flat = img.Image(width: image.width, height: image.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  return img.compositeImage(flat, image);
}

/// Ein Dateiname mit passender Endung. Eingefügte Bilder haben keinen, sie
/// heißen nach dem Zeitpunkt.
String _fileName(String? original, String extension, DateTime? now) {
  final trimmed = original?.trim() ?? '';
  if (trimmed.isEmpty) {
    final t = (now ?? DateTime.now()).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Bild ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}.${two(t.minute)}.${two(t.second)}.$extension';
  }
  final dot = trimmed.lastIndexOf('.');
  final stem = dot > 0 ? trimmed.substring(0, dot) : trimmed;
  return '$stem.$extension';
}
