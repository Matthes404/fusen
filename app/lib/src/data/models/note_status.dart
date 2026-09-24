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

/// Flache Priorität – bewusst keine Hierarchie.
///
/// Die Namen stammen aus der Zeit, als nur Anforderungen eine Priorität
/// hatten (Muss / Soll / Kann). Sie stehen so in der Datenbank und im
/// Sync-Protokoll; für Schritte, Fragen und Ideen zeigt die Oberfläche
/// dieselben drei Stufen als Hoch / Mittel / Niedrig.
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

  /// Sortierschlüssel: je kleiner, desto wichtiger. Ohne Priorität kommt
  /// nach allen dreien.
  static int rankOf(NotePriority? priority) =>
      priority == null ? displayOrder.length : displayOrder.indexOf(priority);
}
