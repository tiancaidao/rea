// HTTP API for the sleep tracker, deployed on Cloud Run.
//
// Identity is Firebase Auth: every /v1 route except /v1/config requires a
// Firebase ID token (Authorization: Bearer <token>). User data itself
// (profile, settings, nights) is read/written by the app directly in
// Firestore under security rules; this service does the work that needs a
// server: signed media URLs, cross-night insights, third-party calls (weather,
// RevenueCat) and privileged writes (premium status, account deletion).

const express = require("express");
const { weeklyReport, DAY } = require("./insights");
const { currentWeather } = require("./weather");
const { recommendations } = require("./recommendations");
const paywalls = require("./paywalls");
const rc = require("./revenuecat");

const DEFAULT_CONFIG = {
  minAppVersion: "0.1.0",
  paywall: {
    trialDays: 7,
    products: [
      { sku: "premium_yearly", period: "P1Y", trialDays: 7, highlight: true },
      { sku: "premium_monthly", period: "P1M", trialDays: 0, highlight: false },
    ],
  },
  features: { alertnessTest: true, breathingDisruptions: true },
};

/**
 * @param deps.db        Firestore
 * @param deps.auth      firebase-admin Auth
 * @param deps.bucket    Cloud Storage bucket (sleep-aid media)
 * @param deps.revenueCat {apiKey, webhookAuth}: RevenueCat secret API key and
 *                       the webhook's Authorization value (either may be null)
 * @param deps.fetchImpl fetch (injectable for tests)
 */
function createApp({ db, auth, bucket, revenueCat = {}, fetchImpl = fetch }) {
  const app = express();
  app.use(express.json({ limit: "2mb" }));
  // one structured line per request (Cloud Logging parses JSON on stdout)
  app.use((req, res, next) => {
    const t0 = Date.now();
    res.on("finish", () => {
      if (req.path.startsWith("/health")) return;
      console.log(
        JSON.stringify({
          severity: "INFO",
          method: req.method,
          path: req.path,
          status: res.statusCode,
          ms: Date.now() - t0,
        }),
      );
    });
    next();
  });

  const asyncRoute = (fn) => (req, res, next) =>
    Promise.resolve(fn(req, res, next)).catch(next);

  const requireUser = asyncRoute(async (req, res, next) => {
    const m = /^Bearer (.+)$/.exec(req.get("authorization") || "");
    if (!m) return res.status(401).json({ error: "missing bearer token" });
    try {
      req.user = await auth.verifyIdToken(m[1]);
    } catch {
      return res.status(401).json({ error: "invalid token" });
    }
    next();
  });

  // /healthz is reserved by Cloud Run's front end; /health works there
  app.get(["/health", "/healthz"], (_req, res) => res.json({ ok: true }));

  // Remote config + paywall definition (public: needed before sign-in).
  app.get(
    "/v1/config",
    asyncRoute(async (_req, res) => {
      const snap = await db.doc("config/app").get();
      res.set("cache-control", "public, max-age=300");
      res.json({ ...DEFAULT_CONFIG, ...(snap.exists ? snap.data() : {}) });
    }),
  );

  // Server-driven paywall for a placement (onboarding, in_app, locked_feature,
  // gift_cards, campaign, app_open). Public, because onboarding shows it
  // before sign-in: the subject is the uid when a valid token is sent, else
  // the app's install id. ?variant= previews a specific variant.
  app.get(
    "/v1/paywall",
    asyncRoute(async (req, res) => {
      const placement = String(req.query.placement || "in_app");
      let subject = String(req.query.installId || "").slice(0, 64) || null;
      let uid = null;
      const m = /^Bearer (.+)$/.exec(req.get("authorization") || "");
      if (m) {
        try {
          uid = subject = (await auth.verifyIdToken(m[1])).uid;
        } catch {
          // fall back to the install id
        }
      }
      const snap = await db.doc("config/paywalls").get();
      const cfg = paywalls.merge(
        paywalls.DEFAULTS,
        snap.exists ? snap.data() : null,
      );
      let forced = req.query.variant ? String(req.query.variant) : null;
      // past subscribers whose Premium lapsed get the placement's returning
      // variant (the early-adopter discount) instead of the experiment
      const returning =
        cfg.placements[placement] && cfg.placements[placement].returningVariant;
      if (!forced && returning && uid) {
        const u = await db.doc(`users/${uid}`).get();
        const prem = u.exists ? u.data().premium : null;
        if (prem && !prem.active) forced = returning;
      }
      const chosen = paywalls.choosePaywall(cfg, placement, subject, forced);
      res.set("cache-control", "private, max-age=300");
      res.json(chosen || { placement, variant: null });
    }),
  );

  // Sleep-aid catalog with short-lived media URLs.
  app.get(
    "/v1/sleep-aid/catalog",
    requireUser,
    asyncRoute(async (_req, res) => {
      const snap = await db.doc("sleepAid/catalog").get();
      if (!snap.exists) return res.json({ sections: [] });
      const catalog = snap.data();
      const sections = await Promise.all(
        (catalog.sections || []).map(async (s) => ({
          ...s,
          items: await Promise.all(
            (s.items || []).map(async (it) => ({
              ...it,
              url: it.storagePath
                ? await mediaUrl(bucket, it.storagePath)
                : null,
            })),
          ),
        })),
      );
      res.json({ ...catalog, sections });
    }),
  );

  // Weekly report from the user's nights; also stored for the Journal.
  app.get(
    "/v1/insights/weekly",
    requireUser,
    asyncRoute(async (req, res) => {
      const tz = Number(req.query.tzOffsetMin || 0);
      const weekStart = req.query.weekStart
        ? Date.parse(`${req.query.weekStart}T00:00:00Z`) - tz * 60000
        : startOfWeek(Date.now(), tz);
      if (!Number.isFinite(weekStart))
        return res.status(400).json({ error: "bad weekStart" });
      const nightsSnap = await db
        .collection(`users/${req.user.uid}/nights`)
        .where("wokeUp", ">=", weekStart - 7 * DAY)
        .where("wokeUp", "<", weekStart + 7 * DAY)
        .get();
      const report = weeklyReport(
        nightsSnap.docs.map((d) => d.data()),
        weekStart,
        tz,
      );
      await db
        .doc(`users/${req.user.uid}/reports/${report.weekStart}`)
        .set({ ...report, createdAt: Date.now() });
      res.json(report);
    }),
  );

  app.get(
    "/v1/weather",
    requireUser,
    asyncRoute(async (req, res) => {
      res.json(
        await currentWeather(
          Number(req.query.lat),
          Number(req.query.lon),
          fetchImpl,
        ),
      );
    }),
  );

  // Mirror the RevenueCat "premium" entitlement into users/{uid}.premium. A
  // gift-card Premium that is still running is kept when the store has none.
  async function recordPremium(uid, premium) {
    const ref = db.doc(`users/${uid}`);
    const snap = await ref.get();
    const cur = snap.exists ? snap.data().premium : null;
    if (
      !premium.active &&
      cur &&
      cur.source === "giftcard" &&
      cur.expiry > Date.now()
    )
      return cur;
    await ref.set({ premium }, { merge: true });
    try {
      const u = await auth.getUser(uid);
      await auth.setCustomUserClaims(uid, {
        ...(u.customClaims || {}),
        premium: premium.active,
      });
    } catch {
      // not a Firebase user (yet): the Firestore record is enough
    }
    return premium;
  }

  // The app calls this after a purchase or restore so Premium is on the
  // server at once, without waiting for the webhook.
  app.post(
    "/v1/billing/sync",
    requireUser,
    asyncRoute(async (req, res) => {
      if (!revenueCat.apiKey)
        return res.status(501).json({
          error: "RevenueCat not configured (set REVENUECAT_API_KEY)",
        });
      const subscriber = await rc.fetchSubscriber(req.user.uid, {
        apiKey: revenueCat.apiKey,
        fetchImpl,
      });
      res.json(
        await recordPremium(req.user.uid, rc.premiumFromSubscriber(subscriber)),
      );
    }),
  );

  // RevenueCat webhook (purchases, renewals, cancellations, expirations,
  // transfers). RevenueCat sends the Authorization value set in its
  // dashboard; with a secret API key the subscriber is re-read from
  // RevenueCat, as it recommends, else the event itself is used.
  app.post(
    "/v1/billing/revenuecat",
    asyncRoute(async (req, res) => {
      if (
        !revenueCat.webhookAuth ||
        req.get("authorization") !== revenueCat.webhookAuth
      )
        return res.status(401).json({ error: "bad webhook authorization" });
      const ev = (req.body || {}).event || {};
      if (ev.type === "TEST") return res.json({ ok: true, updated: [] });
      const updated = [];
      for (const uid of rc.eventUids(ev)) {
        let premium;
        if (revenueCat.apiKey) {
          const subscriber = await rc.fetchSubscriber(uid, {
            apiKey: revenueCat.apiKey,
            fetchImpl,
          });
          premium = rc.premiumFromSubscriber(subscriber);
        } else if (ev.type === "TRANSFER") {
          continue; // needs the REST key to know each side's state
        } else {
          premium = rc.premiumFromEvent(ev);
        }
        await recordPremium(uid, premium);
        updated.push(uid);
      }
      res.json({ ok: true, updated });
    }),
  );

  // Personal recommendations from the last two weeks of nights.
  app.get(
    "/v1/insights/recommendations",
    requireUser,
    asyncRoute(async (req, res) => {
      const tz = Number(req.query.tzOffsetMin || 0);
      const goal = req.query.goalMin ? Number(req.query.goalMin) : null;
      const now = Date.now();
      const snap = await db
        .collection(`users/${req.user.uid}/nights`)
        .where("wokeUp", ">=", now - 14 * DAY)
        .get();
      res.json(
        recommendations(
          snap.docs.map((d) => d.data()),
          now,
          tz,
          goal,
        ),
      );
    }),
  );

  // Consent and privacy choices, stored with a timestamp (GDPR record).
  const CONSENT_KEYS = ["storage", "sounds", "product"];
  app.post(
    "/v1/consent",
    requireUser,
    asyncRoute(async (req, res) => {
      const consent = { updatedAt: Date.now() };
      for (const k of CONSENT_KEYS) {
        if (typeof (req.body || {})[k] !== "boolean")
          return res.status(400).json({ error: `${k} must be a boolean` });
        consent[k] = req.body[k];
      }
      await db.doc(`users/${req.user.uid}`).set({ consent }, { merge: true });
      res.json(consent);
    }),
  );

  // Push / device registration (FCM token or APNs token), one doc per device.
  app.post(
    "/v1/devices/register",
    requireUser,
    asyncRoute(async (req, res) => {
      const { token, platform } = req.body || {};
      if (
        typeof token !== "string" ||
        token.length < 8 ||
        token.length > 4096
      ) {
        return res.status(400).json({ error: "token required" });
      }
      if (!["android", "ios"].includes(platform))
        return res
          .status(400)
          .json({ error: "platform must be android or ios" });
      const id = require("crypto")
        .createHash("sha256")
        .update(token)
        .digest("hex")
        .slice(0, 32);
      await db
        .doc(`users/${req.user.uid}/devices/${id}`)
        .set({ token, platform, updatedAt: Date.now() });
      res.json({ id });
    }),
  );

  // "About you" and the onboarding survey: a whitelisted set of properties.
  const PROPERTY_KEYS = [
    "units",
    "weight",
    "height",
    "gender",
    "birth",
    "survey",
    "goal",
  ];
  app.post(
    "/v1/user/properties",
    requireUser,
    asyncRoute(async (req, res) => {
      const properties = {};
      for (const [k, v] of Object.entries(req.body || {})) {
        if (!PROPERTY_KEYS.includes(k))
          return res.status(400).json({ error: `unknown property ${k}` });
        if (typeof v !== "string" || v.length > 100)
          return res.status(400).json({ error: `${k} must be a short string` });
        properties[k] = v;
      }
      await db
        .doc(`users/${req.user.uid}`)
        .set({ properties }, { merge: true });
      res.json({ properties });
    }),
  );

  // Start the free trial once per account; the trial reminder is scheduled on
  // the device. Store purchases come from RevenueCat (/v1/billing/*).
  app.post(
    "/v1/trial/start",
    requireUser,
    asyncRoute(async (req, res) => {
      const ref = db.doc(`users/${req.user.uid}`);
      const result = await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const existing = snap.exists ? snap.data().trial : null;
        if (existing)
          return {
            status: 409,
            body: { error: "trial already used", trial: existing },
          };
        const cfg = await tx.get(db.doc("config/app"));
        const days =
          (cfg.exists && cfg.data().paywall && cfg.data().paywall.trialDays) ||
          DEFAULT_CONFIG.paywall.trialDays;
        const now = Date.now();
        const trial = {
          startedAt: now,
          endsAt: now + days * DAY,
          productId: (req.body || {}).productId || null,
        };
        tx.set(ref, { trial }, { merge: true });
        return { status: 200, body: trial };
      });
      res.status(result.status).json(result.body);
    }),
  );

  // Redeem a gift card: codes live in giftcards/{code} (created by the
  // seed script or a purchase flow) and can be used once.
  app.post(
    "/v1/giftcards/redeem",
    requireUser,
    asyncRoute(async (req, res) => {
      const code = String((req.body || {}).code || "")
        .trim()
        .toUpperCase()
        .replace(/[^A-Z0-9-]/g, "");
      if (code.length < 6)
        return res.status(400).json({ error: "invalid code" });
      const cardRef = db.doc(`giftcards/${code}`);
      const userRef = db.doc(`users/${req.user.uid}`);
      const result = await db.runTransaction(async (tx) => {
        const card = await tx.get(cardRef);
        if (!card.exists)
          return { status: 404, body: { error: "unknown code" } };
        if (card.data().redeemedBy)
          return { status: 409, body: { error: "code already used" } };
        const user = await tx.get(userRef);
        const now = Date.now();
        const current =
          user.exists && user.data().premium && user.data().premium.expiry;
        const from = current && current > now ? current : now;
        const expiry = from + (card.data().months || 12) * 30 * DAY;
        tx.update(cardRef, { redeemedBy: req.user.uid, redeemedAt: now });
        tx.set(
          userRef,
          {
            premium: {
              active: true,
              source: "giftcard",
              expiry,
              verifiedAt: now,
            },
          },
          { merge: true },
        );
        return {
          status: 200,
          body: {
            premiumUntil: new Date(expiry).toISOString().slice(0, 10),
            expiry,
          },
        };
      });
      if (result.status === 200) {
        await auth.setCustomUserClaims(req.user.uid, {
          ...(req.user.claims || {}),
          premium: true,
        });
      }
      res.status(result.status).json(result.body);
    }),
  );

  // Gift-card paywall ("one for you, two for your friends"): a paying
  // subscriber gets two one-year codes to share, once per account.
  app.post(
    "/v1/giftcards/issue",
    requireUser,
    asyncRoute(async (req, res) => {
      const userRef = db.doc(`users/${req.user.uid}`);
      const result = await db.runTransaction(async (tx) => {
        const user = await tx.get(userRef);
        const data = user.exists ? user.data() : {};
        const p = data.premium;
        if (!p || !p.active || p.source === "giftcard")
          return { status: 403, body: { error: "needs a paid subscription" } };
        if (data.giftcardsIssued)
          return { status: 200, body: { codes: data.giftcardsIssued } };
        const codes = [0, 1].map(() =>
          require("crypto")
            .randomBytes(6)
            .toString("hex")
            .toUpperCase()
            .replace(/(.{4})(.{4})(.{4})/, "$1-$2-$3"),
        );
        const now = Date.now();
        for (const code of codes)
          tx.set(db.doc(`giftcards/${code}`), {
            months: 12,
            issuedBy: req.user.uid,
            createdAt: now,
            newUsersOnly: true,
          });
        tx.set(userRef, { giftcardsIssued: codes }, { merge: true });
        return { status: 200, body: { codes } };
      });
      res.status(result.status).json(result.body);
    }),
  );

  // "Erase your data and account": nights, reports, profile, then the login.
  app.post(
    "/v1/account/delete",
    requireUser,
    asyncRoute(async (req, res) => {
      const uid = req.user.uid;
      await db.recursiveDelete(db.doc(`users/${uid}`));
      await auth.deleteUser(uid);
      res.json({ deleted: true });
    }),
  );

  // "Erase your data": nights and reports only; the account stays.
  app.post(
    "/v1/account/erase-data",
    requireUser,
    asyncRoute(async (req, res) => {
      const uid = req.user.uid;
      await db.recursiveDelete(db.collection(`users/${uid}/nights`));
      await db.recursiveDelete(db.collection(`users/${uid}/reports`));
      res.json({ erased: true });
    }),
  );

  app.use((err, _req, res, _next) => {
    const status = err.status || (err.code === 404 ? 404 : 500);
    if (status >= 500) console.error(err);
    res
      .status(status)
      .json({ error: status >= 500 ? "internal error" : err.message });
  });

  return app;
}

function startOfWeek(nowMs, tzOffsetMin) {
  // Monday 00:00 in the user's local time, expressed in UTC ms
  const local = new Date(nowMs + tzOffsetMin * 60000);
  const dow = (local.getUTCDay() + 6) % 7;
  const midnight = Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate() - dow,
  );
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
    return (
      `http://${host}/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media` +
      (token ? `&token=${token}` : "")
    );
  }
  const [url] = await bucket.file(path).getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + 60 * 60 * 1000,
  });
  return url;
}

module.exports = { createApp, startOfWeek, DEFAULT_CONFIG };
