import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fusen/src/data/attachments/image_prep.dart';
import 'package:fusen/src/data/db/database.dart';
import 'package:fusen/src/data/models/note_status.dart';
import 'package:fusen/src/data/repositories/attachment_repository.dart';

/// Das Schema von Version 1, so wie es drift damals angelegt hat
/// (`SELECT sql FROM sqlite_master`).
const List<String> _schemaV1 = [
  'CREATE TABLE "projects" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"color" INTEGER NOT NULL, "sort_order" REAL NOT NULL, '
      '"created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, '
      '"archived_at" TEXT NULL, "deleted_at" TEXT NULL, '
      '"pending_sync" INTEGER NOT NULL DEFAULT 1 '
      'CHECK ("pending_sync" IN (0, 1)), PRIMARY KEY ("id"))',
  'CREATE TABLE "notes" ("id" TEXT NOT NULL, "project_id" TEXT NULL, '
      '"type" TEXT NOT NULL, "title" TEXT NULL, '
      '"body" TEXT NOT NULL DEFAULT \'\', "answer" TEXT NULL, '
      '"status" TEXT NOT NULL, "priority" TEXT NULL, '
      '"tags" TEXT NOT NULL DEFAULT \'[]\', "sort_order" REAL NOT NULL, '
      '"search_text" TEXT NOT NULL DEFAULT \'\', "created_at" TEXT NOT NULL, '
      '"updated_at" TEXT NOT NULL, "archived_at" TEXT NULL, '
      '"deleted_at" TEXT NULL, "device_id" TEXT NOT NULL, '
      '"pending_sync" INTEGER NOT NULL DEFAULT 1 '
      'CHECK ("pending_sync" IN (0, 1)), PRIMARY KEY ("id"))',
  'CREATE TABLE "settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, '
      'PRIMARY KEY ("key"))',
  'CREATE INDEX idx_notes_project ON notes (project_id, type, status)',
  'CREATE INDEX idx_notes_pending ON notes (pending_sync)',
  'CREATE INDEX idx_projects_pending ON projects (pending_sync)',
];

String _note(String id, String status, String updatedAt) =>
    'INSERT INTO notes (id, type, status, sort_order, created_at, '
    "updated_at, device_id, pending_sync) VALUES ('$id', 'step', "
    "'$status', 1024, '2026-01-01T08:00:00.000Z', '$updatedAt', 'alt', 0)";

FusenDatabase _openV1() {
  return FusenDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        // Die Einrichtung läuft bei jedem Öffnen – nur beim ersten Mal ist
        // die Datei leer.
        final version = raw.select('PRAGMA user_version').first.values.first;
        if (version != 0) return;
        for (final statement in _schemaV1) {
          raw.execute(statement);
        }
        raw.execute(_note('offen', 'open', '2026-01-02T09:00:00.000Z'));
        raw.execute(_note('fertig', 'done', '2026-01-03T10:30:00.000Z'));
        raw.execute('PRAGMA user_version = 1');
      },
    ),
  );
}

Future<Map<String, List<String>>> _columns(FusenDatabase db) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return {
    for (final table in tables)
      table.read<String>('name'): [
        for (final column
            in await db
                .customSelect(
                  'PRAGMA table_info("${table.read<String>('name')}")',
                )
                .get())
          '${column.read<String>('name')} ${column.read<String>('type')} '
              'notnull=${column.read<int>('notnull')} '
              'default=${column.data['dflt_value']}',
      ]..sort(),
  };
}

void main() {
  // Der Vergleichstest öffnet bewusst zwei getrennte Datenbanken.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('Version 1 wird auf Version 2 gehoben', () async {
    final db = _openV1();
    addTearDown(db.close);

    final rows = {for (final n in await db.select(db.notes).get()) n.id: n};

    expect(rows['offen']!.closedAt, isNull);
    // Der beste verfügbare Schätzwert: die letzte Änderung.
    expect(rows['fertig']!.status, NoteStatus.done);
    expect(rows['fertig']!.closedAt, DateTime.utc(2026, 1, 3, 10, 30));
    // Die Migration selbst ist keine Änderung, die zum Server müsste.
    expect(rows.values.every((n) => !n.pendingSync), isTrue);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 2);
  });

  test('nach der Migration lassen sich Bilder anhängen', () async {
    final db = _openV1();
    addTearDown(db.close);

    final repository = AttachmentRepository(db, deviceId: 'neu');
    final image = await repository.add(
      'offen',
      PreparedImage(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        mimeType: 'image/png',
        fileName: 'a.png',
      ),
    );

    expect(await repository.readBytes(image.id), [1, 2, 3]);
  });

  test('migriertes und frisch angelegtes Schema sind gleich', () async {
    final migrated = _openV1();
    final fresh = FusenDatabase.memory();
    addTearDown(migrated.close);
    addTearDown(fresh.close);

    expect(await _columns(migrated), await _columns(fresh));

    Future<List<String>> indexes(FusenDatabase db) async => [
      for (final row
          in await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index' "
                "AND name NOT LIKE 'sqlite_%' ORDER BY name",
              )
              .get())
        row.read<String>('name'),
    ];
    expect(await indexes(migrated), await indexes(fresh));
  });
}
