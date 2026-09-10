import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note_status.dart';
import '../models/note_type.dart';
import 'tables.dart';

part 'database.g.dart';

/// Lokale Datenbank. Fusen ist local-first: alles läuft zuerst gegen SQLite,
/// der Sync arbeitet im Hintergrund und ist optional.
@DriftDatabase(tables: [Projects, Notes, Settings])
class FusenDatabase extends _$FusenDatabase {
  FusenDatabase(super.e);

  /// Datenbank im Anwendungsverzeichnis des Geräts.
  ///
  /// Bewusst das Support- und nicht das Dokumente-Verzeichnis (der Standard
  /// von `drift_flutter`): die Datei ist Anwendungsdatenbestand, kein Dokument
  /// des Nutzers. Auf Linux hängt der Dokumente-Ordner außerdem an
  /// `xdg-user-dirs`; ist das Paket nicht installiert, gibt es ihn gar nicht,
  /// und die App startete dann nicht. Das Support-Verzeichnis leitet sich
  /// dagegen aus `XDG_DATA_HOME` bzw. `~/.local/share` ab und ist immer da.
  FusenDatabase.open({String name = 'fusen'})
    : super(
        driftDatabase(
          name: name,
          native: DriftNativeOptions(
            databaseDirectory: getApplicationSupportDirectory,
          ),
        ),
      );

  /// Flüchtige Datenbank für Tests.
  FusenDatabase.memory() : super(_memoryExecutor());

  static QueryExecutor _memoryExecutor() =>
      DatabaseConnection(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  /// Zeitstempel als ISO-8601-Text speichern.
  ///
  /// Der Standard von drift sind Unix-Sekunden; für den Sync brauchen wir
  /// Millisekunden und eine eindeutige Zeitzone, sonst laufen zwei Geräte
  /// innerhalb derselben Sekunde auseinander.
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_notes_project '
        'ON notes (project_id, type, status)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_notes_pending ON notes (pending_sync)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_projects_pending '
        'ON projects (pending_sync)',
      );
    },
  );
}
