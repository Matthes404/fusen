# Fusen – Konzept

*Fusen (付箋) ist das japanische Wort für Haftnotiz – genau das, was die App sein soll: ein Stapel Zettel, den man schnell beschreibt und an ein Projekt klebt.*

## 1. Problem

Notizen zu mehreren Projekten landen bisher in einem Word-Dokument. Das wird schnell unübersichtlich, weil:

- alles linear untereinander steht, ohne Trennung nach Projekt oder Art der Notiz
- „nächste Schritte“, Anforderungen und spontane Gedanken vermischt werden
- erledigte Punkte nicht verschwinden, sondern das Dokument aufblähen
- das Festhalten eines Gedankens mehrere Schritte braucht (Datei öffnen, Stelle suchen, tippen)

Ziel: Einen Gedanken in **unter 5 Sekunden** ablegen, dem richtigen Projekt zuordnen und später auf jedem Gerät wiederfinden.

## 2. Rahmenbedingungen

| Punkt | Entscheidung |
|---|---|
| Lizenz | **Open Source** (Vorschlag: MIT oder Apache 2.0) |
| Plattformen | **Desktop und Mobil gleichwertig**, Notizen auf beiden Geräten synchron |
| Termine / Kalender | bewusst **nicht** Teil der App |
| Log | jeder Eintrag mit **Zeitstempel** |
| Build | **CI-Pipeline**, die aus jedem Commit ein lauffähiges Build erzeugt |
| Anforderungen | flach, **Priorität reicht** – keine Hierarchie |
| Zugang | **Zugangscode** pro Sync-Instanz, keine Benutzerkonten |

## 3. Grundidee

Die App ist ein digitaler Stapel Notizzettel, sortiert nach Projekt. Jeder Zettel hat einen **Typ**, der ihm eine Rolle gibt. Es gibt genau eine Eingabezeile, in die man einfach reintippt – Zuordnung und Typ ergeben sich aus Kontext oder Kurzbefehl.

### Zwei Modi

| Modus | Zweck |
|---|---|
| **Capture** | Blitzschnell etwas ablegen. Ein Textfeld, sonst nichts. |
| **Review** | Pro Projekt aufräumen, sortieren, priorisieren, abhaken. |

Beim Aufschreiben soll nichts stören, beim Ordnen soll alles greifbar sein.

## 4. Struktur

```
Workspace
└── Projekt (z. B. „Chess Engine“, „Praktikum“, „Studium“)
    ├── Zettel (Typ: Anforderung)
    ├── Zettel (Typ: Nächster Schritt)
    ├── Zettel (Typ: Aktuelle Anweisung)
    ├── Zettel (Typ: Idee)
    ├── ...
    └── Archiv (erledigte / verworfene Zettel)
```

### Zettel-Typen

| Typ | Bedeutung | Besonderheit |
|---|---|---|
| **Anforderung** | Was das Ergebnis können muss | Status: offen / umgesetzt / verworfen |
| **Nächster Schritt** | Konkrete To-dos | Abhakbar, per Drag-and-drop sortierbar |
| **Aktuelle Anweisung** | Was gerade gilt (z. B. Vorgabe vom Betreuer, Fokus der Woche) | Nur *ein* aktiver Zettel pro Projekt, ältere wandern automatisch in den Verlauf |
| **Idee** | Vage Einfälle, noch ohne Verpflichtung | Kann in Anforderung oder Schritt umgewandelt werden |
| **Frage** | Offene Punkte, die geklärt werden müssen | Feld für Antwort; nach Beantwortung archiviert |
| **Log** | Was gemacht wurde, Entscheidungen | Jeder Eintrag mit Zeitstempel (Datum + Uhrzeit), chronologisch, nach 24 h nicht mehr editierbar |
| **Referenz** | Links, Befehle, Snippets, Pfade | Copy-Button, Code-Formatierung |

Ein Zettel kann seinen Typ jederzeit wechseln (Idee → Anforderung → Nächster Schritt).

Anforderung, Nächster Schritt, Idee und Frage sind **Aufgaben**: sie tragen
eine Priorität (hoch / mittel / niedrig, früher Muss / Soll / Kann) und
werden abgehakt – mit einem Tipp auf der Karte, ohne den Zettel zu öffnen.
Wann etwas erledigt wurde, bleibt am Zettel stehen. Erledigtes verschwindet
nicht, sondern klappt weg: sichtbar, wenn man es sucht, aus dem Weg, wenn
nicht.

An jeden Zettel lassen sich **Bilder** hängen – ein Foto vom Whiteboard,
ein Bildschirmfoto der Fehlermeldung.

### Projekt-Ansicht (Review-Modus)

Pro Projekt eine Seite mit festen Bereichen:

1. **Aktuelle Anweisung** – groß, immer sichtbar
2. **Nächste Schritte** – Checkliste
3. **Offene Fragen**
4. **Anforderungen** – gruppiert nach Priorität
5. **Ideen**
6. **Referenzen**
7. **Log** – eingeklappt, neueste Einträge zuerst

Dazu eine **Inbox** für Zettel ohne Projektzuordnung.

### Übersicht

Die Startseite: jedes Projekt als Haftzettel mit Fortschritt, dem nächsten
Schritt und der geltenden Anweisung, daneben die Inbox. Darunter, was über
alle Projekte hinweg priorisiert ist, und das zuletzt Erledigte. Wer die App
öffnet, sieht ohne einen Klick, wo er steht.

## 5. Schnelleingabe (Capture)

- **Desktop:** globaler Hotkey öffnet ein kleines Fenster mit nur einem Textfeld
- **Mobil:** Homescreen-Widget bzw. Schnellaktion auf dem App-Icon, öffnet direkt die Eingabe
- **Kurzsyntax:**
  - `@projekt` – Projekt zuordnen (`@chess`, `@praktikum`)
  - `!typ` – Typ setzen (`!anf`, `!schritt`, `!idee`, `!frage`, `!log`, `!ref`)
  - `!hoch` / `!mittel` / `!niedrig` – Priorität
  - `#tag` – freies Schlagwort
  - Beispiel: `@chess !schritt !hoch NNUE-Export auf int8 testen`
- Ohne Angabe: Zettel landet in der Inbox als „Idee“ – lieber unsauber gespeichert als gar nicht
- Zuletzt bearbeitetes Projekt wird vorgeschlagen
- Enter speichert und schließt; Shift+Enter für Mehrzeiler
- **Listen werden zu Zetteln:** Eine eingefügte Aufzählung legt pro Punkt einen Zettel an, abgehakte Kästchen (`[x]`) gleich als erledigt. Im Projekt nimmt „Aus einer Liste anlegen“ ganze Notizen auf und verteilt sie anhand ihrer Überschriften („Fragen:“, „Nächste Schritte:“) auf die Typen – man sieht vorher, was entsteht, und wählt ab, was nicht soll.
- Bilder kommen per Einfügen oder Hineinziehen mit

## 6. Feature-Priorisierung

**P0 – MVP (ohne das ist die App nicht nutzbar)**

| Feature | Anmerkung |
|---|---|
| Projekte anlegen, umbenennen, archivieren, Farbe | |
| Zettel erstellen, bearbeiten, Typ wechseln, verschieben, archivieren | |
| Alle sieben Zettel-Typen inkl. Regeln (eine aktive Anweisung, Log-Zeitstempel) | |
| Schnelleingabe mit `@` / `!` / `#` | Hotkey auf Desktop, Widget auf Mobil kann P1 sein |
| Projekt-Ansicht mit den sieben Bereichen + Inbox | |
| Sync zwischen Desktop und Mobil | siehe Abschnitt 7 |
| Volltextsuche | |
| Markdown im Zetteltext | Code, Listen, Links |
| CI-Pipeline mit Builds für alle Zielplattformen | siehe Abschnitt 9 |

**P1 – kurz nach dem MVP**

| Feature | Anmerkung |
|---|---|
| Markdown-Export pro Projekt | Ersatz für das bisherige Word-Dokument |
| Mobil-Widget / Schnellaktion für Capture | |
| „Fokus heute“: pro Projekt einen Schritt anpinnen, projektübergreifende Liste | |
| Import: Word-Text in die Inbox kippen und zügig zuordnen | Grundlage steht: „Aus einer Liste anlegen“ zerlegt eingefügten Text in Zettel |
| Verlaufsansicht für Anweisungen (wann galt was?) | |

**Seit dem MVP dazugekommen**

| Feature | Anmerkung |
|---|---|
| Übersicht als Startseite | Fortschritt, nächster Schritt, Wichtiges, zuletzt Erledigtes |
| Priorität und Abhaken für alle Aufgaben, mit Datum | nicht mehr nur für Anforderungen und Schritte |
| Aus Listen Zettel erzeugen | in der Schnelleingabe und als Import im Projekt |
| Bilder an Zetteln | Galerie, Kamera, Zwischenablage, Hineinziehen; im Sync enthalten |
| Rückgängig für Löschen, Abhaken, Verschieben | statt Bestätigungsdialogen |
| Installierbare Releases für alle Plattformen | APK, IPA, Windows-Installer, DMG, .deb |

**P2 – Ausbau**

| Feature | Anmerkung |
|---|---|
| Verknüpfungen zwischen Zetteln (`[[…]]`), z. B. Schritt ↔ Anforderung | |
| Projekt-Vorlagen mit Standard-Anforderungen / -Fragen | |
| Wochenansicht: alle Logs und erledigten Schritte projektübergreifend | |
| Konfliktauflösung im Sync mit Merge-Ansicht statt Last-Write-Wins | |
| Plugin-/Erweiterungsschnittstelle für Community-Beiträge | |

## 7. Sync

Anforderung: Beide Geräte zeigen denselben Stand, auch offline muss man weiterarbeiten können.

Prinzip: **lokal zuerst** (SQLite auf jedem Gerät), Sync läuft im Hintergrund.

| Option | Wie | Vorteil | Nachteil |
|---|---|---|---|
| **A: Eigener kleiner Sync-Server** | Minimaler REST/WebSocket-Dienst, Änderungen als Ereignisse (`note_changed`, `note_deleted`) mit Zeitstempel; Konflikt = letzter Schreiber gewinnt pro Feld | Volle Kontrolle, passt zu Open Source (jeder kann selbst hosten), Docker-Image mitliefern | Eigener Betrieb nötig |
| **B: Fertiges Open-Source-Backend** | z. B. PocketBase (Go, eine Binary, SQLite, Realtime) oder Supabase self-hosted | Sehr wenig eigener Backend-Code, Auth gratis | Abhängigkeit von Fremdprojekt |
| **C: Dateibasiert** | Eine JSON/Markdown-Datei pro Zettel in einem Ordner, Sync durch Syncthing/Nextcloud/iCloud des Nutzers | Kein Server, Daten bleiben lesbar, Git-fähig | Konflikte nur grob lösbar, auf Mobil je nach Plattform umständlich |

**Empfehlung:** Option B (PocketBase) für den MVP – geringster Aufwand, self-hostbar, Realtime-Updates. Die Sync-Schicht in der App wird so gekapselt, dass sie später gegen einen eigenen Server (Option A) ausgetauscht werden kann. Konflikte im MVP per Last-Write-Wins auf Feldebene mit `updated_at`; Zettel werden nie hart gelöscht, sondern per `deleted_at` markiert, damit Löschungen sauber synchronisieren.

**Zugang per Zugangscode:**

- Eine Sync-Instanz gehört genau einer Person. Beim ersten Start der Server-Instanz wird ein Zugangscode erzeugt (oder selbst gesetzt).
- In der App gibt man Server-URL + Zugangscode ein – wahlweise per QR-Code vom Desktop abscannen, damit das Handy in Sekunden angebunden ist.
- Alle Geräte mit demselben Code sehen exakt dieselben Projekte und Zettel. Kein Login, kein Passwort-Reset, keine Benutzerverwaltung.
- Technisch: der Code wird zu einem API-Token, PocketBase-Regeln erlauben Zugriff nur mit gültigem Token. Code ändern = alle Geräte neu verbinden.
- Ohne Server läuft die App rein lokal; Sync ist zuschaltbar, nicht Pflicht.

## 8. Datenmodell

```
Project
  id (UUID), name, color, sort_order
  created_at, updated_at, archived_at, deleted_at

Note
  id (UUID), project_id (nullable → Inbox), type: enum
  title (optional), body: markdown
  status: open | done | discarded
  priority: must | should | could | null
  tags: [string]
  created_at, updated_at, closed_at, archived_at, deleted_at
  device_id (welches Gerät zuletzt geschrieben hat)

Attachment
  id (UUID), note_id, file_name, mime_type, byte_size, width, height, sort_order
  created_at, updated_at, deleted_at, device_id
  (die Bilddaten selbst liegen getrennt davon)

NoteLink (P2)
  from_note_id, to_note_id, kind (relates | implements | blocks)
```

- Log-Einträge sind Notes mit `type = log`; `created_at` ist der angezeigte Zeitstempel.
- Anweisung: `type = instruction`, `status = open` bedeutet „aktuell“; beim Anlegen einer neuen wird die alte auf `done` gesetzt.
- UUIDs statt Auto-Increment, damit Geräte offline IDs vergeben können.

## 9. Technik

**Stack:** **Flutter** (eine Codebasis für Android, iOS, Windows, macOS, Linux), lokale Datenbank mit `drift` (SQLite), Sync gegen PocketBase.

Begründung: Desktop und Mobil gleichwertig ist mit Flutter aus einer Codebasis machbar; für den globalen Hotkey auf Desktop gibt es Plugins (`hotkey_manager`, `window_manager`, `tray_manager`).

**Repository-Struktur (Open Source):**

```
/app            Flutter-App
/server         PocketBase-Konfiguration, Migrationen, Dockerfile
/docs           dieses Konzept, Architektur, Beitrags-Leitfaden
/.github        CI-Workflows, Issue-Templates
LICENSE, README.md, CONTRIBUTING.md
```

**CI-Pipeline (GitHub Actions):**

| Trigger | Was passiert |
|---|---|
| Jeder Push / PR | `flutter analyze`, `flutter test`, Format-Check |
| Push auf `main`, oder ein Branch ändert Natives | Installierbare Pakete für alle Plattformen als Artefakte am Workflow-Lauf |
| Tag `v*` oder Knopfdruck | Dieselben Pakete als GitHub Release mit Installationsanleitung und Changelog; Docker-Image des Servers nach GHCR |

Die Pakete: Android-APK, iOS-IPA (unsigniert, zum Sideloaden – signiert erst bei App-Store-Veröffentlichung), Windows-Installer, macOS-DMG, Linux als .deb und Archiv. Damit gibt es nach jedem Merge ein installierbares Build zum Ausprobieren, ohne lokal bauen zu müssen.

## 10. MVP-Reihenfolge

1. Repo, Lizenz, CI-Grundgerüst (Analyze + Test + Android/Linux-Build)
2. Datenmodell + lokale Datenbank
3. Projekt-Ansicht mit den sieben Bereichen und Inbox
4. Zettel-Logik (Typwechsel, eine aktive Anweisung, Log-Zeitstempel)
5. Schnelleingabe mit Kurzsyntax, Desktop-Hotkey
6. Suche
7. Sync mit PocketBase, Docker-Image, Release-Workflow
8. Restliche Plattform-Builds in die Pipeline

## 11. Name

**Fusen** (付箋, „Haftnotiz“). Kurz, in jeder Sprache aussprechbar, passt zur Zettel-Metapher und lässt sich gut als Icon umsetzen (eine leicht abgeknickte Haftnotiz). Repo: `fusen`, Paket: `dev.fusen.app`. Vor dem ersten Release prüfen, ob der Name in den App-Stores und auf GitHub noch frei ist.

Falls er nicht gefällt, Alternativen aus derselben Ecke: **Pinn**, **Zettl**, **Stapel**.
