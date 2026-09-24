# Architektur

Dieses Dokument beschreibt, wie Fusen gebaut ist und warum. Das *Was* steht im
[Konzept](konzept.md); hier steht das *Wie* – inklusive der Stellen, an denen
der MVP bewusst vom Konzept abweicht.

## Überblick

```
┌─────────────────────────────────────────┐
│ features/  Oberfläche (Flutter Widgets) │
├─────────────────────────────────────────┤
│ app/       Provider (Riverpod)          │
├─────────────────────────────────────────┤
│ data/      Repositories + Regeln        │
│            drift/SQLite                 │
├─────────────────────────────────────────┤
│ sync/      SyncService + SyncBackend    │
└─────────────────────────────────────────┘
                    │
              PocketBase
```

Die Regeln der Zettel-Typen liegen in `data/repositories/`, nicht in Widgets.
Dadurch lassen sie sich ohne Oberfläche testen, und eine zweite Ansicht (etwa
ein Widget auf dem Homescreen) erbt sie automatisch.

**Local-first:** Jede Änderung geht zuerst in die lokale SQLite-Datenbank und
ist damit sofort sichtbar, auch offline. Der Sync läuft danach im Hintergrund
und ist abschaltbar.

## Datenmodell

`Project` und `Note` wie im Konzept, mit drei Ergänzungen:

| Feld | Warum |
|---|---|
| `Note.answer` | Das Konzept verlangt ein Antwortfeld für Fragen, nennt es im Datenmodell aber nicht. |
| `Note.sort_order` | Nächste Schritte sind per Drag-and-drop sortierbar; das braucht eine Position. Fließkommazahl, damit ein Verschieben genau einen Datensatz ändert statt der ganzen Liste. |
| `Note.search_text` | Abgeleitet und nur lokal – siehe [Suche](#suche). |
| `Note.closed_at` | Wann ein Zettel abgehakt, beantwortet oder verworfen wurde. Daraus entstehen „Zuletzt erledigt“ und das Datum am Zettel; `updated_at` taugt dafür nicht, weil jede spätere Bearbeitung es verschiebt. |
| `Attachment` | Bilder an Zetteln, siehe unten. |

Dazu kommt `pending_sync` als reines Gerätefeld: „diese Zeile war noch nicht
beim Server“.

**Bilder** stehen in zwei Tabellen: `attachments` beschreibt das Bild (Zettel,
Name, Typ, Maße), `attachment_blobs` hält die Bytes. drift liest beim
Beobachten einer Tabelle jede Spalte mit – lägen die Bytes in `attachments`,
würde jede Zettelliste Megabytes durch den Speicher schieben. Vor dem
Speichern wird jedes Bild in einem eigenen Isolate auf höchstens 2048 Pixel
Kantenlänge verkleinert; Bildschirmfotos bleiben PNG (Text bleibt scharf),
Fotos werden JPEG.

**Schema-Versionen:** Version 2 brachte `closed_at` und die Bilder. Die
Migration trägt `closed_at` für bereits geschlossene Zettel aus `updated_at`
nach – ungenau, aber besser als ein Zettel, der nie erledigt wurde.
`migration_test.dart` prüft sie gegen eine echte Datenbank im Schema von
Version 1.

Weitere Entscheidungen:

* **UUIDs statt Auto-Increment**, damit ein Gerät offline IDs vergeben kann.
* **Tombstones statt hartem Löschen** (`deleted_at`). Eine gelöschte Zeile,
  die einfach verschwindet, kommt beim nächsten Sync vom anderen Gerät zurück.
* **Kein Fremdschlüssel** von `notes.project_id` auf `projects.id`. Beim Sync
  kann ein Zettel vor seinem Projekt eintreffen; eine Fremdschlüsselprüfung
  würde die ganze Übertragung abbrechen. Zettel ohne auffindbares Projekt
  zeigt die App in der Inbox.
* **Zeitstempel als ISO-8601-Text** statt als Unix-Sekunden (drift-Standard).
  Zwei Geräte, die innerhalb derselben Sekunde schreiben, müssen
  unterscheidbar bleiben.

## Regeln der Zettel-Typen

Alles in `NoteRepository`, jeweils in einer Transaktion:

* **Eine aktive Anweisung pro Projekt.** Wird eine Anweisung angelegt, per
  Typwechsel erzeugt, in ein Projekt verschoben oder wieder geöffnet, gehen
  alle anderen offenen Anweisungen desselben Projekts auf `done` – sie stehen
  dann im Verlauf. Die Inbox zählt dabei als eigenes „Projekt“.
* **Log friert nach 24 Stunden ein.** `updateContent` und `changeType` werfen
  dann `NoteEditLockedException`. Archivieren und Löschen bleiben erlaubt:
  Aufräumen ist kein Umschreiben der Geschichte.
* **Beantwortete Fragen wandern ins Archiv.** `answerQuestion` setzt Antwort,
  Status und `archived_at` in einem Rutsch.
* **Aufgaben** – Anforderung, Schritt, Idee und Frage – tragen eine
  Priorität und lassen sich abhaken. Wer schließt, setzt `closed_at`; wer
  wieder öffnet, leert es.
* **Typwechsel räumt auf.** Felder, die der neue Typ nicht kennt (Priorität
  bei einer Referenz, Antwort bei einer Idee), werden geleert statt unsichtbar
  liegen zu bleiben.
* **Löschen nimmt die Bilder mit** – mit demselben Zeitstempel in
  `deleted_at`. `restore` holt genau die Bilder zurück, die mit dem Zettel
  gegangen sind, und keine, die vorher schon gelöscht waren. Darauf baut
  „Rückgängig“ in der Oberfläche.

## Schnelleingabe

`features/capture/capture_syntax.dart` ist ein reiner Parser ohne Flutter- oder
Datenbankabhängigkeit und entsprechend gut testbar.

Ein Kurzbefehl zählt nur am Wortanfang. Das ist der Unterschied zwischen
„funktioniert“ und „nervt“:

* `betreuer@uni.de` ist keine Projektzuordnung,
* `# Überschrift` ist kein Tag (ein Tag hat kein Leerzeichen nach dem `#`),
* `![bild](x.png)` ist kein Typ.

Ein **unbekannter** Kurzbefehl wie `!schrit` bleibt im Text stehen, statt
stillschweigend zu verschwinden – ein Tippfehler soll sichtbar sein.

Ein `@projekt`, das es noch nicht gibt, legt das Projekt an. Das Konzept sagt
„lieber unsauber gespeichert als gar nicht“; ein Bestätigungsdialog würde die
fünf Sekunden sprengen. Die Vorschau über dem Eingabefeld zeigt vorher an, dass
ein neues Projekt entsteht.

Das zuletzt benutzte Projekt wird **vorgeschlagen**, nicht gesetzt: es
erscheint als Chip, den Tab übernimmt. Ohne Zutun landet der Zettel in der
Inbox – so wie es das Konzept beschreibt.

**Listen** zerlegt `list_syntax.dart`, ebenfalls ohne Flutter: Aufzählungen
mit `-`, `*`, `•` oder Nummern, Kästchen (`[x]` heißt erledigt), eingerückte
Zeilen als Details zum Punkt darüber. Überschriften wie „Fragen:“ oder
„Nächste Schritte:“ bestimmen den Typ der Punkte darunter. Was daraus wird,
entscheidet `CapturePlan`; angelegt wird im `CaptureService` – alle Zettel in
einer Transaktion, und jedes `@projekt` wird genau einmal aufgelöst, damit
eine Liste mit einem neuen Projekt nicht fünf gleichnamige anlegt.

## Suche

Umgesetzt als `LIKE` über eine abgeleitete Spalte `search_text`, die Titel,
Text, Antwort und Tags in Kleinbuchstaben enthält.

Warum nicht SQLites `lower()`? Weil es nur ASCII faltet: „Ärger“ und „ärger“
wären verschiedene Wörter, und genau daran scheitert eine deutschsprachige
Notiz-App. Die Faltung passiert deshalb in Dart beim Schreiben.

Warum nicht FTS5? Für einen persönlichen Zettelkasten ist Teilwort-Suche
(`nnue` findet `NNUE-Export`) nützlicher als Token-Suche, und der Bestand ist
klein genug, dass ein Tabellenscan nicht auffällt. FTS5 bleibt eine Option,
wenn die Datenmengen wachsen – der Umbau beträfe nur `NoteRepository.search`.

## Sync

**Interface statt Implementierung.** Die App kennt nur `SyncBackend`
(`connect` / `pull` / `push`). PocketBase ist die erste Implementierung;
Option A aus dem Konzept – ein eigener kleiner Server – lässt sich später
dahinterhängen, ohne die App anzufassen.

**Ablauf:** erst schieben, dann holen. Eigene Änderungen kommen im selben
Durchlauf wieder herunter; das ist etwas Bandbreite umsonst, aber das
Zusammenführen ist idempotent, und wir sparen einen zweiten Cursor für
„von mir selbst geschrieben“.

**Cursor:** der serverseitige `updated`-Zeitstempel des jüngsten gelesenen
Datensatzes – bewusst die Uhr des Servers. Bei der Uhr des Geräts würde ein
falsch gestelltes Handy Änderungen überspringen.

Zwei Feinheiten, die sonst still Daten verlieren:

* **Nur das Holen stellt den Cursor vor, nie das Schieben.** Setzte das
  Hochladen ihn auf „jetzt“, überspränge das anschließende Holen im selben
  Durchlauf alles, was ein anderes Gerät vorher geschrieben hat – und zwar für
  immer, weil der Cursor nie wieder zurückgeht.
* **Ein paar Sekunden Überlappung** (`syncCursorOverlap`). Ein Zeitstempel als
  Cursor hat zwei Lücken: ein Datensatz, der auf dieselbe Millisekunde fällt
  wie der Cursor, aber erst nach unserer Abfrage festgeschrieben wurde; und
  einer, der zwischen den beiden Abfragen eines Durchlaufs entsteht – Projekte
  und Zettel werden nacheinander geholt. Die Überlappung holt im Zweifel ein
  paar Datensätze doppelt; das Zusammenführen ist idempotent, ein
  übersprungener Datensatz wäre für immer weg.

**IDs:** PocketBase erlaubt eigene Datensatz-IDs aus `[a-z0-9]` mit mindestens
15 Zeichen. Ein UUID ohne Bindestriche passt genau, also ist die Zuordnung
lokale ID ↔ Server-ID eine reine Rechnung ohne Mapping-Tabelle.

**Konflikte: Last-Write-Wins auf Datensatzebene** anhand von `updated_at`.
Das Konzept nennt Feldebene; dafür bräuchte jedes Feld einen eigenen
Zeitstempel, was den Datensatz etwa verdoppelt. Für den MVP wäre das Aufwand
ohne sichtbaren Gewinn: Fusen ist eine Ein-Personen-App, gleichzeitige
Änderungen am selben Zettel auf zwei Geräten sind der Ausnahmefall. Das
Konzept sieht für P2 ohnehin eine Merge-Ansicht vor, die das Thema richtig
löst.

**Fehler kosten nichts.** Bleibt der Server stumm, wird nichts lokal
geändert, `pending_sync` bleibt stehen, und der nächste Versuch schiebt
dieselben Zeilen erneut. Nach dem Hochladen wird `pending_sync` nur
zurückgesetzt, wenn der Zettel zwischenzeitlich nicht erneut bearbeitet wurde.

**Bilder** reisen als eigener Datensatz in der Collection `attachments`.
Beim ersten Hochladen geht die Datei mit (multipart), danach nur noch die
Beschreibung – ein Bild ändert sich nie, nur ob es gelöscht ist. Die Dateien
sind auf dem Server geschützt und nur mit einem kurzlebigen Datei-Token
abrufbar. Kennt ein älterer Server die Collection noch nicht, gleichen
Zettel weiter ab, und die App meldet nur, dass Bilder auf dem Gerät bleiben.

**Zugang** über Server-URL und Zugangscode statt Benutzerkonten. Technisch ist
der Code das Passwort eines einzelnen Auth-Datensatzes; PocketBase gibt dafür
ein Token aus, und die Collection-Regeln verlangen genau dieses Token.

## Ablage der Zugangsdaten

Server-URL, Zugangscode und Sync-Cursor liegen in der lokalen Tabelle
`settings`, also in derselben Datei wie die Zettel. Ein extra verschlüsselter
Speicher würde hier wenig bringen: wer die Datenbank lesen kann, liest die
Notizen ohnehin. Wenn die Datenbank später verschlüsselt wird (SQLCipher ist
über `drift_flutter` erreichbar), sind die Zugangsdaten automatisch mit
geschützt.

## Oberfläche

* **Riverpod** ohne Code-Generierung. Die drift-Streams werden zu
  `StreamProvider`; eine Änderung in der Datenbank aktualisiert die Ansicht,
  ohne dass jemand etwas neu laden muss.
* **Ein Layout, zwei Breiten.** Ab 900 px stehen Liste und Inhalt
  nebeneinander, darunter nacheinander. Dieselben Widgets, kein zweiter
  Code-Pfad – „Desktop und Mobil gleichwertig“ heißt sonst schnell „Mobil
  hinkt hinterher“.
* **Das Log wird getrennt geladen** (`watchLog`), weil es als einziger Bereich
  unbegrenzt wächst und in der Ansicht ohnehin eingeklappt ist.
* **Der globale Hotkey** verkleinert das Fenster nur dann, wenn Fusen gar
  nicht sichtbar war; danach wird die alte Fenstergröße wiederhergestellt.
  Steht das Fenster schon offen, erscheint einfach die Eingabe. Ein Zettel
  soll den Arbeitsplatz nicht umräumen.
* **Rückgängig statt Rückfrage.** Löschen, Abhaken, Archivieren und
  Verschieben passieren sofort; die Meldung danach bietet „Rückgängig“ an.
  Ein Bestätigungsdialog kostet bei jedem Mal einen Klick, ein versehentliches
  Löschen dagegen selten.
* **Die Übersicht** ist die Startseite: Projekte als Haftzettel mit
  Fortschritt, nächstem Schritt und geltender Anweisung, darunter
  Priorisiertes aus allen Projekten und das zuletzt Erledigte. Die Abfragen
  dafür liefern je Projekt einen Wert: `watchProgress` zählt in SQL,
  `watchNextSteps` liest nur offene Schritte – die Übersicht lädt nicht
  jeden Zettel.
* **Die Schriften** – Plus Jakarta Sans und JetBrains Mono – liegen in der
  App. Systemschriften sähen auf jeder Plattform anders aus, und ein
  Nachladen aus dem Netz verträgt sich nicht mit „läuft auch offline“.

## Plattformkram, der leicht durchrutscht

Drei Einstellungen fallen erst im ausgelieferten Build auf, weil die
Debug-Builds sie geschenkt bekommen:

* **Android** braucht `android.permission.INTERNET` im *Haupt*-Manifest.
  `flutter create` legt sie nur im Debug-Manifest an; ohne sie könnte die
  fertige App nicht einmal fragen, ob sie ins Netz darf.
* **macOS** läuft im Sandkasten und braucht
  `com.apple.security.network.client` in `Release.entitlements`, sonst
  erreicht die ausgelieferte App keinen Sync-Server.
* **iOS** beantwortet `canLaunchUrl` mit „nein“, solange das Schema nicht in
  `LSApplicationQueriesSchemes` steht – Links auf Referenz-Zetteln blieben
  sonst tot.

Mit den Bildern kamen drei weitere dazu:

* **iOS** beendet die App, sobald sie Kamera oder Mediathek anfragt, ohne
  dass `NSCameraUsageDescription` und `NSPhotoLibraryUsageDescription` in der
  `Info.plist` stehen.
* **macOS** lässt den Öffnen-Dialog im Sandkasten nur mit
  `com.apple.security.files.user-selected.read-only` zu – in beiden
  Entitlements-Dateien.
* **Windows** bildet den Datenordner aus `CompanyName` und `ProductName` in
  `Runner.rc` (`%APPDATA%\dev.fusen\fusen`). Wer die Namen „verschönert“,
  lässt die Zettel bestehender Installationen zurück; lesbar ist deshalb nur
  `FileDescription`.

Dazu: die Datenbank liegt im **Support**- und nicht im Dokumente-Verzeichnis.
Das ist nicht nur semantisch richtiger, sondern auch robuster – der
Dokumente-Ordner hängt unter Linux an `xdg-user-dirs`, und fehlt das Paket,
startet die App gar nicht.

## Auslieferung

`.github/workflows/package.yml` baut im Release-Modus und packt pro
Plattform, was man tatsächlich installiert:

| Plattform | Paket | Anmerkung |
|---|---|---|
| Android | universelle APK | signiert mit dem Schlüssel aus den Secrets, sonst mit einem Debug-Schlüssel (mit Warnung im Release) |
| iOS | unsignierte IPA | zum Sideloaden über die eigene Apple-ID |
| Windows | Inno-Setup-Installer und ZIP | installiert ohne Administratorrechte; die Visual-C++-Laufzeit liegt bei, sonst fehlt auf frischen Systemen eine DLL |
| macOS | DMG | universell (Apple Silicon und Intel), ad hoc signiert, nicht beglaubigt |
| Linux | .deb und tar.gz | gebaut auf Ubuntu 22.04, damit keine neuere glibc verlangt wird; das .deb nennt die glibc-Version, die der Build tatsächlich braucht |

`build.yml` ruft das für `main` und für Branches mit nativen Änderungen auf,
`release.yml` für einen Tag `v<version>` oder auf Knopfdruck und hängt das
Ergebnis an ein GitHub-Release. Die Version steht an genau einer Stelle, in
`app/pubspec.yaml`; die Pipeline gibt sie per `--dart-define=FUSEN_VERSION`
an die App weiter, die sie in den Einstellungen zeigt.

## Tests

| Datei | Deckt ab |
|---|---|
| `capture_syntax_test.dart` | Kurzbefehle, inklusive der Fälle, in denen `@`, `!` und `#` *keine* Kurzbefehle sind |
| `list_import_test.dart` | Listen und Überschriften, wie sie aus Notizen und Chats eingefügt werden |
| `note_rules_test.dart` | Zettel-Regeln, Suche, Tombstones – gegen eine echte SQLite-Datenbank im Speicher |
| `attachments_test.dart` | Bilder: Verkleinern, Speichern, Löschen und Zurückholen mit dem Zettel |
| `migration_test.dart` | Der Weg von Schema 1 auf 2, gegen eine Datenbank im alten Schema |
| `sync_service_test.dart` | Hochladen, Herunterladen, Konflikte, Cursor-Fallen, Fehlerfälle – gegen eine Server-Attrappe |
| `app_test.dart` | Die echte App: Übersicht, Schnelleingabe mit Listen, Abhaken, Rückgängig, Einsortieren, Listen-Import |
| `pocketbase_sync_test.dart` | Abgleich gegen ein echtes PocketBase. Wird übersprungen, solange keins läuft; die CI startet dafür den Container. |

Die Attrappe prüft, ob der Sync *denkt* wie gedacht; der Lauf gegen ein
echtes PocketBase prüft, ob App und Server dieselbe Sprache sprechen –
Feldnamen, Zeitformate, erlaubte ID-Länge, Filtersyntax. Das eine ersetzt
das andere nicht.

Eine Eigenheit von Widget-Tests: `flutter_test` friert die Zeit ein, und
drift meldet Stream-Ergebnisse über einen Timer. Ein `await stream.first`
im Testkörper wartet deshalb ewig. In `app_test.dart` wird stattdessen direkt
per Future abgefragt.

## Was noch fehlt

Aus der P1-Liste des Konzepts: Markdown-Export pro Projekt, Widget für die
Schnelleingabe auf dem Homescreen, „Fokus heute“, Word-Import und die
Verlaufsansicht als eigene Seite. P2 – Verknüpfungen zwischen Zetteln,
Projekt-Vorlagen, Wochenansicht, Merge-Ansicht im Sync, Plugin-Schnittstelle –
ist unberührt.
