/// <reference path="../pb_data/types.d.ts" />

/**
 * Legt die drei Collections an, die Fusen braucht.
 *
 * - access   Auth-Collection mit genau einem Datensatz: dem Zugang zur
 *            Instanz. Der Zugangscode ist dessen Passwort. Angelegt wird der
 *            Datensatz beim Start durch pb_hooks/main.pb.js.
 * - projects Projekte
 * - notes    Zettel
 *
 * Die Datensatz-ID ist die UUID des Geräts ohne Bindestriche. PocketBase
 * verlangt `[a-z0-9]` mit mindestens 15 Zeichen – 32 Hex-Zeichen passen, das
 * Feld muss dafür nur breiter sein als die voreingestellten 15.
 */

/** Nur angemeldete Geräte, also solche mit gültigem Zugangscode. */
const AUTHENTICATED = '@request.auth.id != ""';

/** Die ID kommt vom Gerät, nicht vom Server. */
const idField = {
  name: "id",
  type: "text",
  system: true,
  primaryKey: true,
  required: true,
  min: 15,
  max: 36,
  pattern: "^[a-z0-9]+$",
  autogeneratePattern: "[a-z0-9]{15}",
};

/**
 * Zeitstempel des Geräts als Text (ISO-8601). Leerer String heißt „nicht
 * gesetzt“ – PocketBase kennt kein NULL für Textfelder.
 */
const timestamp = (name, required) => ({
  name,
  type: "text",
  required: !!required,
  max: 40,
});

/**
 * Die serverseitigen Zeitstempel. `updated` ist der Cursor des Sync: die App
 * fragt „alles, was nach X geändert wurde“ und verlässt sich dabei auf die
 * Uhr des Servers, nicht auf die des Geräts.
 */
const serverTimestamps = [
  { name: "created", type: "autodate", onCreate: true, onUpdate: false },
  { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
];

migrate(
  (app) => {
    // Zugang: kein Lesen, kein Schreiben über die API. Nur Anmelden.
    app.save(
      new Collection({
        type: "auth",
        name: "access",
        listRule: null,
        viewRule: null,
        createRule: null,
        updateRule: null,
        deleteRule: null,
        fields: [],
      }),
    );

    app.save(
      new Collection({
        type: "base",
        name: "projects",
        listRule: AUTHENTICATED,
        viewRule: AUTHENTICATED,
        createRule: AUTHENTICATED,
        updateRule: AUTHENTICATED,
        // Nie hart löschen: Löschungen reisen als deleted_at, sonst kommt der
        // Datensatz beim nächsten Abgleich vom anderen Gerät zurück.
        deleteRule: null,
        fields: [
          idField,
          { name: "name", type: "text", required: true, max: 200 },
          { name: "color", type: "number", onlyInt: true },
          { name: "sort_order", type: "number" },
          timestamp("created_at", true),
          timestamp("updated_at", true),
          timestamp("archived_at"),
          timestamp("deleted_at"),
          ...serverTimestamps,
        ],
        indexes: ["CREATE INDEX idx_projects_updated ON projects (updated)"],
      }),
    );

    app.save(
      new Collection({
        type: "base",
        name: "notes",
        listRule: AUTHENTICATED,
        viewRule: AUTHENTICATED,
        createRule: AUTHENTICATED,
        updateRule: AUTHENTICATED,
        deleteRule: null,
        fields: [
          idField,
          // Bewusst kein relation-Feld: beim Abgleich kann ein Zettel vor
          // seinem Projekt eintreffen, und eine Beziehungsprüfung würde die
          // ganze Übertragung abbrechen.
          { name: "project_id", type: "text", max: 40 },
          { name: "type", type: "text", required: true, max: 20 },
          { name: "title", type: "text", max: 500 },
          { name: "body", type: "text" },
          { name: "answer", type: "text" },
          { name: "status", type: "text", required: true, max: 20 },
          { name: "priority", type: "text", max: 20 },
          { name: "tags", type: "json", maxSize: 20000 },
          { name: "sort_order", type: "number" },
          timestamp("created_at", true),
          timestamp("updated_at", true),
          timestamp("archived_at"),
          timestamp("deleted_at"),
          { name: "device_id", type: "text", max: 40 },
          ...serverTimestamps,
        ],
        indexes: [
          "CREATE INDEX idx_notes_updated ON notes (updated)",
          "CREATE INDEX idx_notes_project ON notes (project_id)",
        ],
      }),
    );
  },
  (app) => {
    for (const name of ["notes", "projects", "access"]) {
      app.delete(app.findCollectionByNameOrId(name));
    }
  },
);
