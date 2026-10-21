// HTTP API for the sleep tracker, deployed on Cloud Run.
//
// Identity is Firebase Auth: every /v1 route except /v1/config requires a
// Firebase ID token (Authorization: Bearer <token>). User data itself
// (profile, settings, nights) is read/written by the app directly in
// Firestore under security rules; this service does the work that needs a
// server: signed media URLs, cross-night insights, third-party calls (weather,
// Google Play) and privileged writes (premium status, account deletion).

const express = require('express');
const { weeklyReport, DAY } = require('./insights');
const { currentWeather } = require('./weather');

const DEFAULT_CONFIG = {
  minAppVersion: '0.1.0',
  paywall: {
    trialDays: 7,
    products: [
      { sku: 'premium_yearly', period: 'P1Y', trialDays: 7, highlight: true },
      { sku: 'premium_monthly', period: 'P1M', trialDays: 0, highlight: false },
    ],
  },
  features: { alertnessTest: true, breathingDisruptions: true },
};

/**
 * @param deps.db        Firestore
 * @param deps.auth      firebase-admin Auth
 * @param deps.bucket    Cloud Storage bucket (sleep-aid media)
 * @param deps.publisher Google Play androidpublisher client, or null
 * @param deps.packageName Android package name for Play verification
 * @param deps.fetchImpl fetch (injectable for tests)
 */
function createApp({ db, auth, bucket, publisher = null, packageName = null, fetchImpl = fetch }) {
  const app = express();
  app.use(express.json({ limit: '2mb' }));
  // one structured line per request (Cloud Logging parses JSON on stdout)
  app.use((req, res, next) => {
    const t0 = Date.now();
    res.on('finish', () => {
      if (req.path.startsWith('/health')) return;
      console.log(JSON.stringify({ severity: 'INFO', method: req.method, path: req.path,
        status: res.statusCode, ms: Date.now() - t0 }));
    });
    next();
  });

  const asyncRoute = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

  const requireUser = asyncRoute(async (req, res, next) => {
    const m = /^Bearer (.+)$/.exec(req.get('authorization') || '');
    if (!m) return res.status(401).json({ error: 'missing bearer token' });
    try {
      req.user = await auth.verifyIdToken(m[1]);
    } catch {
      return res.status(401).json({ error: 'invalid token' });
    }
    next();
  });

  // /healthz is reserved by Cloud Run's front end; /health works there
  app.get(['/health', '/healthz'], (_req, res) => res.json({ ok: true }));

  // Remote config + paywall definition (public: needed before sign-in).
  app.get('/v1/config', asyncRoute(async (_req, res) => {
    const snap = await db.doc('config/app').get();
    res.set('cache-control', 'public, max-age=300');
    res.json({ ...DEFAULT_CONFIG, ...(snap.exists ? snap.data() : {}) });
  }));

  // Sleep-aid catalog with short-lived media URLs.
  app.get('/v1/sleep-aid/catalog', requireUser, asyncRoute(async (_req, res) => {
    const snap = await db.doc('sleepAid/catalog').get();
    if (!snap.exists) return res.json({ sections: [] });
    const catalog = snap.data();
    const sections = await Promise.all((catalog.sections || []).map(async (s) => ({
      ...s,
      items: await Promise.all((s.items || []).map(async (it) => ({
        ...it,
        url: it.storagePath ? await mediaUrl(bucket, it.storagePath) : null,
      }))),
    })));
    res.json({ ...catalog, sections });
  }));

  // Weekly report from the user's nights; also stored for the Journal.
  app.get('/v1/insights/weekly', requireUser, asyncRoute(async (req, res) => {
    const tz = Number(req.query.tzOffsetMin || 0);
    const weekStart = req.query.weekStart
      ? Date.parse(`${req.query.weekStart}T00:00:00Z`) - tz * 60000
      : startOfWeek(Date.now(), tz);
    if (!Number.isFinite(weekStart)) return res.status(400).json({ error: 'bad weekStart' });
    const nightsSnap = await db.collection(`users/${req.user.uid}/nights`)
      .where('wokeUp', '>=', weekStart - 7 * DAY)
      .where('wokeUp', '<', weekStart + 7 * DAY)
      .get();
    const report = weeklyReport(nightsSnap.docs.map((d) => d.data()), weekStart, tz);
    await db.doc(`users/${req.user.uid}/reports/${report.weekStart}`).set({ ...report, createdAt: Date.now() });
    res.json(report);
  }));

  app.get('/v1/weather', requireUser, asyncRoute(async (req, res) => {
    res.json(await currentWeather(Number(req.query.lat), Number(req.query.lon), fetchImpl));
  }));

  // Verify a Google Play subscription purchase and record premium status.
  app.post('/v1/billing/verify', requireUser, asyncRoute(async (req, res) => {
    const { purchaseToken, productId } = req.body || {};
    if (!purchaseToken) return res.status(400).json({ error: 'purchaseToken required' });
    if (!publisher || !packageName) {
      return res.status(501).json({ error: 'Play verification not configured (set PLAY_PACKAGE_NAME and grant the service account Play Console access)' });
    }
    const { data } = await publisher.purchases.subscriptionsv2.get({ packageName, token: purchaseToken });
    const active = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD'].includes(data.subscriptionState);
    const line = (data.lineItems || [])[0] || {};
    const premium = {
      active,
      state: data.subscriptionState,
      productId: line.productId || productId || null,
      expiry: line.expiryTime ? Date.parse(line.expiryTime) : null,
      trial: Boolean(line.offerDetails && /trial/i.test(line.offerDetails.offerId || '')),
      verifiedAt: Date.now(),
    };
    await db.doc(`users/${req.user.uid}`).set({ premium }, { merge: true });
    await auth.setCustomUserClaims(req.user.uid, { ...(req.user.claims || {}), premium: active });
    res.json(premium);
  }));

  // "Erase your data and account": nights, reports, profile, then the login.
  app.post('/v1/account/delete', requireUser, asyncRoute(async (req, res) => {
    const uid = req.user.uid;
    await db.recursiveDelete(db.doc(`users/${uid}`));
    await auth.deleteUser(uid);
    res.json({ deleted: true });
  }));

  // "Erase your data": nights and reports only; the account stays.
  app.post('/v1/account/erase-data', requireUser, asyncRoute(async (req, res) => {
    const uid = req.user.uid;
    await db.recursiveDelete(db.collection(`users/${uid}/nights`));
    await db.recursiveDelete(db.collection(`users/${uid}/reports`));
    res.json({ erased: true });
  }));

  app.use((err, _req, res, _next) => {
    const status = err.status || (err.code === 404 ? 404 : 500);
    if (status >= 500) console.error(err);
    res.status(status).json({ error: status >= 500 ? 'internal error' : err.message });
  });

  return app;
}

function startOfWeek(nowMs, tzOffsetMin) {
  // Monday 00:00 in the user's local time, expressed in UTC ms
  const local = new Date(nowMs + tzOffsetMin * 60000);
  const dow = (local.getUTCDay() + 6) % 7;
  const midnight = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() - dow);
  return midnight - tzOffsetMin * 60000;
}

async function mediaUrl(bucket, path) {
  const emu = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
  if (emu) {
    // Storage emulator can't sign URLs: use the file's download token, and
    // the host the *app* can reach (10.0.2.2 from an Android emulator).
    const host = process.env.PUBLIC_STORAGE_HOST || emu;
    const [md] = await bucket.file(path).getMetadata();
    const token = md.metadata && md.metadata.firebaseStorageDownloadTokens;
    return `http://${host}/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media` +
      (token ? `&token=${token}` : '');
  }
  const [url] = await bucket.file(path).getSignedUrl({
    version: 'v4',
    action: 'read',
    expires: Date.now() + 60 * 60 * 1000,
  });
  return url;
}

module.exports = { createApp, startOfWeek, DEFAULT_CONFIG };
