// Cloud Run entrypoint. Uses Application Default Credentials (the service's
// runtime service account on Cloud Run; FIREBASE_*_EMULATOR_HOST locally).
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const { createApp } = require("./app");

initializeApp({
  projectId: process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT,
  storageBucket: process.env.STORAGE_BUCKET,
});

const app = createApp({
  // a named database keeps this app's data apart when the project is shared
  db: getFirestore(process.env.FIRESTORE_DATABASE || "(default)"),
  auth: getAuth(),
  bucket: getStorage().bucket(),
  revenueCat: {
    apiKey: process.env.REVENUECAT_API_KEY || null,
    webhookAuth: process.env.REVENUECAT_WEBHOOK_AUTH || null,
  },
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => console.log(`sleep-tracker-api listening on :${port}`));
