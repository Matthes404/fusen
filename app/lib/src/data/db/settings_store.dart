import 'database.dart';

/// Bekannte Einstellungsschlüssel an einer Stelle, damit sie nicht als
/// Zeichenketten durch die App wandern.
abstract final class SettingKeys {
  static const deviceId = 'device_id';
  static const serverUrl = 'sync.server_url';
  static const accessCode = 'sync.access_code';
  static const authToken = 'sync.auth_token';
  static const lastPulledAt = 'sync.last_pulled_at';
  static const lastProjectId = 'ui.last_project_id';
  static const themeMode = 'ui.theme_mode';
}

/// Dünne Hülle um die `settings`-Tabelle.
class SettingsStore {
  SettingsStore(this._db);

  final FusenDatabase _db;

  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watch(String key) {
    return (_db.select(_db.settings)..where((t) => t.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  Future<void> write(String key, String? value) async {
    if (value == null) {
      await (_db.delete(_db.settings)..where((t) => t.key.equals(key))).go();
      return;
    }
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(SettingRow(key: key, value: value));
  }

  Future<DateTime?> readDateTime(String key) async {
    final raw = await read(key);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> writeDateTime(String key, DateTime? value) =>
      write(key, value?.toUtc().toIso8601String());
}
