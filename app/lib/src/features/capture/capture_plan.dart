import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../data/repositories/capture_service.dart';
import 'capture_syntax.dart';
import 'list_syntax.dart';

/// Was aus einer Eingabe würde – ein Zettel oder mehrere.
///
/// Schnelleingabe, Listen-Import und das Anlegen direkt in einem Bereich
/// zeigen vorher an, was entsteht. Dafür wird hier geplant und erst in
/// [CaptureService.createAll] angelegt.
class CapturePlan {
  const CapturePlan({
    required this.drafts,
    required this.entryCount,
    required this.isList,
    required this.split,
  });

  static const CapturePlan empty = CapturePlan(
    drafts: [],
    entryCount: 0,
    isList: false,
    split: false,
  );

  /// Die Zettel, die angelegt würden. Leere sind schon herausgefiltert.
  final List<NoteDraft> drafts;

  /// Wie viele Zettel es als Liste wären – auch dann, wenn gerade nicht
  /// aufgeteilt wird. Die Oberfläche bietet ab zwei das Aufteilen an.
  final int entryCount;

  /// Ob die Eingabe erkennbar eine Liste ist (Aufzählungszeichen,
  /// Kästchen). Dann wird ohne Zutun aufgeteilt.
  final bool isList;

  /// Ob tatsächlich aufgeteilt wird.
  final bool split;

  bool get isEmpty => drafts.isEmpty;

  /// Ob sich Aufteilen überhaupt anbietet.
  bool get canSplit => entryCount > 1;
}

/// Plant, was aus [input] wird.
///
/// [split] `null` heißt automatisch: eine erkennbare Liste wird aufgeteilt,
/// alles andere bleibt ein Zettel. [type] und [priority] gelten, wo die
/// Eingabe selbst nichts sagt. Mit [typeFromHeadings] bestimmt eine
/// Überschrift wie „Ideen:“ den Typ der Einträge darunter – beim Anlegen
/// in einem bestimmten Bereich ist das abgeschaltet.
CapturePlan planCapture(
  String input, {
  bool? split,
  NoteType? type,
  NotePriority? priority,
  bool typeFromHeadings = true,
  List<String> tags = const [],
}) {
  if (input.trim().isEmpty) return CapturePlan.empty;

  final list = parseList(input);
  final entries = list.entries;
  final doSplit = (split ?? list.isList) && entries.length > 1;

  if (!doSplit) {
    final draft = parseCapture(input);
    final single = NoteDraft(
      body: draft.body,
      projectName: draft.projectQuery,
      type: draft.type ?? type ?? NoteType.idea,
      priority: draft.priority ?? priority,
      tags: _merge(tags, draft.tags),
    );
    return CapturePlan(
      drafts: single.isEmpty ? const [] : [single],
      entryCount: entries.length,
      isList: list.isList,
      split: false,
    );
  }

  final drafts = <NoteDraft>[];
  for (final entry in entries) {
    final heading = entry.heading;
    final context = heading == null
        ? const CaptureDraft(body: '')
        : parseCapture(heading);
    final own = parseCapture(entry.text);
    final headingType = typeFromHeadings && heading != null
        ? typeForHeading(heading)
        : null;

    final details = entry.details;
    final draft = NoteDraft(
      // Mit Details wird die Zeile zum Titel und die Details zum Text –
      // so steht auf dem Zettel oben fett, worum es geht.
      title: details == null ? null : own.body,
      body: details ?? own.body,
      projectName: own.projectQuery ?? context.projectQuery,
      type: own.type ?? context.type ?? headingType ?? type ?? NoteType.idea,
      priority: own.priority ?? context.priority ?? priority,
      tags: _merge(tags, [...context.tags, ...own.tags]),
      done: entry.checked,
    );
    if (!draft.isEmpty) drafts.add(draft);
  }

  return CapturePlan(
    drafts: List.unmodifiable(drafts),
    entryCount: entries.length,
    isList: list.isList,
    split: true,
  );
}

List<String> _merge(List<String> a, List<String> b) {
  final seen = <String>{};
  return [
    for (final tag in [...a, ...b])
      if (seen.add(tag.toLowerCase())) tag,
  ];
}
