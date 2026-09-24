import '../../data/models/note_type.dart';
import 'capture_syntax.dart';

/// Ein Eintrag aus einer eingefügten Liste – daraus wird ein Zettel.
class ListEntry {
  const ListEntry({
    required this.text,
    this.details,
    this.checked = false,
    this.heading,
  });

  /// Die Zeile ohne Aufzählungszeichen, Kurzbefehle noch enthalten.
  final String text;

  /// Eingerückte Zeilen darunter, als Markdown. `null`, wenn es keine gibt.
  final String? details;

  /// Stand in der Liste schon als erledigt da (`- [x]`, `✓`).
  final bool checked;

  /// Die Überschrift, unter der der Eintrag stand – roh, mit allen
  /// Kurzbefehlen. Sie gibt den Rahmen vor: „Nächste Schritte:“ macht aus
  /// den Zeilen darunter Schritte, `@chess !hoch` gilt für alle darunter.
  final String? heading;

  @override
  String toString() =>
      'ListEntry("$text", details: $details, checked: $checked, '
      'heading: $heading)';
}

/// Was in einem eingefügten Text an Liste steckt.
class ListParse {
  const ListParse({required this.entries, required this.hasMarkers});

  final List<ListEntry> entries;

  /// Ob der Text echte Aufzählungszeichen oder Kästchen enthielt. Nur dann
  /// ist es eindeutig eine Liste; mehrere schlichte Zeilen können genauso
  /// gut ein Absatz sein.
  final bool hasMarkers;

  /// Mehr als ein Eintrag, und zwar erkennbar als Liste.
  bool get isList => entries.length > 1 && hasMarkers;
}

/// Aufzählungszeichen: Striche, Punkte, Nummern, `a)`.
///
/// Kein `a.` – sonst würde aus „z. B. …“ ein Eintrag „B. …“.
final RegExp _bullet = RegExp(
  r'^(?:[-*+•‣◦▪▫●○·–—]|\d{1,3}[.)]|[a-zA-Z]\))\s+(.*)$',
);

/// Ein Kästchen: `[ ]`, `[x]` – nach dem Aufzählungszeichen oder allein.
final RegExp _checkbox = RegExp(r'^\[([ xX✓✔])\]\s*(.*)$');

/// Unicode-Kästchen, wie sie aus Notiz-Apps und Word kommen.
final RegExp _unicodeBox = RegExp(r'^([☐□☑☒✅✔✓])\s*(.*)$');

final RegExp _markdownHeading = RegExp(r'^#{1,6}\s+(.*)$');

/// Zerlegt eingefügten Text in Einträge.
///
/// Die Regeln, so wie sie auch in der Hilfe stehen:
///
/// * Jede Zeile mit Aufzählungszeichen wird ein Eintrag. Gibt es keine,
///   wird jede Zeile ein Eintrag.
/// * Eingerückte Zeilen gehören als Details zum Eintrag darüber.
/// * Eine Zeile mit Doppelpunkt am Ende, eine Markdown-Überschrift, eine
///   Zeile nur aus Kurzbefehlen – und in einer Aufzählung jede Zeile ohne
///   Aufzählungszeichen – ist eine Überschrift: sie gilt für die Einträge
///   darunter, wird aber selbst keiner.
/// * `[x]` und `✓` heißen „schon erledigt“.
ListParse parseList(String input) {
  final lines = input
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map(_classify)
      .toList();

  final hasMarkers = lines.any((l) => l.kind == _Kind.item);
  final itemIndents = [
    for (final line in lines)
      if (line.kind == (hasMarkers ? _Kind.item : _Kind.plain)) line.indent,
  ];
  final base = itemIndents.isEmpty
      ? 0
      : itemIndents.reduce((a, b) => a < b ? a : b);

  final entries = <ListEntry>[];
  String? heading;
  _Builder? current;

  void flush() {
    final built = current?.build();
    if (built != null) entries.add(built);
    current = null;
  }

  for (final line in lines) {
    final nested = current != null && line.indent > base;
    switch (line.kind) {
      case _Kind.blank:
        break;
      case _Kind.heading:
        flush();
        heading = line.text;
      case _Kind.item when nested:
        // Unterpunkte bleiben als Unterpunkte erhalten.
        current!.addDetail(line.indent, '- ${line.markerText}');
      case _Kind.item:
        flush();
        current = _Builder(line.text, line.checked, heading);
      case _Kind.plain when nested:
        current!.addDetail(line.indent, line.text);
      case _Kind.plain when !hasMarkers:
        flush();
        current = _Builder(line.text, false, heading);
      case _Kind.plain:
        // Freistehender Text zwischen Aufzählungen – so sehen in Word und
        // in Mails Zwischenüberschriften aus.
        flush();
        heading = line.text;
    }
  }
  flush();

  return ListParse(entries: List.unmodifiable(entries), hasMarkers: hasMarkers);
}

/// Welcher Zettel-Typ zu einer Überschrift passt – „Nächste Schritte:“,
/// „## Ideen“, „Offene Fragen“. `null`, wenn keiner passt.
NoteType? typeForHeading(String heading) {
  final text = parseCapture(heading).body
      .replaceAll(RegExp(r'[*_:#]'), ' ')
      .trim()
      .toLowerCase();
  if (text.isEmpty) return null;

  final exact = _headingTypes[text];
  if (exact != null) return exact;
  // „Meine Ideen“, „Fragen an den Betreuer“ – ein passendes Wort genügt.
  for (final word in text.split(RegExp(r'\s+'))) {
    final match = _headingTypes[word];
    if (match != null) return match;
  }
  return null;
}

final Map<String, NoteType> _headingTypes = {
  for (final type in NoteType.values) ...{_plain(type.name): type},
  ...captureTypeAliases,
  'anweisungen': NoteType.instruction,
  'fokus': NoteType.instruction,
  'nächste schritte': NoteType.step,
  'next steps': NoteType.step,
  'schritte': NoteType.step,
  'aufgaben': NoteType.step,
  'aufgabe': NoteType.step,
  'to-do': NoteType.step,
  'to-dos': NoteType.step,
  'todos': NoteType.step,
  'tasks': NoteType.step,
  'offene fragen': NoteType.question,
  'fragen': NoteType.question,
  'questions': NoteType.question,
  'anforderungen': NoteType.requirement,
  'requirements': NoteType.requirement,
  'ideen': NoteType.idea,
  'ideas': NoteType.idea,
  'einfälle': NoteType.idea,
  'referenzen': NoteType.reference,
  'links': NoteType.reference,
  'references': NoteType.reference,
  'logbuch': NoteType.log,
};

String _plain(String value) => value.toLowerCase();

enum _Kind { blank, heading, item, plain }

class _Line {
  const _Line(
    this.kind, {
    this.indent = 0,
    this.text = '',
    this.markerText = '',
    this.checked = false,
  });

  final _Kind kind;
  final int indent;

  /// Der Text ohne Aufzählungszeichen und Kästchen.
  final String text;

  /// Für Unterpunkte: der Text samt Kästchen, damit ein `[x]` in den
  /// Details sichtbar bleibt.
  final String markerText;
  final bool checked;
}

_Line _classify(String raw) {
  final expanded = raw.replaceAll('\t', '    ');
  final content = expanded.trimLeft();
  if (content.trim().isEmpty) return const _Line(_Kind.blank);
  final indent = expanded.length - content.length;
  final trimmed = content.trimRight();

  final heading = _markdownHeading.firstMatch(trimmed);
  if (heading != null) {
    return _Line(_Kind.heading, indent: indent, text: heading.group(1)!.trim());
  }

  final bullet = _bullet.firstMatch(trimmed);
  final afterBullet = bullet?.group(1) ?? trimmed;
  final box =
      _checkbox.firstMatch(afterBullet) ?? _unicodeBox.firstMatch(afterBullet);
  if (bullet != null || box != null) {
    final text = (box?.group(2) ?? afterBullet).trim();
    final mark = box?.group(1);
    final checked = mark != null && mark != ' ' && mark != '☐' && mark != '□';
    return _Line(
      _Kind.item,
      indent: indent,
      text: text,
      markerText: afterBullet,
      checked: checked,
    );
  }

  // Eine Zeile nur aus Kurzbefehlen gibt den Rahmen vor, statt selbst ein
  // Zettel zu werden: `@chess !schritt` über einer Liste.
  final markersOnly = parseCapture(trimmed).body.isEmpty;
  final labelled = trimmed.endsWith(':') && trimmed.length <= 80;
  if (markersOnly || labelled) {
    final label = labelled
        ? trimmed.substring(0, trimmed.length - 1).trim()
        : trimmed;
    return _Line(_Kind.heading, indent: indent, text: label);
  }

  return _Line(_Kind.plain, indent: indent, text: trimmed);
}

class _Builder {
  _Builder(this.text, this.checked, this.heading);

  final String text;
  final bool checked;
  final String? heading;
  final List<(int, String)> _details = [];

  void addDetail(int indent, String text) => _details.add((indent, text));

  ListEntry? build() {
    if (text.trim().isEmpty) return null;
    String? details;
    if (_details.isNotEmpty) {
      // Relativ zur flachsten Detailzeile einrücken – so bleibt die
      // Verschachtelung erhalten, ohne dass der ganze Block als Codeblock
      // (vier Leerzeichen) gelesen wird.
      final shallowest = _details
          .map((d) => d.$1)
          .reduce((a, b) => a < b ? a : b);
      details = _details
          .map((d) => '${' ' * (d.$1 - shallowest)}${d.$2}')
          .join('\n');
    }
    return ListEntry(
      text: text,
      details: details,
      checked: checked,
      heading: heading,
    );
  }
}
