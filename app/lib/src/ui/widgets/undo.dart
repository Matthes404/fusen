import 'package:flutter/material.dart';

/// Meldet, was gerade passiert ist, und bietet „Rückgängig“ an.
///
/// Statt vor dem Löschen zu fragen: sofort tun und die Rücknahme anbieten.
/// Eine Rückfrage hält bei jedem Mal auf; ein Fehlgriff kommt selten vor
/// und ist mit einem Tipp repariert.
void showUndoSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  required VoidCallback onUndo,
  Duration duration = const Duration(seconds: 5),
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: SnackBarAction(label: 'Rückgängig', onPressed: onUndo),
      ),
    );
}

/// Eine kurze Meldung ohne Aktion.
void showMessage(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
}
