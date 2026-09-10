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
    this.cursor,
  });

  final List<SyncProject> projects;
  final List<SyncNote> notes;

  /// Serverseitiger Zeitstempel des jüngsten gelesenen Datensatzes.
  ///
  /// Bewusst die Uhr des Servers und nicht die des Geräts: sonst würde eine
  /// falsch gestellte Uhr auf einem Handy Änderungen überspringen.
  final DateTime? cursor;

  bool get isEmpty => projects.isEmpty && notes.isEmpty;
}

class SyncBackendException implements Exception {
  const SyncBackendException(this.message, {this.isAuthFailure = false});

  final String message;
  final bool isAuthFailure;

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

  /// Schiebt lokale Änderungen hoch und liefert den Serverzeitstempel des
  /// zuletzt geschriebenen Datensatzes.
  Future<DateTime?> push({
    List<SyncProject> projects = const [],
    List<SyncNote> notes = const [],
  });
}
