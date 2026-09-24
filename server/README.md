# Fusen-Sync-Server

Ein [PocketBase](https://pocketbase.io) mit den Collections und dem Zugang,
die Fusen erwartet. Der Server ist optional: ohne ihn läuft die App rein
lokal.

Eine Instanz gehört genau einer Person. Es gibt keine Benutzerkonten – nur
einen **Zugangscode**, den sich alle Geräte teilen.

## Mit Docker

```bash
cp .env.example .env      # FUSEN_ACCESS_CODE eintragen, mindestens 8 Zeichen
docker compose up -d
```

Lässt man `FUSEN_ACCESS_CODE` leer, erzeugt der erste Start einen Code und
schreibt ihn ins Log – dort steht er genau einmal:

```bash
docker compose logs fusen
```

Danach in der App unter **Einstellungen → Sync** eintragen:

* Server-URL: `https://fusen.deine-domain.de` (oder `http://127.0.0.1:8090`
  zum Ausprobieren)
* Zugangscode: der Code von oben

Jedes weitere Gerät bekommt denselben Code.

## Ohne Docker

```bash
# Binary von https://github.com/pocketbase/pocketbase/releases holen
FUSEN_ACCESS_CODE=deincode ./pocketbase serve \
  --http=127.0.0.1:8090 \
  --migrationsDir=./pb_migrations \
  --hooksDir=./pb_hooks
```

## Ins Netz stellen

Der Container hört bewusst nur auf `127.0.0.1`. Davor gehört ein
Reverse-Proxy mit HTTPS (Caddy, nginx, Traefik) – der Zugangscode geht bei
jeder Anmeldung über die Leitung und hat im Klartext nichts im Netz verloren.

Beispiel für Caddy:

```
fusen.deine-domain.de {
    reverse_proxy 127.0.0.1:8090
}
```

## Zugangscode ändern

`FUSEN_ACCESS_CODE` in der `.env` ändern und neu starten:

```bash
docker compose up -d
```

PocketBase verwirft dabei alle ausgegebenen Token: **alle Geräte müssen sich
neu verbinden**. Genau dafür ist der Vorgang da – ein Gerät, das man nicht
mehr hat, verliert damit den Zugriff.

## Was drin ist

| Collection | Inhalt | Regeln |
|---|---|---|
| `access` | Ein Datensatz: der Zugang. Der Code ist sein Passwort. | Lesen und Schreiben nur für Administratoren, Anmelden für jeden mit dem richtigen Code |
| `projects` | Projekte | Lesen und Schreiben nur mit gültigem Token |
| `notes` | Zettel | Lesen und Schreiben nur mit gültigem Token |
| `attachments` | Bilder an Zetteln, die Datei im Feld `file` | Lesen und Schreiben nur mit gültigem Token; die Datei selbst nur mit einem kurzlebigen Datei-Token |

**Gelöscht wird nie hart.** Keine der Collections hat eine Delete-Regel; eine
Löschung reist als `deleted_at`. Ein Datensatz, der einfach verschwände, käme
beim nächsten Abgleich vom anderen Gerät zurück.

**Bilder** sind geschützte Dateien: wer nur die Adresse kennt, bekommt sie
nicht. Die App holt sich vor dem Herunterladen ein Datei-Token, das nur ein
angemeldetes Gerät bekommt. Angenommen werden JPEG, PNG, GIF, WebP, BMP und
HEIC bis 25 MB; die App verkleinert große Fotos vorher auf 2048 Pixel.

## Aktualisieren

Neue Versionen bringen ihre Migrationen mit; sie laufen beim Start von selbst.

```bash
docker compose pull && docker compose up -d
```

Die App kommt auch mit einem älteren Server zurecht: Zettel gleichen dann
weiter ab, nur Bilder bleiben auf dem Gerät, bis der Server aktualisiert ist –
die App sagt das unter **Einstellungen → Sync** dazu.

Die Datensatz-ID ist die UUID des Geräts ohne Bindestriche. Dadurch kennt
jedes Gerät die Server-ID eines Zettels, ohne nachfragen zu müssen.

`created_at` und `updated_at` sind die Zeitstempel des **Geräts** und
entscheiden Konflikte (der jüngere Schreibvorgang gewinnt). `created` und
`updated` sind die des **Servers**; `updated` ist der Cursor, mit dem die App
fragt „was hat sich seit meinem letzten Abgleich getan?“.

## Administrator-Oberfläche

PocketBase bringt ein Dashboard unter `/_/` mit. Beim ersten Aufruf legt man
dort ein Administratorkonto an – oder auf der Kommandozeile:

```bash
docker compose exec fusen pocketbase superuser \
  create admin@example.com einlangespasswort --dir=/pb/pb_data
```

Das ist für Fusen nicht nötig; nützlich ist es zum Nachsehen, was
synchronisiert wurde.

## Datensicherung

Alles liegt in `pb_data`:

```bash
docker compose stop fusen
docker run --rm -v fusen_fusen_data:/data -v "$PWD:/backup" alpine \
  tar czf /backup/fusen-backup.tar.gz -C /data .
docker compose start fusen
```
