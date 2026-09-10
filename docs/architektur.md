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

Dazu kommt `pending_sync` als reines Gerätefeld: „diese Zeile war noch nicht
beim Server“.

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
* **Typwechsel räumt auf.** Felder, die der neue Typ nicht kennt (Priorität
  bei einem Schritt, Antwort bei einer Idee), werden geleert statt unsichtbar
  liegen zu bleiben.

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

## Tests

| Datei | Deckt ab |
|---|---|
| `capture_syntax_test.dart` | Kurzbefehle, inklusive der Fälle, in denen `@`, `!` und `#` *keine* Kurzbefehle sind |
| `note_rules_test.dart` | Zettel-Regeln, Suche, Tombstones – gegen eine echte SQLite-Datenbank im Speicher |
| `sync_service_test.dart` | Hochladen, Herunterladen, Konflikte, Fehlerfälle – gegen eine Server-Attrappe |
| `app_test.dart` | Die echte App, von der Schnelleingabe bis zum abgehakten Schritt |

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
