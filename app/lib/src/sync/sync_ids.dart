/// Übersetzung zwischen lokalen UUIDs und Datensatz-IDs auf dem Server.
///
/// PocketBase erlaubt eigene IDs nur als `[a-z0-9]` mit mindestens 15 Zeichen.
/// Ein UUID ohne Bindestriche erfüllt das (32 Hex-Zeichen), also bleibt die
/// Zuordnung eine reine Rechnung – wir brauchen keine Mapping-Tabelle und
/// können denselben Datensatz von jedem Gerät aus direkt adressieren.
library;

final RegExp _compactUuid = RegExp(r'^[0-9a-f]{32}$');

/// Lokale UUID → ID auf dem Server.
String remoteIdFor(String localId) => localId.replaceAll('-', '').toLowerCase();

/// ID auf dem Server → lokale UUID.
///
/// Was nicht wie ein UUID aussieht, wird unverändert übernommen: ein fremder
/// Datensatz soll den Sync nicht zum Absturz bringen.
String localIdFor(String remoteId) {
  final compact = remoteId.toLowerCase();
  if (!_compactUuid.hasMatch(compact)) return remoteId;
  return '${compact.substring(0, 8)}-${compact.substring(8, 12)}-'
      '${compact.substring(12, 16)}-${compact.substring(16, 20)}-'
      '${compact.substring(20)}';
}
