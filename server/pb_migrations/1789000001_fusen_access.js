/// <reference path="../pb_data/types.d.ts" />

/**
 * Legt den einen Zugang dieser Instanz an.
 *
 * Es gibt keine Benutzerkonten: eine Instanz gehört genau einer Person, und
 * alle ihre Geräte teilen sich einen Zugangscode. Technisch ist der Code das
 * Passwort dieses einen Datensatzes; PocketBase gibt dafür ein Token aus, und
 * die Regeln von `projects` und `notes` verlangen genau dieses Token.
 *
 * Der Code kommt aus FUSEN_ACCESS_CODE. Ist die Variable leer, wird einer
 * erzeugt und einmalig ins Log geschrieben.
 *
 * Diese Migration läuft nur beim allerersten Start. Wer den Code später
 * ändern will, setzt FUSEN_ACCESS_CODE und startet neu – darum kümmert sich
 * pb_hooks/main.pb.js.
 */

const IDENTITY = "owner@fusen.local";
const MIN_LENGTH = 8;

migrate(
  (app) => {
    const configured = ($os.getenv("FUSEN_ACCESS_CODE") || "").trim();

    if (configured && configured.length < MIN_LENGTH) {
      throw new Error(
        `FUSEN_ACCESS_CODE ist zu kurz: mindestens ${MIN_LENGTH} Zeichen.`,
      );
    }

    const code = configured || $security.randomString(20);

    const record = new Record(app.findCollectionByNameOrId("access"));
    record.set("email", IDENTITY);
    record.set("verified", true);
    record.setPassword(code);
    app.save(record);

    if (configured) {
      console.log("Fusen: Zugang mit FUSEN_ACCESS_CODE angelegt.");
      return;
    }

    // Der einzige Moment, in dem der Code irgendwo im Klartext steht.
    console.log(
      "\n" +
        "──────────────────────────────────────────────\n" +
        "  Fusen: Zugangscode für diese Instanz\n" +
        "\n" +
        "      " + code + "\n" +
        "\n" +
        "  In der App unter Einstellungen -> Sync eintragen.\n" +
        "  Er erscheint nur bei diesem einen Start.\n" +
        "──────────────────────────────────────────────\n",
    );
  },
  (app) => {
    const found = app.findRecordsByFilter(
      "access",
      "email = {:email}",
      "",
      1,
      0,
      { email: IDENTITY },
    );
    if (found.length > 0) {
      app.delete(found[0]);
    }
  },
);
