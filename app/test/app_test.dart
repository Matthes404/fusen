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
import 'package:fusen/src/ui/note_style.dart';

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

void main() {
  testWidgets('startet mit leerer Inbox', (tester) async {
    await runAppTest(tester, (db) async {
      expect(find.text('Fusen'), findsOneWidget);
      expect(find.text('Inbox'), findsWidgets);
      expect(find.text('Die Inbox ist leer.'), findsOneWidget);
      expect(find.text('Noch keine Projekte.'), findsOneWidget);
    });
  });

  testWidgets('legt über die Schnelleingabe einen Zettel ab', (tester) async {
    await runAppTest(tester, (db) async {
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

      await tester.tap(find.text('Chess Engine'));
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

      await tester.tap(find.text('Praktikum'));
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

      await tester.tap(find.text('Chess'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect((await notes.findById(step.id))!.status, NoteStatus.done);
      expect(find.text('Erledigt (1)'), findsOneWidget);
    });
  });

  testWidgets('auf schmalen Fenstern öffnet ein Projekt als eigene Seite', (
    tester,
  ) async {
    await runAppTest(tester, size: const Size(420, 900), (db) async {
      await ProjectRepository(db).create(name: 'Studium');
      await tester.pumpAndSettle();

      expect(find.text('Fusen'), findsOneWidget);

      await tester.tap(find.text('Studium'));
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
}
