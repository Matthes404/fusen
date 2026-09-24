import 'package:flutter_test/flutter_test.dart';
import 'package:fusen/src/data/models/note_status.dart';
import 'package:fusen/src/data/models/note_type.dart';
import 'package:fusen/src/features/capture/capture_syntax.dart';

void main() {
  group('parseCapture', () {
    test('Beispiel aus dem Konzept', () {
      final draft = parseCapture('@chess !schritt NNUE-Export auf int8 testen');

      expect(draft.projectQuery, 'chess');
      expect(draft.type, NoteType.step);
      expect(draft.body, 'NNUE-Export auf int8 testen');
      expect(draft.tags, isEmpty);
    });

    test('ohne Angabe bleibt alles offen', () {
      final draft = parseCapture('Kurz nachdenken');

      expect(draft.projectQuery, isNull);
      expect(draft.type, isNull);
      expect(draft.tags, isEmpty);
      expect(draft.body, 'Kurz nachdenken');
    });

    test('Kurzbefehle dürfen überall stehen', () {
      final draft = parseCapture('Abgabe klären !frage @praktikum #deadline');

      expect(draft.projectQuery, 'praktikum');
      expect(draft.type, NoteType.question);
      expect(draft.tags, ['deadline']);
      expect(draft.body, 'Abgabe klären');
    });

    test('sammelt mehrere Tags und wirft Dubletten weg', () {
      final draft = parseCapture('#Nnue Export #nnue #int8 testen');

      expect(draft.tags, ['nnue', 'int8']);
      expect(draft.body, 'Export testen');
    });

    test('nimmt nur das erste Projekt und den ersten Typ', () {
      final draft = parseCapture('@a @b !idee !log Text');

      expect(draft.projectQuery, 'a');
      expect(draft.type, NoteType.idea);
      expect(draft.body, '@b !log Text');
    });

    test('unbekannter Typ bleibt im Text stehen', () {
      final draft = parseCapture('!schrit Tippfehler');

      expect(draft.type, isNull);
      expect(draft.body, '!schrit Tippfehler');
    });

    test('E-Mail-Adressen sind keine Projekte', () {
      final draft = parseCapture('Mail an betreuer@uni.de schreiben');

      expect(draft.projectQuery, isNull);
      expect(draft.body, 'Mail an betreuer@uni.de schreiben');
    });

    test('Markdown-Überschrift ist kein Tag', () {
      final draft = parseCapture('# Überschrift\nText');

      expect(draft.tags, isEmpty);
      expect(draft.body, '# Überschrift\nText');
    });

    test('Markdown-Bild ist kein Typ', () {
      final draft = parseCapture('![alt](bild.png)');

      expect(draft.type, isNull);
      expect(draft.body, '![alt](bild.png)');
    });

    test('englische Kurzbefehle funktionieren auch', () {
      expect(parseCapture('!todo x').type, NoteType.step);
      expect(parseCapture('!req x').type, NoteType.requirement);
      expect(parseCapture('!now x').type, NoteType.instruction);
      expect(parseCapture('!link x').type, NoteType.reference);
    });

    test('Groß-/Kleinschreibung ist beim Typ egal', () {
      expect(parseCapture('!SCHRITT x').type, NoteType.step);
    });

    test('Einrückung im Codeblock bleibt erhalten', () {
      final draft = parseCapture(
        '@chess !ref Aufruf:\n    cargo run --release',
      );

      expect(draft.projectQuery, 'chess');
      expect(draft.type, NoteType.reference);
      expect(draft.body, 'Aufruf:\n    cargo run --release');
    });

    test('Umlaute und Bindestriche im Projektnamen', () {
      final draft = parseCapture('@bachelor-arbeit Gliederung überarbeiten');

      expect(draft.projectQuery, 'bachelor-arbeit');
      expect(draft.body, 'Gliederung überarbeiten');
    });

    test('leere Eingabe ist leer', () {
      expect(parseCapture('   ').isEmpty, isTrue);
      expect(parseCapture('@chess !idee').isEmpty, isTrue);
    });

    test('jeder Typ hat einen kanonischen Kurzbefehl, der auch parst', () {
      for (final type in NoteType.values) {
        final alias = canonicalTypeAlias[type];
        expect(alias, isNotNull, reason: 'Kein Kurzbefehl für $type');
        expect(parseCapture('!$alias Text').type, type);
      }
    });
  });

  group('Priorität', () {
    test('!hoch, !mittel, !niedrig', () {
      expect(
        parseCapture('!hoch Server neu starten').priority,
        NotePriority.must,
      );
      expect(parseCapture('!mittel Doku lesen').priority, NotePriority.should);
      expect(parseCapture('!niedrig aufräumen').priority, NotePriority.could);
    });

    test('Muss/Soll/Kann und die Kurzformen gehen genauso', () {
      expect(parseCapture('!muss x').priority, NotePriority.must);
      expect(parseCapture('!soll x').priority, NotePriority.should);
      expect(parseCapture('!kann x').priority, NotePriority.could);
      expect(parseCapture('!p1 x').priority, NotePriority.must);
      expect(parseCapture('!P3 x').priority, NotePriority.could);
      expect(parseCapture('!high x').priority, NotePriority.must);
    });

    test('verträgt sich mit Typ, Projekt und Tags', () {
      final draft = parseCapture('@chess !schritt !hoch Perft reparieren #bug');

      expect(draft.projectQuery, 'chess');
      expect(draft.type, NoteType.step);
      expect(draft.priority, NotePriority.must);
      expect(draft.tags, ['bug']);
      expect(draft.body, 'Perft reparieren');
    });

    test('die Reihenfolge von Typ und Priorität ist egal', () {
      final draft = parseCapture('!hoch !frage Wer zahlt?');

      expect(draft.type, NoteType.question);
      expect(draft.priority, NotePriority.must);
      expect(draft.body, 'Wer zahlt?');
    });

    test('eine zweite Priorität bleibt im Text stehen', () {
      final draft = parseCapture('!hoch !niedrig Text');

      expect(draft.priority, NotePriority.must);
      expect(draft.body, '!niedrig Text');
    });
  });
}
