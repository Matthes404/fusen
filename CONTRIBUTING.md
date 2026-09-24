# Mitmachen

Danke für dein Interesse an Fusen. Hier steht, wie du am schnellsten
loslegst und was beim Einreichen hilft.

## Entwicklungsumgebung

Du brauchst [Flutter](https://docs.flutter.dev/get-started/install) 3.47 oder
neuer. Für den Server zusätzlich Docker (oder eine PocketBase-Binary).

Auf Linux kommen zwei Systempakete dazu – `libkeybinder-3.0-dev` braucht
`hotkey_manager` für den globalen Hotkey, und ohne das Paket bricht schon
CMake ab:

```bash
sudo apt-get install ninja-build libgtk-3-dev libkeybinder-3.0-dev
```

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
| `app/assets/fonts/` | Plus Jakarta Sans und JetBrains Mono (beide OFL), fest eingebunden |
| `app/tool/` | Erzeugt die App-Symbole aller Plattformen |
| `app/linux/packaging/`, `app/windows/packaging/` | Starter, Symbole, .deb-Skript und Windows-Installer |
| `server/` | PocketBase-Migrationen und Docker-Setup |
| `.github/workflows/` | CI, Builds zum Ausprobieren, Releases |

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

## Schrift und App-Symbol

Die Schriften liegen unter `app/assets/fonts/` und werden mit der App
ausgeliefert – ohne Nachladen aus dem Netz, auf jeder Plattform gleich.
Ihre Lizenzen erscheinen unter **Einstellungen → Lizenzen**.

Das App-Symbol ist kein Bild, sondern `FusenIconPainter` in
`lib/src/ui/widgets/fusen_logo.dart`. Wer es ändert, erzeugt danach alle
Plattform-Symbole neu und checkt sie ein:

```bash
cd app
flutter test tool/app_icons.dart
```

## Releases

Ein Release hängt installierbare Pakete für alle Plattformen an eine
GitHub-Release-Seite und schiebt das Server-Image nach GHCR. So entsteht
eins:

1. `version:` in `app/pubspec.yaml` hochzählen – den Namen und die Zahl
   hinter dem `+`. Die Zahl muss mit jedem Release steigen, sonst verweigert
   Android das Update.
2. Auf `main` bringen.
3. Unter **Actions → Release → Run workflow** starten. Der Lauf liest die
   Version aus der pubspec und legt den Tag `v<version>` selbst an.
   Alternativ einen passenden Tag pushen: `git tag v0.2.0 && git push origin
   v0.2.0`. Passen Tag und pubspec nicht zusammen, bricht der Lauf ab.

Was dabei entsteht und wie man es installiert, steht in der
[README](README.md#installieren); gebaut wird in
`.github/workflows/package.yml`, das auch die Pakete zum Ausprobieren
(`build.yml`) erzeugt.

### Android-Signierschlüssel (einmalig)

Android installiert ein Update nur, wenn es mit demselben Schlüssel signiert
ist wie die installierte Version. Ohne hinterlegten Schlüssel signiert die
Pipeline mit einem Debug-Schlüssel, der bei jedem Lauf neu entsteht – dann
lässt sich keine APK über die vorige installieren, und das Release weist
darauf hin. Einrichten:

```bash
keytool -genkeypair -v -keystore fusen-upload.jks -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 -alias fusen
base64 -w0 fusen-upload.jks > fusen-upload.jks.b64   # macOS: base64 -i …
```

Dann unter **Settings → Secrets and variables → Actions** vier Secrets
anlegen:

| Secret | Inhalt |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Inhalt von `fusen-upload.jks.b64` |
| `ANDROID_KEYSTORE_PASSWORD` | das Passwort aus `keytool` |
| `ANDROID_KEY_ALIAS` | `fusen` |
| `ANDROID_KEY_PASSWORD` | dasselbe Passwort (PKCS12 kennt nur eines) |

Die `.jks`-Datei und das Passwort gut aufheben und nie einchecken: geht der
Schlüssel verloren, lässt sich keine spätere Version mehr über eine
installierte spielen. Wer lokal signiert bauen will, legt
`app/android/key.properties` an (steht in `.gitignore`):

```properties
storeFile=/pfad/zu/fusen-upload.jks
storePassword=…
keyAlias=fusen
keyPassword=…
```

iOS, macOS und Windows bleiben unsigniert; dafür bräuchte es ein
Apple-Entwicklerkonto bzw. ein Code-Signing-Zertifikat. Die Folgen – die
Rückfragen beim ersten Start – beschreibt die README.

## Commits

Eine Zeile Betreff im Imperativ, danach ein Absatz, der erklärt, warum die
Änderung nötig war. Kein Präfix-Schema.

## Fehler melden

Am hilfreichsten sind: was du getan hast, was passiert ist, was du erwartet
hast, dazu Plattform und Version. Wenn es um den Sync geht, hilft die
Gerätekennung aus **Einstellungen → Gerät** – sie steht in jedem Zettel unter
`device_id`.
