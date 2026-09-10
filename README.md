# Fusen

*Fusen (付箋) ist das japanische Wort für Haftnotiz – genau das, was die App sein
soll: ein Stapel Zettel, den man schnell beschreibt und an ein Projekt klebt.*

Fusen hält Notizen zu mehreren Projekten getrennt, statt sie in einem
Word-Dokument untereinander wachsen zu lassen. Ein Gedanke soll in unter fünf
Sekunden abgelegt sein, dem richtigen Projekt gehören und später auf jedem
Gerät wieder auftauchen.

Das ausführliche Konzept steht in [docs/konzept.md](docs/konzept.md), die
technischen Entscheidungen in [docs/architektur.md](docs/architektur.md).

## Was drin ist

* **Schnelleingabe** – ein Textfeld, sonst nichts. `@projekt` ordnet zu,
  `!typ` setzt den Zettel-Typ, `#tag` hängt ein Schlagwort an.
  Beispiel: `@chess !schritt NNUE-Export auf int8 testen`.
  Enter speichert, Shift+Enter macht eine neue Zeile.
  Auf dem Desktop öffnet **Strg+Umschalt+Leertaste** von überall ein kleines
  Fenster – auch wenn Fusen gar nicht sichtbar ist.
* **Sieben Zettel-Typen** mit eigenen Regeln: Anforderung, Nächster Schritt,
  Aktuelle Anweisung, Idee, Frage, Log, Referenz. Jeder Zettel kann seinen Typ
  jederzeit wechseln.
* **Projekt-Ansicht** mit sieben festen Bereichen, damit immer klar ist, wo
  etwas steht – plus eine Inbox für alles ohne Zuordnung.
* **Markdown** im Zetteltext: Code, Listen, Links.
* **Volltextsuche** über alle Projekte, mit denselben Kurzbefehlen wie die
  Schnelleingabe.
* **Sync** zwischen allen Geräten über eine selbst gehostete
  PocketBase-Instanz. Zugang über einen Zugangscode, keine Benutzerkonten.
  Ohne Server läuft Fusen rein lokal weiter.
* **Desktop und Mobil gleichwertig** aus einer Flutter-Codebasis: Android,
  iOS, Linux, macOS, Windows.

## Zettel-Typen

| Typ | Kurzbefehl | Besonderheit |
|---|---|---|
| Anforderung | `!anf` | Status offen / umgesetzt / verworfen, Priorität Muss / Soll / Kann |
| Nächster Schritt | `!schritt` | abhakbar, per Drag-and-drop sortierbar |
| Aktuelle Anweisung | `!anw` | nur **eine** aktive pro Projekt, ältere wandern in den Verlauf |
| Idee | `!idee` | Standard, wenn nichts angegeben ist |
| Frage | `!frage` | Feld für die Antwort; beantwortet heißt archiviert |
| Log | `!log` | Zeitstempel, chronologisch, nach 24 Stunden festgeschrieben |
| Referenz | `!ref` | Links, Befehle, Snippets – mit Kopier-Knopf |

Die englischen Kurzbefehle (`!todo`, `!req`, `!now`, `!link`, …) funktionieren
genauso.

## App bauen und starten

Voraussetzung: [Flutter](https://docs.flutter.dev/get-started/install) 3.47
oder neuer.

```bash
cd app
flutter pub get
dart run build_runner build      # erzeugt den drift-Code
flutter run                      # -d linux | windows | macos | android | ios
```

Auf Linux vorher noch:

```bash
sudo apt-get install ninja-build libgtk-3-dev libkeybinder-3.0-dev
```

Prüfen, was die CI auch prüft:

```bash
cd app
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Fertige Builds hängen an jedem Workflow-Lauf auf `main` – siehe
[Actions](../../actions). Man muss also nicht lokal bauen, um etwas
auszuprobieren.

## Sync einrichten

Ohne Server ist nichts zu tun: Fusen speichert lokal und ist sofort benutzbar.
Für den Abgleich zwischen Geräten läuft ein kleiner Server, den man selbst
hostet.

```bash
cd server
cp .env.example .env        # FUSEN_ACCESS_CODE eintragen (mindestens 8 Zeichen)
docker compose up -d
```

Danach in der App unter **Einstellungen → Sync** die Server-URL und den
Zugangscode eintragen und auf *Verbinden und abgleichen* tippen. Jedes weitere
Gerät bekommt denselben Code und sieht dieselben Zettel.

Details, auch zum Betrieb ohne Docker, stehen in
[server/README.md](server/README.md).

## Projektstruktur

```
app/       Flutter-App (Android, iOS, Linux, macOS, Windows)
server/    PocketBase-Konfiguration, Migrationen, Dockerfile
docs/      Konzept und Architektur
.github/   CI-Workflows
```

## Mitmachen

Fehler und Ideen gerne als Issue. Wie man am besten einsteigt, steht in
[CONTRIBUTING.md](CONTRIBUTING.md).

## Lizenz

[MIT](LICENSE).
