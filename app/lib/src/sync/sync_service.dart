import 'package:drift/drift.dart';

import '../core/clock.dart';
import '../data/db/database.dart';
import '../data/db/settings_store.dart';
import '../data/repositories/note_repository.dart';
import 'sync_backend.dart';
import 'sync_records.dart';

enum SyncStatus {
  /// Kein Server hinterlegt – die App läuft rein lokal.
  disabled,
  idle,
  running,
  success,

  /// Zugangscode passt nicht (mehr).
  authFailed,
  error,
}

class SyncOutcome {
  const SyncOutcome({
    required this.status,
    this.pushed = 0,
    this.pulled = 0,
    this.message,
    this.at,
  });

  final SyncStatus status;
  final int pushed;
  final int pulled;
  final String? message;
  final DateTime? at;

  bool get isSuccess => status == SyncStatus.success;
}

/// Gleicht die lokale Datenbank mit dem Server ab.
///
/// Ablauf: erst schieben, dann holen. Dadurch kommen eigene Änderungen im
/// selben Durchlauf wieder herunter – das ist verschwendete Bandbreite, aber
/// das Zusammenführen ist idempotent, und wir sparen uns einen zweiten
/// Cursor für „von mir selbst geschrieben“.
///
/// Konflikte: Last-Write-Wins auf Datensatzebene anhand von `updated_at`.
/// Zwei Geräte, die denselben Zettel gleichzeitig ändern, verlieren also die
/// ältere Fassung. Eine Merge-Ansicht steht im Konzept als P2.
class SyncService {
  SyncService({
    required FusenDatabase database,
    required SyncBackend backend,
    required SettingsStore settings,
    this._clock = const SystemClock(),
  })  : _db = database,
        _backend = backend,
        _settings = settings;

  final FusenDatabase _db;
  final SyncBackend _backend;
  final SettingsStore _settings;
  final Clock _clock;

  SyncCredentials? _connectedWith;
  bool _running = false;

  Future<SyncCredentials?> readCredentials() async {
    final url = await _settings.read(SettingKeys.serverUrl);
    final code = await _settings.read(SettingKeys.accessCode);
    if (url == null || code == null) return null;
    final credentials = SyncCredentials(serverUrl: url, accessCode: code);
    return credentials.isComplete ? credentials : null;
  }

  Future<void> saveCredentials(SyncCredentials? credentials) async {
    await _settings.write(SettingKeys.serverUrl, credentials?.serverUrl);
    await _settings.write(SettingKeys.accessCode, credentials?.accessCode);
    if (credentials == null) {
      await _settings.write(SettingKeys.lastPulledAt, null);
      await _backend.disconnect();
    }
    _connectedWith = null;
  }

  /// Prüft Server und Code, ohne etwas zu übertragen.
  Future<SyncOutcome> testConnection(SyncCredentials credentials) async {
    try {
      await _backend.connect(credentials);
      _connectedWith = credentials;
      return SyncOutcome(status: SyncStatus.success, at: _clock.now());
    } on SyncBackendException catch (error) {
      _connectedWith = null;
      return SyncOutcome(
        status: error.isAuthFailure ? SyncStatus.authFailed : SyncStatus.error,
        message: error.message,
        at: _clock.now(),
      );
    }
  }

  Future<SyncOutcome> syncNow() async {
    if (_running) {
      return SyncOutcome(status: SyncStatus.running, at: _clock.now());
    }
    final credentials = await readCredentials();
    if (credentials == null) {
      return SyncOutcome(status: SyncStatus.disabled, at: _clock.now());
    }

    _running = true;
    try {
      if (_connectedWith != credentials) {
        await _backend.connect(credentials);
        _connectedWith = credentials;
      }

      final pushed = await _pushPending();
      final pulled = await _pullAndMerge();

      return SyncOutcome(
        status: SyncStatus.success,
        pushed: pushed,
        pulled: pulled,
        at: _clock.now(),
      );
    } on SyncBackendException catch (error) {
      if (error.isAuthFailure) _connectedWith = null;
      return SyncOutcome(
        status: error.isAuthFailure ? SyncStatus.authFailed : SyncStatus.error,
        message: error.message,
        at: _clock.now(),
      );
    } catch (error) {
      return SyncOutcome(
        status: SyncStatus.error,
        message: error.toString(),
        at: _clock.now(),
      );
    } finally {
      _running = false;
    }
  }

  // --- Hochladen ---------------------------------------------------------

  Future<int> _pushPending() async {
    final projects = await (_db.select(_db.projects)
          ..where((t) => t.pendingSync.equals(true)))
        .get();
    final notes = await (_db.select(_db.notes)
          ..where((t) => t.pendingSync.equals(true)))
        .get();

    if (projects.isEmpty && notes.isEmpty) return 0;

    final cursor = await _backend.push(
      projects: projects.map(SyncProject.fromRow).toList(),
      notes: notes.map(SyncNote.fromRow).toList(),
    );

    await _db.transaction(() async {
      for (final project in projects) {
        await _clearPendingProject(project);
      }
      for (final note in notes) {
        await _clearPendingNote(note);
      }
    });

    await _advanceCursor(cursor);
    return projects.length + notes.length;
  }

  /// Setzt `pendingSync` nur zurück, wenn der Datensatz seit dem Hochladen
  /// nicht erneut bearbeitet wurde – sonst ginge die neuere Änderung verloren.
  Future<void> _clearPendingProject(ProjectRow pushed) async {
    await (_db.update(_db.projects)
          ..where((t) =>
              t.id.equals(pushed.id) & t.updatedAt.equals(pushed.updatedAt)))
        .write(const ProjectsCompanion(pendingSync: Value(false)));
  }

  Future<void> _clearPendingNote(NoteRow pushed) async {
    await (_db.update(_db.notes)
          ..where((t) =>
              t.id.equals(pushed.id) & t.updatedAt.equals(pushed.updatedAt)))
        .write(const NotesCompanion(pendingSync: Value(false)));
  }

  // --- Herunterladen -----------------------------------------------------

  Future<int> _pullAndMerge() async {
    final since = await _settings.readDateTime(SettingKeys.lastPulledAt);
    final batch = await _backend.pull(since: since);

    var applied = 0;
    await _db.transaction(() async {
      for (final project in batch.projects) {
        if (await _mergeProject(project)) applied++;
      }
      for (final note in batch.notes) {
        if (await _mergeNote(note)) applied++;
      }
    });

    await _advanceCursor(batch.cursor);
    return applied;
  }

  Future<bool> _mergeProject(SyncProject remote) async {
    final local = await (_db.select(_db.projects)
          ..where((t) => t.id.equals(remote.id)))
        .getSingleOrNull();

    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
      return false;
    }
    await _db
        .into(_db.projects)
        .insertOnConflictUpdate(remote.toRow(pendingSync: false));
    return true;
  }

  Future<bool> _mergeNote(SyncNote remote) async {
    final local = await (_db.select(_db.notes)
          ..where((t) => t.id.equals(remote.id)))
        .getSingleOrNull();

    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
      return false;
    }

    await _db.into(_db.notes).insertOnConflictUpdate(
          NoteRow(
            id: remote.id,
            projectId: remote.projectId,
            type: remote.type,
            title: remote.title,
            body: remote.body,
            answer: remote.answer,
            status: remote.status,
            priority: remote.priority,
            tags: remote.tags,
            sortOrder: remote.sortOrder,
            // Lokal abgeleitet, kommt nicht über die Leitung.
            searchText: buildSearchText(
              title: remote.title,
              body: remote.body,
              answer: remote.answer,
              tags: remote.tags,
            ),
            createdAt: remote.createdAt,
            updatedAt: remote.updatedAt,
            archivedAt: remote.archivedAt,
            deletedAt: remote.deletedAt,
            deviceId: remote.deviceId,
            pendingSync: false,
          ),
        );
    return true;
  }

  Future<void> _advanceCursor(DateTime? candidate) async {
    if (candidate == null) return;
    final current = await _settings.readDateTime(SettingKeys.lastPulledAt);
    if (current != null && !candidate.isAfter(current)) return;
    await _settings.writeDateTime(SettingKeys.lastPulledAt, candidate);
  }
}
