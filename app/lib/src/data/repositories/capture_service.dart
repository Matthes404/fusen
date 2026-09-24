import '../db/database.dart';
import '../models/note_status.dart';
import '../models/note_type.dart';
import 'note_repository.dart';
import 'project_repository.dart';

/// Ein Zettel, wie er angelegt werden soll – noch ohne ID und mit dem
/// Projekt als Namen, so wie er getippt wurde.
class NoteDraft {
  const NoteDraft({
    required this.body,
    this.title,
    this.projectName,
    this.type = NoteType.idea,
    this.priority,
    this.tags = const [],
    this.done = false,
  });

  final String body;
  final String? title;

  /// `@projekt` aus der Eingabe. Wird beim Anlegen aufgelöst – und das
  /// Projekt angelegt, falls es noch keins gibt.
  final String? projectName;

  final NoteType type;
  final NotePriority? priority;
  final List<String> tags;

  /// Schon erledigt anlegen – für `- [x]` in einer eingefügten Liste.
  final bool done;

  bool get isEmpty => body.trim().isEmpty && (title?.trim().isEmpty ?? true);

  NoteDraft copyWith({
    NoteType? type,
    NotePriority? priority,
    bool clearPriority = false,
  }) => NoteDraft(
    body: body,
    title: title,
    projectName: projectName,
    type: type ?? this.type,
    priority: clearPriority ? null : (priority ?? this.priority),
    tags: tags,
    done: done,
  );

  @override
  String toString() =>
      'NoteDraft(title: $title, body: "$body", project: $projectName, '
      'type: $type, priority: $priority, tags: $tags, done: $done)';
}

/// Legt Zettel aus der Schnelleingabe an – einen oder viele auf einmal.
///
/// Gehört in die Datenschicht, damit Schnelleingabe, Listen-Import und das
/// Anlegen direkt im Bereich dieselben Regeln teilen: ein unbekanntes
/// `@projekt` legt das Projekt an („lieber unsauber gespeichert als gar
/// nicht“), und eine Liste landet ganz oder gar nicht.
class CaptureService {
  CaptureService({
    required FusenDatabase database,
    required this._projects,
    required this._notes,
  }) : _db = database;

  final FusenDatabase _db;
  final ProjectRepository _projects;
  final NoteRepository _notes;

  /// Legt alle [drafts] in einer Transaktion an.
  ///
  /// [projectId] gilt für jeden Entwurf ohne eigenes `@projekt`; `null`
  /// heißt Inbox. Leere Entwürfe werden übersprungen.
  Future<List<NoteRow>> createAll(List<NoteDraft> drafts, {String? projectId}) {
    return _db.transaction(() async {
      final resolved = <String, String>{};
      final created = <NoteRow>[];
      for (final draft in drafts) {
        if (draft.isEmpty) continue;
        var target = projectId;
        final name = draft.projectName?.trim();
        if (name != null && name.isNotEmpty) {
          target = resolved[name.toLowerCase()] ??=
              (await _projects.findOrCreate(name)).id;
        }
        created.add(
          await _notes.create(
            projectId: target,
            type: draft.type,
            title: draft.title,
            body: draft.body,
            tags: draft.tags,
            priority: draft.priority,
            status: draft.done ? NoteStatus.done : NoteStatus.open,
          ),
        );
      }
      return created;
    });
  }

  /// Nimmt einen Import zurück. Projekte, die dabei entstanden sind, bleiben –
  /// sie könnten inzwischen schon anderswo benutzt werden.
  Future<void> undo(List<NoteRow> created) async {
    await _db.transaction(() async {
      for (final note in created) {
        await _notes.delete(note.id);
      }
    });
  }
}
