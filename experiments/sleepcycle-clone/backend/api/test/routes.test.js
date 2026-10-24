// Route tests against an in-memory Firestore (no emulators needed).
const test = require("node:test");
const assert = require("node:assert");
const { createApp } = require("../src/app");
const { makeDb, fakeAuth } = require("./fake_firestore");

const DAY = 86400e3;

async function start(initial, opts = {}) {
  const db = makeDb(initial);
  const server = createApp({
    db,
    auth: fakeAuth,
    bucket: null,
    ...opts,
  }).listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = (method, path, body, uid = "u1") =>
    fetch(base + path, {
      method,
      headers: {
        authorization: `Bearer uid:${uid}`,
        "content-type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  return { db, server, call };
}

test("consent is validated and stored with a timestamp", async (t) => {
  const { db, server, call } = await start();
  t.after(() => server.close());
  assert.equal(
    (await call("POST", "/v1/consent", { storage: true })).status,
    400,
  );
  const r = await call("POST", "/v1/consent", {
    storage: true,
    sounds: false,
    product: true,
  });
  assert.equal(r.status, 200);
  const stored = db.docs.get("users/u1").consent;
  assert.deepStrictEqual(
    [stored.storage, stored.sounds, stored.product],
    [true, false, true],
  );
  assert.ok(stored.updatedAt > 0);
});

test("device registration hashes the token into the doc id", async (t) => {
  const { db, server, call } = await start();
  t.after(() => server.close());
  assert.equal(
    (
      await call("POST", "/v1/devices/register", {
        token: "abc",
        platform: "android",
      })
    ).status,
    400,
  );
  const r = await (
    await call("POST", "/v1/devices/register", {
      token: "fcm-token-123",
      platform: "android",
    })
  ).json();
  assert.match(r.id, /^[0-9a-f]{32}$/);
  assert.equal(db.docs.get(`users/u1/devices/${r.id}`).platform, "android");
});

test("user properties are whitelisted", async (t) => {
  const { db, server, call } = await start();
  t.after(() => server.close());
  assert.equal(
    (await call("POST", "/v1/user/properties", { premium: "yes" })).status,
    400,
  );
  assert.equal(
    (
      await call("POST", "/v1/user/properties", {
        units: "Metric",
        birth: "1990",
      })
    ).status,
    200,
  );
  assert.deepStrictEqual(db.docs.get("users/u1").properties, {
    units: "Metric",
    birth: "1990",
  });
});

test("trial starts once with the configured length", async (t) => {
  const { db, server, call } = await start({
    "config/app": { paywall: { trialDays: 14 } },
  });
  t.after(() => server.close());
  const r = await call("POST", "/v1/trial/start", {
    productId: "premium_yearly",
  });
  assert.equal(r.status, 200);
  const trial = await r.json();
  assert.equal(Math.round((trial.endsAt - trial.startedAt) / DAY), 14);
  assert.equal(db.docs.get("users/u1").trial.productId, "premium_yearly");
  assert.equal((await call("POST", "/v1/trial/start", {})).status, 409);
});

test("gift cards grant premium once and stack on an active subscription", async (t) => {
  const later = Date.now() + 10 * DAY;
  const { db, server, call } = await start({
    "giftcards/GIFT-1234": { months: 3 },
    "users/u2": { premium: { active: true, expiry: later } },
  });
  t.after(() => server.close());
  assert.equal(
    (await call("POST", "/v1/giftcards/redeem", { code: "nope" })).status,
    400,
  );
  assert.equal(
    (await call("POST", "/v1/giftcards/redeem", { code: "MISSING-1" })).status,
    404,
  );
  const r = await call(
    "POST",
    "/v1/giftcards/redeem",
    { code: "gift-1234" },
    "u2",
  );
  assert.equal(r.status, 200);
  const p = db.docs.get("users/u2").premium;
  assert.equal(p.source, "giftcard");
  assert.equal(Math.round((p.expiry - later) / DAY), 90);
  assert.equal(db.docs.get("giftcards/GIFT-1234").redeemedBy, "u2");
  assert.equal(fakeAuth.claims.u2.premium, true);
  assert.equal(
    (await call("POST", "/v1/giftcards/redeem", { code: "GIFT-1234" }, "u1"))
      .status,
    409,
  );
});

test("recommendations come from the last two weeks of nights", async (t) => {
  const now = Date.now();
  const nights = {};
  for (let d = 1; d <= 5; d++) {
    const wokeUp = now - d * DAY;
    // irregular bedtimes and ~5 h asleep: both tips should fire
    const startedAt = wokeUp - (6 + (d % 2) * 2) * 3600e3;
    nights[`users/u1/nights/n${d}`] = {
      wokeUp,
      snoreMinutes: 45,
      lightLux: 9,
      session: {
        startedAt,
        endedAt: wokeUp,
        sleepScore: 60,
        phases: Array.from({ length: 600 }, (_, i) => ({
          t: i,
          phase: i < 600 ? "light" : "awake",
        })),
      },
    };
  }
  const { server, call } = await start(nights);
  t.after(() => server.close());
  const r = await (
    await call("GET", "/v1/insights/recommendations?goalMin=480")
  ).json();
  assert.equal(r.nights, 5);
  const ids = r.items.map((i) => i.id);
  for (const id of ["regular-bedtime", "more-sleep", "snoring", "dark-room"])
    assert.ok(ids.includes(id), id);
});

test("new routes require a token", async (t) => {
  const { server } = await start();
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  for (const p of [
    "/v1/consent",
    "/v1/trial/start",
    "/v1/giftcards/redeem",
    "/v1/devices/register",
  ]) {
    assert.equal((await fetch(base + p, { method: "POST" })).status, 401, p);
  }
});

test("paywall: sticky weighted variant per placement, previews and overrides", async (t) => {
  const { server, call } = await start({
    "users/old": { premium: { active: false, source: "play" } },
    "config/paywalls": {
      variants: {
        campaign: {
          name: "Spring",
          modules: [{ type: "hero", title: "Spring sale" }],
          offers: [{ product: "premium_yearly" }],
          displayInterval: "everyWeek",
        },
      },
    },
  });
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  const get = async (q) => (await fetch(`${base}/v1/paywall?${q}`)).json();
  const a = await get("placement=onboarding&installId=i1");
  const b = await get("placement=onboarding&installId=i1");
  assert.equal(a.variant, b.variant);
  assert.ok(
    [
      "trial_journey",
      "trial_journey_tracking",
      "standard",
      "opt_in_feature_list",
      "two_plan",
    ].includes(a.variant),
  );
  assert.ok(a.config.modules.some((m) => m.type === "pricing"));
  assert.ok(a.products.premium_yearly);
  // every variant shows up for some users
  const seen = new Set();
  for (let i = 0; i < 400; i++)
    seen.add((await get(`placement=onboarding&installId=x${i}`)).variant);
  assert.equal(seen.size, 5);
  assert.ok(
    ["dynamic", "standard"].includes(
      (await get("placement=locked_feature")).variant,
    ),
  );
  const lapsed = await (
    await call("GET", "/v1/paywall?placement=locked_feature", null, "old")
  ).json();
  assert.equal(lapsed.variant, "early_adopter");
  assert.equal(
    (await get("placement=in_app&variant=gift_cards")).config.modules[0].type,
    "gift_cards",
  );
  const c = await get("placement=campaign");
  assert.equal(c.config.modules[0].title, "Spring sale");
  assert.equal(c.config.displayInterval, "everyWeek");
  assert.equal((await get("placement=app_open")).variant, null);
  // signed in, the account id decides (same on every device)
  const u = await (
    await call(
      "GET",
      "/v1/paywall?placement=onboarding&installId=i1",
      null,
      "u9",
    )
  ).json();
  const v = await (
    await call(
      "GET",
      "/v1/paywall?placement=onboarding&installId=i2",
      null,
      "u9",
    )
  ).json();
  assert.equal(u.variant, v.variant);
  assert.equal((await call("GET", "/v1/paywall?placement=nope")).status, 404);
  assert.equal((await call("GET", "/v1/paywall?variant=nope")).status, 404);
});

test("paywall defaults match the app's offline copy", () => {
  const path = require("path");
  const fs = require("fs");
  const app = path.join(__dirname, "../../../flutter_app/assets/paywalls.json");
  if (!fs.existsSync(app)) return;
  assert.deepStrictEqual(
    JSON.parse(fs.readFileSync(app, "utf8")),
    require("../src/paywalls.json"),
  );
});

test("gift cards: a subscriber gets two codes once, and a friend can redeem one", async (t) => {
  const { db, server, call } = await start({
    "users/u1": { premium: { active: true, source: "play" } },
  });
  t.after(() => server.close());
  assert.equal(
    (await call("POST", "/v1/giftcards/issue", {}, "u2")).status,
    403,
  );
  const a = await (await call("POST", "/v1/giftcards/issue", {})).json();
  assert.equal(a.codes.length, 2);
  assert.match(a.codes[0], /^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$/);
  assert.deepStrictEqual(
    (await (await call("POST", "/v1/giftcards/issue", {})).json()).codes,
    a.codes,
  );
  assert.equal(
    (await call("POST", "/v1/giftcards/redeem", { code: a.codes[0] }, "friend"))
      .status,
    200,
  );
  assert.equal(db.docs.get("users/friend").premium.source, "giftcard");
  assert.equal(
    (await call("POST", "/v1/giftcards/issue", {}, "friend")).status,
    403,
  );
});

test("RevenueCat webhook mirrors the premium entitlement", async (t) => {
  const now = Date.now();
  const { db, server } = await start(
    {
      "users/gift": {
        premium: { active: true, source: "giftcard", expiry: now + 30 * DAY },
      },
    },
    { revenueCat: { webhookAuth: "Bearer hook-secret" } },
  );
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  const hook = (event, auth = "Bearer hook-secret") =>
    fetch(`${base}/v1/billing/revenuecat`, {
      method: "POST",
      headers: { authorization: auth, "content-type": "application/json" },
      body: JSON.stringify({ event }),
    });
  assert.equal((await hook({ type: "TEST" }, "Bearer wrong")).status, 401);
  const buy = await hook({
    type: "INITIAL_PURCHASE",
    app_user_id: "u1",
    aliases: ["$RCAnonymousID:abc", "u1"],
    entitlement_ids: ["lulu_wake_pro"],
    product_id: "premium_yearly:yearly",
    period_type: "TRIAL",
    expiration_at_ms: now + 7 * DAY,
    store: "PLAY_STORE",
  });
  assert.deepStrictEqual((await buy.json()).updated, ["u1"]);
  const p = db.docs.get("users/u1").premium;
  assert.deepStrictEqual(
    [p.active, p.source, p.productId, p.trial],
    [true, "store", "premium_yearly", true],
  );
  await hook({
    type: "EXPIRATION",
    app_user_id: "u1",
    entitlement_ids: ["lulu_wake_pro"],
    expiration_at_ms: now - 1000,
  });
  assert.equal(db.docs.get("users/u1").premium.active, false);
  // a running gift card outlives a lapsed store subscription
  await hook({
    type: "EXPIRATION",
    app_user_id: "gift",
    entitlement_ids: ["lulu_wake_pro"],
    expiration_at_ms: now - 1000,
  });
  assert.equal(db.docs.get("users/gift").premium.source, "giftcard");
});

test("billing sync reads the subscriber from RevenueCat", async (t) => {
  const seen = [];
  const fetchImpl = async (url, init) => {
    seen.push([url, init.headers.authorization]);
    return new Response(
      JSON.stringify({
        subscriber: {
          entitlements: {
            lulu_wake_pro: {
              expires_date: new Date(Date.now() + 300 * DAY).toISOString(),
              product_identifier: "premium_yearly",
            },
          },
          subscriptions: {
            premium_yearly: { period_type: "normal", store: "app_store" },
          },
        },
      }),
      { headers: { "content-type": "application/json" } },
    );
  };
  const { db, server, call } = await start(
    {},
    { revenueCat: { apiKey: "sk_test" }, fetchImpl },
  );
  t.after(() => server.close());
  const r = await call("POST", "/v1/billing/sync");
  assert.equal(r.status, 200);
  assert.equal((await r.json()).active, true);
  assert.deepStrictEqual(seen, [
    ["https://api.revenuecat.com/v1/subscribers/u1", "Bearer sk_test"],
  ]);
  assert.equal(db.docs.get("users/u1").premium.store, "app_store");
});
