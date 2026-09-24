import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/capture/desktop_capture.dart';
import '../features/shell/home_shell.dart';
import '../ui/theme.dart';
import 'providers.dart';

class FusenApp extends ConsumerStatefulWidget {
  const FusenApp({super.key});

  @override
  ConsumerState<FusenApp> createState() => _FusenAppState();
}

class _FusenAppState extends ConsumerState<FusenApp> {
  final _shellKey = GlobalKey<HomeShellState>();
  DesktopCapture? _desktopCapture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  @override
  void dispose() {
    _desktopCapture?.unregister();
    super.dispose();
  }

  Future<void> _afterFirstFrame() async {
    // Erst abgleichen, wenn etwas zu sehen ist – der Start soll nicht auf
    // dem Netz warten.
    unawaitedSync();
    // Bilddaten entfernter Bilder aufräumen, sobald „Rückgängig“ keine Rolle
    // mehr spielt – die Beschreibung bleibt als Tombstone für den Sync.
    ref.read(attachmentRepositoryProvider).purgeDeletedData().ignore();

    if (!isDesktop) return;
    final capture = DesktopCapture(
      openCapture: () async => _shellKey.currentState?.openCapture(),
    );
    await capture.register();
    if (mounted) _desktopCapture = capture;
  }

  void unawaitedSync() {
    ref.read(syncControllerProvider.notifier).syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Fusen',
      debugShowCheckedModeBanner: false,
      theme: fusenTheme(Brightness.light),
      darkTheme: fusenTheme(Brightness.dark),
      themeMode: themeMode,
      home: HomeShell(key: _shellKey),
    );
  }
}
