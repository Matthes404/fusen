import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Fenstersteuerung und globaler Hotkey gibt es nur auf dem Desktop.
///
/// Fusen baut nicht für Web, deshalb ist `dart:io` hier sicher.
bool get isDesktop =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

/// Der globale Hotkey aus dem Konzept: „Ein Textfeld, sonst nichts.“
final HotKey captureHotKey = HotKey(
  key: LogicalKeyboardKey.space,
  modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
  scope: HotKeyScope.system,
);

String get captureHotKeyLabel =>
    Platform.isMacOS ? '⌃⇧Space' : 'Strg+Umschalt+Leertaste';

/// Größe des kleinen Fensters, das der Hotkey aufmacht.
const Size captureWindowSize = Size(680, 220);

/// Verbindet den globalen Hotkey mit der Schnelleingabe.
///
/// Zwei Fälle: steht das Fenster schon offen, wird nur die Eingabe geöffnet.
/// War es weg, klappt es klein und im Vordergrund auf und verschwindet
/// danach wieder – ein Zettel soll das laufende Fenster nicht umräumen.
class DesktopCapture {
  DesktopCapture({required this.openCapture});

  /// Öffnet die Schnelleingabe und liefert, wenn sie wieder zu ist.
  final Future<void> Function() openCapture;

  Rect? _boundsBeforeCapture;
  bool _busy = false;

  /// Ob der Hotkey tatsächlich beim System angemeldet ist.
  bool get isRegistered => _registered;
  bool _registered = false;

  /// Meldet den Hotkey an.
  ///
  /// Schlägt fehl, wenn eine andere Anwendung dieselbe Tastenkombination
  /// belegt oder die Desktop-Umgebung sie nicht vergibt. Das ist kein Grund,
  /// die App zu beenden – Fusen läuft dann eben ohne Hotkey.
  Future<void> register() async {
    if (!isDesktop) return;
    try {
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        captureHotKey,
        keyDownHandler: (_) => trigger(),
      );
      _registered = true;
    } on Object catch (error) {
      _registered = false;
      debugPrint('Fusen: globaler Hotkey nicht verfügbar ($error)');
    }
  }

  Future<void> unregister() async {
    if (!isDesktop || !_registered) return;
    try {
      await hotKeyManager.unregisterAll();
    } on Object catch (_) {
      // Beim Beenden ist ein fehlgeschlagenes Abmelden folgenlos.
    }
    _registered = false;
  }

  Future<void> trigger() async {
    if (!isDesktop || _busy) return;
    _busy = true;
    try {
      final wasVisible = await windowManager.isVisible();
      final wasFocused = wasVisible && await windowManager.isFocused();

      if (wasFocused) {
        await openCapture();
        return;
      }

      if (wasVisible) {
        await windowManager.focus();
        await openCapture();
        return;
      }

      await _enterCaptureWindow();
      await openCapture();
      await _leaveCaptureWindow();
    } finally {
      _busy = false;
    }
  }

  Future<void> _enterCaptureWindow() async {
    _boundsBeforeCapture = await windowManager.getBounds();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(captureWindowSize);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _leaveCaptureWindow() async {
    await windowManager.setAlwaysOnTop(false);
    final bounds = _boundsBeforeCapture;
    if (bounds != null) await windowManager.setBounds(bounds);
    await windowManager.hide();
  }
}

/// Fenstergrundeinstellungen beim Start.
Future<void> initDesktopWindow() async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1100, 780),
      minimumSize: Size(380, 480),
      center: true,
      title: 'Fusen',
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}
