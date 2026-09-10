import 'package:flutter/material.dart';

import '../data/models/note_status.dart';
import '../data/models/note_type.dart';

/// Beschriftungen und Symbole der sieben Zettel-Typen an einer Stelle.
extension NoteTypeStyle on NoteType {
  String get label => switch (this) {
    NoteType.instruction => 'Aktuelle Anweisung',
    NoteType.step => 'Nächster Schritt',
    NoteType.question => 'Frage',
    NoteType.requirement => 'Anforderung',
    NoteType.idea => 'Idee',
    NoteType.reference => 'Referenz',
    NoteType.log => 'Log',
  };

  /// Überschrift des Bereichs in der Projekt-Ansicht.
  String get sectionTitle => switch (this) {
    NoteType.instruction => 'Aktuelle Anweisung',
    NoteType.step => 'Nächste Schritte',
    NoteType.question => 'Offene Fragen',
    NoteType.requirement => 'Anforderungen',
    NoteType.idea => 'Ideen',
    NoteType.reference => 'Referenzen',
    NoteType.log => 'Log',
  };

  String get emptyHint => switch (this) {
    NoteType.instruction => 'Keine Anweisung gesetzt.',
    NoteType.step => 'Nichts offen.',
    NoteType.question => 'Alles geklärt.',
    NoteType.requirement => 'Noch nichts festgehalten.',
    NoteType.idea => 'Noch keine Einfälle.',
    NoteType.reference => 'Keine Links oder Snippets.',
    NoteType.log => 'Noch nichts passiert.',
  };

  IconData get icon => switch (this) {
    NoteType.instruction => Icons.push_pin_outlined,
    NoteType.step => Icons.check_circle_outline,
    NoteType.question => Icons.help_outline,
    NoteType.requirement => Icons.rule_outlined,
    NoteType.idea => Icons.lightbulb_outline,
    NoteType.reference => Icons.link,
    NoteType.log => Icons.history,
  };

  Color color(ColorScheme scheme) => switch (this) {
    NoteType.instruction => const Color(0xFFE5484D),
    NoteType.step => const Color(0xFF30A46C),
    NoteType.question => const Color(0xFFFFB224),
    NoteType.requirement => const Color(0xFF0091FF),
    NoteType.idea => const Color(0xFF6E56CF),
    NoteType.reference => const Color(0xFF12A594),
    NoteType.log => scheme.outline,
  };
}

extension NotePriorityStyle on NotePriority {
  String get label => switch (this) {
    NotePriority.must => 'Muss',
    NotePriority.should => 'Soll',
    NotePriority.could => 'Kann',
  };

  Color get color => switch (this) {
    NotePriority.must => const Color(0xFFE5484D),
    NotePriority.should => const Color(0xFFF76B15),
    NotePriority.could => const Color(0xFF8B8D98),
  };
}

/// Statusbezeichnungen hängen vom Typ ab: eine Anforderung ist „umgesetzt“,
/// ein Schritt „erledigt“.
String statusLabel(NoteType type, NoteStatus status) =>
    switch ((type, status)) {
      (_, NoteStatus.open) when type == NoteType.instruction => 'gilt gerade',
      (_, NoteStatus.open) => 'offen',
      (NoteType.requirement, NoteStatus.done) => 'umgesetzt',
      (NoteType.question, NoteStatus.done) => 'beantwortet',
      (NoteType.instruction, NoteStatus.done) => 'im Verlauf',
      (_, NoteStatus.done) => 'erledigt',
      (_, NoteStatus.discarded) => 'verworfen',
    };
