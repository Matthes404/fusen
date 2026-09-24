import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../core/sort_order.dart';
import '../attachments/image_prep.dart';
import '../db/database.dart';

/// Bilder an Zetteln.
///
/// Wie bei Zetteln gilt: nichts wird hart gelöscht. Ein entferntes Bild
/// bekommt einen Tombstone, damit die Löschung beim Abgleich ankommt; die
/// Bilddaten bleiben noch eine Weile liegen, damit „Rückgängig“ funktioniert
/// (siehe [purgeDeletedData]).
class AttachmentRepository {
  AttachmentRepository(
    this._db, {
    required this.deviceId,
    this._clock = const SystemClock(),
  });

  final FusenDatabase _db;
  final String deviceId;
  final Clock _clock;

  // --- Lesen -------------------------------------------------------------

  /// Die sichtbaren Bilder eines Zettels, in der Reihenfolge des Anhängens.
  Stream<List<AttachmentRow>> watchForNote(String noteId) =>
      _forNoteQuery(noteId).watch();

  Future<List<AttachmentRow>> forNote(String noteId) =>
      _forNoteQuery(noteId).get();

  Future<AttachmentRow?> findById(String id) => (_db.select(
    _db.attachments,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Die Bilddaten – `null`, solange sie noch nicht heruntergeladen sind.
  Future<Uint8List?> readBytes(String id) async {
    final row = await (_db.select(
      _db.attachmentBlobs,
    )..where((t) => t.attachmentId.equals(id))).getSingleOrNull();
    return row?.bytes;
  }

  /// Die Bilddaten, sobald sie da sind.
  ///
  /// Beobachtet wird nur das Merkmal `hasData` der Beschreibung und nicht
  /// die Daten selbst: drift fragt beobachtete Tabellen bei jeder Änderung
  /// neu ab, und jedes sichtbare Bild bei jedem Abgleich neu zu lesen,
  /// wären schnell ein paar hundert Megabyte.
  Stream<Uint8List?> watchBytes(String id) {
    final query = _db.selectOnly(_db.attachments)
      ..addColumns([_db.attachments.hasData])
      ..where(_db.attachments.id.equals(id));
    return query
        .watchSingleOrNull()
        .map((row) => row?.read(_db.attachments.hasData) ?? false)
        .distinct()
        .asyncMap((hasData) => hasData ? readBytes(id) : Future.value());
  }

  // --- Schreiben ---------------------------------------------------------

  /// Hängt ein aufbereitetes Bild (siehe [prepareImage]) an einen Zettel.
  Future<AttachmentRow> add(String noteId, PreparedImage image) async {
    final now = _clock.now();
    final row = AttachmentRow(
      id: newId(),
      noteId: noteId,
      fileName: image.fileName,
      mimeType: image.mimeType,
      byteSize: image.bytes.length,
      width: image.width,
      height: image.height,
      sortOrder: await _nextSortOrder(noteId),
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
      hasData: true,
      uploaded: false,
      pendingSync: true,
    );
    await _db.transaction(() async {
      await _db.into(_db.attachments).insert(row);
      await _db
          .into(_db.attachmentBlobs)
          .insert(AttachmentBlobRow(attachmentId: row.id, bytes: image.bytes));
    });
    return row;
  }

  /// Entfernt ein Bild vom Zettel (Tombstone). Die Daten bleiben vorerst
  /// liegen, damit [restore] sie zurückholen kann.
  Future<void> delete(String id) =>
      _write(id, AttachmentsCompanion(deletedAt: Value(_clock.now())));

  Future<void> restore(String id) =>
      _write(id, const AttachmentsCompanion(deletedAt: Value(null)));

  /// Räumt die Bilddaten gelöschter Bilder weg, sobald „Rückgängig“ keine
  /// Rolle mehr spielt. Die Beschreibung bleibt als Tombstone erhalten.
  ///
  /// Liefert die Anzahl der entfernten Bilder.
  Future<int> purgeDeletedData({
    Duration olderThan = const Duration(days: 7),
  }) async {
    final cutoff = _clock.now().subtract(olderThan);
    return _db.transaction(() async {
      final stale =
          await (_db.select(_db.attachments)..where(
                (t) =>
                    t.deletedAt.isNotNull() &
                    t.deletedAt.isSmallerThanValue(cutoff) &
                    t.hasData.equals(true),
              ))
              .get();
      if (stale.isEmpty) return 0;
      final ids = stale.map((a) => a.id).toList();
      await (_db.delete(
        _db.attachmentBlobs,
      )..where((t) => t.attachmentId.isIn(ids))).go();
      // Nur ein lokales Merkmal – deshalb ohne updatedAt und pendingSync.
      await (_db.update(_db.attachments)..where((t) => t.id.isIn(ids))).write(
        const AttachmentsCompanion(hasData: Value(false)),
      );
      return ids.length;
    });
  }

  // --- Interna -----------------------------------------------------------

  SimpleSelectStatement<$AttachmentsTable, AttachmentRow> _forNoteQuery(
    String noteId,
  ) {
    return _db.select(_db.attachments)
      ..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.createdAt),
      ]);
  }

  Future<void> _write(String id, AttachmentsCompanion changes) async {
    await (_db.update(_db.attachments)..where((t) => t.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(_clock.now()),
        deviceId: Value(deviceId),
        pendingSync: const Value(true),
      ),
    );
  }

  Future<double> _nextSortOrder(String noteId) async {
    final max = _db.attachments.sortOrder.max();
    final row =
        await (_db.selectOnly(_db.attachments)
              ..addColumns([max])
              ..where(_db.attachments.noteId.equals(noteId)))
            .getSingle();
    return (row.read(max) ?? 0) + sortOrderGap;
  }
}

/// Setzt Tombstones für alle noch sichtbaren Bilder dieser Zettel.
///
/// Gehört zum Löschen eines Zettels oder Projekts und läuft in dessen
/// Transaktion. [deviceId] ist `null`, wenn der Aufrufer kein Gerät kennt
/// (Projekte tragen keins) – dann bleibt das bisherige stehen.
Future<void> tombstoneAttachmentsOf(
  FusenDatabase db,
  List<String> noteIds, {
  required DateTime now,
  String? deviceId,
}) async {
  if (noteIds.isEmpty) return;
  await (db.update(
    db.attachments,
  )..where((t) => t.noteId.isIn(noteIds) & t.deletedAt.isNull())).write(
    AttachmentsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      deviceId: deviceId == null ? const Value.absent() : Value(deviceId),
      pendingSync: const Value(true),
    ),
  );
}
