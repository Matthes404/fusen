# Mitmachen

Danke für dein Interesse an Fusen. Hier steht, wie du am schnellsten
loslegst und was beim Einreichen hilft.

## Entwicklungsumgebung

Du brauchst [Flutter](https://docs.flutter.dev/get-started/install) 3.47 oder
neuer. Für den Server zusätzlich Docker (oder eine PocketBase-Binary).

```bash
git clone https://github.com/matthes404/fusen.git
cd fusen/app
flutter pub get
dart run build_runner build
flutter run
```

`build_runner` erzeugt `lib/src/data/db/database.g.dart` aus den
Tabellendefinitionen. Die Datei liegt im Repository, damit ein frischer Klon
sofort baut – nach jeder Änderung an `tables.dart` muss sie neu erzeugt und
mit eingecheckt werden.

## Vor dem Pull Request

Genau das prüft auch die CI:

```bash
cd app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## Wo was liegt

| Ordner | Inhalt |
|---|---|
| `app/lib/src/core/` | Kleinigkeiten ohne Abhängigkeiten (Zeit, IDs, Sortierung) |
| `app/lib/src/data/` | Datenbank, Modelle, Repositories – hier stehen die Regeln |
| `app/lib/src/sync/` | Sync-Interface, PocketBase-Anbindung, Zusammenführen |
| `app/lib/src/features/` | Oberfläche, nach Funktion sortiert |
| `app/lib/src/ui/` | Farben, Beschriftungen, gemeinsame Widgets |
| `server/` | PocketBase-Migrationen und Docker-Setup |

Eine Regel, die für alle Beiträge gilt: **Logik gehört in `data/`, nicht in
ein Widget.** Was im Repository steht, lässt sich ohne Oberfläche testen und
gilt automatisch auch für jede weitere Ansicht.

Der Aufbau und die Begründungen dahinter stehen in
[docs/architektur.md](docs/architektur.md).

## Stil

* Code und Bezeichner auf Englisch, Kommentare und Oberflächentexte auf
  Deutsch – so wie der Bestand.
* Kommentare erklären das *Warum*. Was der Code tut, steht im Code.
* Neue Regeln für Zettel brauchen einen Test in `note_rules_test.dart`.
* Änderungen am Sync-Format brauchen einen Test in `sync_service_test.dart`.

## Commits

Eine Zeile Betreff im Imperativ, danach ein Absatz, der erklärt, warum die
Änderung nötig war. Kein Präfix-Schema.

## Fehler melden

Am hilfreichsten sind: was du getan hast, was passiert ist, was du erwartet
hast, dazu Plattform und Version. Wenn es um den Sync geht, hilft die
Gerätekennung aus **Einstellungen → Gerät** – sie steht in jedem Zettel unter
`device_id`.
