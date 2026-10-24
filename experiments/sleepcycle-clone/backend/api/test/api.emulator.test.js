// End-to-end tests against the Firebase emulators. Skipped unless they're
// running:   cd backend && npm run emulators   (then npm test in api/)
const test = require("node:test");
const assert = require("node:assert");

const PROJECT = "demo-sleep-tracker";
const AUTH = "127.0.0.1:9099";
const FS = "127.0.0.1:8085";
const ST = "127.0.0.1:9199";

async function up(host) {
  try {
    await fetch(`http://${host}/`);
    return true;
  } catch {
    return false;
  }
}

test("API against emulators", async (t) => {
  if (!(await up(AUTH)) || !(await up(FS))) {
    t.skip("emulators not running");
    return;
  }
  process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH;
  process.env.FIRESTORE_EMULATOR_HOST = FS;
  process.env.FIREBASE_STORAGE_EMULATOR_HOST = ST;
  const { initializeApp } = require("firebase-admin/app");
  const { getAuth } = require("firebase-admin/auth");
  const { getFirestore } = require("firebase-admin/firestore");
  const { getStorage } = require("firebase-admin/storage");
  const { createApp } = require("../src/app");
  initializeApp(
    { projectId: PROJECT, storageBucket: `${PROJECT}.appspot.com` },
    "test",
  );
  const { getApp } = require("firebase-admin/app");
  const fa = getApp("test");
  const db = getFirestore(fa);
  const auth = getAuth(fa);

  const weather = async () => ({
    ok: true,
    json: async () => ({
      current: {
        temperature_2m: 20,
        weather_code: 3,
        time: "2026-10-21T07:00",
      },
    }),
  });
  const server = createApp({
    db,
    auth,
    bucket: getStorage(fa).bucket(),
    fetchImpl: weather,
  }).listen(0);
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;

  // sign up a user on the Auth emulator and get an ID token
  const email = `u${Date.now()}@example.com`;
  const signUp = await (
    await fetch(
      `http://${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`,
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          email,
          password: "secret123",
          returnSecureToken: true,
        }),
      },
    )
  ).json();
  const { idToken, localId: uid } = signUp;
  const H = {
    authorization: `Bearer ${idToken}`,
    "content-type": "application/json",
  };

  await t.test("config is public", async () => {
    const r = await fetch(`${base}/v1/config`);
    assert.equal(r.status, 200);
    assert.equal((await r.json()).paywall.trialDays, 7);
  });

  await t.test("protected routes need a valid token", async () => {
    assert.equal((await fetch(`${base}/v1/sleep-aid/catalog`)).status, 401);
    assert.equal(
      (
        await fetch(`${base}/v1/sleep-aid/catalog`, {
          headers: { authorization: "Bearer nope" },
        })
      ).status,
      401,
    );
  });

  await t.test("catalog returns media URLs for seeded items", async () => {
    const j = await (
      await fetch(`${base}/v1/sleep-aid/catalog`, { headers: H })
    ).json();
    if (!j.sections.length)
      return t.skip("catalog not seeded (npm run seed:emulators)");
    const withUrl = j.sections.flatMap((s) => s.items).filter((i) => i.url);
    assert.ok(withUrl.length > 0);
    assert.match(withUrl[0].url, /alt=media/);
  });

  await t.test(
    "weekly report is computed from the user's nights and stored",
    async () => {
      const mon = Date.UTC(2026, 9, 19);
      for (let d = 0; d < 3; d++) {
        const wokeUp = mon + d * 86400e3 + 7 * 3600e3;
        await db.doc(`users/${uid}/nights/n${d}`).set({
          wokeUp,
          notes: [],
          snoreMinutes: 5,
          session: {
            startedAt: wokeUp - 8 * 3600e3,
            endedAt: wokeUp,
            sleepScore: 70 + d * 10,
            phases: [{ t: 0, phase: "light" }],
          },
        });
      }
      const r = await (
        await fetch(`${base}/v1/insights/weekly?weekStart=2026-10-19`, {
          headers: H,
        })
      ).json();
      assert.equal(r.nights, 3);
      assert.equal(r.avgQuality, 80);
      assert.ok((await db.doc(`users/${uid}/reports/2026-10-19`).get()).exists);
    },
  );

  await t.test("weather is proxied with rounded coordinates", async () => {
    const r = await (
      await fetch(`${base}/v1/weather?lat=1.3521&lon=103.8198`, { headers: H })
    ).json();
    assert.deepStrictEqual(
      [r.tempC, r.tempF, r.description],
      [20, 68, "Overcast"],
    );
    assert.equal(
      (await fetch(`${base}/v1/weather`, { headers: H })).status,
      400,
    );
  });

  await t.test(
    "billing sync reports when RevenueCat is not configured",
    async () => {
      const r = await fetch(`${base}/v1/billing/sync`, {
        method: "POST",
        headers: H,
      });
      assert.equal(r.status, 501);
    },
  );

  await t.test(
    "security rules: owner can write nights, not premium or others' data",
    async () => {
      const doc = (p) =>
        `http://${FS}/v1/projects/${PROJECT}/databases/(default)/documents/${p}`;
      const patch = (p, fields, token = idToken) =>
        fetch(doc(p), {
          method: "PATCH",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({ fields }),
        });
      const night = {
        wokeUp: { integerValue: "1" },
        session: {
          mapValue: { fields: { phases: { arrayValue: { values: [] } } } },
        },
      };
      assert.equal(
        (await patch(`users/${uid}/nights/mine`, night)).status,
        200,
      );
      assert.equal(
        (await patch(`users/someone-else/nights/x`, night)).status,
        403,
      );
      assert.equal(
        (await patch(`users/${uid}`, { email: { stringValue: email } })).status,
        200,
      );
      assert.equal(
        (
          await patch(`users/${uid}`, {
            premium: {
              mapValue: { fields: { active: { booleanValue: true } } },
            },
          })
        ).status,
        403,
      );
      assert.equal(
        (await patch(`users/${uid}/reports/w`, { a: { integerValue: "1" } }))
          .status,
        403,
      );
    },
  );

  await t.test(
    "erase data keeps the account; delete removes both",
    async () => {
      assert.equal(
        (
          await fetch(`${base}/v1/account/erase-data`, {
            method: "POST",
            headers: H,
          })
        ).status,
        200,
      );
      assert.equal((await db.collection(`users/${uid}/nights`).get()).size, 0);
      assert.equal(
        (
          await fetch(`${base}/v1/account/delete`, {
            method: "POST",
            headers: H,
          })
        ).status,
        200,
      );
      await assert.rejects(auth.getUser(uid));
    },
  );
});
