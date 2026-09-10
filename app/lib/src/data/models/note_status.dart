/// Lebenszyklus eines Zettels.
///
/// Die Bedeutung hängt vom Typ ab:
/// * Anforderung: offen / umgesetzt / verworfen
/// * Nächster Schritt: offen / erledigt / verworfen
/// * Aktuelle Anweisung: `open` heißt „gilt gerade“, `done` heißt
///   „steht im Verlauf“
/// * Frage: `done` heißt „beantwortet“
enum NoteStatus {
  open,
  done,
  discarded;

  bool get isOpen => this == NoteStatus.open;
}

/// Flache Priorität für Anforderungen – bewusst keine Hierarchie.
enum NotePriority {
  must,
  should,
  could;

  /// Reihenfolge in der Projekt-Ansicht: Muss zuerst.
  static const List<NotePriority> displayOrder = [
    NotePriority.must,
    NotePriority.should,
    NotePriority.could,
  ];
}
