import 'package:flutter_test/flutter_test.dart';
import 'package:fusen/src/core/clock.dart';
import 'package:fusen/src/data/db/database.dart';
import 'package:fusen/src/data/models/note_status.dart';
import 'package:fusen/src/data/models/note_type.dart';
import 'package:fusen/src/data/repositories/capture_service.dart';
import 'package:fusen/src/data/repositories/note_repository.dart';
import 'package:fusen/src/data/repositories/project_repository.dart';
import 'package:fusen/src/features/capture/capture_plan.dart';
import 'package:fusen/src/features/capture/list_syntax.dart';

List<String> _texts(String input) =>
    parseList(input).entries.map((e) => e.text).toList();

void main() {
  group('parseList', () {
    test('Striche, Sternchen, Punkte und Nummern', () {
      expect(_texts('- eins\n* zwei\n• drei\n1. vier\n2) fünf'), [
        'eins',
        'zwei',
        'drei',
        'vier',
        'fünf',
      ]);
      expect(parseList('- eins\n- zwei').isList, isTrue);
    });

    test('aus Word kommt oft ein Tabulator nach dem Punkt', () {
      expect(_texts('•\tTabelle fixen\n•\tMail schreiben'), [
        'Tabelle fixen',
        'Mail schreiben',
      ]);
    });

    test('ohne Aufzählungszeichen ist jede Zeile ein Eintrag', () {
      final parsed = parseList('Milch\n\nBrot\nButter');

      expect(parsed.entries.map((e) => e.text), ['Milch', 'Brot', 'Butter']);
      // Mehrere Zeilen sind aber noch keine erkennbare Liste.
      expect(parsed.isList, isFalse);
    });

    test('Kästchen und Haken markieren Erledigtes', () {
      final entries = parseList(
        '- [ ] offen\n- [x] fertig\n[X] auch fertig\n☐ offen\n✓ fertig',
      ).entries;

      expect(entries.map((e) => e.text), [
        'offen',
        'fertig',
        'auch fertig',
        'offen',
        'fertig',
      ]);
      expect(entries.map((e) => e.checked), [false, true, true, false, true]);
    });

    test('Eingerücktes gehört als Details zum Eintrag darüber', () {
      final entries = parseList(
        '- NNUE exportieren\n'
        '  - int8 testen\n'
        '    - [x] Skalierung prüfen\n'
        '  Achtung: Vorzeichen\n'
        '- Perft ergänzen',
      ).entries;

      expect(entries.map((e) => e.text), [
        'NNUE exportieren',
        'Perft ergänzen',
      ]);
      expect(
        entries.first.details,
        '- int8 testen\n  - [x] Skalierung prüfen\nAchtung: Vorzeichen',
      );
      expect(entries.last.details, isNull);
    });

    test('Überschriften werden keine Einträge, geben aber den Rahmen vor', () {
      final entries = parseList(
        'Nächste Schritte:\n'
        '- bauen\n'
        '## Ideen\n'
        '- Eröffnungsbuch\n'
        'Sonstiges\n'
        '- Kaffee',
      ).entries;

      expect(entries.map((e) => e.text), ['bauen', 'Eröffnungsbuch', 'Kaffee']);
      expect(entries.map((e) => e.heading), [
        'Nächste Schritte',
        'Ideen',
        'Sonstiges',
      ]);
    });

    test('eine Zeile nur aus Kurzbefehlen ist eine Überschrift', () {
      final entries = parseList('@chess !schritt\nNNUE testen\nPerft').entries;

      expect(entries.map((e) => e.text), ['NNUE testen', 'Perft']);
      expect(entries.first.heading, '@chess !schritt');
    });

    test('„z. B.“ und Datumsangaben sind keine Aufzählung', () {
      expect(parseList('z. B. so\noder so').isList, isFalse);
      expect(parseList('-5 Grad\n-3 Grad').isList, isFalse);
    });

    test('leere Aufzählungspunkte fallen weg', () {
      expect(_texts('- eins\n- \n-\n- zwei'), ['eins', 'zwei']);
    });

    test('Windows-Zeilenenden', () {
      expect(_texts('- eins\r\n- zwei\r\n'), ['eins', 'zwei']);
    });
  });

  group('typeForHeading', () {
    test('erkennt die Bereiche der Projekt-Ansicht', () {
      expect(typeForHeading('Nächste Schritte'), NoteType.step);
      expect(typeForHeading('To-dos'), NoteType.step);
      expect(typeForHeading('Offene Fragen'), NoteType.question);
      expect(typeForHeading('Anforderungen'), NoteType.requirement);
      expect(typeForHeading('**Ideen**'), NoteType.idea);
      expect(typeForHeading('Links'), NoteType.reference);
    });

    test('ein passendes Wort genügt', () {
      expect(typeForHeading('Fragen an den Betreuer'), NoteType.question);
      expect(typeForHeading('Meine Ideen für später'), NoteType.idea);
    });

    test('sonst nichts', () {
      expect(typeForHeading('Sonstiges'), isNull);
      expect(typeForHeading('@chess'), isNull);
    });
  });

  group('planCapture', () {
    test('ein Satz bleibt ein Zettel', () {
      final plan = planCapture('@chess !schritt NNUE testen');

      expect(plan.split, isFalse);
      expect(plan.drafts.single.body, 'NNUE testen');
      expect(plan.drafts.single.projectName, 'chess');
      expect(plan.drafts.single.type, NoteType.step);
    });

    test('eine Liste wird ohne Zutun aufgeteilt', () {
      final plan = planCapture('- eins\n- zwei\n- drei');

      expect(plan.split, isTrue);
      expect(plan.drafts.map((d) => d.body), ['eins', 'zwei', 'drei']);
    });

    test('schlichte Zeilen nur auf Wunsch', () {
      expect(planCapture('eins\nzwei').split, isFalse);
      expect(planCapture('eins\nzwei').canSplit, isTrue);
      expect(planCapture('eins\nzwei', split: true).drafts.length, 2);
    });

    test('als ein Zettel behält die Liste ihr Markdown', () {
      final plan = planCapture('Einkauf:\n- Milch\n- Brot', split: false);

      expect(plan.drafts.single.body, 'Einkauf:\n- Milch\n- Brot');
    });

    test('Kurzbefehle der Überschrift gelten für alle darunter', () {
      final plan = planCapture(
        '@chess !schritt #nnue\n- exportieren !hoch\n- testen #int8',
      );

      expect(plan.drafts.map((d) => d.projectName), ['chess', 'chess']);
      expect(plan.drafts.map((d) => d.type), [NoteType.step, NoteType.step]);
      expect(plan.drafts.map((d) => d.priority), [NotePriority.must, null]);
      expect(plan.drafts.last.tags, ['nnue', 'int8']);
    });

    test('Überschriften bestimmen den Typ – außer man legt ihn fest', () {
      const input = 'Ideen:\n- Buch\nFragen:\n- Wann?\n- !schritt bauen';

      expect(planCapture(input).drafts.map((d) => d.type), [
        NoteType.idea,
        NoteType.question,
        NoteType.step,
      ]);
      expect(
        planCapture(
          input,
          type: NoteType.requirement,
          typeFromHeadings: false,
        ).drafts.map((d) => d.type),
        [NoteType.requirement, NoteType.requirement, NoteType.step],
      );
    });

    test('mit Details wird die Zeile zum Titel', () {
      final plan = planCapture('- NNUE\n  int8 testen\n- Perft');

      expect(plan.drafts.first.title, 'NNUE');
      expect(plan.drafts.first.body, 'int8 testen');
      expect(plan.drafts.last.title, isNull);
      expect(plan.drafts.last.body, 'Perft');
    });

    test('Abgehaktes wird erledigt angelegt', () {
      final plan = planCapture('- [x] fertig\n- [ ] offen');

      expect(plan.drafts.map((d) => d.done), [true, false]);
    });

    test('Vorgaben gelten, wo die Eingabe nichts sagt', () {
      final plan = planCapture(
        '- eins\n- zwei !niedrig',
        type: NoteType.step,
        priority: NotePriority.should,
      );

      expect(plan.drafts.map((d) => d.type), [NoteType.step, NoteType.step]);
      expect(plan.drafts.map((d) => d.priority), [
        NotePriority.should,
        NotePriority.could,
      ]);
    });

    test('leer bleibt leer', () {
      expect(planCapture('   \n ').isEmpty, isTrue);
      expect(planCapture('@chess !schritt').isEmpty, isTrue);
    });
  });

  group('CaptureService', () {
    late FusenDatabase db;
    late ProjectRepository projects;
    late NoteRepository notes;
    late CaptureService capture;

    setUp(() {
      final clock = FixedClock(DateTime.utc(2026, 9, 24, 9));
      db = FusenDatabase.memory();
      projects = ProjectRepository(db, clock: clock);
      notes = NoteRepository(db, deviceId: 't', clock: clock);
      capture = CaptureService(database: db, projects: projects, notes: notes);
    });

    tearDown(() => db.close());

    test('legt eine ganze Liste auf einmal an', () async {
      final project = await projects.create(name: 'Chess');
      final plan = planCapture(
        '- [x] bauen\n- testen !hoch\n- veröffentlichen',
        type: NoteType.step,
      );

      final created = await capture.createAll(
        plan.drafts,
        projectId: project.id,
      );

      expect(created.length, 3);
      final board = await notes.watchBoard(project.id).first;
      expect(board.map((n) => n.body), ['bauen', 'testen', 'veröffentlichen']);
      expect(board.map((n) => n.status), [
        NoteStatus.done,
        NoteStatus.open,
        NoteStatus.open,
      ]);
      expect(board[1].priority, NotePriority.must);
    });

    test('ein neues @projekt entsteht nur einmal', () async {
      final plan = planCapture('- @neu eins\n- @Neu zwei\n- drei');

      final created = await capture.createAll(plan.drafts);

      final all = await projects.watchProjects().first;
      expect(all.single.name, 'neu');
      expect(created.map((n) => n.projectId), [
        all.single.id,
        all.single.id,
        null,
      ]);
    });

    test('Rückgängig nimmt den ganzen Import zurück', () async {
      final created = await capture.createAll(
        planCapture('- eins\n- zwei').drafts,
      );

      await capture.undo(created);

      expect(await notes.watchInbox().first, isEmpty);
    });
  });
}
