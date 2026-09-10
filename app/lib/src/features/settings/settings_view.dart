import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../sync/sync_backend.dart';
import '../../sync/sync_service.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/fusen_logo.dart';
import '../../ui/widgets/labels.dart';
import '../../ui/widgets/note_card.dart';
import '../../ui/widgets/page_body.dart';
import '../../ui/widgets/paper.dart';
import '../note/note_editor.dart' show copyToClipboard;
import '../project/project_view.dart' show PageHeader;

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
      appBar: const PageHeader(
        title: 'Einstellungen',
        icon: Icons.settings_outlined,
        maxWidth: 720,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : PageBody(
              maxWidth: 720,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  pageGutter(context),
                  Insets.lg,
                  pageGutter(context),
                  Insets.xxl,
                ),
                children: [
                  _Group(
                    label: 'Sync',
                    description:
                        'Ohne Server läuft Fusen rein lokal. Mit Server sehen '
                        'alle Geräte mit demselben Zugangscode dieselben '
                        'Zettel.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _urlController,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Server-URL',
                            hintText: 'https://fusen.beispiel.de',
                          ),
                        ),
                        const SizedBox(height: Insets.md),
                        TextField(
                          controller: _codeController,
                          obscureText: true,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Zugangscode',
                            helperText:
                                'Wird beim ersten Start des Servers '
                                'ausgegeben.',
                          ),
                        ),
                        const SizedBox(height: Insets.lg),
                        Wrap(
                          spacing: Insets.sm,
                          runSpacing: Insets.sm,
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
                          const SizedBox(height: Insets.lg),
                          _Banner(text: _feedback!, isError: _feedbackIsError),
                        ],
                        const SizedBox(height: Insets.lg),
                        _SyncStatusTile(outcome: outcome),
                      ],
                    ),
                  ),
                  _Group(
                    label: 'Erscheinungsbild',
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined, size: 18),
                          label: Text('System'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined, size: 18),
                          label: Text('Hell'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined, size: 18),
                          label: Text('Dunkel'),
                        ),
                      ],
                      selected: {themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) => ref
                          .read(themeModeProvider.notifier)
                          .set(selection.first),
                    ),
                  ),
                  _Group(
                    label: 'Gerät',
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gerätekennung',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                deviceId,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: monoFamily,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kopieren',
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => copyToClipboard(context, deviceId),
                        ),
                      ],
                    ),
                  ),
                  const _About(),
                ],
              ),
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

/// Ein Block Einstellungen: Überschrift, optional ein Satz Erklärung,
/// darunter die Bedienelemente auf eigener Fläche.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.child, this.description});

  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Insets.xs, bottom: Insets.sm),
            child: SectionLabel(label),
          ),
          PaperPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (description != null) ...[
                  Text(description!, style: theme.textTheme.bodySmall),
                  const SizedBox(height: Insets.lg),
                ],
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusTile extends ConsumerWidget {
  const _SyncStatusTile({required this.outcome});

  final SyncOutcome outcome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (icon, text, color) = switch (outcome.status) {
      SyncStatus.disabled => (
        Icons.cloud_off_outlined,
        'Kein Server',
        scheme.onSurfaceVariant,
      ),
      SyncStatus.idle => (
        Icons.schedule,
        'Noch nicht abgeglichen',
        scheme.onSurfaceVariant,
      ),
      SyncStatus.running => (Icons.sync, 'Läuft …', scheme.primary),
      SyncStatus.success => (
        Icons.cloud_done_outlined,
        'Abgeglichen: ${outcome.pushed} hoch, ${outcome.pulled} runter',
        scheme.tertiary,
      ),
      SyncStatus.authFailed => (
        Icons.lock_outline,
        'Zugangscode passt nicht',
        scheme.error,
      ),
      SyncStatus.error => (
        Icons.cloud_off_outlined,
        outcome.message ?? 'Fehler beim Abgleich',
        scheme.error,
      ),
    };

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: Radii.smAll,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: theme.textTheme.bodyMedium),
              if (outcome.at != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Zuletzt ${formatTimestamp(outcome.at!)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: 'Jetzt abgleichen',
          icon: const Icon(Icons.refresh, size: 18),
          onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = isError ? scheme.error : scheme.tertiary;

    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: Radii.smAll,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: Insets.md),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Der Abbinder – die Marke einmal groß, dazu der Satz, woher der Name
/// kommt.
class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FusenLogo(size: 32),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fusen', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'Fusen (付箋) ist das japanische Wort für Haftnotiz. '
                  'Open Source unter der MIT-Lizenz.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
