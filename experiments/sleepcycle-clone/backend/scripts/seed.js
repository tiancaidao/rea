#!/usr/bin/env node
// Seed Firestore (remote config + sleep-aid catalog) and, optionally, upload
// sleep-aid audio to Cloud Storage.
//
//   # against the emulators
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 \
//     node scripts/seed.js --project demo-sleep-tracker --audio-dir ../flutter_app/assets/audio
//
//   # against a real project (uses your gcloud application-default credentials)
//   node scripts/seed.js --project <id> --bucket <id>.firebasestorage.app --audio-dir <dir>
//
// --audio-dir is optional. The files there are your local comparison
// placeholders; they go to a private path readable only by signed-in users
// of your own project (see storage.rules). Items without their own file get a
// stable pick from the uploaded pool, mirroring the app's local behaviour.

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const fromApi = (m) =>
  require(require.resolve(m, { paths: [path.join(__dirname, "../api")] }));
const { initializeApp } = fromApi("firebase-admin/app");
const { getFirestore } = fromApi("firebase-admin/firestore");
const { getStorage } = fromApi("firebase-admin/storage");

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : def;
}

async function main() {
  const projectId = arg("project");
  if (!projectId) throw new Error("--project is required");
  const bucketName = arg("bucket", `${projectId}.appspot.com`);
  const audioDir = arg("audio-dir");
  const database = arg("database", "(default)");
  const store = process.env.ACCESS_TOKEN
    ? restStore(projectId, database, bucketName, process.env.ACCESS_TOKEN)
    : adminStore(projectId, database, bucketName);

  const catalog = JSON.parse(
    fs.readFileSync(path.join(__dirname, "catalog.json"), "utf8"),
  );

  let ambience = [],
    melodic = [];
  if (audioDir && fs.existsSync(audioDir)) {
    const files = fs
      .readdirSync(audioDir)
      .filter((f) => /\.(mp3|ogg|m4a)$/.test(f) && !f.includes("silence"))
      .sort();
    for (const f of files) {
      const dest = `sleep-aid/audio/${f}`;
      await store.upload(
        path.join(audioDir, f),
        dest,
        f.endsWith(".ogg")
          ? "audio/ogg"
          : f.endsWith(".m4a")
            ? "audio/mp4"
            : "audio/mpeg",
      );
      (f.startsWith("alarm_sound") ? melodic : ambience).push(dest);
      process.stdout.write(".");
    }
    console.log(
      `\nuploaded ${files.length} audio files to gs://${bucketName}/sleep-aid/audio/`,
    );
  }

  const pick = (item) => {
    if (
      item.audio &&
      [...ambience, ...melodic].includes(`sleep-aid/audio/${item.audio}`)
    ) {
      return `sleep-aid/audio/${item.audio}`;
    }
    const pool = item.minutes
      ? melodic.length
        ? melodic
        : ambience
      : ambience.length
        ? ambience
        : melodic;
    if (!pool.length) return null;
    const h = [...item.id].reduce((a, c) => a + c.charCodeAt(0), 0);
    return pool[h % pool.length];
  };
  for (const s of catalog.sections) {
    for (const it of s.items) {
      const p = pick(it);
      if (p) it.storagePath = p;
      delete it.audio;
    }
  }
  await store.set("sleepAid/catalog", { ...catalog, updatedAt: Date.now() });
  await store.set("config/app", {
    minAppVersion: "0.1.0",
    paywall: {
      trialDays: 7,
      products: [
        { sku: "premium_yearly", period: "P1Y", trialDays: 7, highlight: true },
        {
          sku: "premium_monthly",
          period: "P1M",
          trialDays: 0,
          highlight: false,
        },
      ],
    },
    features: { alertnessTest: true, breathingDisruptions: true },
  });
  console.log(
    `seeded config/app and sleepAid/catalog (${catalog.sections.length} sections) in ${projectId}/${database}`,
  );
}

/** firebase-admin with Application Default Credentials (or the emulators). */
function adminStore(projectId, database, bucketName) {
  initializeApp({ projectId, storageBucket: bucketName });
  const db = getFirestore(database);
  const bucket = getStorage().bucket();
  return {
    set: (docPath, data) => db.doc(docPath).set(data),
    upload: (file, dest, contentType) =>
      bucket.upload(file, {
        destination: dest,
        metadata: {
          contentType,
          // lets the Storage *emulator* serve the file by token (it can't sign
          // URLs); in the cloud the API hands out signed URLs instead
          metadata: { firebaseStorageDownloadTokens: crypto.randomUUID() },
        },
      }),
  };
}

/** Firestore + Cloud Storage REST with a user access token
 *  (ACCESS_TOKEN=$(gcloud auth print-access-token)) — no ADC login needed. */
function restStore(projectId, database, bucketName, token) {
  const headers = {
    authorization: `Bearer ${token}`,
    "x-goog-user-project": projectId,
  };
  const enc = (v) => {
    if (v === null || v === undefined) return { nullValue: null };
    if (typeof v === "boolean") return { booleanValue: v };
    if (typeof v === "number")
      return Number.isInteger(v)
        ? { integerValue: String(v) }
        : { doubleValue: v };
    if (typeof v === "string") return { stringValue: v };
    if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(v).map(([k, x]) => [k, enc(x)]),
        ),
      },
    };
  };
  const check = async (r) => {
    if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  };
  return {
    set: async (docPath, data) =>
      check(
        await fetch(
          `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${encodeURIComponent(database)}/documents/${docPath}`,
          {
            method: "PATCH",
            headers: { ...headers, "content-type": "application/json" },
            body: JSON.stringify({ fields: enc(data).mapValue.fields }),
          },
        ),
      ),
    upload: async (file, dest, contentType) =>
      check(
        await fetch(
          `https://storage.googleapis.com/upload/storage/v1/b/${bucketName}/o?uploadType=media&name=${encodeURIComponent(dest)}`,
          {
            method: "POST",
            headers: { ...headers, "content-type": contentType },
            body: fs.readFileSync(file),
          },
        ),
      ),
  };
}

main().then(
  () => process.exit(0),
  (e) => {
    console.error(e);
    process.exit(1);
  },
);
