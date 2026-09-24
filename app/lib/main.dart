import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/app.dart';
import 'src/app/providers.dart';
import 'src/core/ids.dart';
import 'src/data/db/database.dart';
import 'src/data/db/settings_store.dart';
import 'src/features/capture/desktop_capture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  await initDesktopWindow();

  final database = FusenDatabase.open();
  final settings = SettingsStore(database);
  final deviceId = await _deviceId(settings);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        deviceIdProvider.overrideWithValue(deviceId),
      ],
      child: const _Bootstrap(child: FusenApp()),
    ),
  );
}

/// Die mitgelieferten Schriften stehen unter der SIL Open Font License. Sie
/// verlangt, dass die Lizenz mit der Schrift reist – so steht sie auch in
/// der Lizenzübersicht unter Einstellungen.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Plus Jakarta Sans', 'PlusJakartaSans-OFL.txt'),
      ('JetBrains Mono', 'JetBrainsMono-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}

/// Kennung dieses Geräts – einmal vergeben, dann bleibt sie.
Future<String> _deviceId(SettingsStore settings) async {
  final existing = await settings.read(SettingKeys.deviceId);
  if (existing != null && existing.isNotEmpty) return existing;
  final created = newId();
  await settings.write(SettingKeys.deviceId, created);
  return created;
}

/// Lädt gespeicherte Oberflächen-Einstellungen, bevor die App erscheint.
class _Bootstrap extends ConsumerStatefulWidget {
  const _Bootstrap({required this.child});

  final Widget child;

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap> {
  @override
  void initState() {
    super.initState();
    ref.read(themeModeProvider.notifier).restore();
    ref.read(lastProjectProvider.notifier).restore();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
