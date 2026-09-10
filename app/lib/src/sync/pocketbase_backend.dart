import 'package:pocketbase/pocketbase.dart';

import 'sync_backend.dart';
import 'sync_ids.dart';
import 'sync_records.dart';

/// Name der Auth-Collection, in der genau ein Datensatz liegt: der Zugang zur
/// Instanz. Der Zugangscode ist dessen Passwort.
const String accessCollection = 'access';

/// Feste Kennung des einen Zugangs-Datensatzes.
///
/// Es gibt keine Benutzerverwaltung, also braucht auch niemand eine E-Mail
/// auszudenken – die App kennt die Kennung und fragt nur nach dem Code.
const String accessIdentity = 'owner@fusen.local';

const String projectsCollection = 'projects';
const String notesCollection = 'notes';

/// Sync gegen eine PocketBase-Instanz.
class PocketBaseSyncBackend implements SyncBackend {
  PocketBaseSyncBackend({PocketBase Function(String baseUrl)? clientFactory})
    : _clientFactory = clientFactory ?? PocketBase.new;

  final PocketBase Function(String baseUrl) _clientFactory;

  PocketBase? _client;

  @override
  Future<void> connect(SyncCredentials credentials) async {
    final client = _clientFactory(credentials.serverUrl.trim());
    try {
      await client
          .collection(accessCollection)
          .authWithPassword(accessIdentity, credentials.accessCode);
    } on ClientException catch (error) {
      throw SyncBackendException(
        _describe(error),
        isAuthFailure: error.statusCode == 400 || error.statusCode == 403,
      );
    }
    _client = client;
  }

  @override
  Future<void> disconnect() async {
    _client?.authStore.clear();
    _client = null;
  }

  @override
  Future<RemoteBatch> pull({DateTime? since}) async {
    final client = _requireClient();
    final projects = await _fetch(client, projectsCollection, since);
    final notes = await _fetch(client, notesCollection, since);

    return RemoteBatch(
      projects: projects.map((r) => SyncProject.fromJson(r.toJson())).toList(),
      notes: notes.map((r) => SyncNote.fromJson(r.toJson())).toList(),
      cursor: _latestUpdated([...projects, ...notes]) ?? since,
    );
  }

  @override
  Future<DateTime?> push({
    List<SyncProject> projects = const [],
    List<SyncNote> notes = const [],
  }) async {
    final client = _requireClient();
    DateTime? latest;

    // Projekte zuerst: sonst zeigt ein Zettel kurzzeitig auf ein Projekt,
    // das der Server noch nicht kennt.
    for (final project in projects) {
      final record = await _upsert(
        client,
        projectsCollection,
        project.id,
        project.toJson(),
      );
      latest = _laterOf(latest, _updatedOf(record));
    }
    for (final note in notes) {
      final record = await _upsert(
        client,
        notesCollection,
        note.id,
        note.toJson(),
      );
      latest = _laterOf(latest, _updatedOf(record));
    }
    return latest;
  }

  /// PocketBase kennt kein Upsert, also: anlegen, und bei „gibt es schon“
  /// stattdessen aktualisieren.
  Future<RecordModel> _upsert(
    PocketBase client,
    String collection,
    String localId,
    Map<String, dynamic> body,
  ) async {
    final remoteId = remoteIdFor(localId);
    try {
      return await client.collection(collection).create(body: body);
    } on ClientException catch (error) {
      if (error.statusCode != 400) {
        throw SyncBackendException(_describe(error));
      }
      try {
        return await client.collection(collection).update(remoteId, body: body);
      } on ClientException catch (updateError) {
        throw SyncBackendException(_describe(updateError));
      }
    }
  }

  Future<List<RecordModel>> _fetch(
    PocketBase client,
    String collection,
    DateTime? since,
  ) async {
    try {
      return await client
          .collection(collection)
          .getFullList(
            batch: 200,
            sort: 'updated',
            filter: since == null
                ? null
                : 'updated > "${_pocketBaseTime(since)}"',
          );
    } on ClientException catch (error) {
      throw SyncBackendException(
        _describe(error),
        isAuthFailure: error.statusCode == 401 || error.statusCode == 403,
      );
    }
  }

  PocketBase _requireClient() {
    final client = _client;
    if (client == null) {
      throw const SyncBackendException('Nicht mit einem Server verbunden.');
    }
    return client;
  }

  static DateTime? _updatedOf(RecordModel record) {
    final raw = record.get<String?>('updated') ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'))?.toUtc();
  }

  static DateTime? _latestUpdated(List<RecordModel> records) {
    DateTime? latest;
    for (final record in records) {
      latest = _laterOf(latest, _updatedOf(record));
    }
    return latest;
  }

  static DateTime? _laterOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// PocketBase filtert auf sein eigenes Format `YYYY-MM-DD hh:mm:ss.sssZ`.
  static String _pocketBaseTime(DateTime value) =>
      value.toUtc().toIso8601String().replaceFirst('T', ' ');

  static String _describe(ClientException error) {
    final message = error.response['message']?.toString();
    if (message != null && message.isNotEmpty) {
      return 'PocketBase: $message (${error.statusCode})';
    }
    return 'PocketBase: ${error.originalError ?? error.statusCode}';
  }
}
