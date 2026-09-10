import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// UUIDs statt Auto-Increment: Geräte müssen offline IDs vergeben können,
/// ohne dass es beim Sync zu Kollisionen kommt.
String newId() => _uuid.v4();
