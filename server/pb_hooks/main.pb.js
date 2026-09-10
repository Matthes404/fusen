/// <reference path="../pb_data/types.d.ts" />

/**
 * Hält den Zugangscode mit FUSEN_ACCESS_CODE in Übereinstimmung.
 *
 * Angelegt wird der Zugang von der Migration `1789000001_fusen_access.js`;
 * hier geht es nur darum, ihn später ändern zu können: Variable anpassen,
 * Server neu starten, fertig. PocketBase verwirft dabei alle ausgegebenen
 * Token – alle Geräte müssen sich neu verbinden, so wie es sein soll.
 *
 * Achtung beim Bearbeiten: PocketBase führt Hook-Funktionen in einer eigenen
 * JS-Umgebung aus. Konstanten aus dem Dateikopf sind darin *nicht* sichtbar,
 * deshalb steht alles innerhalb der Funktion.
 */
onBootstrap((e) => {
  e.next();

  const identity = "owner@fusen.local";
  const minLength = 8;

  const configured = ($os.getenv("FUSEN_ACCESS_CODE") || "").trim();
  if (!configured) {
    return;
  }

  if (configured.length < minLength) {
    throw new Error(
      "FUSEN_ACCESS_CODE ist zu kurz: mindestens " + minLength + " Zeichen.",
    );
  }

  // Beim allerersten Start gibt es die Collection noch nicht: Migrationen
  // laufen erst nach dem Bootstrap. Dann übernimmt die Migration den Code,
  // und hier ist nichts zu tun.
  let record;
  try {
    const found = e.app.findRecordsByFilter(
      "access",
      "email = {:email}",
      "",
      1,
      0,
      { email: identity },
    );
    if (found.length === 0) {
      return;
    }
    record = found[0];
  } catch (err) {
    return;
  }

  if (record.validatePassword(configured)) {
    return; // Code steht schon so in der Datenbank.
  }

  record.setPassword(configured);
  e.app.save(record);
  console.log(
    "Fusen: Zugangscode aus FUSEN_ACCESS_CODE übernommen – " +
      "alle Geräte müssen sich neu verbinden.",
  );
});
