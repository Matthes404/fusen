import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/db/settings_store.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/capture_service.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/project_repository.dart';
import '../sync/pocketbase_backend.dart';
import '../sync/sync_backend.dart';
import '../sync/sync_service.dart';

/// Wird beim Start in `main()` überschrieben – die Datenbank muss geöffnet
/// sein, bevor das erste Widget baut.
final databaseProvider = Provider<FusenDatabase>(
  (ref) => throw UnimplementedError('databaseProvider wurde nicht gesetzt'),
);

/// Kennung dieses Geräts, ebenfalls beim Start gesetzt.
final deviceIdProvider = Provider<String>(
  (ref) => throw UnimplementedError('deviceIdProvider wurde nicht gesetzt'),
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(databaseProvider)),
);

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepository(ref.watch(databaseProvider)),
);

final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => NoteRepository(
    ref.watch(databaseProvider),
    deviceId: ref.watch(deviceIdProvider),
  ),
);

final attachmentRepositoryProvider = Provider<AttachmentRepository>(
  (ref) => AttachmentRepository(
    ref.watch(databaseProvider),
    deviceId: ref.watch(deviceIdProvider),
  ),
);

final captureServiceProvider = Provider<CaptureService>(
  (ref) => CaptureService(
    database: ref.watch(databaseProvider),
    projects: ref.watch(projectRepositoryProvider),
    notes: ref.watch(noteRepositoryProvider),
  ),
);

final syncBackendProvider = Provider<SyncBackend>(
  (ref) => PocketBaseSyncBackend(),
);

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(
    database: ref.watch(databaseProvider),
    backend: ref.watch(syncBackendProvider),
    settings: ref.watch(settingsStoreProvider),
  ),
);

// --- Abgeleitete Daten ----------------------------------------------------

final projectsProvider = StreamProvider<List<ProjectRow>>(
  (ref) => ref.watch(projectRepositoryProvider).watchProjects(),
);

final archivedProjectsProvider = StreamProvider<List<ProjectRow>>(
  (ref) => ref
      .watch(projectRepositoryProvider)
      .watchProjects(includeArchived: true)
      .map((all) => all.where((p) => p.archivedAt != null).toList()),
);

final projectProvider = StreamProvider.family<ProjectRow?, String>(
  (ref, id) => ref.watch(projectRepositoryProvider).watchProject(id),
);

final openCountsProvider = StreamProvider<Map<String?, int>>(
  (ref) => ref.watch(noteRepositoryProvider).watchOpenCounts(),
);

/// Alle sichtbaren Zettel eines Projekts außer dem Log. `null` = Inbox.
final boardProvider = StreamProvider.family<List<NoteRow>, String?>(
  (ref, projectId) => ref.watch(noteRepositoryProvider).watchBoard(projectId),
);

/// Die Inbox – alle Zettel ohne Projekt.
final inboxProvider = StreamProvider<List<NoteRow>>(
  (ref) => ref.watch(noteRepositoryProvider).watchInbox(),
);

final logProvider = StreamProvider.family<List<NoteRow>, String?>(
  (ref, projectId) => ref.watch(noteRepositoryProvider).watchLog(projectId),
);

final archiveProvider = StreamProvider.family<List<NoteRow>, String?>(
  (ref, projectId) => ref.watch(noteRepositoryProvider).watchArchive(projectId),
);

final noteProvider = StreamProvider.family<NoteRow?, String>(
  (ref, id) => ref.watch(noteRepositoryProvider).watchNote(id),
);

/// Die Bilder eines Zettels.
final noteAttachmentsProvider =
    StreamProvider.family<List<AttachmentRow>, String>(
      (ref, noteId) =>
          ref.watch(attachmentRepositoryProvider).watchForNote(noteId),
    );

/// Die Bilddaten eines Anhangs – `null`, solange sie noch unterwegs sind.
final attachmentBytesProvider = StreamProvider.family<Uint8List?, String>(
  (ref, attachmentId) =>
      ref.watch(attachmentRepositoryProvider).watchBytes(attachmentId),
);

/// Offene, priorisierte Arbeitszettel aus allen Projekten.
final prioritizedProvider = StreamProvider<List<NoteRow>>(
  (ref) => ref.watch(noteRepositoryProvider).watchPrioritized(),
);

/// Zuletzt abgeschlossene Arbeitszettel aus allen Projekten.
final recentlyClosedProvider = StreamProvider<List<NoteRow>>(
  (ref) => ref.watch(noteRepositoryProvider).watchRecentlyClosed(),
);

/// Offen und erledigt pro Projekt – `null` ist die Inbox.
final progressProvider = StreamProvider<Map<String?, NoteProgress>>(
  (ref) => ref.watch(noteRepositoryProvider).watchProgress(),
);

/// Die gerade geltende Anweisung pro Projekt.
final currentInstructionsProvider = StreamProvider<Map<String?, NoteRow>>(
  (ref) => ref.watch(noteRepositoryProvider).watchCurrentInstructions(),
);

/// Der nächste offene Schritt pro Projekt.
final nextStepsProvider = StreamProvider<Map<String?, NoteRow>>(
  (ref) => ref.watch(noteRepositoryProvider).watchNextSteps(),
);

// --- Oberfläche -----------------------------------------------------------

/// Zuletzt geöffnetes Projekt – die Schnelleingabe schlägt es vor.
class LastProjectNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void remember(String? projectId) {
    state = projectId;
    unawaited(
      ref
          .read(settingsStoreProvider)
          .write(SettingKeys.lastProjectId, projectId),
    );
  }

  Future<void> restore() async {
    state = await ref
        .read(settingsStoreProvider)
        .read(SettingKeys.lastProjectId);
  }
}

final lastProjectProvider = NotifierProvider<LastProjectNotifier, String?>(
  LastProjectNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  Future<void> restore() async {
    final stored = await ref
        .read(settingsStoreProvider)
        .read(SettingKeys.themeMode);
    state = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref
        .read(settingsStoreProvider)
        .write(SettingKeys.themeMode, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// --- Sync -----------------------------------------------------------------

/// Wie oft im Hintergrund abgeglichen wird, solange die App offen ist.
const Duration syncInterval = Duration(minutes: 2);

class SyncController extends Notifier<SyncOutcome> {
  Timer? _timer;

  @override
  SyncOutcome build() {
    _timer = Timer.periodic(syncInterval, (_) => unawaited(syncNow()));
    ref.onDispose(() => _timer?.cancel());
    return const SyncOutcome(status: SyncStatus.idle);
  }

  Future<SyncOutcome> syncNow() async {
    if (state.status == SyncStatus.running) return state;
    state = const SyncOutcome(status: SyncStatus.running);
    final outcome = await ref.read(syncServiceProvider).syncNow();
    state = outcome;
    return outcome;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncOutcome>(
  SyncController.new,
);

/// Ob überhaupt ein Server hinterlegt ist.
final syncEnabledProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(settingsStoreProvider)
      .watch(SettingKeys.serverUrl)
      .map((url) => url != null && url.trim().isNotEmpty),
);
