/// Was rechts (oder auf dem Handy als eigene Seite) angezeigt wird.
sealed class Destination {
  const Destination();
}

/// Ein Projekt – oder die Inbox, wenn [projectId] `null` ist.
class ProjectDestination extends Destination {
  const ProjectDestination(this.projectId);

  final String? projectId;

  @override
  bool operator ==(Object other) =>
      other is ProjectDestination && other.projectId == projectId;

  @override
  int get hashCode => projectId.hashCode;
}

class SearchDestination extends Destination {
  const SearchDestination();

  @override
  bool operator ==(Object other) => other is SearchDestination;

  @override
  int get hashCode => 'search'.hashCode;
}

class SettingsDestination extends Destination {
  const SettingsDestination();

  @override
  bool operator ==(Object other) => other is SettingsDestination;

  @override
  int get hashCode => 'settings'.hashCode;
}
