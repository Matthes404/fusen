import 'package:flutter/widgets.dart';

/// Alle Abstände sind Vielfache von vier.
///
/// Eine Handvoll benannter Werte statt gestreuter Zahlen: dadurch stehen
/// gleichartige Dinge überall gleich weit auseinander, ohne dass man beim
/// Bauen jedes Mal neu abschätzt.
abstract final class Insets {
  /// Zwischen Symbol und Beschriftung.
  static const double xs = 4;

  /// Zwischen eng zusammengehörenden Zeilen.
  static const double sm = 8;

  /// Innenabstand kleiner Elemente, Abstand zwischen Karten.
  static const double md = 12;

  /// Innenabstand einer Karte, Seitenrand auf dem Handy.
  static const double lg = 16;

  /// Abstand zwischen zwei Bereichen.
  static const double xl = 24;

  /// Luft um eine ganze Seite.
  static const double xxl = 32;

  /// Platz unter der letzten Karte, damit sie nicht unter dem
  /// Schwebe-Knopf klebt.
  static const double listBottom = 112;
}

/// Radien in vier Stufen – je größer die Fläche, desto runder die Ecke.
abstract final class Radii {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;

  /// Für Elemente, die vollständig rund sein sollen (Pillen, Punkte).
  static const double pill = 999;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Bewegung soll erklären, nicht unterhalten: kurz, weich, ohne Nachfedern.
abstract final class Motion {
  /// Zustandswechsel unter dem Zeiger (Hover, Druck).
  static const Duration fast = Duration(milliseconds: 120);

  /// Der Normalfall: Auf- und Zuklappen, Ein- und Ausblenden.
  static const Duration base = Duration(milliseconds: 220);

  /// Seitenwechsel.
  static const Duration slow = Duration(milliseconds: 320);

  /// Standardkurve: schnell los, sanft aus.
  static const Curve standard = Curves.easeOutCubic;

  /// Für Dinge, die hereinkommen und Aufmerksamkeit verdienen.
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
}

/// Ab dieser Breite bekommt ein Dialog seine volle Größe.
const double compactWidth = 700;
