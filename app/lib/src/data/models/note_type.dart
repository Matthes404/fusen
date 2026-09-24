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

  /// Zettel, die man abarbeitet – im Gegensatz zu Anweisung, Referenz und
  /// Log, die etwas festhalten.
  ///
  /// Nur sie tragen eine Priorität und lassen sich abhaken. Eine Referenz
  /// ist nicht „erledigt“, ein Log-Eintrag nicht „dringend“.
  bool get isWorkItem => switch (this) {
    NoteType.step ||
    NoteType.requirement ||
    NoteType.question ||
    NoteType.idea => true,
    NoteType.instruction || NoteType.reference || NoteType.log => false,
  };

  /// Typen, die eine Priorität tragen dürfen.
  bool get supportsPriority => isWorkItem;

  /// Typen, die abgehakt werden können.
  bool get isCheckable => isWorkItem;

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
