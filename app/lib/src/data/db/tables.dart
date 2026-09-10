import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/note_status.dart';
import '../models/note_type.dart';

/// Speichert Tag-Listen als JSON-Array.
///
/// Ein eigenes `tags`-Tabellchen wäre normalisierter, aber Tags werden immer
/// zusammen mit dem Zettel gelesen und geschrieben – als JSON bleibt der
/// Sync-Datensatz ein einziges Feld und damit konfliktfrei überschreibbar.
class TagListConverter extends TypeConverter<List<String>, String>
    with JsonTypeConverter2<List<String>, String, List<dynamic>> {
  const TagListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    final decoded = json.decode(fromDb);
    if (decoded is! List) return const [];
    return decoded.map((e) => e.toString()).toList(growable: false);
  }

  @override
  String toSql(List<String> value) => json.encode(value);

  @override
  List<String> fromJson(List<dynamic> json) =>
      json.map((e) => e.toString()).toList(growable: false);

  @override
  List<dynamic> toJson(List<String> value) => value;
}

@DataClassName('ProjectRow')
class Projects extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 200)();

  /// ARGB-Wert der Projektfarbe.
  IntColumn get color => integer()();

  RealColumn get sortOrder => real()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get archivedAt => dateTime().nullable()();

  /// Tombstone: Zettel und Projekte werden nie hart gelöscht, damit
  /// Löschungen sauber synchronisieren.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Nur lokal: Datensatz wartet darauf, zum Server geschoben zu werden.
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();

  /// `null` bedeutet: liegt in der Inbox.
  ///
  /// Bewusst ohne Fremdschlüssel: beim Sync kann ein Zettel vor seinem
  /// Projekt eintreffen, und ein FK-Fehler würde die ganze Übertragung
  /// abbrechen. Verwaiste Zettel werden in der Inbox angezeigt.
  TextColumn get projectId => text().nullable()();

  TextColumn get type => textEnum<NoteType>()();

  TextColumn get title => text().nullable()();

  /// Markdown.
  TextColumn get body => text().withDefault(const Constant(''))();

  /// Antwort auf eine Frage (`type == question`).
  TextColumn get answer => text().nullable()();

  TextColumn get status => textEnum<NoteStatus>()();

  TextColumn get priority => textEnum<NotePriority>().nullable()();

  TextColumn get tags =>
      text().map(const TagListConverter()).withDefault(const Constant('[]'))();

  RealColumn get sortOrder => real()();

  /// Abgeleitet: Titel, Text, Antwort und Tags in Kleinbuchstaben.
  ///
  /// SQLites `lower()` und `LIKE` kennen nur ASCII – „Ärger“ und „ärger“
  /// wären damit verschiedene Wörter. Die Faltung passiert deshalb in Dart
  /// beim Schreiben, gesucht wird dann mit einem einfachen `LIKE`.
  /// Wird nicht synchronisiert, sondern auf jedem Gerät neu berechnet.
  TextColumn get searchText => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get archivedAt => dateTime().nullable()();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Welches Gerät zuletzt geschrieben hat – hilft bei der Fehlersuche im Sync.
  TextColumn get deviceId => text()();

  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Schlüssel-Wert-Speicher für Geräteeinstellungen.
///
/// Bleibt bewusst lokal: Server-URL, Zugangscode und Sync-Cursor gehören zum
/// Gerät, nicht zum Workspace.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
