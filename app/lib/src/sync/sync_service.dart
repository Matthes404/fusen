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
    this.warning,
    this.at,
  });

  final SyncStatus status;
  final int pushed;
  final int pulled;
  final String? message;

  /// Was nicht geklappt hat, ohne den Abgleich scheitern zu lassen – ein
  /// Server ohne Bilder, ein Bild, das sich nicht laden ließ.
  final String? warning;
  final DateTime? at;

  bool get isSuccess => status == SyncStatus.success;
}

/// Sicherheitsabstand beim Fortschreiben des Sync-Cursors.
///
/// Der Cursor ist ein Zeitstempel, und daran können zwei Dinge vorbeirutschen:
///
/// * ein Datensatz, der auf dieselbe Millisekunde fällt wie der Cursor, aber
///   erst nach unserer Abfrage festgeschrieben wurde – `updated > cursor`
///   würde ihn nie sehen;
/// * ein Datensatz, der zwischen zwei Abfragen desselben Durchlaufs
///   geschrieben wird. Projekte und Zettel werden nacheinander geholt; schiebt
///   ein anderes Gerät genau dazwischen erst ein Projekt und dann einen
///   Zettel, käme der Zettel an und das Projekt nicht.
///
/// Ein paar Sekunden Überlappung holen im Zweifel ein paar Datensätze
/// doppelt. Das kostet Bandbreite, aber nichts sonst: das Zusammenführen ist
/// idempotent. Ein übersprungener Datensatz wäre dagegen für immer weg.
const Duration syncCursorOverlap = Duration(seconds: 5);

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
///
/// Bilder reisen in zwei Teilen: die Beschreibung wie ein Zettel, die Datei
/// nur einmal beim ersten Hochladen. Heruntergeladen wird nach dem
/// Zusammenführen, was noch fehlt – ein Bild, das nicht kommt, hält den
/// übrigen Abgleich nicht auf.
class SyncService {
  SyncService({
    required FusenDatabase database,
    required this._backend,
    required this._settings,
    this._clock = const SystemClock(),
  }) : _db = database;

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
      final pushedAttachments = await _pushAttachments();
      final (pulled, attachmentsSupported) = await _pullAndMerge();
      final failedDownloads = attachmentsSupported && pushedAttachments != null
          ? await _downloadMissing()
          : 0;

      return SyncOutcome(
        status: SyncStatus.success,
        pushed: pushed + (pushedAttachments ?? 0),
        pulled: pulled,
        warning: !attachmentsSupported || pushedAttachments == null
            ? 'Der Server kennt noch keine Bilder – Zettel gleichen ab, '
                  'Bilder bleiben auf diesem Gerät. Den Sync-Server '
                  'aktualisieren, dann kommen sie mit.'
            : switch (failedDownloads) {
                0 => null,
                1 => 'Ein Bild ließ sich nicht laden.',
                _ => '$failedDownloads Bilder ließen sich nicht laden.',
              },
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
    final projects = await (_db.select(
      _db.projects,
    )..where((t) => t.pendingSync.equals(true))).get();
    final notes = await (_db.select(
      _db.notes,
    )..where((t) => t.pendingSync.equals(true))).get();

    if (projects.isEmpty && notes.isEmpty) return 0;

    await _backend.push(
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

    // Der Cursor bleibt, wo er ist: ihn hier auf „jetzt“ zu stellen würde
    // das anschließende Holen alles überspringen lassen, was ein anderes
    // Gerät vor unserem Hochladen geschrieben hat.
    return projects.length + notes.length;
  }

  /// Setzt `pendingSync` nur zurück, wenn der Datensatz seit dem Hochladen
  /// nicht erneut bearbeitet wurde – sonst ginge die neuere Änderung verloren.
  Future<void> _clearPendingProject(ProjectRow pushed) async {
    await (_db.update(_db.projects)..where(
          (t) => t.id.equals(pushed.id) & t.updatedAt.equals(pushed.updatedAt),
        ))
        .write(const ProjectsCompanion(pendingSync: Value(false)));
  }

  Future<void> _clearPendingNote(NoteRow pushed) async {
    await (_db.update(_db.notes)..where(
          (t) => t.id.equals(pushed.id) & t.updatedAt.equals(pushed.updatedAt),
        ))
        .write(const NotesCompanion(pendingSync: Value(false)));
  }

  /// Schiebt Bilder hoch – beim ersten Mal samt Datei, danach nur die
  /// Beschreibung. Liefert die Anzahl, oder `null`, wenn der Server keine
  /// Bilder kennt.
  Future<int?> _pushAttachments() async {
    final pending = await (_db.select(
      _db.attachments,
    )..where((t) => t.pendingSync.equals(true))).get();

    var pushed = 0;
    for (final attachment in pending) {
      // Nie beim Server angekommen und schon wieder entfernt: es gibt
      // nichts zu erzählen.
      if (attachment.deletedAt != null && !attachment.uploaded) {
        await _clearPendingAttachment(attachment);
        continue;
      }

      Uint8List? bytes;
      if (!attachment.uploaded) {
        bytes = await _readBlob(attachment.id);
        if (bytes == null) continue;
      }

      final String? remoteFile;
      try {
        remoteFile = await _backend.pushAttachment(
          SyncAttachment.fromRow(attachment),
          bytes: bytes,
        );
      } on SyncBackendException catch (error) {
        if (error.isUnsupported) return null;
        if (error.isNotFound && attachment.uploaded) {
          // Der Server hat das Bild nicht mehr, etwa nach einem Neuaufsetzen.
          // Beim nächsten Abgleich geht die Datei deshalb wieder mit.
          await (_db.update(_db.attachments)
                ..where((t) => t.id.equals(attachment.id)))
              .write(const AttachmentsCompanion(uploaded: Value(false)));
          continue;
        }
        rethrow;
      }

      await _db.transaction(() async {
        if (bytes != null) {
          await (_db.update(
            _db.attachments,
          )..where((t) => t.id.equals(attachment.id))).write(
            AttachmentsCompanion(
              uploaded: const Value(true),
              remoteFile: Value(remoteFile ?? attachment.remoteFile),
            ),
          );
        }
        await _clearPendingAttachment(attachment);
      });
      pushed++;
    }
    return pushed;
  }

  Future<void> _clearPendingAttachment(AttachmentRow pushed) async {
    await (_db.update(_db.attachments)..where(
          (t) => t.id.equals(pushed.id) & t.updatedAt.equals(pushed.updatedAt),
        ))
        .write(const AttachmentsCompanion(pendingSync: Value(false)));
  }

  Future<Uint8List?> _readBlob(String attachmentId) async {
    final row = await (_db.select(
      _db.attachmentBlobs,
    )..where((t) => t.attachmentId.equals(attachmentId))).getSingleOrNull();
    return row?.bytes;
  }

  // --- Herunterladen -----------------------------------------------------

  /// Holt und führt zusammen. Liefert die Anzahl übernommener Datensätze und
  /// ob der Server Bilder kennt.
  Future<(int, bool)> _pullAndMerge() async {
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
      for (final attachment in batch.attachments) {
        if (await _mergeAttachment(attachment)) applied++;
      }
    });

    await _advanceCursor(batch.cursor);
    return (applied, batch.attachmentsSupported);
  }

  Future<bool> _mergeAttachment(SyncAttachment remote) async {
    final local = await (_db.select(
      _db.attachments,
    )..where((t) => t.id.equals(remote.id))).getSingleOrNull();

    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
      // Die lokale Fassung gewinnt – den Dateinamen auf dem Server merken
      // wir uns trotzdem, falls wir ihn noch nicht kannten.
      if (local.remoteFile == null && remote.remoteFile != null) {
        await (_db.update(_db.attachments)..where((t) => t.id.equals(local.id)))
            .write(AttachmentsCompanion(remoteFile: Value(remote.remoteFile)));
      }
      return false;
    }

    await _db
        .into(_db.attachments)
        .insertOnConflictUpdate(
          AttachmentRow(
            id: remote.id,
            noteId: remote.noteId,
            fileName: remote.fileName,
            mimeType: remote.mimeType,
            byteSize: remote.byteSize,
            width: remote.width,
            height: remote.height,
            sortOrder: remote.sortOrder,
            createdAt: remote.createdAt,
            updatedAt: remote.updatedAt,
            deletedAt: remote.deletedAt,
            deviceId: remote.deviceId,
            // Die Daten bleiben, wenn sie schon da sind – ein Bild ändert
            // sich nie, nur seine Beschreibung.
            hasData: local?.hasData ?? false,
            uploaded: true,
            remoteFile: remote.remoteFile ?? local?.remoteFile,
            pendingSync: false,
          ),
        );
    return true;
  }

  /// Lädt Bilddaten, die dieses Gerät noch nicht hat. Liefert die Anzahl der
  /// Fehlschläge – sie werden beim nächsten Abgleich erneut versucht.
  Future<int> _downloadMissing({int limit = 40}) async {
    final missing =
        await (_db.select(_db.attachments)
              ..where(
                (t) =>
                    t.hasData.equals(false) &
                    t.deletedAt.isNull() &
                    t.remoteFile.isNotNull(),
              )
              ..limit(limit))
            .get();

    var failed = 0;
    for (final attachment in missing) {
      final Uint8List bytes;
      try {
        bytes = await _backend.downloadAttachment(
          SyncAttachment.fromRow(attachment),
        );
      } on SyncBackendException catch (error) {
        if (error.isAuthFailure) rethrow;
        failed++;
        continue;
      }
      await _db.transaction(() async {
        await _db
            .into(_db.attachmentBlobs)
            .insertOnConflictUpdate(
              AttachmentBlobRow(attachmentId: attachment.id, bytes: bytes),
            );
        // Ein lokales Merkmal: ändert nichts, was zum Server müsste.
        await (_db.update(_db.attachments)
              ..where((t) => t.id.equals(attachment.id)))
            .write(const AttachmentsCompanion(hasData: Value(true)));
      });
    }
    return failed;
  }

  Future<bool> _mergeProject(SyncProject remote) async {
    final local = await (_db.select(
      _db.projects,
    )..where((t) => t.id.equals(remote.id))).getSingleOrNull();

    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
      return false;
    }
    await _db
        .into(_db.projects)
        .insertOnConflictUpdate(remote.toRow(pendingSync: false));
    return true;
  }

  Future<bool> _mergeNote(SyncNote remote) async {
    final local = await (_db.select(
      _db.notes,
    )..where((t) => t.id.equals(remote.id))).getSingleOrNull();

    if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
      return false;
    }

    await _db
        .into(_db.notes)
        .insertOnConflictUpdate(
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
            closedAt: remote.closedAt,
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
    final next = candidate.subtract(syncCursorOverlap);
    final current = await _settings.readDateTime(SettingKeys.lastPulledAt);
    if (current != null && !next.isAfter(current)) return;
    await _settings.writeDateTime(SettingKeys.lastPulledAt, next);
  }
}
