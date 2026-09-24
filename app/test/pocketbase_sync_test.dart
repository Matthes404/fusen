@Tags(['integration'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:fusen/src/core/clock.dart';
import 'package:fusen/src/data/db/database.dart';
import 'package:fusen/src/data/attachments/image_prep.dart';
import 'package:fusen/src/data/db/settings_store.dart';
import 'package:fusen/src/data/models/note_status.dart';
import 'package:fusen/src/data/models/note_type.dart';
import 'package:fusen/src/data/repositories/attachment_repository.dart';
import 'package:fusen/src/data/repositories/note_repository.dart';
import 'package:fusen/src/data/repositories/project_repository.dart';
import 'package:fusen/src/sync/pocketbase_backend.dart';
import 'package:fusen/src/sync/sync_backend.dart';
import 'package:fusen/src/sync/sync_service.dart';

/// Abgleich gegen eine echte PocketBase-Instanz.
///
/// Wird übersprungen, solange keine läuft. Zum Ausführen:
///
/// ```
/// cd server && docker compose up -d
/// FUSEN_TEST_SERVER=http://127.0.0.1:8090 \
///   FUSEN_TEST_CODE=deincode \
///   flutter test test/pocketbase_sync_test.dart
/// ```
void main() {
  // Der Test spielt zwei Geräte und braucht dafür zwei getrennte
  // Datenbanken – die Warnung von drift trifft hier nicht zu.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final serverUrl = Platform.environment['FUSEN_TEST_SERVER'];
  final accessCode = Platform.environment['FUSEN_TEST_CODE'];

  if (serverUrl == null || accessCode == null) {
    test(
      'PocketBase-Abgleich',
      () {},
      skip: 'Setze FUSEN_TEST_SERVER und FUSEN_TEST_CODE, um ihn zu fahren.',
    );
    return;
  }

  final credentials = SyncCredentials(
    serverUrl: serverUrl,
    accessCode: accessCode,
  );

  test('falscher Zugangscode wird als solcher gemeldet', () async {
    final backend = PocketBaseSyncBackend();
    final service = SyncService(
      database: FusenDatabase.memory(),
      backend: backend,
      settings: SettingsStore(FusenDatabase.memory()),
    );

    final outcome = await service.testConnection(
      SyncCredentials(serverUrl: serverUrl, accessCode: 'ganz-sicher-falsch'),
    );

    expect(outcome.status, SyncStatus.authFailed);
  });

  test('ein Zettel überlebt den Weg zum Server und zurück', () async {
    final clock = FixedClock(DateTime.now().toUtc());

    // Gerät A legt an und schiebt hoch.
    final dbA = FusenDatabase.memory();
    final syncA = SyncService(
      database: dbA,
      backend: PocketBaseSyncBackend(),
      settings: SettingsStore(dbA),
      clock: clock,
    );
    await syncA.saveCredentials(credentials);

    final projects = ProjectRepository(dbA, clock: clock);
    final notes = NoteRepository(dbA, deviceId: 'geraet-a', clock: clock);

    final project = await projects.create(name: 'Chess Engine ${clock.now()}');
    final note = await notes.create(
      projectId: project.id,
      type: NoteType.step,
      title: 'NNUE',
      body: 'Export auf int8 testen\n\n```\ncargo run --release\n```',
      tags: ['nnue', 'performance'],
    );

    final pushed = await syncA.syncNow();
    expect(pushed.status, SyncStatus.success, reason: pushed.message);
    expect(pushed.pushed, greaterThanOrEqualTo(2));

    // Gerät B kennt nichts und holt alles.
    final dbB = FusenDatabase.memory();
    final syncB = SyncService(
      database: dbB,
      backend: PocketBaseSyncBackend(),
      settings: SettingsStore(dbB),
      clock: clock,
    );
    await syncB.saveCredentials(credentials);

    final pulled = await syncB.syncNow();
    expect(pulled.status, SyncStatus.success, reason: pulled.message);

    final onB = await NoteRepository(
      dbB,
      deviceId: 'geraet-b',
    ).findById(note.id);
    expect(onB, isNotNull, reason: 'Der Zettel ist nicht angekommen.');
    expect(onB!.body, note.body);
    expect(onB.title, 'NNUE');
    expect(onB.type, NoteType.step);
    expect(onB.tags, ['nnue', 'performance']);
    expect(onB.projectId, project.id);
    expect(onB.deviceId, 'geraet-a');
    expect(onB.pendingSync, isFalse);

    expect(
      (await ProjectRepository(dbB).findById(project.id))!.name,
      project.name,
    );

    // Und der Zettel ist auf B sofort auffindbar.
    final hits = await NoteRepository(
      dbB,
      deviceId: 'geraet-b',
    ).search(terms: ['int8']).first;
    expect(hits.map((n) => n.id), contains(note.id));

    // Gerät B ändert, Gerät A übernimmt die neuere Fassung.
    clock.advance(const Duration(minutes: 1));
    await NoteRepository(
      dbB,
      deviceId: 'geraet-b',
      clock: clock,
    ).updateContent(note.id, body: 'Doch erst int16');
    final pushedB = await syncB.syncNow();
    expect(pushedB.status, SyncStatus.success, reason: pushedB.message);

    final backOnA = await syncA.syncNow();
    expect(backOnA.status, SyncStatus.success, reason: backOnA.message);
    expect((await notes.findById(note.id))!.body, 'Doch erst int16');

    // Eine Löschung reist als Tombstone.
    clock.advance(const Duration(minutes: 1));
    await notes.delete(note.id);
    await syncA.syncNow();
    await syncB.syncNow();
    expect(
      (await NoteRepository(dbB, deviceId: 'geraet-b').findById(note.id))!
          .deletedAt,
      isNotNull,
    );

    await dbA.close();
    await dbB.close();
  });

  test('ein Bild reist samt Datei, und nur Angemeldete kommen dran', () async {
    final clock = FixedClock(DateTime.now().toUtc());

    final dbA = FusenDatabase.memory();
    final syncA = SyncService(
      database: dbA,
      backend: PocketBaseSyncBackend(),
      settings: SettingsStore(dbA),
      clock: clock,
    );
    await syncA.saveCredentials(credentials);
    final notesA = NoteRepository(dbA, deviceId: 'geraet-a', clock: clock);
    final imagesA = AttachmentRepository(
      dbA,
      deviceId: 'geraet-a',
      clock: clock,
    );

    // Ein echtes PNG – PocketBase prüft den Inhalt, nicht die Endung.
    final prepared = prepareImageSync(
      Uint8List.fromList(_tinyPng),
      fileName: 'skizze.png',
    );
    final note = await notesA.create(
      type: NoteType.step,
      body: 'Mit Skizze',
      status: NoteStatus.done,
    );
    final image = await imagesA.add(note.id, prepared);

    final pushed = await syncA.syncNow();
    expect(pushed.status, SyncStatus.success, reason: pushed.message);
    expect(pushed.warning, isNull, reason: pushed.warning);
    final uploaded = (await imagesA.findById(image.id))!;
    expect(uploaded.uploaded, isTrue);
    expect(uploaded.remoteFile, isNotNull);

    // Ohne Anmeldung gibt es die Datei nicht.
    final anonymous = await HttpClient()
        .getUrl(
          Uri.parse(
            '$serverUrl/api/files/attachments/'
            '${image.id.replaceAll('-', '')}/${uploaded.remoteFile}',
          ),
        )
        .then((request) => request.close());
    expect(anonymous.statusCode, isNot(200));
    await anonymous.drain<void>();

    // Gerät B holt Zettel, Beschreibung und Datei.
    final dbB = FusenDatabase.memory();
    final syncB = SyncService(
      database: dbB,
      backend: PocketBaseSyncBackend(),
      settings: SettingsStore(dbB),
      clock: clock,
    );
    await syncB.saveCredentials(credentials);
    final pulled = await syncB.syncNow();
    expect(pulled.status, SyncStatus.success, reason: pulled.message);
    expect(pulled.warning, isNull, reason: pulled.warning);

    final noteOnB = await NoteRepository(
      dbB,
      deviceId: 'geraet-b',
    ).findById(note.id);
    expect(noteOnB!.status, NoteStatus.done);
    expect(noteOnB.closedAt, note.closedAt);

    final imagesB = AttachmentRepository(dbB, deviceId: 'geraet-b');
    final onB = (await imagesB.forNote(note.id)).single;
    expect(onB.fileName, 'skizze.png');
    expect(onB.mimeType, 'image/png');
    expect((onB.width, onB.height), (prepared.width, prepared.height));
    expect(await imagesB.readBytes(onB.id), prepared.bytes);

    // Entfernen reist als Tombstone, ohne die Datei erneut zu schicken.
    clock.advance(const Duration(minutes: 1));
    await imagesA.delete(image.id);
    final removed = await syncA.syncNow();
    expect(removed.status, SyncStatus.success, reason: removed.message);
    await syncB.syncNow();
    expect(await imagesB.forNote(note.id), isEmpty);

    await dbA.close();
    await dbB.close();
  });
}

/// Ein PNG mit einem einzigen roten Pixel.
const List<int> _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
