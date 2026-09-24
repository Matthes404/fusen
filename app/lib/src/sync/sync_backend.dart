import 'dart:typed_data';

import 'sync_records.dart';

/// Zugangsdaten einer Sync-Instanz.
///
/// Keine Benutzerkonten: eine Instanz gehört genau einer Person, der Zugang
/// läuft über einen Code, den alle Geräte teilen.
class SyncCredentials {
  const SyncCredentials({required this.serverUrl, required this.accessCode});

  final String serverUrl;
  final String accessCode;

  bool get isComplete => serverUrl.trim().isNotEmpty && accessCode.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is SyncCredentials &&
      other.serverUrl == serverUrl &&
      other.accessCode == accessCode;

  @override
  int get hashCode => Object.hash(serverUrl, accessCode);
}

/// Was der Server seit dem letzten Abgleich geändert hat.
class RemoteBatch {
  const RemoteBatch({
    this.projects = const [],
    this.notes = const [],
    this.attachments = const [],
    this.attachmentsSupported = true,
    this.cursor,
  });

  final List<SyncProject> projects;
  final List<SyncNote> notes;
  final List<SyncAttachment> attachments;

  /// `false`, wenn der Server noch kein Sync-Format 2 kennt – dann gibt es
  /// dort keine Bilder, der Rest gleicht trotzdem ab.
  final bool attachmentsSupported;

  /// Serverseitiger Zeitstempel des jüngsten gelesenen Datensatzes.
  ///
  /// Bewusst die Uhr des Servers und nicht die des Geräts: sonst würde eine
  /// falsch gestellte Uhr auf einem Handy Änderungen überspringen.
  final DateTime? cursor;

  bool get isEmpty => projects.isEmpty && notes.isEmpty && attachments.isEmpty;
}

class SyncBackendException implements Exception {
  const SyncBackendException(
    this.message, {
    this.isAuthFailure = false,
    this.isNotFound = false,
    this.isUnsupported = false,
  });

  final String message;
  final bool isAuthFailure;

  /// Der Datensatz fehlt auf dem Server – etwa, weil der neu aufgesetzt wurde.
  final bool isNotFound;

  /// Der Server kennt die Sammlung nicht: ein Server von vor Version 2.
  final bool isUnsupported;

  @override
  String toString() => message;
}

/// Alles, was der Sync vom Server braucht.
///
/// Die App kennt nur dieses Interface. PocketBase ist die erste
/// Implementierung; ein eigener kleiner Server (Option A im Konzept) lässt
/// sich später dahinter hängen, ohne die App anzufassen.
abstract class SyncBackend {
  /// Meldet das Gerät an. Wirft [SyncBackendException] bei falschem Code.
  Future<void> connect(SyncCredentials credentials);

  Future<void> disconnect();

  /// Alle Änderungen, die nach [since] auf dem Server passiert sind.
  Future<RemoteBatch> pull({DateTime? since});

  /// Schiebt lokale Änderungen hoch.
  ///
  /// Bewusst ohne Rückgabe: den Cursor stellt allein [pull] vor. Würde das
  /// Hochladen ihn auf „jetzt“ setzen, überspränge das nächste Holen alles,
  /// was ein anderes Gerät vorher geschrieben hat.
  Future<void> push({
    List<SyncProject> projects = const [],
    List<SyncNote> notes = const [],
  });

  /// Schiebt ein Bild hoch.
  ///
  /// Mit [bytes] wird die Datei mitgeschickt – beim ersten Mal. Danach
  /// ändert sich an einem Bild nur noch die Beschreibung (etwa der
  /// Tombstone), dann bleibt [bytes] leer. Liefert den Dateinamen, unter dem
  /// der Server die Datei abgelegt hat.
  ///
  /// Wirft [SyncBackendException] mit `isUnsupported`, wenn der Server keine
  /// Bilder kennt, und mit `isNotFound`, wenn ohne [bytes] aktualisiert
  /// werden soll, der Datensatz aber fehlt.
  Future<String?> pushAttachment(SyncAttachment attachment, {Uint8List? bytes});

  /// Holt die Bilddaten eines Bildes, das der Server kennt.
  Future<Uint8List> downloadAttachment(SyncAttachment attachment);
}
