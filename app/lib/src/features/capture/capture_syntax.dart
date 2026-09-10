import '../../data/models/note_type.dart';

/// Ergebnis der Schnelleingabe: was der Nutzer getippt hat, aufgeteilt in
/// Zuordnung und Text.
class CaptureDraft {
  const CaptureDraft({
    required this.body,
    this.projectQuery,
    this.type,
    this.tags = const [],
  });

  /// Der Text ohne die Kurzbefehle.
  final String body;

  /// Was hinter `@` stand – noch nicht auf ein Projekt aufgelöst.
  final String? projectQuery;

  /// Was hinter `!` stand, sofern es ein bekannter Typ war.
  final NoteType? type;

  /// Alle `#tags`, klein geschrieben und ohne Dubletten.
  final List<String> tags;

  bool get isEmpty => body.trim().isEmpty;

  @override
  String toString() =>
      'CaptureDraft(body: "$body", project: $projectQuery, type: $type, '
      'tags: $tags)';
}

/// Kurzbefehle für Zettel-Typen.
///
/// Deutsch wie im Konzept, plus die englischen Entsprechungen – wer die App
/// auf Englisch denkt, soll nicht raten müssen.
const Map<String, NoteType> captureTypeAliases = {
  // Anforderung
  'anf': NoteType.requirement,
  'anforderung': NoteType.requirement,
  'req': NoteType.requirement,
  'requirement': NoteType.requirement,
  // Nächster Schritt
  'schritt': NoteType.step,
  'step': NoteType.step,
  'todo': NoteType.step,
  'next': NoteType.step,
  // Aktuelle Anweisung
  'anw': NoteType.instruction,
  'anweisung': NoteType.instruction,
  'instruction': NoteType.instruction,
  'now': NoteType.instruction,
  // Idee
  'idee': NoteType.idea,
  'idea': NoteType.idea,
  // Frage
  'frage': NoteType.question,
  'question': NoteType.question,
  'q': NoteType.question,
  // Log
  'log': NoteType.log,
  'protokoll': NoteType.log,
  // Referenz
  'ref': NoteType.reference,
  'referenz': NoteType.reference,
  'reference': NoteType.reference,
  'link': NoteType.reference,
};

/// Der Kurzbefehl, der in der Oberfläche als Hilfe angezeigt wird.
const Map<NoteType, String> canonicalTypeAlias = {
  NoteType.requirement: 'anf',
  NoteType.step: 'schritt',
  NoteType.instruction: 'anw',
  NoteType.idea: 'idee',
  NoteType.question: 'frage',
  NoteType.log: 'log',
  NoteType.reference: 'ref',
};

/// Ein Kurzbefehl gilt nur am Wortanfang – `mail@example.com` ist kein
/// Projekt und `![bild](…)` kein Typ.
final RegExp _markerPattern = RegExp(
  r'(?<=^|\s)([@!#])([\p{L}\p{N}][\p{L}\p{N}_\-.]*)',
  unicode: true,
  multiLine: true,
);

/// Zerlegt eine Eingabe wie `@chess !schritt NNUE-Export testen #nnue`.
///
/// Nicht erkannte Kurzbefehle bleiben im Text stehen: ein vertipptes `!schrit`
/// soll sichtbar sein und nicht stillschweigend verschwinden.
CaptureDraft parseCapture(String input) {
  String? projectQuery;
  NoteType? type;
  final tags = <String>[];
  final consumed = <_Range>[];

  for (final match in _markerPattern.allMatches(input)) {
    final marker = match.group(1)!;
    final word = match.group(2)!;

    switch (marker) {
      case '@':
        if (projectQuery != null) continue;
        projectQuery = word;
      case '!':
        final resolved = captureTypeAliases[word.toLowerCase()];
        if (resolved == null || type != null) continue;
        type = resolved;
      case '#':
        final tag = word.toLowerCase();
        if (!tags.contains(tag)) tags.add(tag);
      default:
        continue;
    }
    consumed.add(_Range(match.start, match.end));
  }

  return CaptureDraft(
    body: _removeRanges(input, consumed).trim(),
    projectQuery: projectQuery,
    type: type,
    tags: List.unmodifiable(tags),
  );
}

class _Range {
  const _Range(this.start, this.end);

  final int start;
  final int end;
}

/// Schneidet die Kurzbefehle heraus und räumt das dabei entstehende
/// Leerzeichen mit weg – Einrückungen (Markdown-Codeblöcke) bleiben erhalten.
String _removeRanges(String input, List<_Range> ranges) {
  if (ranges.isEmpty) return input;

  final buffer = StringBuffer();
  var cursor = 0;
  for (final range in ranges) {
    var start = range.start;
    var end = range.end;
    if (end < input.length && (input[end] == ' ' || input[end] == '\t')) {
      end += 1;
    } else if (start > 0 &&
        (input[start - 1] == ' ' || input[start - 1] == '\t')) {
      start -= 1;
    }
    if (start > cursor) buffer.write(input.substring(cursor, start));
    cursor = end;
  }
  if (cursor < input.length) buffer.write(input.substring(cursor));
  return buffer.toString();
}
