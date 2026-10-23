// Route tests against an in-memory Firestore (no emulators needed).
const test = require('node:test');
const assert = require('node:assert');
const { createApp } = require('../src/app');
const { makeDb, fakeAuth } = require('./fake_firestore');

const DAY = 86400e3;

async function start(initial) {
  const db = makeDb(initial);
  const server = createApp({ db, auth: fakeAuth, bucket: null }).listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = (method, path, body, uid = 'u1') => fetch(base + path, {
    method,
    headers: { authorization: `Bearer uid:${uid}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { db, server, call };
}

test('consent is validated and stored with a timestamp', async (t) => {
  const { db, server, call } = await start();
  t.after(() => server.close());
  assert.equal((await call('POST', '/v1/consent', { storage: true })).status, 400);
  const r = await call('POST', '/v1/consent', { storage: true, sounds: false, product: true });
  assert.equal(r.status, 200);
  const stored = db.docs.get('users/u1').consent;
  assert.deepStrictEqual([stored.storage, stored.sounds, stored.product], [true, false, true]);
  assert.ok(stored.updatedAt > 0);
});

test('device registration hashes the token into the doc id', async (t) => {
  const { db, server, call } = await start();
  t.after(() => server.close());
  assert.equal((await call('POST', '/v1/devices/register', { token: 'abc', platform: 'android' })).status, 400);
  const r = await (await call('POST', '/v1/devices/register', { token: 'fcm-token-123', platform: 'android' })).json();
  assert.match(r.id, /^[0-9a-f]{32}$/);
  assert.equal(db.docs.get(`users/u1/devices/${r.id}`).platform, 'android');
});

test('user properties are whitelisted', async (t) => {
  const { db, server, call } = await start();
  t.after(() => server.close());
  assert.equal((await call('POST', '/v1/user/properties', { premium: 'yes' })).status, 400);
  assert.equal((await call('POST', '/v1/user/properties', { units: 'Metric', birth: '1990' })).status, 200);
  assert.deepStrictEqual(db.docs.get('users/u1').properties, { units: 'Metric', birth: '1990' });
});

test('trial starts once with the configured length', async (t) => {
  const { db, server, call } = await start({ 'config/app': { paywall: { trialDays: 14 } } });
  t.after(() => server.close());
  const r = await call('POST', '/v1/trial/start', { productId: 'premium_yearly' });
  assert.equal(r.status, 200);
  const trial = await r.json();
  assert.equal(Math.round((trial.endsAt - trial.startedAt) / DAY), 14);
  assert.equal(db.docs.get('users/u1').trial.productId, 'premium_yearly');
  assert.equal((await call('POST', '/v1/trial/start', {})).status, 409);
});

test('gift cards grant premium once and stack on an active subscription', async (t) => {
  const later = Date.now() + 10 * DAY;
  const { db, server, call } = await start({
    'giftcards/GIFT-1234': { months: 3 },
    'users/u2': { premium: { active: true, expiry: later } },
  });
  t.after(() => server.close());
  assert.equal((await call('POST', '/v1/giftcards/redeem', { code: 'nope' })).status, 400);
  assert.equal((await call('POST', '/v1/giftcards/redeem', { code: 'MISSING-1' })).status, 404);
  const r = await call('POST', '/v1/giftcards/redeem', { code: 'gift-1234' }, 'u2');
  assert.equal(r.status, 200);
  const p = db.docs.get('users/u2').premium;
  assert.equal(p.source, 'giftcard');
  assert.equal(Math.round((p.expiry - later) / DAY), 90);
  assert.equal(db.docs.get('giftcards/GIFT-1234').redeemedBy, 'u2');
  assert.equal(fakeAuth.claims.u2.premium, true);
  assert.equal((await call('POST', '/v1/giftcards/redeem', { code: 'GIFT-1234' }, 'u1')).status, 409);
});

test('recommendations come from the last two weeks of nights', async (t) => {
  const now = Date.now();
  const nights = {};
  for (let d = 1; d <= 5; d++) {
    const wokeUp = now - d * DAY;
    // irregular bedtimes and ~5 h asleep: both tips should fire
    const startedAt = wokeUp - (6 + (d % 2) * 2) * 3600e3;
    nights[`users/u1/nights/n${d}`] = {
      wokeUp, snoreMinutes: 45, lightLux: 9,
      session: { startedAt, endedAt: wokeUp, sleepScore: 60,
        phases: Array.from({ length: 600 }, (_, i) => ({ t: i, phase: i < 600 ? 'light' : 'awake' })) },
    };
  }
  const { server, call } = await start(nights);
  t.after(() => server.close());
  const r = await (await call('GET', '/v1/insights/recommendations?goalMin=480')).json();
  assert.equal(r.nights, 5);
  const ids = r.items.map((i) => i.id);
  for (const id of ['regular-bedtime', 'more-sleep', 'snoring', 'dark-room']) assert.ok(ids.includes(id), id);
});

test('new routes require a token', async (t) => {
  const { server } = await start();
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;
  for (const p of ['/v1/consent', '/v1/trial/start', '/v1/giftcards/redeem', '/v1/devices/register']) {
    assert.equal((await fetch(base + p, { method: 'POST' })).status, 401, p);
  }
});
