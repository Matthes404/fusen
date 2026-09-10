/// Zeitquelle der App.
///
/// Wird injiziert, damit Tests Zeit kontrollieren können (z. B. die
/// 24-Stunden-Frist, nach der Log-Einträge nicht mehr editierbar sind).
abstract class Clock {
  const Clock();

  /// Aktueller Zeitpunkt – immer in UTC, damit Zeitstempel geräteübergreifend
  /// vergleichbar bleiben.
  DateTime now();
}

class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Feste Zeit für Tests.
class FixedClock extends Clock {
  FixedClock(this._now);

  DateTime _now;

  void setNow(DateTime value) => _now = value.toUtc();

  @override
  DateTime now() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}
