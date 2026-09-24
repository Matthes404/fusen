/// Die Version, mit der gebaut wurde.
///
/// Die Release-Pipeline setzt sie per `--dart-define=FUSEN_VERSION=…` aus dem
/// Tag; ein lokaler Build heißt schlicht „Entwicklungsstand“. So muss niemand
/// daran denken, sie an zwei Stellen hochzuzählen.
const String appVersion = String.fromEnvironment(
  'FUSEN_VERSION',
  defaultValue: 'Entwicklungsstand',
);

/// Wo der Quellcode und die fertigen Pakete liegen.
const String repositoryUrl = 'https://github.com/Matthes404/fusen';
