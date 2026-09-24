import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fusen/src/app/app.dart';
import 'package:fusen/src/app/providers.dart';
import 'package:fusen/src/data/db/database.dart';
import 'package:fusen/src/data/models/note_status.dart';
import 'package:fusen/src/data/models/note_type.dart';
import 'package:fusen/src/data/repositories/note_repository.dart';
import 'package:fusen/src/data/repositories/project_repository.dart';
import 'package:fusen/src/features/capture/capture_sheet.dart';
import 'package:fusen/src/features/capture/list_import_dialog.dart';
import 'package:fusen/src/features/overview/overview_view.dart';
import 'package:fusen/src/ui/note_style.dart';
import 'package:fusen/src/ui/widgets/completion_check.dart';

/// Startet die echte App gegen eine Datenbank im Speicher und räumt danach
/// wieder auf.
///
/// Das Aufräumen gehört in den Testkörper und nicht in `addTearDown`: beim
/// Abbauen des Widget-Baums legen drift und Riverpod noch Timer an, und die
/// prüft `flutter_test` bereits, bevor `addTearDown` an der Reihe ist.
Future<void> runAppTest(
  WidgetTester tester,
  Future<void> Function(FusenDatabase db) body, {
  Size size = const Size(1200, 900),
}) async {
  final database = FusenDatabase.memory();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        deviceIdProvider.overrideWithValue('test-device'),
      ],
      child: const FusenApp(),
    ),
  );
  await tester.pumpAndSettle();

  try {
    await body(database);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await database.close();
  }
}

/// Die Zettel eines Projekts in ihrer Reihenfolge.
///
/// Als einmalige Abfrage: ein `watch…().first` wartet im Testtakt auf einen
/// Timer, den ohne `pump` niemand auslöst – der Test hinge.
Future<List<NoteRow>> notesOf(FusenDatabase db, String projectId) =>
    (db.select(db.notes)
          ..where((n) => n.projectId.equals(projectId))
          ..orderBy([(n) => OrderingTerm(expression: n.sortOrder)]))
        .get();

void main() {
  testWidgets('startet mit der Übersicht', (tester) async {
    await runAppTest(tester, (db) async {
      expect(find.text('Fusen'), findsOneWidget);
      expect(find.text('Übersicht'), findsOneWidget);
      expect(find.text('Noch keine Projekte.'), findsOneWidget);
      expect(find.text('Neues Projekt'), findsOneWidget);

      await tester.tap(find.text('Inbox').first);
      await tester.pumpAndSettle();
      expect(find.text('Die Inbox ist leer.'), findsOneWidget);
    });
  });

  testWidgets('legt über die Schnelleingabe einen Zettel ab', (tester) async {
    await runAppTest(tester, (db) async {
      await tester.tap(find.text('Inbox').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zettel ablegen'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'Kurz nachdenken über den Aufbau',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ablegen'));
      await tester.pumpAndSettle();

      expect(find.text('Kurz nachdenken über den Aufbau'), findsOneWidget);

      // Streams von drift melden sich über einen Timer, der im Widget-Test
      // nur beim Pumpen läuft – hier deshalb direkt abfragen.
      final notes = await db.select(db.notes).get();
      expect(notes.single.type, NoteType.idea);
      expect(notes.single.projectId, isNull);
    });
  });

  testWidgets('legt per @projekt ein neues Projekt an', (tester) async {
    await runAppTest(tester, (db) async {
      await tester.tap(find.text('Zettel ablegen'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        '@chess !schritt NNUE-Export testen',
      );
      await tester.pumpAndSettle();

      // Die Vorschau zeigt Ziel und Typ, bevor gespeichert wird.
      expect(find.text('chess (neu)'), findsOneWidget);
      expect(find.text('Nächster Schritt'), findsOneWidget);

      await tester.tap(find.text('Ablegen'));
      await tester.pumpAndSettle();

      final projects = await db.select(db.projects).get();
      expect(projects.single.name, 'chess');

      final notes = await db.select(db.notes).get();
      expect(notes.single.projectId, projects.single.id);
      expect(notes.single.type, NoteType.step);
      expect(notes.single.body, 'NNUE-Export testen');
    });
  });

  testWidgets('zeigt die sieben Bereiche eines Projekts', (tester) async {
    await runAppTest(tester, (db) async {
      await ProjectRepository(db).create(name: 'Chess Engine');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chess Engine').first);
      await tester.pumpAndSettle();

      for (final type in NoteType.sectionOrder) {
        expect(
          find.text(type.sectionTitle),
          findsWidgets,
          reason: 'Bereich "${type.sectionTitle}" fehlt',
        );
      }
    });
  });

  testWidgets('zeigt immer nur eine aktive Anweisung', (tester) async {
    await runAppTest(tester, (db) async {
      final project = await ProjectRepository(db).create(name: 'Praktikum');
      final notes = NoteRepository(db, deviceId: 't');
      await notes.create(
        projectId: project.id,
        type: NoteType.instruction,
        body: 'Alte Anweisung',
      );
      await notes.create(
        projectId: project.id,
        type: NoteType.instruction,
        body: 'Neue Anweisung',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Praktikum').first);
      await tester.pumpAndSettle();

      expect(find.text('Neue Anweisung'), findsOneWidget);
      expect(find.text('Alte Anweisung'), findsNothing);
      expect(find.text('Verlauf (1)'), findsOneWidget);
    });
  });

  testWidgets('findet Zettel über die Suche', (tester) async {
    await runAppTest(tester, (db) async {
      final notes = NoteRepository(db, deviceId: 't');
      await notes.create(body: 'NNUE-Export auf int8 testen');
      await notes.create(body: 'Völlig anderes Thema');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suche'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'nnue');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('NNUE-Export auf int8 testen'), findsOneWidget);
      expect(find.text('Völlig anderes Thema'), findsNothing);
    });
  });

  testWidgets('hakt einen Schritt über die Karte ab', (tester) async {
    await runAppTest(tester, (db) async {
      final notes = NoteRepository(db, deviceId: 't');
      final project = await ProjectRepository(db).create(name: 'Chess');
      final step = await notes.create(
        projectId: project.id,
        type: NoteType.step,
        body: 'Erst mal bauen',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chess').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CompletionCheck).first);
      await tester.pumpAndSettle();

      expect((await notes.findById(step.id))!.status, NoteStatus.done);
      expect(find.text('Erledigt (1)'), findsOneWidget);
      // Die Meldung bietet an, es zurückzunehmen.
      expect(find.text('Rückgängig'), findsOneWidget);
    });
  });

  testWidgets('auf schmalen Fenstern öffnet ein Projekt als eigene Seite', (
    tester,
  ) async {
    await runAppTest(tester, size: const Size(420, 900), (db) async {
      await ProjectRepository(db).create(name: 'Studium');
      await tester.pumpAndSettle();

      expect(find.text('Fusen'), findsOneWidget);

      await tester.tap(find.text('Studium').first);
      await tester.pumpAndSettle();

      expect(find.text('Aktuelle Anweisung'), findsWidgets);
      expect(find.byType(BackButton), findsOneWidget);
    });
  });

  testWidgets('läuft ohne Server rein lokal', (tester) async {
    await runAppTest(tester, (db) async {
      await tester.tap(find.text('Einstellungen'));
      await tester.pumpAndSettle();

      expect(find.text('Kein Server'), findsOneWidget);
    });
  });

  testWidgets('legt direkt im Bereich an – eine Zeile oder eine ganze Liste', (
    tester,
  ) async {
    await runAppTest(tester, (db) async {
      final project = await ProjectRepository(db).create(name: 'Chess');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chess').first);
      await tester.pumpAndSettle();

      final field = find.widgetWithText(
        TextField,
        'Nächsten Schritt hinzufügen …',
      );
      await tester.enterText(field, 'Erst mal bauen !hoch');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Anlegen'));
      await tester.pumpAndSettle();

      await tester.enterText(field, 'testen\nmessen\nveröffentlichen');
      await tester.pumpAndSettle();
      expect(find.text('Enter legt 3 Schritte an'), findsOneWidget);
      await tester.tap(find.byTooltip('3 anlegen'));
      await tester.pumpAndSettle();

      final steps = await notesOf(db, project.id);
      expect(steps.map((n) => n.body), [
        'Erst mal bauen',
        'testen',
        'messen',
        'veröffentlichen',
      ]);
      expect(steps.every((n) => n.type == NoteType.step), isTrue);
      expect(steps.first.priority, NotePriority.must);
      expect(find.text('HOCH'), findsOneWidget);
    });
  });

  testWidgets('die Schnelleingabe teilt eine Liste in einzelne Zettel', (
    tester,
  ) async {
    await runAppTest(tester, (db) async {
      await tester.tap(find.text('Zettel ablegen'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(CaptureDialog),
          matching: find.byType(TextField),
        ),
        '@umzug !schritt\n- Kartons besorgen\n- [x] Termin festlegen',
      );
      await tester.pumpAndSettle();
      expect(find.text('2 Einträge erkannt'), findsOneWidget);

      await tester.tap(find.text('2 Zettel ablegen'));
      await tester.pumpAndSettle();

      final notes = await db.select(db.notes).get();
      expect(notes.map((n) => n.body).toSet(), {
        'Kartons besorgen',
        'Termin festlegen',
      });
      expect(notes.every((n) => n.type == NoteType.step), isTrue);
      final done = notes.singleWhere((n) => n.body == 'Termin festlegen');
      expect(done.status, NoteStatus.done);
      expect(done.closedAt, isNotNull);
      final project = (await db.select(db.projects).get()).single;
      expect(project.name, 'umzug');
      expect(notes.every((n) => n.projectId == project.id), isTrue);
    });
  });

  testWidgets('Löschen lässt sich zurücknehmen', (tester) async {
    await runAppTest(tester, (db) async {
      await NoteRepository(db, deviceId: 't').create(body: 'Weg damit');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inbox').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Aktionen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      expect(find.text('Weg damit'), findsNothing);

      await tester.tap(find.text('Rückgängig'));
      await tester.pumpAndSettle();
      expect(find.text('Weg damit'), findsOneWidget);
    });
  });

  testWidgets('sortiert aus der Inbox in ein Projekt', (tester) async {
    await runAppTest(tester, (db) async {
      final project = await ProjectRepository(db).create(name: 'Chess');
      final notes = NoteRepository(db, deviceId: 't');
      final note = await notes.create(body: 'Gehört zu Chess');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inbox').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Einsortieren'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chess').last);
      await tester.pumpAndSettle();

      expect((await notes.findById(note.id))!.projectId, project.id);
      expect(find.text('Die Inbox ist leer.'), findsOneWidget);
    });
  });

  testWidgets('die Übersicht zeigt Wichtiges und öffnet Projekte', (
    tester,
  ) async {
    await runAppTest(tester, (db) async {
      final project = await ProjectRepository(db).create(name: 'Chess');
      await NoteRepository(db, deviceId: 't').create(
        projectId: project.id,
        type: NoteType.step,
        body: 'Wichtiger Schritt',
        priority: NotePriority.must,
      );
      await tester.pumpAndSettle();

      expect(find.text('Wichtig'), findsOneWidget);
      expect(find.text('Wichtiger Schritt'), findsOneWidget);

      await tester.tap(find.widgetWithText(ProjectTile, 'Chess'));
      await tester.pumpAndSettle();
      expect(find.text('Nächste Schritte'), findsOneWidget);
    });
  });

  testWidgets('legt aus einer eingefügten Liste Zettel an', (tester) async {
    await runAppTest(tester, (db) async {
      final project = await ProjectRepository(db).create(name: 'Chess');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chess').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Aus einer Liste anlegen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(ListImportDialog),
          matching: find.byType(TextField),
        ),
        'Ideen:\n- Eröffnungsbuch\n\nFragen:\n- Reicht int8?\n- Wie schnell?',
      );
      await tester.pumpAndSettle();
      expect(find.text('3 von 3 ausgewählt'), findsOneWidget);

      await tester.tap(find.text('3 Zettel anlegen'));
      await tester.pumpAndSettle();

      final board = await notesOf(db, project.id);
      expect(
        {for (final n in board) n.body: n.type},
        {
          'Eröffnungsbuch': NoteType.idea,
          'Reicht int8?': NoteType.question,
          'Wie schnell?': NoteType.question,
        },
      );
      expect(find.text('3 Zettel angelegt'), findsOneWidget);
    });
  });
}
