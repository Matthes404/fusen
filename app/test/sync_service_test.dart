import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fusen/src/core/clock.dart';
import 'package:fusen/src/data/db/database.dart';
import 'package:fusen/src/data/db/settings_store.dart';
import 'package:fusen/src/data/models/note_status.dart';
import 'package:fusen/src/data/attachments/image_prep.dart';
import 'package:fusen/src/data/models/note_type.dart';
import 'package:fusen/src/data/repositories/attachment_repository.dart';
import 'package:fusen/src/data/repositories/note_repository.dart';
import 'package:fusen/src/data/repositories/project_repository.dart';
import 'package:fusen/src/sync/sync_backend.dart';
import 'package:fusen/src/sync/sync_ids.dart';
import 'package:fusen/src/sync/sync_records.dart';
import 'package:fusen/src/sync/sync_service.dart';

/// Server-Attrappe: hält Datensätze im Speicher und vergibt – wie PocketBase –
/// eigene `updated`-Zeitstempel.
class FakeSyncBackend implements SyncBackend {
  FakeSyncBackend({this.serverClock});

  final FixedClock? serverClock;

  final Map<String, (SyncProject, DateTime)> projects = {};
  final Map<String, (SyncNote, DateTime)> notes = {};
  final Map<String, (SyncAttachment, DateTime)> attachments = {};
  final Map<String, Uint8List> files = {};

  /// Ein Server von vor Version 2 kennt keine Bilder.
  bool supportsAttachments = true;

  /// Wie oft eine Bilddatei tatsächlich mitgeschickt wurde.
  int uploads = 0;
  final Set<String> failDownloads = {};

  SyncCredentials? connectedWith;
  int connectCount = 0;
  int pullCount = 0;
  SyncBackendException? failWith;
  String? expectedCode;

  DateTime _serverNow() => serverClock?.now() ?? DateTime.now().toUtc();

  @override
  Future<void> connect(SyncCredentials credentials) async {
    connectCount++;
    if (expectedCode != null && credentials.accessCode != expectedCode) {
      throw const SyncBackendException(
        'Zugangscode stimmt nicht.',
        isAuthFailure: true,
      );
    }
    connectedWith = credentials;
  }

  @override
  Future<void> disconnect() async => connectedWith = null;

  @override
  Future<RemoteBatch> pull({DateTime? since}) async {
    pullCount++;
    if (failWith != null) throw failWith!;

    bool isNew((Object, DateTime) entry) =>
        since == null || entry.$2.isAfter(since);

    final freshProjects = projects.values.where(isNew).toList();
    final freshNotes = notes.values.where(isNew).toList();
    final freshAttachments = supportsAttachments
        ? attachments.values.where(isNew).toList()
        : const <(SyncAttachment, DateTime)>[];
    DateTime? cursor = since;
    for (final stamp in [
      ...freshProjects.map((e) => e.$2),
      ...freshNotes.map((e) => e.$2),
      ...freshAttachments.map((e) => e.$2),
    ]) {
      if (cursor == null || stamp.isAfter(cursor)) cursor = stamp;
    }

    return RemoteBatch(
      projects: freshProjects.map((e) => e.$1).toList(),
      notes: freshNotes.map((e) => e.$1).toList(),
      attachments: freshAttachments.map((e) => e.$1).toList(),
      attachmentsSupported: supportsAttachments,
      cursor: cursor,
    );
  }

  @override
  Future<String?> pushAttachment(
    SyncAttachment attachment, {
    Uint8List? bytes,
  }) async {
    if (failWith != null) throw failWith!;
    if (!supportsAttachments) {
      throw const SyncBackendException('keine Bilder', isUnsupported: true);
    }
    final existing = attachments[attachment.id]?.$1;
    String? remoteFile;
    if (bytes == null) {
      if (existing == null) {
        throw const SyncBackendException('fehlt', isNotFound: true);
      }
      remoteFile = existing.remoteFile;
    } else {
      uploads++;
      files[attachment.id] = bytes;
      remoteFile = 'datei_${remoteIdFor(attachment.id)}.png';
    }
    attachments[attachment.id] = (
      withFile(attachment, remoteFile),
      _serverNow(),
    );
    return remoteFile;
  }

  @override
  Future<Uint8List> downloadAttachment(SyncAttachment attachment) async {
    if (failDownloads.contains(attachment.id)) {
      throw const SyncBackendException('Download gescheitert');
    }
    final bytes = files[attachment.id];
    if (bytes == null) {
      throw const SyncBackendException('keine Datei', isNotFound: true);
    }
    return bytes;
  }

  /// Simuliert ein anderes Gerät, das ein Bild hochgeladen hat.
  void seedAttachment(SyncAttachment attachment, List<int> bytes) {
    files[attachment.id] = Uint8List.fromList(bytes);
    attachments[attachment.id] = (
      withFile(attachment, 'datei_${remoteIdFor(attachment.id)}.png'),
      _serverNow(),
    );
  }

  static SyncAttachment withFile(SyncAttachment a, String? remoteFile) =>
      SyncAttachment(
        id: a.id,
        noteId: a.noteId,
        fileName: a.fileName,
        mimeType: a.mimeType,
        byteSize: a.byteSize,
        width: a.width,
        height: a.height,
        sortOrder: a.sortOrder,
        createdAt: a.createdAt,
        updatedAt: a.updatedAt,
        deletedAt: a.deletedAt,
        deviceId: a.deviceId,
        remoteFile: remoteFile,
      );

  @override
  Future<void> push({
    List<SyncProject> projects = const [],
    List<SyncNote> notes = const [],
  }) async {
    if (failWith != null) throw failWith!;
    final stamp = _serverNow();
    for (final project in projects) {
      this.projects[project.id] = (project, stamp);
    }
    for (final note in notes) {
      this.notes[note.id] = (note, stamp);
    }
  }

  /// Simuliert ein anderes Gerät, das etwas hochgeladen hat.
  void seedNote(SyncNote note, {DateTime? at}) {
    notes[note.id] = (note, at ?? _serverNow());
  }
}

SyncNote remoteNote({
  required String id,
  required DateTime updatedAt,
  String body = 'aus der Ferne',
  String? projectId,
  NoteType type = NoteType.idea,
  NoteStatus status = NoteStatus.open,
  DateTime? deletedAt,
}) {
  return SyncNote(
    id: id,
    projectId: projectId,
    type: type,
    body: body,
    status: status,
    sortOrder: 0,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    deviceId: 'anderes-geraet',
  );
}

SyncAttachment remoteAttachment({
  required String id,
  String noteId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0001',
  DateTime? updatedAt,
}) {
  final at = updatedAt ?? DateTime.utc(2026, 5, 1, 11);
  return SyncAttachment(
    id: id,
    noteId: noteId,
    fileName: 'skizze.png',
    mimeType: 'image/png',
    byteSize: 3,
    width: 3,
    height: 1,
    sortOrder: 1024,
    createdAt: at,
    updatedAt: at,
    deviceId: 'anderes-geraet',
  );
}

void main() {
  late FusenDatabase db;
  late FixedClock clock;
  late FixedClock serverClock;
  late SettingsStore settings;
  late ProjectRepository projects;
  late NoteRepository notes;
  late FakeSyncBackend backend;
  late SyncService sync;

  const credentials = SyncCredentials(
    serverUrl: 'https://fusen.example',
    accessCode: 'geheim',
  );

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 5, 1, 12));
    serverClock = FixedClock(DateTime.utc(2026, 5, 1, 12));
    db = FusenDatabase.memory();
    settings = SettingsStore(db);
    projects = ProjectRepository(db, clock: clock);
    notes = NoteRepository(db, deviceId: 'dieses-geraet', clock: clock);
    backend = FakeSyncBackend(serverClock: serverClock);
    sync = SyncService(
      database: db,
      backend: backend,
      settings: settings,
      clock: clock,
    );
    await sync.saveCredentials(credentials);
  });

  tearDown(() => db.close());

  group('Zugang', () {
    test('ohne Server läuft die App rein lokal', () async {
      await sync.saveCredentials(null);

      final outcome = await sync.syncNow();

      expect(outcome.status, SyncStatus.disabled);
      expect(backend.connectCount, 0);
    });

    test('falscher Zugangscode wird als solcher gemeldet', () async {
      backend.expectedCode = 'richtig';

      final outcome = await sync.syncNow();

      expect(outcome.status, SyncStatus.authFailed);
    });

    test('meldet sich nur einmal an', () async {
      await sync.syncNow();
      await sync.syncNow();

      expect(backend.connectCount, 1);
    });

    test('Verbindungstest meldet Erfolg, ohne zu übertragen', () async {
      await notes.create(body: 'bleibt hier');

      final outcome = await sync.testConnection(credentials);

      expect(outcome.isSuccess, isTrue);
      expect(backend.notes, isEmpty);
    });
  });

  group('Hochladen', () {
    test('schiebt neue Zettel und Projekte hoch', () async {
      final project = await projects.create(name: 'Chess Engine');
      await notes.create(projectId: project.id, body: 'NNUE testen');

      final outcome = await sync.syncNow();

      expect(outcome.isSuccess, isTrue);
      expect(outcome.pushed, 2);
      expect(backend.projects.values.single.$1.name, 'Chess Engine');
      expect(backend.notes.values.single.$1.body, 'NNUE testen');
    });

    test('markiert hochgeladene Datensätze als erledigt', () async {
      final note = await notes.create(body: 'einmal');
      await sync.syncNow();

      expect((await notes.findById(note.id))!.pendingSync, isFalse);

      final second = await sync.syncNow();
      expect(second.pushed, 0);
    });

    test('behält Änderungen, die während des Hochladens passieren', () async {
      final note = await notes.create(body: 'erste Fassung');
      await sync.syncNow();

      clock.advance(const Duration(minutes: 1));
      await notes.updateContent(note.id, body: 'zweite Fassung');

      expect((await notes.findById(note.id))!.pendingSync, isTrue);

      serverClock.advance(const Duration(minutes: 1));
      await sync.syncNow();
      expect(backend.notes[note.id]!.$1.body, 'zweite Fassung');
    });

    test('überträgt Löschungen als Tombstone', () async {
      final note = await notes.create(body: 'weg');
      await sync.syncNow();

      clock.advance(const Duration(minutes: 1));
      serverClock.advance(const Duration(minutes: 1));
      await notes.delete(note.id);
      await sync.syncNow();

      expect(backend.notes[note.id]!.$1.deletedAt, isNotNull);
    });
  });

  group('Herunterladen', () {
    test('übernimmt unbekannte Zettel', () async {
      backend.seedNote(
        remoteNote(
          id: 'aaaaaaaa-0000-4000-8000-000000000001',
          updatedAt: DateTime.utc(2026, 5, 1, 11),
          body: 'von woanders',
        ),
      );

      final outcome = await sync.syncNow();

      expect(outcome.pulled, 1);
      final row = await notes.findById('aaaaaaaa-0000-4000-8000-000000000001');
      expect(row!.body, 'von woanders');
      expect(row.pendingSync, isFalse);
    });

    test('macht heruntergeladene Zettel durchsuchbar', () async {
      backend.seedNote(
        remoteNote(
          id: 'aaaaaaaa-0000-4000-8000-000000000002',
          updatedAt: DateTime.utc(2026, 5, 1, 11),
          body: 'Ähnliches Thema',
        ),
      );

      await sync.syncNow();

      expect(await notes.search(terms: ['ähnliches']).first, hasLength(1));
    });

    test('holt fremde Änderungen, während eigene hochgehen', () async {
      // Der Reihenfolge wegen heikel: erst schieben, dann holen. Wenn das
      // Hochladen den Cursor vorstellt, überspringt das anschließende Holen
      // alles, was das andere Gerät vorher geschrieben hat – und zwar für
      // immer.
      backend.seedNote(
        remoteNote(
          id: 'aaaaaaaa-0000-4000-8000-000000000004',
          updatedAt: DateTime.utc(2026, 5, 1, 11, 30),
          body: 'vom anderen Gerät',
        ),
        at: DateTime.utc(2026, 5, 1, 11, 30),
      );
      await notes.create(body: 'von hier');

      final outcome = await sync.syncNow();

      expect(outcome.pushed, 1);
      expect(
        await notes.findById('aaaaaaaa-0000-4000-8000-000000000004'),
        isNotNull,
        reason: 'Die fremde Änderung wurde übersprungen.',
      );
    });

    test('verliert nichts, was auf dieselbe Millisekunde fällt', () async {
      // Zwei Geräte schreiben im selben Augenblick. Der zweite Datensatz
      // trägt denselben Serverzeitstempel wie der Cursor – ohne
      // Überlappung würde `updated > cursor` ihn nie wieder zeigen.
      final sameInstant = DateTime.utc(2026, 5, 1, 11, 30);
      backend.seedNote(
        remoteNote(
          id: 'aaaaaaaa-0000-4000-8000-000000000005',
          updatedAt: sameInstant,
          body: 'erster',
        ),
        at: sameInstant,
      );

      expect((await sync.syncNow()).pulled, 1);

      backend.seedNote(
        remoteNote(
          id: 'aaaaaaaa-0000-4000-8000-000000000006',
          updatedAt: sameInstant,
          body: 'zweiter',
        ),
        at: sameInstant,
      );

      expect((await sync.syncNow()).pulled, 1);
      expect(
        await notes.findById('aaaaaaaa-0000-4000-8000-000000000006'),
        isNotNull,
      );
    });

    test('holt beim zweiten Mal nur Neues', () async {
      backend.seedNote(
        remoteNote(
          id: 'aaaaaaaa-0000-4000-8000-000000000003',
          updatedAt: DateTime.utc(2026, 5, 1, 11),
        ),
        at: DateTime.utc(2026, 5, 1, 11),
      );

      expect((await sync.syncNow()).pulled, 1);
      expect((await sync.syncNow()).pulled, 0);
    });
  });

  group('Konflikte (Last-Write-Wins)', () {
    const id = 'aaaaaaaa-0000-4000-8000-00000000000f';

    test(
      'die neuere Fassung gewinnt – auch wenn sie vom Server kommt',
      () async {
        await notes.create(body: 'lokal');
        final local = (await notes.watchBoard(null).first).single;
        await sync.syncNow();

        serverClock.advance(const Duration(minutes: 10));
        backend.seedNote(
          remoteNote(
            id: local.id,
            updatedAt: clock.now().add(const Duration(minutes: 5)),
            body: 'ferngesteuert',
          ),
        );

        await sync.syncNow();

        expect((await notes.findById(local.id))!.body, 'ferngesteuert');
      },
    );

    test('eine ältere Fassung vom Server überschreibt nichts', () async {
      await notes.create(body: 'lokal neu');
      final local = (await notes.watchBoard(null).first).single;
      await sync.syncNow();

      serverClock.advance(const Duration(minutes: 10));
      backend.seedNote(
        remoteNote(
          id: local.id,
          updatedAt: clock.now().subtract(const Duration(hours: 1)),
          body: 'veraltet',
        ),
      );

      final outcome = await sync.syncNow();

      expect(outcome.pulled, 0);
      expect((await notes.findById(local.id))!.body, 'lokal neu');
    });

    test('eine Löschung vom Server setzt sich durch', () async {
      backend.seedNote(
        remoteNote(id: id, updatedAt: DateTime.utc(2026, 5, 1, 11)),
        at: DateTime.utc(2026, 5, 1, 11),
      );
      await sync.syncNow();
      expect(await notes.watchBoard(null).first, hasLength(1));

      serverClock.advance(const Duration(minutes: 10));
      backend.seedNote(
        remoteNote(
          id: id,
          updatedAt: DateTime.utc(2026, 5, 1, 13),
          deletedAt: DateTime.utc(2026, 5, 1, 13),
        ),
      );
      await sync.syncNow();

      expect(await notes.watchBoard(null).first, isEmpty);
      expect((await notes.findById(id))!.deletedAt, isNotNull);
    });
  });

  group('Fehler', () {
    test('ein Serverfehler lässt lokale Daten unangetastet', () async {
      final note = await notes.create(body: 'bleibt');
      backend.failWith = const SyncBackendException('Server nicht erreichbar');

      final outcome = await sync.syncNow();

      expect(outcome.status, SyncStatus.error);
      expect((await notes.findById(note.id))!.pendingSync, isTrue);
      expect((await notes.findById(note.id))!.body, 'bleibt');
    });

    test('nach einem Fehler wird beim nächsten Mal erneut geschoben', () async {
      await notes.create(body: 'zweiter Versuch');
      backend.failWith = const SyncBackendException('kurz weg');
      await sync.syncNow();

      backend.failWith = null;
      final outcome = await sync.syncNow();

      expect(outcome.pushed, 1);
      expect(backend.notes.values.single.$1.body, 'zweiter Versuch');
    });
  });

  group('IDs', () {
    test('UUID und Server-ID lassen sich verlustfrei umrechnen', () {
      const uuid = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

      expect(remoteIdFor(uuid), '3f2504e04f8941d39a0c0305e82c3301');
      expect(localIdFor(remoteIdFor(uuid)), uuid);
    });

    test('fremde IDs bleiben unverändert', () {
      expect(localIdFor('pbkurzid1234567'), 'pbkurzid1234567');
    });

    test('Zettel behalten ihre ID über den Server hinweg', () async {
      final note = await notes.create(body: 'Runde eins');
      await sync.syncNow();

      final onServer = backend.notes.values.single.$1;
      expect(onServer.id, note.id);
      expect(onServer.toJson()['id'], remoteIdFor(note.id));
      expect(SyncNote.fromJson(onServer.toJson()).id, note.id);
    });
  });

  group('Abschlusszeitpunkt', () {
    test('reist mit dem Zettel', () async {
      final step = await notes.create(type: NoteType.step, body: 'bauen');
      clock.advance(const Duration(minutes: 3));
      await notes.setStatus(step.id, NoteStatus.done);

      await sync.syncNow();

      final remote = backend.notes[step.id]!.$1;
      expect(remote.closedAt, DateTime.utc(2026, 5, 1, 12, 3));
      expect(remote.toJson()['closed_at'], '2026-05-01T12:03:00.000Z');
    });

    test('Zettel von vor Version 2 bekommen die letzte Änderung', () {
      final json = remoteNote(
        id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0001',
        updatedAt: DateTime.utc(2026, 1, 3, 10),
        status: NoteStatus.done,
      ).toJson()..['closed_at'] = '';

      expect(SyncNote.fromJson(json).closedAt, DateTime.utc(2026, 1, 3, 10));
      expect(SyncNote.fromJson(json..['status'] = 'open').closedAt, isNull);
    });
  });

  group('Bilder', () {
    late AttachmentRepository attachments;

    PreparedImage png([List<int> bytes = const [1, 2, 3]]) => PreparedImage(
      bytes: Uint8List.fromList(bytes),
      mimeType: 'image/png',
      fileName: 'skizze.png',
      width: 3,
      height: 1,
    );

    setUp(() {
      attachments = AttachmentRepository(
        db,
        deviceId: 'dieses-geraet',
        clock: clock,
      );
    });

    test(
      'ein neues Bild geht samt Datei hoch, danach nur die Beschreibung',
      () async {
        final note = await notes.create(body: 'mit Bild');
        final image = await attachments.add(note.id, png());

        final first = await sync.syncNow();
        expect(first.isSuccess, isTrue);
        expect(first.warning, isNull);
        expect(backend.uploads, 1);
        expect(backend.files[image.id], [1, 2, 3]);
        final local = (await attachments.findById(image.id))!;
        expect(local.uploaded, isTrue);
        expect(local.pendingSync, isFalse);
        expect(local.remoteFile, isNotNull);

        clock.advance(const Duration(minutes: 1));
        await attachments.delete(image.id);
        await sync.syncNow();

        expect(backend.uploads, 1, reason: 'Die Datei geht nur einmal mit.');
        expect(backend.attachments[image.id]!.$1.deletedAt, isNotNull);
      },
    );

    test(
      'ein Bild vom anderen Gerät wird geholt und heruntergeladen',
      () async {
        backend.seedAttachment(
          remoteAttachment(id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff00a1'),
          const [9, 8, 7],
        );

        final outcome = await sync.syncNow();

        expect(outcome.isSuccess, isTrue);
        final local = (await attachments.forNote(
          'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0001',
        )).single;
        expect(local.hasData, isTrue);
        expect(local.uploaded, isTrue);
        expect(local.pendingSync, isFalse);
        expect(await attachments.readBytes(local.id), [9, 8, 7]);
      },
    );

    test(
      'schon wieder entfernt, bevor es oben war: geht gar nicht erst hoch',
      () async {
        final note = await notes.create(body: 'x');
        final image = await attachments.add(note.id, png());
        await attachments.delete(image.id);

        await sync.syncNow();

        expect(backend.attachments, isEmpty);
        expect((await attachments.findById(image.id))!.pendingSync, isFalse);
      },
    );

    test('ein alter Server ohne Bilder hält den Rest nicht auf', () async {
      backend.supportsAttachments = false;
      final note = await notes.create(body: 'Zettel mit Bild');
      final image = await attachments.add(note.id, png());

      final outcome = await sync.syncNow();

      expect(outcome.isSuccess, isTrue);
      expect(outcome.warning, contains('keine Bilder'));
      expect(backend.notes.containsKey(note.id), isTrue);
      // Das Bild wartet, bis der Server aktualisiert ist.
      expect((await attachments.findById(image.id))!.pendingSync, isTrue);

      backend.supportsAttachments = true;
      final later = await sync.syncNow();
      expect(later.warning, isNull);
      expect(backend.files[image.id], [1, 2, 3]);
    });

    test(
      'ein Bild, das nicht kommt, wird beim nächsten Mal nachgeholt',
      () async {
        const id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff00a2';
        backend.seedAttachment(remoteAttachment(id: id), const [5]);
        backend.failDownloads.add(id);

        final first = await sync.syncNow();
        expect(first.isSuccess, isTrue);
        expect(first.warning, 'Ein Bild ließ sich nicht laden.');
        expect((await attachments.findById(id))!.hasData, isFalse);

        backend.failDownloads.clear();
        await sync.syncNow();
        expect(await attachments.readBytes(id), [5]);
      },
    );

    test(
      'hat der Server das Bild verloren, geht die Datei erneut hoch',
      () async {
        final note = await notes.create(body: 'x');
        final image = await attachments.add(note.id, png());
        await sync.syncNow();
        backend.attachments.clear();
        backend.files.clear();

        clock.advance(const Duration(minutes: 1));
        await attachments.delete(image.id);
        await attachments.restore(image.id);
        await sync.syncNow();
        expect((await attachments.findById(image.id))!.uploaded, isFalse);

        await sync.syncNow();
        expect(backend.files[image.id], [1, 2, 3]);
        expect((await attachments.findById(image.id))!.uploaded, isTrue);
      },
    );

    test('die Beschreibung überlebt den Weg über die Leitung', () {
      final original = remoteAttachment(
        id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff00a3',
      );
      final json = original.toJson()..['file'] = 'skizze_ab12cd.png';

      final back = SyncAttachment.fromJson(json);

      expect(back.id, original.id);
      expect(back.noteId, original.noteId);
      expect(back.fileName, 'skizze.png');
      expect(back.remoteFile, 'skizze_ab12cd.png');
      expect((back.width, back.height), (3, 1));
      expect(json['id'], 'aaaaaaaabbbbccccddddeeeeffff00a3');
      expect(json.containsKey('file'), isTrue);
      expect(original.toJson().containsKey('file'), isFalse);
    });
  });
}
