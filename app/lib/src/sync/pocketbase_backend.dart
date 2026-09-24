import 'dart:typed_data';

import 'package:http/http.dart' as http;
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
const String attachmentsCollection = 'attachments';

/// Sync gegen eine PocketBase-Instanz.
class PocketBaseSyncBackend implements SyncBackend {
  PocketBaseSyncBackend({
    PocketBase Function(String baseUrl)? clientFactory,
    http.Client Function()? httpClientFactory,
  }) : _clientFactory = clientFactory ?? PocketBase.new,
       _httpClientFactory = httpClientFactory ?? http.Client.new;

  final PocketBase Function(String baseUrl) _clientFactory;
  final http.Client Function() _httpClientFactory;

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

    // Ein Server von vor Version 2 kennt keine Bilder. Das ist kein Grund,
    // Projekte und Zettel nicht abzugleichen.
    var attachmentsSupported = true;
    var attachments = const <RecordModel>[];
    try {
      attachments = await _fetch(client, attachmentsCollection, since);
    } on SyncBackendException catch (error) {
      if (!error.isNotFound) rethrow;
      attachmentsSupported = false;
    }

    return RemoteBatch(
      projects: projects.map((r) => SyncProject.fromJson(r.toJson())).toList(),
      notes: notes.map((r) => SyncNote.fromJson(r.toJson())).toList(),
      attachments: attachments
          .map((r) => SyncAttachment.fromJson(r.toJson()))
          .toList(),
      attachmentsSupported: attachmentsSupported,
      cursor: _latestUpdated([...projects, ...notes, ...attachments]) ?? since,
    );
  }

  @override
  Future<String?> pushAttachment(
    SyncAttachment attachment, {
    Uint8List? bytes,
  }) async {
    final client = _requireClient();
    final collection = client.collection(attachmentsCollection);
    final remoteId = remoteIdFor(attachment.id);
    final body = attachment.toJson();

    if (bytes == null) {
      try {
        final record = await collection.update(remoteId, body: body);
        return _fileOf(record);
      } on ClientException catch (error) {
        throw _attachmentError(error);
      }
    }

    http.MultipartFile file() => http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: attachment.fileName,
    );
    try {
      return _fileOf(await collection.create(body: body, files: [file()]));
    } on ClientException catch (error) {
      if (error.statusCode != 400) throw _attachmentError(error);
      // Gibt es schon – etwa weil die Antwort auf das erste Hochladen
      // unterwegs verloren ging. Dann eben ersetzen, samt Datei.
      try {
        final record = await collection.update(
          remoteId,
          body: body,
          files: [file()],
        );
        return _fileOf(record);
      } on ClientException catch (updateError) {
        throw _attachmentError(updateError);
      }
    }
  }

  @override
  Future<Uint8List> downloadAttachment(SyncAttachment attachment) async {
    final client = _requireClient();
    final remoteFile = attachment.remoteFile;
    if (remoteFile == null || remoteFile.isEmpty) {
      throw const SyncBackendException(
        'Zu diesem Bild liegt auf dem Server keine Datei.',
        isNotFound: true,
      );
    }

    // Die Dateien sind geschützt: herunterladen nur mit einem kurzlebigen
    // Token, das nur ein angemeldetes Gerät bekommt.
    final String token;
    try {
      token = await client.files.getToken();
    } on ClientException catch (error) {
      throw SyncBackendException(
        _describe(error),
        isAuthFailure: error.statusCode == 401 || error.statusCode == 403,
      );
    }

    final url = client.buildURL(
      '/api/files/$attachmentsCollection/${remoteIdFor(attachment.id)}/'
      '${Uri.encodeComponent(remoteFile)}',
      {'token': token},
    );
    final httpClient = _httpClientFactory();
    try {
      final response = await httpClient.get(url);
      if (response.statusCode != 200) {
        throw SyncBackendException(
          'Bild nicht abrufbar (${response.statusCode})',
          isNotFound: response.statusCode == 404,
        );
      }
      return response.bodyBytes;
    } on SyncBackendException {
      rethrow;
    } on Object catch (error) {
      throw SyncBackendException('Bild nicht abrufbar: $error');
    } finally {
      httpClient.close();
    }
  }

  static String? _fileOf(RecordModel record) {
    final file = record.get<String?>('file') ?? '';
    return file.isEmpty ? null : file;
  }

  static SyncBackendException _attachmentError(ClientException error) {
    // 404 beim Anlegen heißt: die Sammlung gibt es nicht, der Server ist zu
    // alt. 404 beim Aktualisieren heißt: der Datensatz fehlt.
    final missingCollection =
        error.statusCode == 404 &&
        (error.response['message']?.toString().contains('collection') ?? false);
    return SyncBackendException(
      _describe(error),
      isAuthFailure: error.statusCode == 401 || error.statusCode == 403,
      isNotFound: error.statusCode == 404 && !missingCollection,
      isUnsupported: missingCollection,
    );
  }

  @override
  Future<void> push({
    List<SyncProject> projects = const [],
    List<SyncNote> notes = const [],
  }) async {
    final client = _requireClient();

    // Projekte zuerst: sonst zeigt ein Zettel kurzzeitig auf ein Projekt,
    // das der Server noch nicht kennt.
    for (final project in projects) {
      await _upsert(client, projectsCollection, project.id, project.toJson());
    }
    for (final note in notes) {
      await _upsert(client, notesCollection, note.id, note.toJson());
    }
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
        isNotFound: error.statusCode == 404,
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
