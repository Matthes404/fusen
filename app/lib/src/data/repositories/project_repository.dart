import 'package:drift/drift.dart';

import '../../core/clock.dart';
import '../../core/ids.dart';
import '../../core/sort_order.dart';
import '../db/database.dart';

/// Vorschlagsfarben für neue Projekte (ARGB).
const List<int> projectPalette = [
  0xFFE5484D, // rot
  0xFFF76B15, // orange
  0xFFFFB224, // gelb
  0xFF30A46C, // grün
  0xFF12A594, // türkis
  0xFF0091FF, // blau
  0xFF6E56CF, // violett
  0xFFE93D82, // pink
];

/// Lesen und Schreiben von Projekten. Kennt keine Widgets und keinen Sync –
/// jede Änderung markiert den Datensatz nur als `pendingSync`.
class ProjectRepository {
  ProjectRepository(this._db, {this._clock = const SystemClock()});

  final FusenDatabase _db;
  final Clock _clock;

  Stream<List<ProjectRow>> watchProjects({bool includeArchived = false}) {
    final query = _db.select(_db.projects)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.name),
      ]);
    if (!includeArchived) {
      query.where((t) => t.archivedAt.isNull());
    }
    return query.watch();
  }

  Stream<ProjectRow?> watchProject(String id) => (_db.select(
    _db.projects,
  )..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<ProjectRow?> findById(String id) => (_db.select(
    _db.projects,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Sucht ein Projekt anhand einer Eingabe aus der Schnelleingabe (`@chess`).
  ///
  /// Erst exakt (ohne Rücksicht auf Groß-/Kleinschreibung), dann als Präfix.
  /// Ein Präfix zählt nur, wenn er eindeutig ist – sonst würde `@p` mal in
  /// „Praktikum“ und mal in „Portfolio“ landen.
  Future<ProjectRow?> findByNameOrPrefix(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return null;

    final all = await (_db.select(
      _db.projects,
    )..where((t) => t.deletedAt.isNull())).get();

    for (final project in all) {
      if (project.name.toLowerCase() == needle) return project;
    }

    final active = all.where((p) => p.archivedAt == null);
    final prefixMatches = active
        .where((p) => p.name.toLowerCase().startsWith(needle))
        .toList();
    if (prefixMatches.length == 1) return prefixMatches.first;
    return null;
  }

  Future<ProjectRow> create({required String name, int? color}) async {
    final now = _clock.now();
    final existingMax = await _maxSortOrder();
    final row = ProjectRow(
      id: newId(),
      name: name.trim(),
      color: color ?? projectPalette[_nextPaletteIndex(await _projectCount())],
      sortOrder: existingMax + sortOrderGap,
      createdAt: now,
      updatedAt: now,
      pendingSync: true,
    );
    await _db.into(_db.projects).insert(row);
    return row;
  }

  /// Liefert das Projekt mit diesem Namen oder legt es an.
  ///
  /// Beim Capture soll ein `@neuesprojekt` nicht in einem Dialog enden –
  /// lieber unsauber gespeichert als gar nicht.
  Future<ProjectRow> findOrCreate(String name) async {
    final existing = await findByNameOrPrefix(name);
    if (existing != null) return existing;
    return create(name: name);
  }

  Future<void> rename(String id, String name) =>
      _update(id, ProjectsCompanion(name: Value(name.trim())));

  Future<void> setColor(String id, int color) =>
      _update(id, ProjectsCompanion(color: Value(color)));

  Future<void> archive(String id) =>
      _update(id, ProjectsCompanion(archivedAt: Value(_clock.now())));

  Future<void> unarchive(String id) =>
      _update(id, const ProjectsCompanion(archivedAt: Value(null)));

  /// Setzt einen Tombstone statt hart zu löschen, damit die Löschung auf
  /// anderen Geräten ankommt. Die Zettel des Projekts werden mitgelöscht.
  Future<void> delete(String id) async {
    final now = _clock.now();
    await _db.transaction(() async {
      await (_db.update(_db.projects)..where((t) => t.id.equals(id))).write(
        ProjectsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          pendingSync: const Value(true),
        ),
      );
      await (_db.update(
        _db.notes,
      )..where((t) => t.projectId.equals(id) & t.deletedAt.isNull())).write(
        NotesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          pendingSync: const Value(true),
        ),
      );
    });
  }

  /// Schreibt die Reihenfolge nach einem Drag-and-drop.
  Future<void> reorder(List<String> idsInOrder) async {
    final orders = rebalancedSortOrders(idsInOrder.length);
    final now = _clock.now();
    await _db.transaction(() async {
      for (var i = 0; i < idsInOrder.length; i++) {
        await (_db.update(
          _db.projects,
        )..where((t) => t.id.equals(idsInOrder[i]))).write(
          ProjectsCompanion(
            sortOrder: Value(orders[i]),
            updatedAt: Value(now),
            pendingSync: const Value(true),
          ),
        );
      }
    });
  }

  Future<void> _update(String id, ProjectsCompanion changes) async {
    await (_db.update(_db.projects)..where((t) => t.id.equals(id))).write(
      changes.copyWith(
        updatedAt: Value(_clock.now()),
        pendingSync: const Value(true),
      ),
    );
  }

  Future<double> _maxSortOrder() async {
    final max = _db.projects.sortOrder.max();
    final row = await (_db.selectOnly(
      _db.projects,
    )..addColumns([max])).getSingle();
    return row.read(max) ?? 0;
  }

  Future<int> _projectCount() async {
    final count = _db.projects.id.count();
    final row = await (_db.selectOnly(
      _db.projects,
    )..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  int _nextPaletteIndex(int count) => count % projectPalette.length;
}
