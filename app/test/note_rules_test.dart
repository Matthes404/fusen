import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:fusen/src/core/clock.dart';
import 'package:fusen/src/data/db/database.dart';
import 'package:fusen/src/data/models/note_status.dart';
import 'package:fusen/src/data/models/note_type.dart';
import 'package:fusen/src/data/repositories/note_repository.dart';
import 'package:fusen/src/data/repositories/project_repository.dart';

void main() {
  late FusenDatabase db;
  late FixedClock clock;
  late ProjectRepository projects;
  late NoteRepository notes;

  setUp(() {
    clock = FixedClock(DateTime.utc(2026, 3, 1, 9));
    db = FusenDatabase.memory();
    projects = ProjectRepository(db, clock: clock);
    notes = NoteRepository(db, deviceId: 'test-device', clock: clock);
  });

  tearDown(() => db.close());

  group('Aktuelle Anweisung', () {
    test('nur eine ist gleichzeitig aktiv', () async {
      final project = await projects.create(name: 'Chess Engine');

      final first = await notes.create(
        projectId: project.id,
        type: NoteType.instruction,
        body: 'Fokus: Suche verbessern',
      );
      clock.advance(const Duration(minutes: 5));
      final second = await notes.create(
        projectId: project.id,
        type: NoteType.instruction,
        body: 'Fokus: NNUE',
      );

      expect((await notes.findById(first.id))!.status, NoteStatus.done);
      expect((await notes.findById(second.id))!.status, NoteStatus.open);
    });

    test('gilt pro Projekt, nicht global', () async {
      final a = await projects.create(name: 'A');
      final b = await projects.create(name: 'B');

      final inA = await notes.create(
          projectId: a.id, type: NoteType.instruction, body: 'A gilt');
      final inB = await notes.create(
          projectId: b.id, type: NoteType.instruction, body: 'B gilt');

      expect((await notes.findById(inA.id))!.status, NoteStatus.open);
      expect((await notes.findById(inB.id))!.status, NoteStatus.open);
    });

    test('gilt auch in der Inbox', () async {
      final first =
          await notes.create(type: NoteType.instruction, body: 'alt');
      await notes.create(type: NoteType.instruction, body: 'neu');

      expect((await notes.findById(first.id))!.status, NoteStatus.done);
    });

    test('Typwechsel zu Anweisung verdrängt die bisherige', () async {
      final project = await projects.create(name: 'Praktikum');
      final old = await notes.create(
          projectId: project.id,
          type: NoteType.instruction,
          body: 'Woche 1');
      final idea = await notes.create(
          projectId: project.id, type: NoteType.idea, body: 'Woche 2');

      await notes.changeType(idea.id, NoteType.instruction);

      expect((await notes.findById(old.id))!.status, NoteStatus.done);
      expect((await notes.findById(idea.id))!.status, NoteStatus.open);
    });

    test('Verschieben ins Projekt verdrängt dessen Anweisung', () async {
      final project = await projects.create(name: 'Studium');
      final resident = await notes.create(
          projectId: project.id, type: NoteType.instruction, body: 'alt');
      final incoming =
          await notes.create(type: NoteType.instruction, body: 'aus Inbox');

      await notes.moveToProject(incoming.id, project.id);

      expect((await notes.findById(resident.id))!.status, NoteStatus.done);
      expect((await notes.findById(incoming.id))!.status, NoteStatus.open);
    });

    test('eine alte Anweisung wieder öffnen verdrängt die aktuelle', () async {
      final project = await projects.create(name: 'Chess');
      final first = await notes.create(
          projectId: project.id, type: NoteType.instruction, body: 'erste');
      final second = await notes.create(
          projectId: project.id, type: NoteType.instruction, body: 'zweite');

      await notes.setStatus(first.id, NoteStatus.open);

      expect((await notes.findById(first.id))!.status, NoteStatus.open);
      expect((await notes.findById(second.id))!.status, NoteStatus.done);
    });
  });

  group('Log', () {
    test('trägt den Zeitpunkt der Erstellung', () async {
      final entry = await notes.create(type: NoteType.log, body: 'gebaut');

      expect(entry.createdAt, DateTime.utc(2026, 3, 1, 9));
    });

    test('bleibt innerhalb von 24 Stunden editierbar', () async {
      final entry = await notes.create(type: NoteType.log, body: 'Tippfehler');
      clock.advance(const Duration(hours: 23, minutes: 59));

      await notes.updateContent(entry.id, body: 'korrigiert');

      expect((await notes.findById(entry.id))!.body, 'korrigiert');
    });

    test('friert nach 24 Stunden ein', () async {
      final entry = await notes.create(type: NoteType.log, body: 'endgültig');
      clock.advance(const Duration(hours: 24, minutes: 1));

      expect(
        () => notes.updateContent(entry.id, body: 'umgeschrieben'),
        throwsA(isA<NoteEditLockedException>()),
      );
      expect(
        () => notes.changeType(entry.id, NoteType.idea),
        throwsA(isA<NoteEditLockedException>()),
      );
    });

    test('lässt sich auch nach der Frist archivieren und löschen', () async {
      final entry = await notes.create(type: NoteType.log, body: 'alt');
      clock.advance(const Duration(days: 3));

      await notes.archive(entry.id);
      expect((await notes.findById(entry.id))!.archivedAt, isNotNull);

      await notes.delete(entry.id);
      expect((await notes.findById(entry.id))!.deletedAt, isNotNull);
    });

    test('andere Typen frieren nie ein', () async {
      final idea = await notes.create(type: NoteType.idea, body: 'alt');
      clock.advance(const Duration(days: 400));

      await notes.updateContent(idea.id, body: 'immer noch änderbar');
      expect((await notes.findById(idea.id))!.body, 'immer noch änderbar');
    });

    test('erscheint nicht auf dem Board, sondern im Log', () async {
      final project = await projects.create(name: 'Chess');
      await notes.create(
          projectId: project.id, type: NoteType.log, body: 'gebaut');
      await notes.create(
          projectId: project.id, type: NoteType.idea, body: 'Einfall');

      final board = await notes.watchBoard(project.id).first;
      final log = await notes.watchLog(project.id).first;

      expect(board.map((n) => n.type), [NoteType.idea]);
      expect(log.map((n) => n.type), [NoteType.log]);
    });

    test('das Log zeigt den neuesten Eintrag zuerst', () async {
      final project = await projects.create(name: 'Chess');
      await notes.create(
          projectId: project.id, type: NoteType.log, body: 'zuerst');
      clock.advance(const Duration(hours: 1));
      await notes.create(
          projectId: project.id, type: NoteType.log, body: 'danach');

      final log = await notes.watchLog(project.id).first;
      expect(log.map((n) => n.body), ['danach', 'zuerst']);
    });
  });

  group('Frage', () {
    test('wird beim Beantworten geschlossen und archiviert', () async {
      final question =
          await notes.create(type: NoteType.question, body: 'Bis wann?');

      await notes.answerQuestion(question.id, 'Bis zum 30.');

      final answered = (await notes.findById(question.id))!;
      expect(answered.answer, 'Bis zum 30.');
      expect(answered.status, NoteStatus.done);
      expect(answered.archivedAt, isNotNull);
    });

    test('die Antwort ist durchsuchbar', () async {
      final question =
          await notes.create(type: NoteType.question, body: 'Bis wann?');
      await notes.answerQuestion(question.id, 'Bis Karfreitag');

      final hits = await notes.search(terms: ['karfreitag']).first;
      expect(hits.map((n) => n.id), [question.id]);
    });
  });

  group('Typwechsel', () {
    test('Idee wird zur Anforderung mit Priorität', () async {
      final idea = await notes.create(type: NoteType.idea, body: 'Undo');

      await notes.changeType(idea.id, NoteType.requirement);
      await notes.setPriority(idea.id, NotePriority.should);

      final row = (await notes.findById(idea.id))!;
      expect(row.type, NoteType.requirement);
      expect(row.priority, NotePriority.should);
    });

    test('räumt Felder auf, die der neue Typ nicht kennt', () async {
      final requirement =
          await notes.create(type: NoteType.requirement, body: 'Undo');
      await notes.setPriority(requirement.id, NotePriority.must);

      await notes.changeType(requirement.id, NoteType.step);

      expect((await notes.findById(requirement.id))!.priority, isNull);
    });

    test('Priorität lässt sich nur bei Anforderungen setzen', () async {
      final step = await notes.create(type: NoteType.step, body: 'bauen');

      await notes.setPriority(step.id, NotePriority.must);

      expect((await notes.findById(step.id))!.priority, isNull);
    });
  });

  group('Board und Inbox', () {
    test('Zettel ohne Projekt liegen in der Inbox', () async {
      final project = await projects.create(name: 'Chess');
      await notes.create(body: 'ohne Projekt');
      await notes.create(projectId: project.id, body: 'mit Projekt');

      final inbox = await notes.watchBoard(null).first;
      expect(inbox.map((n) => n.body), ['ohne Projekt']);
    });

    test('archivierte und gelöschte Zettel verschwinden vom Board', () async {
      final visible = await notes.create(body: 'sichtbar');
      final archived = await notes.create(body: 'archiviert');
      final deleted = await notes.create(body: 'gelöscht');

      await notes.archive(archived.id);
      await notes.delete(deleted.id);

      final board = await notes.watchBoard(null).first;
      expect(board.map((n) => n.id), [visible.id]);

      final archive = await notes.watchArchive(null).first;
      expect(archive.map((n) => n.id), [archived.id]);
    });

    test('Reihenfolge der Schritte lässt sich umstellen', () async {
      final a = await notes.create(type: NoteType.step, body: 'a');
      final b = await notes.create(type: NoteType.step, body: 'b');
      final c = await notes.create(type: NoteType.step, body: 'c');

      await notes.reorder([c.id, a.id, b.id]);

      final board = await notes.watchBoard(null).first;
      expect(board.map((n) => n.body), ['c', 'a', 'b']);
    });

    test('offene Zettel werden pro Projekt gezählt', () async {
      final project = await projects.create(name: 'Chess');
      final done = await notes.create(
          projectId: project.id, type: NoteType.step, body: 'fertig');
      await notes.create(
          projectId: project.id, type: NoteType.step, body: 'offen');
      await notes.create(
          projectId: project.id, type: NoteType.log, body: 'zählt nicht');
      await notes.create(body: 'inbox');
      await notes.setStatus(done.id, NoteStatus.done);

      final counts = await notes.watchOpenCounts().first;
      expect(counts[project.id], 1);
      expect(counts[null], 1);
    });
  });

  group('Löschen', () {
    test('setzt einen Tombstone statt hart zu löschen', () async {
      final note = await notes.create(body: 'weg damit');

      await notes.delete(note.id);

      final row = await notes.findById(note.id);
      expect(row, isNotNull);
      expect(row!.deletedAt, isNotNull);
      expect(row.pendingSync, isTrue);
    });

    test('ein gelöschtes Projekt nimmt seine Zettel mit', () async {
      final project = await projects.create(name: 'Verworfen');
      final note = await notes.create(projectId: project.id, body: 'dazu');

      await projects.delete(project.id);

      expect((await notes.findById(note.id))!.deletedAt, isNotNull);
      expect((await projects.findById(project.id))!.deletedAt, isNotNull);
    });
  });

  group('Projekte', () {
    test('@-Eingabe findet ein Projekt exakt oder als eindeutigen Präfix',
        () async {
      await projects.create(name: 'Chess Engine');
      await projects.create(name: 'Praktikum');

      expect((await projects.findByNameOrPrefix('chess'))!.name, 'Chess Engine');
      expect((await projects.findByNameOrPrefix('CHESS ENGINE'))!.name,
          'Chess Engine');
      expect(await projects.findByNameOrPrefix('x'), isNull);
    });

    test('mehrdeutiger Präfix trifft nicht', () async {
      await projects.create(name: 'Praktikum');
      await projects.create(name: 'Prototyp');

      expect(await projects.findByNameOrPrefix('pr'), isNull);
    });

    test('findOrCreate legt unbekannte Projekte an', () async {
      final created = await projects.findOrCreate('Neues Ding');
      final again = await projects.findOrCreate('neues ding');

      expect(again.id, created.id);
      expect((await projects.watchProjects().first).length, 1);
    });

    test('archivierte Projekte sind nur auf Wunsch sichtbar', () async {
      final project = await projects.create(name: 'Alt');
      await projects.archive(project.id);

      expect(await projects.watchProjects().first, isEmpty);
      expect(
          (await projects.watchProjects(includeArchived: true).first).length, 1);
    });
  });

  group('Suche', () {
    test('findet über Titel, Text und Tags', () async {
      final project = await projects.create(name: 'Chess');
      final note = await notes.create(
        projectId: project.id,
        title: 'NNUE',
        body: 'Export auf int8 testen',
        tags: ['performance'],
      );
      await notes.create(projectId: project.id, body: 'völlig anderes Thema');

      expect((await notes.search(terms: ['nnue']).first).single.id, note.id);
      expect((await notes.search(terms: ['int8']).first).single.id, note.id);
      expect(
          (await notes.search(terms: ['performance']).first).single.id, note.id);
    });

    test('verknüpft mehrere Begriffe mit UND', () async {
      await notes.create(body: 'Alpha Beta');
      await notes.create(body: 'Alpha Gamma');

      expect((await notes.search(terms: ['alpha']).first).length, 2);
      expect((await notes.search(terms: ['alpha', 'beta']).first).length, 1);
      expect((await notes.search(terms: ['alpha', 'delta']).first), isEmpty);
    });

    test('ignoriert Groß-/Kleinschreibung auch bei Umlauten', () async {
      final note = await notes.create(body: 'Überarbeiten und ÄNDERN');

      expect((await notes.search(terms: ['überarbeiten']).first).single.id,
          note.id);
      expect((await notes.search(terms: ['ändern']).first).single.id, note.id);
      expect((await notes.search(terms: ['ÄNDERN']).first).single.id, note.id);
    });

    test('filtert nach Projekt und Typ', () async {
      final a = await projects.create(name: 'A');
      final b = await projects.create(name: 'B');
      final target = await notes.create(
          projectId: a.id, type: NoteType.step, body: 'gemeinsames Wort');
      await notes.create(
          projectId: b.id, type: NoteType.step, body: 'gemeinsames Wort');
      await notes.create(
          projectId: a.id, type: NoteType.idea, body: 'gemeinsames Wort');

      final hits = await notes
          .search(
            terms: ['gemeinsames'],
            projectId: a.id,
            projectFilterActive: true,
            type: NoteType.step,
          )
          .first;

      expect(hits.map((n) => n.id), [target.id]);
    });

    test('findet gelöschte Zettel nicht mehr', () async {
      final note = await notes.create(body: 'verschwindet');
      await notes.delete(note.id);

      expect(await notes.search(terms: ['verschwindet']).first, isEmpty);
    });

    test('findet archivierte Zettel nur auf Wunsch', () async {
      final note = await notes.create(body: 'im Archiv');
      await notes.archive(note.id);

      expect(await notes.search(terms: ['archiv']).first, isNotEmpty);
      expect(
        await notes.search(terms: ['archiv'], includeArchived: false).first,
        isEmpty,
      );
    });
  });

  group('Sync-Markierung', () {
    test('jede Änderung markiert den Datensatz als offen', () async {
      final note = await notes.create(body: 'neu');
      expect(note.pendingSync, isTrue);

      await (db.update(db.notes)..where((t) => t.id.equals(note.id)))
          .write(const NotesCompanion(pendingSync: Value(false)));

      await notes.updateContent(note.id, body: 'geändert');
      expect((await notes.findById(note.id))!.pendingSync, isTrue);
    });
  });
}
