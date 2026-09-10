import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../core/sort_order.dart';
import '../db/database.dart';
import '../models/note_status.dart';
import '../models/note_type.dart';

/// Wird geworfen, wenn ein Log-Eintrag nach Ablauf der 24-Stunden-Frist
/// geändert werden soll.
class NoteEditLockedException implements Exception {
  const NoteEditLockedException(this.noteId);

  final String noteId;

  @override
  String toString() =>
      'Log-Eintrag $noteId ist älter als 24 Stunden und nicht mehr editierbar.';
}

/// Ob der Inhalt dieses Zettels noch geändert werden darf.
///
/// Betrifft nur Log-Einträge: sie sind ein Protokoll und frieren nach
/// [logEditWindow] ein. Archivieren und Löschen bleiben immer erlaubt.
bool isContentEditable(NoteRow note, DateTime now) {
  if (!note.type.isImmutableAfterGracePeriod) return true;
  return now.difference(note.createdAt.toUtc()) < logEditWindow;
}

/// Alle Schreib- und Lesezugriffe auf Zettel, inklusive der Regeln aus dem
/// Konzept (eine aktive Anweisung pro Projekt, Log-Frist, beantwortete Fragen
/// wandern ins Archiv).
class NoteRepository {
  NoteRepository(
    this._db, {
    required this.deviceId,
    this._clock = const SystemClock(),
  });

  final FusenDatabase _db;

  /// Gerät, das den Datensatz zuletzt geschrieben hat – landet in jedem Zettel
  /// und hilft, Sync-Probleme zuzuordnen.
  final String deviceId;
  final Clock _clock;

  // --- Lesen -------------------------------------------------------------

  /// Alle sichtbaren Zettel eines Projekts außer dem Log.
  ///
  /// Das Log wird getrennt geladen ([watchLog]), weil es als einziger Bereich
  /// unbegrenzt wächst und in der Ansicht ohnehin eingeklappt ist.
  Stream<List<NoteRow>> watchBoard(String? projectId) {
    final query = _db.select(_db.notes)
      ..where((t) => t.deletedAt.isNull() & t.archivedAt.isNull())
      ..where((t) => t.type.equalsValue(NoteType.log).not())
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.createdAt),
      ]);
    _applyProjectFilter(query, projectId);
    return query.watch();
  }

  Stream<List<NoteRow>> watchLog(String? projectId, {int limit = 100}) {
    final query = _db.select(_db.notes)
      ..where((t) => t.deletedAt.isNull() & t.archivedAt.isNull())
      ..where((t) => t.type.equalsValue(NoteType.log))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    _applyProjectFilter(query, projectId);
    return query.watch();
  }

  /// Die Inbox: alles ohne Projekt, neueste zuerst.
  ///
  /// Anders als die Projekt-Ansicht wird hier nicht nach Typ getrennt – die
  /// Inbox ist zum Wegsortieren da, nicht zum Nachschlagen.
  Stream<List<NoteRow>> watchInbox() {
    return (_db.select(_db.notes)
          ..where(
            (t) =>
                t.projectId.isNull() &
                t.deletedAt.isNull() &
                t.archivedAt.isNull(),
          )
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<NoteRow>> watchArchive(String? projectId) {
    final query = _db.select(_db.notes)
      ..where((t) => t.deletedAt.isNull() & t.archivedAt.isNotNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.archivedAt, mode: OrderingMode.desc),
      ]);
    _applyProjectFilter(query, projectId);
    return query.watch();
  }

  Stream<NoteRow?> watchNote(String id) => (_db.select(
    _db.notes,
  )..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<NoteRow?> findById(String id) =>
      (_db.select(_db.notes)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Zählt offene Zettel pro Projekt – für die Badges in der Projektliste.
  Stream<Map<String?, int>> watchOpenCounts() {
    final count = _db.notes.id.count();
    final query = _db.selectOnly(_db.notes)
      ..addColumns([_db.notes.projectId, count])
      ..where(
        _db.notes.deletedAt.isNull() &
            _db.notes.archivedAt.isNull() &
            _db.notes.status.equalsValue(NoteStatus.open) &
            _db.notes.type.equalsValue(NoteType.log).not(),
      )
      ..groupBy([_db.notes.projectId]);
    return query.watch().map((rows) {
      return {
        for (final row in rows)
          row.read(_db.notes.projectId): row.read(count) ?? 0,
      };
    });
  }

  // --- Schreiben ---------------------------------------------------------

  Future<NoteRow> create({
    String? projectId,
    NoteType type = NoteType.idea,
    String body = '',
    String? title,
    List<String> tags = const [],
    NotePriority? priority,
    DateTime? createdAt,
  }) async {
    final now = _clock.now();
    final row = NoteRow(
      id: newId(),
      projectId: projectId,
      type: type,
      title: title,
      body: body,
      status: NoteStatus.open,
      priority: type.supportsPriority ? priority : null,
      tags: _normalizeTags(tags),
      sortOrder: await _nextSortOrder(projectId),
      searchText: buildSearchText(
        title: title,
        body: body,
        tags: _normalizeTags(tags),
      ),
      createdAt: createdAt?.toUtc() ?? now,
      updatedAt: now,
      deviceId: deviceId,
      pendingSync: true,
    );

    await _db.transaction(() async {
      await _db.into(_db.notes).insert(row);
      if (type == NoteType.instruction) {
        await _retireOtherInstructions(projectId, keep: row.id, now: now);
      }
    });
    return row;
  }

  Future<void> updateContent(
    String id, {
    String? title,
    String? body,
    List<String>? tags,
  }) async {
    final note = await _requireEditable(id);
    final nextTitle = title == null
        ? note.title
        : (title.isEmpty ? null : title);
    final nextBody = body ?? note.body;
    final nextTags = tags == null ? note.tags : _normalizeTags(tags);

    await _write(
      note.id,
      NotesCompanion(
        title: Value(nextTitle),
        body: Value(nextBody),
        tags: Value(nextTags),
        searchText: Value(
          buildSearchText(
            title: nextTitle,
            body: nextBody,
            answer: note.answer,
            tags: nextTags,
          ),
        ),
      ),
    );
  }

  /// Wechselt den Typ (Idee → Anforderung → Nächster Schritt …).
  ///
  /// Felder, die der neue Typ nicht kennt, werden geleert, damit keine
  /// unsichtbaren Altdaten zurückbleiben.
  Future<void> changeType(String id, NoteType type) async {
    final note = await _requireEditable(id);
    if (note.type == type) return;

    final now = _clock.now();
    await _db.transaction(() async {
      await _write(
        note.id,
        NotesCompanion(
          type: Value(type),
          priority: type.supportsPriority
              ? Value(note.priority)
              : const Value(null),
          answer: type.hasAnswer ? Value(note.answer) : const Value(null),
        ),
        now: now,
      );
      if (type == NoteType.instruction && note.status.isOpen) {
        await _retireOtherInstructions(note.projectId, keep: note.id, now: now);
      }
    });
  }

  /// Verschiebt einen Zettel in ein anderes Projekt (`null` = Inbox).
  Future<void> moveToProject(String id, String? projectId) async {
    final note = await findById(id);
    if (note == null || note.projectId == projectId) return;

    final now = _clock.now();
    await _db.transaction(() async {
      await _write(
        note.id,
        NotesCompanion(
          projectId: Value(projectId),
          sortOrder: Value(await _nextSortOrder(projectId)),
        ),
        now: now,
      );
      if (note.type == NoteType.instruction && note.status.isOpen) {
        await _retireOtherInstructions(projectId, keep: note.id, now: now);
      }
    });
  }

  Future<void> setStatus(String id, NoteStatus status) async {
    final note = await findById(id);
    if (note == null || note.status == status) return;

    final now = _clock.now();
    await _db.transaction(() async {
      await _write(note.id, NotesCompanion(status: Value(status)), now: now);
      if (note.type == NoteType.instruction && status.isOpen) {
        await _retireOtherInstructions(note.projectId, keep: note.id, now: now);
      }
    });
  }

  Future<void> setPriority(String id, NotePriority? priority) async {
    final note = await _requireEditable(id);
    if (!note.type.supportsPriority) return;
    await _write(note.id, NotesCompanion(priority: Value(priority)));
  }

  /// Beantwortet eine Frage: Antwort speichern, Frage schließen und
  /// archivieren – so verschwindet sie aus „Offene Fragen“.
  Future<void> answerQuestion(String id, String answer) async {
    final note = await _requireEditable(id);
    if (note.type != NoteType.question) return;
    final now = _clock.now();
    await _write(
      note.id,
      NotesCompanion(
        answer: Value(answer),
        status: const Value(NoteStatus.done),
        archivedAt: Value(now),
        searchText: Value(
          buildSearchText(
            title: note.title,
            body: note.body,
            answer: answer,
            tags: note.tags,
          ),
        ),
      ),
      now: now,
    );
  }

  Future<void> archive(String id) =>
      _write(id, NotesCompanion(archivedAt: Value(_clock.now())));

  Future<void> unarchive(String id) =>
      _write(id, const NotesCompanion(archivedAt: Value(null)));

  /// Tombstone statt hartem Löschen – siehe [ProjectRepository.delete].
  Future<void> delete(String id) =>
      _write(id, NotesCompanion(deletedAt: Value(_clock.now())));

  /// Neue Reihenfolge für die Nächsten Schritte eines Projekts.
  Future<void> reorder(List<String> idsInOrder) async {
    final orders = rebalancedSortOrders(idsInOrder.length);
    final now = _clock.now();
    await _db.transaction(() async {
      for (var i = 0; i < idsInOrder.length; i++) {
        await _write(
          idsInOrder[i],
          NotesCompanion(sortOrder: Value(orders[i])),
          now: now,
        );
      }
    });
  }

  // --- Suche -------------------------------------------------------------

  /// Volltextsuche über alle Zettel.
  ///
  /// Die Eingabe versteht dieselben Kurzbefehle wie die Schnelleingabe:
  /// `@projekt` und `!typ` müssen vorher aufgelöst und als [projectId] bzw.
  /// [type] übergeben werden, `#tag` und freie Wörter landen in [terms].
  /// Alle Begriffe müssen zutreffen (UND).
  Stream<List<NoteRow>> search({
    List<String> terms = const [],
    String? projectId,
    bool projectFilterActive = false,
    NoteType? type,
    bool includeArchived = true,
  }) {
    final needles = terms
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();

    final query = _db.select(_db.notes)..where((t) => t.deletedAt.isNull());
    if (!includeArchived) {
      query.where((t) => t.archivedAt.isNull());
    }
    if (projectFilterActive) {
      _applyProjectFilter(query, projectId);
    }
    if (type != null) {
      query.where((t) => t.type.equalsValue(type));
    }
    for (final needle in needles) {
      query.where((t) => t.searchText.contains(needle));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  // --- Interna -----------------------------------------------------------

  /// Nur *eine* aktive Anweisung pro Projekt: alle anderen offenen
  /// Anweisungen wandern in den Verlauf (`done`).
  Future<void> _retireOtherInstructions(
    String? projectId, {
    required String keep,
    required DateTime now,
  }) async {
    final update = _db.update(_db.notes)
      ..where(
        (t) =>
            t.type.equalsValue(NoteType.instruction) &
            t.status.equalsValue(NoteStatus.open) &
            t.id.equals(keep).not() &
            t.deletedAt.isNull(),
      );
    if (projectId == null) {
      update.where((t) => t.projectId.isNull());
    } else {
      update.where((t) => t.projectId.equals(projectId));
    }
    await update.write(
      NotesCompanion(
        status: const Value(NoteStatus.done),
        updatedAt: Value(now),
        deviceId: Value(deviceId),
        pendingSync: const Value(true),
      ),
    );
  }

  Future<NoteRow> _requireEditable(String id) async {
    final note = await findById(id);
    if (note == null) throw StateError('Zettel $id existiert nicht.');
    if (!isContentEditable(note, _clock.now())) {
      throw NoteEditLockedException(id);
    }
    return note;
  }

  Future<void> _write(
    String id,
    NotesCompanion changes, {
    DateTime? now,
  }) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(now ?? _clock.now()),
        deviceId: Value(deviceId),
        pendingSync: const Value(true),
      ),
    );
  }

  void _applyProjectFilter(
    SimpleSelectStatement<$NotesTable, NoteRow> query,
    String? projectId,
  ) {
    if (projectId == null) {
      query.where((t) => t.projectId.isNull());
    } else {
      query.where((t) => t.projectId.equals(projectId));
    }
  }

  Future<double> _nextSortOrder(String? projectId) async {
    final max = _db.notes.sortOrder.max();
    final query = _db.selectOnly(_db.notes)..addColumns([max]);
    if (projectId == null) {
      query.where(_db.notes.projectId.isNull());
    } else {
      query.where(_db.notes.projectId.equals(projectId));
    }
    final row = await query.getSingle();
    return (row.read(max) ?? 0) + sortOrderGap;
  }

  static List<String> _normalizeTags(List<String> tags) {
    final seen = <String>{};
    for (final tag in tags) {
      final clean = tag.trim().toLowerCase().replaceAll(RegExp(r'^#+'), '');
      if (clean.isNotEmpty) seen.add(clean);
    }
    return seen.toList(growable: false)..sort();
  }
}

/// Baut den durchsuchbaren Text eines Zettels.
///
/// Kleinbuchstaben in Dart, damit Umlaute korrekt gefaltet werden – siehe
/// `Notes.searchText`.
String buildSearchText({
  String? title,
  String? body,
  String? answer,
  List<String> tags = const [],
}) {
  final parts = <String>[
    if (title != null && title.isNotEmpty) title,
    if (body != null && body.isNotEmpty) body,
    if (answer != null && answer.isNotEmpty) answer,
    for (final tag in tags) '#$tag',
  ];
  return parts.join('\n').toLowerCase();
}
