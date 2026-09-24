/// <reference path="../pb_data/types.d.ts" />

/**
 * Version 2 des Sync-Formats.
 *
 * - notes.closed_at  Wann ein Zettel abgehakt, beantwortet oder verworfen
 *                    wurde. Leer, solange er offen ist.
 * - attachments      Bilder an Zetteln. Die Beschreibung reist wie ein
 *                    Zettel, die Bilddatei liegt im Feld `file`.
 *
 * Ältere App-Versionen stört beides nicht: ein Feld, das sie nicht kennen,
 * schicken sie nicht mit, und PocketBase lässt es beim Aktualisieren stehen.
 */

/** Nur angemeldete Geräte, also solche mit gültigem Zugangscode. */
const AUTHENTICATED = '@request.auth.id != ""';

/** Die ID kommt vom Gerät, nicht vom Server – wie bei Zetteln. */
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

const timestamp = (name, required) => ({
  name,
  type: "text",
  required: !!required,
  max: 40,
});

migrate(
  (app) => {
    const notes = app.findCollectionByNameOrId("notes");
    notes.fields.add(new TextField({ name: "closed_at", max: 40 }));
    app.save(notes);

    app.save(
      new Collection({
        type: "base",
        name: "attachments",
        listRule: AUTHENTICATED,
        viewRule: AUTHENTICATED,
        createRule: AUTHENTICATED,
        updateRule: AUTHENTICATED,
        // Wie bei Zetteln: Löschungen reisen als deleted_at.
        deleteRule: null,
        fields: [
          idField,
          // Kein relation-Feld – ein Bild kann vor seinem Zettel eintreffen.
          { name: "note_id", type: "text", required: true, max: 40 },
          {
            name: "file",
            type: "file",
            maxSelect: 1,
            // Die App verkleinert vorher und nimmt höchstens 20 MB an; hier
            // ist etwas Luft, damit die Grenze der App die maßgebliche ist.
            maxSize: 25 * 1024 * 1024,
            mimeTypes: [
              "image/jpeg",
              "image/png",
              "image/gif",
              "image/webp",
              "image/bmp",
              "image/heic",
              "image/heif",
            ],
            // Geschützt: herunterladen nur mit einem kurzlebigen Datei-Token,
            // das nur ein angemeldetes Gerät bekommt. Sonst wäre jedes Bild
            // für jeden abrufbar, der seine Adresse kennt.
            protected: true,
          },
          { name: "file_name", type: "text", max: 255 },
          { name: "mime_type", type: "text", max: 100 },
          { name: "byte_size", type: "number", onlyInt: true },
          { name: "width", type: "number", onlyInt: true },
          { name: "height", type: "number", onlyInt: true },
          { name: "sort_order", type: "number" },
          timestamp("created_at", true),
          timestamp("updated_at", true),
          timestamp("deleted_at"),
          { name: "device_id", type: "text", max: 40 },
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
          { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
        ],
        indexes: [
          "CREATE INDEX idx_attachments_updated ON attachments (updated)",
          "CREATE INDEX idx_attachments_note ON attachments (note_id)",
        ],
      }),
    );
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("attachments"));
    const notes = app.findCollectionByNameOrId("notes");
    notes.fields.removeByName("closed_at");
    app.save(notes);
  },
);
