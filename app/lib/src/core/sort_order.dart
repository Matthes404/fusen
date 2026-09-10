/// Hilfsfunktionen für die Sortierung per Drag-and-drop.
///
/// Positionen sind Fließkommazahlen, damit ein Element zwischen zwei andere
/// geschoben werden kann, ohne alle folgenden Einträge neu zu schreiben.
/// Das hält den Sync klein: eine Verschiebung ändert genau einen Datensatz.
library;

const double sortOrderGap = 1024;

/// Position für ein Element, das zwischen [before] und [after] landen soll.
///
/// `null` bedeutet „kein Nachbar auf dieser Seite“.
double sortOrderBetween(double? before, double? after) {
  if (before == null && after == null) return 0;
  if (before == null) return after! - sortOrderGap;
  if (after == null) return before + sortOrderGap;
  return (before + after) / 2;
}

/// Neue Positionen, wenn [items] bereits in der gewünschten Reihenfolge liegen.
///
/// Wird benutzt, wenn die Abstände nach vielen Verschiebungen zu klein
/// geworden sind (siehe [needsRebalance]).
List<double> rebalancedSortOrders(int count) =>
    List<double>.generate(count, (i) => i * sortOrderGap);

/// Ob die Abstände zwischen benachbarten Positionen zu klein geworden sind.
///
/// `double` hat rund 15 signifikante Stellen; ab etwa 50 Halbierungen
/// zwischen denselben zwei Nachbarn ist keine Zwischenposition mehr
/// darstellbar. Wir greifen deutlich früher ein.
bool needsRebalance(List<double> orders) {
  for (var i = 1; i < orders.length; i++) {
    if ((orders[i] - orders[i - 1]).abs() < 0.000001) return true;
  }
  return false;
}
