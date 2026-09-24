import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/database.dart';
import '../../data/models/note_status.dart';
import '../../data/models/note_type.dart';
import '../../data/repositories/note_repository.dart';
import '../../ui/note_style.dart';
import '../../ui/widgets/undo.dart';
import '../attachments/image_input.dart';

/// Was man mit einem Zettel tun kann – mit Rückmeldung und „Rückgängig“.
///
/// Die Regeln stehen im Repository; hier geht es nur darum, dass Karte,
/// Menü, Wischgeste und Editor dasselbe sagen und dieselbe Rücknahme
/// anbieten.
abstract final class NoteActions {
  /// Abhaken oder wieder öffnen.
  static Future<void> setDone(
    BuildContext context,
    WidgetRef ref,
    NoteRow note, {
    required bool done,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(noteRepositoryProvider);
    final previous = note.status;
    final next = done ? NoteStatus.done : NoteStatus.open;
    if (previous == next) return;

    await repository.setStatus(note.id, next);
    // Beim Abhaken wandert die Karte in die eingeklappte Gruppe – dann soll
    // man sehen, wohin, und sie mit einem Tipp zurückholen können.
    if (done && messenger != null) {
      final label = statusLabel(note.type, NoteStatus.done);
      showUndoSnackBar(
        messenger,
        '${label[0].toUpperCase()}${label.substring(1)}: ${_short(note)}',
        onUndo: () => repository.setStatus(note.id, previous),
        duration: const Duration(seconds: 4),
      );
    }
  }

  static Future<void> setStatus(
    WidgetRef ref,
    NoteRow note,
    NoteStatus status,
  ) => ref.read(noteRepositoryProvider).setStatus(note.id, status);

  static Future<void> archive(
    BuildContext context,
    WidgetRef ref,
    NoteRow note,
  ) async {
    // Schon archiviert: nichts tun. Sonst bekäme der Zettel einen neuen
    // Archivzeitpunkt, und „Rückgängig“ holte ihn aufs Board zurück, wo er
    // vorher gar nicht lag.
    if (note.archivedAt != null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(noteRepositoryProvider);
    await repository.archive(note.id);
    if (messenger != null) {
      showUndoSnackBar(
        messenger,
        'Archiviert: ${_short(note)}',
        onUndo: () => repository.unarchive(note.id),
      );
    }
  }

  /// Aus dem Archiv zurück aufs Board.
  static Future<void> unarchive(
    BuildContext context,
    WidgetRef ref,
    NoteRow note,
  ) async {
    if (note.archivedAt == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(noteRepositoryProvider);
    await repository.unarchive(note.id);
    if (messenger != null) {
      showUndoSnackBar(
        messenger,
        'Zurückgeholt: ${_short(note)}',
        onUndo: () => repository.archive(note.id),
      );
    }
  }

  static Future<void> delete(
    BuildContext context,
    WidgetRef ref,
    NoteRow note,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(noteRepositoryProvider);
    await repository.delete(note.id);
    if (messenger != null) {
      showUndoSnackBar(
        messenger,
        'Gelöscht: ${_short(note)}',
        onUndo: () => repository.restore(note.id),
      );
    }
  }

  static Future<void> moveTo(
    BuildContext context,
    WidgetRef ref,
    NoteRow note,
    String? projectId,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(noteRepositoryProvider);
    final projects = ref.read(projectsProvider).value ?? const [];
    final move = await repository.moveToProject(note.id, projectId);
    if (messenger == null || move == null) return;
    final name = projectId == null
        ? 'Inbox'
        : projects.where((p) => p.id == projectId).firstOrNull?.name ??
              'Projekt';
    showUndoSnackBar(
      messenger,
      'Nach „$name“ verschoben',
      onUndo: () => repository.undoMove(move),
    );
  }

  static Future<void> changeType(
    BuildContext context,
    WidgetRef ref,
    NoteRow note,
    NoteType type,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(noteRepositoryProvider).changeType(note.id, type);
    } on NoteEditLockedException catch (error) {
      if (messenger != null) showMessage(messenger, error.toString());
    }
  }

  /// Bilder auswählen (oder fotografieren) und anhängen.
  static Future<void> addImages(
    BuildContext context,
    WidgetRef ref,
    NoteRow note, {
    bool camera = false,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(attachmentRepositoryProvider);
    try {
      final images = camera
          ? [?await ImageInput.camera()]
          : await ImageInput.pick();
      for (final image in images) {
        await repository.add(note.id, image);
      }
      if (images.isNotEmpty && messenger != null) {
        showMessage(
          messenger,
          images.length == 1
              ? 'Bild angehängt'
              : '${images.length} Bilder angehängt',
        );
      }
    } on Object catch (error) {
      if (messenger != null) showMessage(messenger, describeImageError(error));
    }
  }

  /// Die ersten Worte eines Zettels – für Meldungen.
  static String _short(NoteRow note) {
    final text = (note.title?.isNotEmpty ?? false) ? note.title! : note.body;
    final line = text.split('\n').first.trim();
    return line.length <= 40 ? line : '${line.substring(0, 39)}…';
  }
}
