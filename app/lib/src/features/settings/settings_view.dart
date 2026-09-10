import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../sync/sync_backend.dart';
import '../../sync/sync_service.dart';
import '../../ui/widgets/note_card.dart';
import '../note/note_editor.dart' show copyToClipboard;

/// Einstellungen: Sync-Zugang, Erscheinungsbild, Gerätekennung.
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _urlController = TextEditingController();
  final _codeController = TextEditingController();

  bool _loaded = false;
  bool _busy = false;
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadCredentials() async {
    final credentials = await ref.read(syncServiceProvider).readCredentials();
    if (!mounted) return;
    setState(() {
      _urlController.text = credentials?.serverUrl ?? '';
      _codeController.text = credentials?.accessCode ?? '';
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = ref.watch(syncControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final deviceId = ref.watch(deviceIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text('Sync', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Ohne Server läuft Fusen rein lokal. Mit Server sehen alle '
                  'Geräte mit demselben Zugangscode dieselben Zettel.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server-URL',
                    hintText: 'https://fusen.beispiel.de',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Zugangscode',
                    helperText:
                        'Wird beim ersten Start des Servers ausgegeben.',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _connect,
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Verbinden und abgleichen'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _disconnect,
                      icon: const Icon(Icons.link_off, size: 18),
                      label: const Text('Trennen'),
                    ),
                  ],
                ),
                if (_feedback != null) ...[
                  const SizedBox(height: 12),
                  _Banner(text: _feedback!, isError: _feedbackIsError),
                ],
                const SizedBox(height: 12),
                _SyncStatusTile(outcome: outcome),
                const Divider(height: 40),
                Text('Erscheinungsbild', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(value: ThemeMode.light, label: Text('Hell')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dunkel')),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) =>
                      ref.read(themeModeProvider.notifier).set(selection.first),
                ),
                const Divider(height: 40),
                Text('Gerät', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gerätekennung'),
                  subtitle: Text(deviceId),
                  trailing: IconButton(
                    tooltip: 'Kopieren',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => copyToClipboard(context, deviceId),
                  ),
                ),
                const Divider(height: 40),
                Text('Über Fusen', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Fusen (付箋) ist das japanische Wort für Haftnotiz. '
                  'Open Source unter der MIT-Lizenz.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _feedback = null;
    });

    final sync = ref.read(syncServiceProvider);
    final credentials = SyncCredentials(
      serverUrl: _urlController.text.trim(),
      accessCode: _codeController.text,
    );

    if (!credentials.isComplete) {
      setState(() {
        _busy = false;
        _feedback = 'Server-URL und Zugangscode ausfüllen.';
        _feedbackIsError = true;
      });
      return;
    }

    final test = await sync.testConnection(credentials);
    if (!test.isSuccess) {
      setState(() {
        _busy = false;
        _feedbackIsError = true;
        _feedback = test.status == SyncStatus.authFailed
            ? 'Der Zugangscode passt nicht.'
            : test.message ?? 'Der Server antwortet nicht.';
      });
      return;
    }

    await sync.saveCredentials(credentials);
    final outcome = await ref.read(syncControllerProvider.notifier).syncNow();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _feedbackIsError = !outcome.isSuccess;
      _feedback = outcome.isSuccess
          ? 'Verbunden. ${outcome.pushed} hoch, ${outcome.pulled} runter.'
          : outcome.message ?? 'Abgleich fehlgeschlagen.';
    });
  }

  Future<void> _disconnect() async {
    await ref.read(syncServiceProvider).saveCredentials(null);
    if (!mounted) return;
    setState(() {
      _codeController.clear();
      _urlController.clear();
      _feedback = 'Getrennt. Die Zettel bleiben auf diesem Gerät.';
      _feedbackIsError = false;
    });
  }
}

class _SyncStatusTile extends ConsumerWidget {
  const _SyncStatusTile({required this.outcome});

  final SyncOutcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, text) = switch (outcome.status) {
      SyncStatus.disabled => (Icons.cloud_off_outlined, 'Kein Server'),
      SyncStatus.idle => (Icons.schedule, 'Noch nicht abgeglichen'),
      SyncStatus.running => (Icons.sync, 'Läuft …'),
      SyncStatus.success => (
        Icons.cloud_done_outlined,
        'Abgeglichen: ${outcome.pushed} hoch, ${outcome.pulled} runter',
      ),
      SyncStatus.authFailed => (Icons.lock_outline, 'Zugangscode passt nicht'),
      SyncStatus.error => (
        Icons.cloud_off_outlined,
        outcome.message ?? 'Fehler beim Abgleich',
      ),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(text),
      subtitle: outcome.at == null
          ? null
          : Text('Zuletzt ${formatTimestamp(outcome.at!)}'),
      trailing: IconButton(
        tooltip: 'Jetzt abgleichen',
        icon: const Icon(Icons.refresh),
        onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
