// Cloud Run entrypoint. Uses Application Default Credentials (the service's
// runtime service account on Cloud Run; FIREBASE_*_EMULATOR_HOST locally).
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { createApp } = require('./app');

initializeApp({
  projectId: process.env.GOOGLE_CLOUD_PROJECT || process.env.GCLOUD_PROJECT,
  storageBucket: process.env.STORAGE_BUCKET,
});

let publisher = null;
const packageName = process.env.PLAY_PACKAGE_NAME || null;
if (packageName) {
  const { androidpublisher } = require('@googleapis/androidpublisher');
  const { GoogleAuth } = require('google-auth-library');
  publisher = androidpublisher({
    version: 'v3',
    auth: new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] }),
  });
}

const app = createApp({
  // a named database keeps this app's data apart when the project is shared
  db: getFirestore(process.env.FIRESTORE_DATABASE || '(default)'),
  auth: getAuth(),
  bucket: getStorage().bucket(),
  publisher,
  packageName,
  appleBundleId: process.env.APPLE_BUNDLE_ID || 'com.matchlab.lullwake',
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => console.log(`sleep-tracker-api listening on :${port}`));
