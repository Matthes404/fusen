/// Die sieben Zettel-Typen aus dem Konzept.
///
/// Der Name des Enum-Werts ist gleichzeitig der Wert in der Datenbank und im
/// Sync-Protokoll – er darf deshalb nicht umbenannt werden, ohne eine
/// Migration zu schreiben.
enum NoteType {
  /// Was gerade gilt. Pro Projekt ist immer nur einer offen.
  instruction,

  /// Konkrete To-dos, abhakbar und sortierbar.
  step,

  /// Offene Punkte mit Feld für die Antwort.
  question,

  /// Was das Ergebnis können muss – mit Priorität.
  requirement,

  /// Vage Einfälle, noch ohne Verpflichtung.
  idea,

  /// Links, Befehle, Snippets, Pfade.
  reference,

  /// Was gemacht wurde – mit Zeitstempel, chronologisch.
  log;

  /// Reihenfolge der Bereiche in der Projekt-Ansicht.
  static const List<NoteType> sectionOrder = [
    NoteType.instruction,
    NoteType.step,
    NoteType.question,
    NoteType.requirement,
    NoteType.idea,
    NoteType.reference,
    NoteType.log,
  ];

  /// Typen, die eine Priorität tragen dürfen.
  bool get supportsPriority => this == NoteType.requirement;

  /// Typen, die abgehakt werden können.
  bool get isCheckable => this == NoteType.step || this == NoteType.requirement;

  /// Typen, deren Reihenfolge der Nutzer selbst bestimmt.
  bool get isManuallySortable => this == NoteType.step;

  /// Typen, die ein Antwortfeld haben.
  bool get hasAnswer => this == NoteType.question;

  /// Ob der Zettel nachträglich änderbar bleibt.
  ///
  /// Log-Einträge sind ein Protokoll: nach 24 Stunden friert der Text ein,
  /// damit der Verlauf verlässlich bleibt.
  bool get isImmutableAfterGracePeriod => this == NoteType.log;
}

/// Frist, nach der ein Log-Eintrag nicht mehr editierbar ist.
const Duration logEditWindow = Duration(hours: 24);
