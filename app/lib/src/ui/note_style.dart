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

  /// Die Kennfarbe des Typs.
  ///
  /// Zwei Sätze statt einem: dieselbe Farbe, die auf Papier kräftig wirkt,
  /// leuchtet im Dunkeln viel zu grell. Beide Sätze sind gegen ihren
  /// Untergrund auf Lesbarkeit geprüft.
  Color color(ColorScheme scheme) {
    final light = scheme.brightness == Brightness.light;
    return switch (this) {
      NoteType.instruction =>
        light ? const Color(0xFFBE2B54) : const Color(0xFFFF94B0),
      NoteType.step =>
        light ? const Color(0xFF1E7A4C) : const Color(0xFF5FD196),
      NoteType.question =>
        light ? const Color(0xFFC2410C) : const Color(0xFFFFA26B),
      NoteType.requirement =>
        light ? const Color(0xFF1160B0) : const Color(0xFF7CC0FF),
      NoteType.idea =>
        light ? const Color(0xFF6D3FC4) : const Color(0xFFBFAAFF),
      NoteType.reference =>
        light ? const Color(0xFF0E7C72) : const Color(0xFF5FD9CC),
      NoteType.log => scheme.outline,
    };
  }

  /// Der Hauch Farbe, den der Zettel selbst bekommt.
  ///
  /// Gerade so viel, dass ein Stapel Zettel nach Typ sortiert aussieht,
  /// ohne dass der Text darauf schlechter zu lesen wäre. Das Log bleibt
  /// bewusst farblos – ein Protokoll ist Hintergrund, kein Blickfang.
  Color wash(ColorScheme scheme) {
    if (this == NoteType.log) return const Color(0x00000000);
    final strength = scheme.brightness == Brightness.light ? 0.055 : 0.07;
    return color(scheme).withValues(alpha: strength);
  }
}

extension NotePriorityStyle on NotePriority {
  String get label => switch (this) {
    NotePriority.must => 'Muss',
    NotePriority.should => 'Soll',
    NotePriority.could => 'Kann',
  };

  Color color(ColorScheme scheme) {
    final light = scheme.brightness == Brightness.light;
    return switch (this) {
      NotePriority.must =>
        light ? const Color(0xFFBE2B54) : const Color(0xFFFF94B0),
      NotePriority.should =>
        light ? const Color(0xFFC2410C) : const Color(0xFFFFA26B),
      NotePriority.could => scheme.onSurfaceVariant,
    };
  }

  /// Wie dringlich das aussehen soll: „Muss“ trägt Farbe, „Kann“ nicht.
  bool get isEmphasised => this != NotePriority.could;
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
