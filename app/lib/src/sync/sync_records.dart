import '../data/db/database.dart';
import '../data/models/note_status.dart';
import '../data/models/note_type.dart';
import 'sync_ids.dart';

DateTime? _parseTime(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  if (text.isEmpty) return null;
  // PocketBase liefert "2026-01-31 12:00:00.000Z", Dart erwartet ein "T".
  return DateTime.tryParse(text.replaceFirst(' ', 'T'))?.toUtc();
}

String _formatTime(DateTime value) => value.toUtc().toIso8601String();

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name.toString()) return value;
  }
  return null;
}

/// Ein Projekt so, wie es über die Leitung geht.
///
/// Bewusst getrennt von [ProjectRow]: das lokale Schema darf sich ändern
/// (z. B. `pendingSync`), ohne das Sync-Format zu brechen.
class SyncProject {
  const SyncProject({
    required this.id,
    required this.name,
    required this.color,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
    this.deletedAt,
  });

  factory SyncProject.fromRow(ProjectRow row) => SyncProject(
    id: row.id,
    name: row.name,
    color: row.color,
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    archivedAt: row.archivedAt,
    deletedAt: row.deletedAt,
  );

  factory SyncProject.fromJson(Map<String, dynamic> json) => SyncProject(
    id: localIdFor(json['id'].toString()),
    name: json['name']?.toString() ?? '',
    color: (json['color'] as num?)?.toInt() ?? 0xFF6E56CF,
    sortOrder: (json['sort_order'] as num?)?.toDouble() ?? 0,
    createdAt: _parseTime(json['created_at']) ?? DateTime.now().toUtc(),
    updatedAt: _parseTime(json['updated_at']) ?? DateTime.now().toUtc(),
    archivedAt: _parseTime(json['archived_at']),
    deletedAt: _parseTime(json['deleted_at']),
  );

  final String id;
  final String name;
  final int color;
  final double sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final DateTime? deletedAt;

  Map<String, dynamic> toJson() => {
    'id': remoteIdFor(id),
    'name': name,
    'color': color,
    'sort_order': sortOrder,
    'created_at': _formatTime(createdAt),
    'updated_at': _formatTime(updatedAt),
    'archived_at': archivedAt == null ? '' : _formatTime(archivedAt!),
    'deleted_at': deletedAt == null ? '' : _formatTime(deletedAt!),
  };

  ProjectRow toRow({required bool pendingSync}) => ProjectRow(
    id: id,
    name: name,
    color: color,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    archivedAt: archivedAt,
    deletedAt: deletedAt,
    pendingSync: pendingSync,
  );
}

/// Ein Zettel so, wie er über die Leitung geht.
class SyncNote {
  const SyncNote({
    required this.id,
    required this.type,
    required this.status,
    required this.body,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
    this.projectId,
    this.title,
    this.answer,
    this.priority,
    this.tags = const [],
    this.archivedAt,
    this.deletedAt,
  });

  factory SyncNote.fromRow(NoteRow row) => SyncNote(
    id: row.id,
    projectId: row.projectId,
    type: row.type,
    title: row.title,
    body: row.body,
    answer: row.answer,
    status: row.status,
    priority: row.priority,
    tags: row.tags,
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    archivedAt: row.archivedAt,
    deletedAt: row.deletedAt,
    deviceId: row.deviceId,
  );

  factory SyncNote.fromJson(Map<String, dynamic> json) {
    final rawProject = json['project_id']?.toString() ?? '';
    final rawTags = json['tags'];
    return SyncNote(
      id: localIdFor(json['id'].toString()),
      projectId: rawProject.isEmpty ? null : localIdFor(rawProject),
      type: _enumByName(NoteType.values, json['type']) ?? NoteType.idea,
      title: (json['title']?.toString().isEmpty ?? true)
          ? null
          : json['title'].toString(),
      body: json['body']?.toString() ?? '',
      answer: (json['answer']?.toString().isEmpty ?? true)
          ? null
          : json['answer'].toString(),
      status: _enumByName(NoteStatus.values, json['status']) ?? NoteStatus.open,
      priority: _enumByName(NotePriority.values, json['priority']),
      tags: rawTags is List
          ? rawTags.map((e) => e.toString()).toList(growable: false)
          : const [],
      sortOrder: (json['sort_order'] as num?)?.toDouble() ?? 0,
      createdAt: _parseTime(json['created_at']) ?? DateTime.now().toUtc(),
      updatedAt: _parseTime(json['updated_at']) ?? DateTime.now().toUtc(),
      archivedAt: _parseTime(json['archived_at']),
      deletedAt: _parseTime(json['deleted_at']),
      deviceId: json['device_id']?.toString() ?? '',
    );
  }

  final String id;
  final String? projectId;
  final NoteType type;
  final String? title;
  final String body;
  final String? answer;
  final NoteStatus status;
  final NotePriority? priority;
  final List<String> tags;
  final double sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final DateTime? deletedAt;
  final String deviceId;

  Map<String, dynamic> toJson() => {
    'id': remoteIdFor(id),
    'project_id': projectId == null ? '' : remoteIdFor(projectId!),
    'type': type.name,
    'title': title ?? '',
    'body': body,
    'answer': answer ?? '',
    'status': status.name,
    'priority': priority?.name ?? '',
    'tags': tags,
    'sort_order': sortOrder,
    'created_at': _formatTime(createdAt),
    'updated_at': _formatTime(updatedAt),
    'archived_at': archivedAt == null ? '' : _formatTime(archivedAt!),
    'deleted_at': deletedAt == null ? '' : _formatTime(deletedAt!),
    'device_id': deviceId,
  };
}
