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

  /// Wann der Zettel abgeschlossen wurde – erledigt, umgesetzt, beantwortet
  /// oder verworfen. `null`, solange er offen ist.
  ///
  /// `updatedAt` taugt dafür nicht: jede spätere Änderung am Text würde den
  /// Zeitpunkt des Abhakens überschreiben.
  DateTimeColumn get closedAt => dateTime().nullable()();

  DateTimeColumn get archivedAt => dateTime().nullable()();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Welches Gerät zuletzt geschrieben hat – hilft bei der Fehlersuche im Sync.
  TextColumn get deviceId => text()();

  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Ein Bild an einem Zettel.
///
/// Hier steht nur die Beschreibung, die Bilddaten liegen in
/// [AttachmentBlobs]. Die Trennung hält jede Liste leicht: drift fragt eine
/// beobachtete Tabelle bei jeder Änderung neu ab, und dabei jedes Mal ein
/// paar Megabyte Bilder mitzulesen, würde man beim Scrollen merken.
@DataClassName('AttachmentRow')
class Attachments extends Table {
  TextColumn get id => text()();

  /// Bewusst ohne Fremdschlüssel – aus demselben Grund wie bei
  /// `Notes.projectId`: beim Sync kann ein Bild vor seinem Zettel eintreffen.
  TextColumn get noteId => text()();

  /// Der ursprüngliche Dateiname, etwa „Bildschirmfoto.png“.
  TextColumn get fileName => text()();

  TextColumn get mimeType => text()();

  IntColumn get byteSize => integer()();

  /// Maße in Pixeln, damit die Oberfläche den Platz reservieren kann, bevor
  /// das Bild geladen ist. `null`, wenn das Format sie nicht verrät.
  IntColumn get width => integer().nullable()();

  IntColumn get height => integer().nullable()();

  RealColumn get sortOrder => real()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get deviceId => text()();

  /// Nur lokal: die Bilddaten liegen auf diesem Gerät vor.
  ///
  /// Nach einem Abgleich kennt ein Gerät das Bild oft schon, hat es aber noch
  /// nicht heruntergeladen – die Oberfläche zeigt dann einen Platzhalter.
  BoolColumn get hasData => boolean().withDefault(const Constant(false))();

  /// Nur lokal: die Bilddaten sind beim Server angekommen. Bis dahin muss
  /// jeder Abgleich die Datei mitschicken, danach nur noch die Beschreibung.
  BoolColumn get uploaded => boolean().withDefault(const Constant(false))();

  /// Nur lokal: Dateiname auf dem Server. PocketBase hängt beim Hochladen
  /// einen Zufallsteil an, zum Herunterladen braucht man den echten Namen.
  TextColumn get remoteFile => text().nullable()();

  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Die Bilddaten zu [Attachments] – geschrieben einmal, gelesen bei Bedarf.
@DataClassName('AttachmentBlobRow')
class AttachmentBlobs extends Table {
  TextColumn get attachmentId => text()();

  BlobColumn get bytes => blob()();

  @override
  Set<Column<Object>> get primaryKey => {attachmentId};
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
