import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../core/sort_order.dart';
import '../db/database.dart';
import '../models/note_status.dart';
import '../models/note_type.dart';
import 'attachment_repository.dart';

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

/// Was ein Verschieben verändert hat – genug, um es zurückzunehmen.
///
/// Mehr als „zurück ins alte Projekt“: der Zettel soll wieder an seiner
/// alten Stelle stehen, und eine Anweisung, die ihm im Zielprojekt weichen
/// musste, soll wieder gelten.
class NoteMove {
  const NoteMove({
    required this.noteId,
    required this.fromProjectId,
    required this.fromSortOrder,
    this.retiredInstructionIds = const [],
  });

  final String noteId;
  final String? fromProjectId;
  final double fromSortOrder;
  final List<String> retiredInstructionIds;
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

  // --- Übersicht über alle Projekte ---------------------------------------

  /// Offene Arbeitszettel mit Priorität aus allen Projekten, wichtigste
  /// zuerst, bei gleicher Priorität der zuletzt bearbeitete – „was steht
  /// an?“ auf einen Blick.
  Stream<List<NoteRow>> watchPrioritized({int limit = 12}) {
    return (_db.select(_db.notes)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.archivedAt.isNull() &
                t.status.equalsValue(NoteStatus.open) &
                t.priority.isNotNull() &
                t.type.isInValues(_workTypes) &
                _outsideArchivedProjects(t),
          )
          ..orderBy([
            (t) => OrderingTerm(expression: _priorityRank(t)),
            (t) =>
                OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  /// Zuletzt abgeschlossene Arbeitszettel, neueste zuerst.
  ///
  /// Archivierte Zettel zählen mit: eine beantwortete Frage wandert sofort
  /// ins Archiv, erledigt ist sie trotzdem. Zettel archivierter Projekte
  /// dagegen nicht – das Projekt ist aus dem Blick, dann auch sie.
  Stream<List<NoteRow>> watchRecentlyClosed({int limit = 8}) {
    return (_db.select(_db.notes)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.closedAt.isNotNull() &
                t.status.equalsValue(NoteStatus.done) &
                t.type.isInValues(_workTypes) &
                _outsideArchivedProjects(t),
          )
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.closedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  /// Offene und abgeschlossene Arbeitszettel pro Projekt (`null` = Inbox) –
  /// für die Fortschrittsbalken.
  ///
  /// Gezählt wird, was auf dem Board liegt; Archiviertes ist aufgeräumt und
  /// verschwindet auch aus der Rechnung.
  Stream<Map<String?, NoteProgress>> watchProgress() {
    final count = _db.notes.id.count();
    final query = _db.selectOnly(_db.notes)
      ..addColumns([_db.notes.projectId, _db.notes.status, count])
      ..where(
        _db.notes.deletedAt.isNull() &
            _db.notes.archivedAt.isNull() &
            _db.notes.type.isInValues(_workTypes),
      )
      ..groupBy([_db.notes.projectId, _db.notes.status]);
    return query.watch().map((rows) {
      final open = <String?, int>{};
      final closed = <String?, int>{};
      for (final row in rows) {
        final projectId = row.read(_db.notes.projectId);
        final status = row.readWithConverter(_db.notes.status)!;
        final target = status.isOpen ? open : closed;
        target[projectId] = (target[projectId] ?? 0) + (row.read(count) ?? 0);
      }
      return {
        for (final projectId in {...open.keys, ...closed.keys})
          projectId: NoteProgress(
            open: open[projectId] ?? 0,
            closed: closed[projectId] ?? 0,
          ),
      };
    });
  }

  /// Die gerade geltende Anweisung jedes Projekts (`null` = Inbox).
  Stream<Map<String?, NoteRow>> watchCurrentInstructions() {
    return (_db.select(_db.notes)..where(
          (t) =>
              t.deletedAt.isNull() &
              t.archivedAt.isNull() &
              t.type.equalsValue(NoteType.instruction) &
              t.status.equalsValue(NoteStatus.open),
        ))
        .watch()
        .map((notes) => {for (final note in notes) note.projectId: note});
  }

  /// Der nächste offene Schritt jedes Projekts – wichtigster zuerst, bei
  /// gleicher Priorität der, der in der Liste oben steht.
  Stream<Map<String?, NoteRow>> watchNextSteps() {
    return (_db.select(_db.notes)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.archivedAt.isNull() &
                t.type.equalsValue(NoteType.step) &
                t.status.equalsValue(NoteStatus.open),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .watch()
        .map((steps) {
          final next = <String?, NoteRow>{};
          for (final step in steps) {
            final current = next[step.projectId];
            if (current == null ||
                NotePriority.rankOf(step.priority) <
                    NotePriority.rankOf(current.priority)) {
              next[step.projectId] = step;
            }
          }
          return next;
        });
  }

  static final List<NoteType> _workTypes = NoteType.values
      .where((type) => type.isWorkItem)
      .toList(growable: false);

  /// Der Rang der Priorität als Zahl, wie [NotePriority.rankOf]. In SQL, weil
  /// die Priorität als Name in der Tabelle steht und alphabetisch „could“
  /// vor „must“ käme – und damit `LIMIT` die wichtigsten trifft.
  Expression<int> _priorityRank($NotesTable t) => CaseWhenExpression<int>(
    cases: [
      for (final priority in NotePriority.displayOrder)
        CaseWhen(
          t.priority.equalsValue(priority),
          then: Constant(NotePriority.rankOf(priority)),
        ),
    ],
    orElse: Constant(NotePriority.rankOf(null)),
  );

  /// Nicht in einem archivierten Projekt. Inbox-Zettel und solche, deren
  /// Projekt noch nicht angekommen ist, zählen mit – die zeigt die App in
  /// der Inbox.
  Expression<bool> _outsideArchivedProjects($NotesTable t) {
    final archived = _db.selectOnly(_db.projects)
      ..addColumns([_db.projects.id])
      ..where(_db.projects.archivedAt.isNotNull());
    return t.projectId.isNull() | t.projectId.isNotInQuery(archived);
  }

  // --- Schreiben ---------------------------------------------------------

  /// Legt einen Zettel an.
  ///
  /// [status] erlaubt, gleich einen abgeschlossenen Zettel anzulegen – beim
  /// Import einer Liste, in der schon Punkte abgehakt sind (`- [x] …`).
  Future<NoteRow> create({
    String? projectId,
    NoteType type = NoteType.idea,
    String body = '',
    String? title,
    List<String> tags = const [],
    NotePriority? priority,
    NoteStatus status = NoteStatus.open,
    DateTime? createdAt,
  }) async {
    final now = _clock.now();
    final row = NoteRow(
      id: newId(),
      projectId: projectId,
      type: type,
      title: title == null || title.isEmpty ? null : title,
      body: body,
      status: status,
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
      closedAt: status.isOpen ? null : now,
      deviceId: deviceId,
      pendingSync: true,
    );

    await _db.transaction(() async {
      await _db.into(_db.notes).insert(row);
      if (type == NoteType.instruction && status.isOpen) {
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

  /// Verschiebt einen Zettel ans Ende eines anderen Projekts (`null` =
  /// Inbox). Liefert, was [undoMove] braucht, oder `null`, wenn sich nichts
  /// geändert hat.
  Future<NoteMove?> moveToProject(String id, String? projectId) async {
    final note = await findById(id);
    if (note == null || note.projectId == projectId) return null;

    final now = _clock.now();
    return _db.transaction(() async {
      await _write(
        note.id,
        NotesCompanion(
          projectId: Value(projectId),
          sortOrder: Value(await _nextSortOrder(projectId)),
        ),
        now: now,
      );
      final retired = note.type == NoteType.instruction && note.status.isOpen
          ? await _retireOtherInstructions(projectId, keep: note.id, now: now)
          : const <String>[];
      return NoteMove(
        noteId: note.id,
        fromProjectId: note.projectId,
        fromSortOrder: note.sortOrder,
        retiredInstructionIds: retired,
      );
    });
  }

  /// Nimmt [move] zurück: der Zettel steht wieder an seiner alten Stelle,
  /// und was ihm weichen musste, gilt wieder.
  Future<void> undoMove(NoteMove move) async {
    final note = await findById(move.noteId);
    if (note == null) return;

    final now = _clock.now();
    await _db.transaction(() async {
      await _write(
        note.id,
        NotesCompanion(
          projectId: Value(move.fromProjectId),
          sortOrder: Value(move.fromSortOrder),
        ),
        now: now,
      );
      // Auch zurück gilt: eine aktive Anweisung pro Projekt. Hat jemand
      // inzwischen im alten Projekt eine neue angelegt, geht die in den
      // Verlauf.
      if (note.type == NoteType.instruction && note.status.isOpen) {
        await _retireOtherInstructions(
          move.fromProjectId,
          keep: note.id,
          now: now,
        );
      }
      for (final id in move.retiredInstructionIds) {
        await _write(
          id,
          const NotesCompanion(
            status: Value(NoteStatus.open),
            closedAt: Value(null),
          ),
          now: now,
        );
      }
    });
  }

  /// Setzt den Status und hält den Abschlusszeitpunkt mit.
  ///
  /// Wechselt ein Zettel nur zwischen „erledigt“ und „verworfen“, bleibt der
  /// Zeitpunkt stehen: abgeschlossen war er da schon.
  Future<void> setStatus(String id, NoteStatus status) async {
    final note = await findById(id);
    if (note == null || note.status == status) return;

    final now = _clock.now();
    await _db.transaction(() async {
      await _write(
        note.id,
        NotesCompanion(
          status: Value(status),
          closedAt: Value(status.isOpen ? null : (note.closedAt ?? now)),
        ),
        now: now,
      );
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
        closedAt: Value(note.closedAt ?? now),
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
  ///
  /// Die Bilder des Zettels gehen mit, und zwar mit genau demselben
  /// Zeitstempel: daran erkennt [restore], welche Bilder zu dieser Löschung
  /// gehören und welche schon vorher einzeln entfernt wurden.
  Future<void> delete(String id) async {
    final now = _clock.now();
    await _db.transaction(() async {
      await _write(id, NotesCompanion(deletedAt: Value(now)), now: now);
      await tombstoneAttachmentsOf(_db, [id], now: now, deviceId: deviceId);
    });
  }

  /// Holt einen gelöschten Zettel zurück – für „Rückgängig“ nach dem Löschen.
  Future<void> restore(String id) async {
    final note = await findById(id);
    final deletedAt = note?.deletedAt;
    if (note == null || deletedAt == null) return;

    final now = _clock.now();
    await _db.transaction(() async {
      await _write(id, const NotesCompanion(deletedAt: Value(null)), now: now);
      await (_db.update(_db.attachments)
            ..where((t) => t.noteId.equals(id) & t.deletedAt.equals(deletedAt)))
          .write(
            AttachmentsCompanion(
              deletedAt: const Value(null),
              updatedAt: Value(now),
              deviceId: Value(deviceId),
              pendingSync: const Value(true),
            ),
          );
    });
  }

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
  /// `@projekt`, `!typ` und `!hoch` müssen vorher aufgelöst und als
  /// [projectId], [type] bzw. [priority] übergeben werden, `#tag` und freie
  /// Wörter landen in [terms].
  /// Alle Begriffe müssen zutreffen (UND).
  Stream<List<NoteRow>> search({
    List<String> terms = const [],
    String? projectId,
    bool projectFilterActive = false,
    NoteType? type,
    NotePriority? priority,
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
    if (priority != null) {
      query.where((t) => t.priority.equalsValue(priority));
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
  /// Anweisungen wandern in den Verlauf (`done`). Liefert ihre IDs, damit
  /// sich das zurücknehmen lässt.
  Future<List<String>> _retireOtherInstructions(
    String? projectId, {
    required String keep,
    required DateTime now,
  }) async {
    final query = _db.selectOnly(_db.notes)
      ..addColumns([_db.notes.id])
      ..where(
        _db.notes.type.equalsValue(NoteType.instruction) &
            _db.notes.status.equalsValue(NoteStatus.open) &
            _db.notes.id.equals(keep).not() &
            _db.notes.deletedAt.isNull() &
            (projectId == null
                ? _db.notes.projectId.isNull()
                : _db.notes.projectId.equals(projectId)),
      );
    final ids = await query.map((row) => row.read(_db.notes.id)!).get();
    if (ids.isEmpty) return const [];

    await (_db.update(_db.notes)..where((t) => t.id.isIn(ids))).write(
      NotesCompanion(
        status: const Value(NoteStatus.done),
        // Ab jetzt steht sie im Verlauf – „galt bis“.
        closedAt: Value(now),
        updatedAt: Value(now),
        deviceId: Value(deviceId),
        pendingSync: const Value(true),
      ),
    );
    return ids;
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

/// Wie weit ein Projekt ist: offene und abgeschlossene Arbeitszettel.
class NoteProgress {
  const NoteProgress({required this.open, required this.closed});

  static const NoteProgress empty = NoteProgress(open: 0, closed: 0);

  final int open;
  final int closed;

  int get total => open + closed;

  /// Anteil abgeschlossen, von 0 bis 1. Ein leeres Projekt steht bei 0.
  double get ratio => total == 0 ? 0 : closed / total;

  @override
  bool operator ==(Object other) =>
      other is NoteProgress && other.open == open && other.closed == closed;

  @override
  int get hashCode => Object.hash(open, closed);

  @override
  String toString() => 'NoteProgress(open: $open, closed: $closed)';
}
