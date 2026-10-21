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

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const fromApi = (m) => require(require.resolve(m, { paths: [path.join(__dirname, '../api')] }));
const { initializeApp } = fromApi('firebase-admin/app');
const { getFirestore } = fromApi('firebase-admin/firestore');
const { getStorage } = fromApi('firebase-admin/storage');

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : def;
}

async function main() {
  const projectId = arg('project');
  if (!projectId) throw new Error('--project is required');
  const bucketName = arg('bucket', `${projectId}.appspot.com`);
  const audioDir = arg('audio-dir');
  initializeApp({ projectId, storageBucket: bucketName });
  const db = getFirestore();

  const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, 'catalog.json'), 'utf8'));

  let ambience = [], melodic = [];
  if (audioDir && fs.existsSync(audioDir)) {
    const bucket = getStorage().bucket();
    const files = fs.readdirSync(audioDir)
      .filter((f) => /\.(mp3|ogg|m4a)$/.test(f) && !f.includes('silence'))
      .sort();
    for (const f of files) {
      const dest = `sleep-aid/audio/${f}`;
      await bucket.upload(path.join(audioDir, f), {
        destination: dest,
        metadata: {
          contentType: f.endsWith('.ogg') ? 'audio/ogg' : f.endsWith('.m4a') ? 'audio/mp4' : 'audio/mpeg',
          // lets the Storage *emulator* serve the file by token (it can't sign
          // URLs); in the cloud the API hands out signed URLs instead
          metadata: { firebaseStorageDownloadTokens: crypto.randomUUID() },
        },
      });
      (f.startsWith('alarm_sound') ? melodic : ambience).push(dest);
      process.stdout.write('.');
    }
    console.log(`\nuploaded ${files.length} audio files to gs://${bucketName}/sleep-aid/audio/`);
  }

  const pick = (item) => {
    if (item.audio && [...ambience, ...melodic].includes(`sleep-aid/audio/${item.audio}`)) {
      return `sleep-aid/audio/${item.audio}`;
    }
    const pool = item.minutes ? (melodic.length ? melodic : ambience) : (ambience.length ? ambience : melodic);
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
  await db.doc('sleepAid/catalog').set({ ...catalog, updatedAt: Date.now() });
  await db.doc('config/app').set({
    minAppVersion: '0.1.0',
    paywall: {
      trialDays: 7,
      products: [
        { sku: 'premium_yearly', period: 'P1Y', trialDays: 7, highlight: true },
        { sku: 'premium_monthly', period: 'P1M', trialDays: 0, highlight: false },
      ],
    },
    features: { alertnessTest: true, breathingDisruptions: true },
  });
  console.log(`seeded config/app and sleepAid/catalog (${catalog.sections.length} sections) in ${projectId}`);
}

main().then(() => process.exit(0), (e) => {
  console.error(e);
  process.exit(1);
});
