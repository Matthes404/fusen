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
@DriftDatabase(
  tables: [Projects, Notes, Attachments, AttachmentBlobs, Settings],
)
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

  /// Version 2: Abschlusszeitpunkt an Zetteln, Bilder als Anhänge.
  @override
  int get schemaVersion => 2;

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
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(notes, notes.closedAt);
        // Wann ein Zettel abgehakt wurde, weiß Version 1 nicht. Die letzte
        // Änderung ist die beste Schätzung – meist war sie das Abhaken.
        await customStatement(
          "UPDATE notes SET closed_at = updated_at WHERE status != 'open'",
        );
        await m.createTable(attachments);
        await m.createTable(attachmentBlobs);
      }
      await _createIndexes();
    },
  );

  Future<void> _createIndexes() async {
    for (final statement in const [
      'CREATE INDEX IF NOT EXISTS idx_notes_project '
          'ON notes (project_id, type, status)',
      'CREATE INDEX IF NOT EXISTS idx_notes_pending ON notes (pending_sync)',
      'CREATE INDEX IF NOT EXISTS idx_projects_pending '
          'ON projects (pending_sync)',
      'CREATE INDEX IF NOT EXISTS idx_attachments_note '
          'ON attachments (note_id)',
      'CREATE INDEX IF NOT EXISTS idx_attachments_pending '
          'ON attachments (pending_sync)',
    ]) {
      await customStatement(statement);
    }
  }
}
