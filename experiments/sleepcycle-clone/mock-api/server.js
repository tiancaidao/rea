/*
 * Mock backend for the Sleep Cycle-style client rebuild.
 *
 * Fuller version: token auth, sessions persisted to disk, and insights computed
 * from whatever sessions have been uploaded. Endpoint shape is modelled on the
 * reverse-engineered app (Ory-style identity, a session upload service, an
 * insights service, remote config / dynamic paywall). Zero dependencies.
 *
 *   node server.js      # listens on :8787
 *
 * This is a stand-in so the client can be built and run before a real backend
 * exists. For production you'd stand up Ory Kratos+Hydra + your own API; nothing
 * here contacts any real Sleep Cycle endpoint.
 */
const http = require("http");
const fs = require("fs");
const path = require("path");

const DB_FILE = path.join(__dirname, "mock-db.json");
const db = loadDb();

function loadDb() {
  try {
    return JSON.parse(fs.readFileSync(DB_FILE, "utf8"));
  } catch {
    return { users: {}, sessions: [] };
  }
}
function saveDb() {
  try { fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2)); } catch {}
}

const json = (res, code, body) => {
  const s = JSON.stringify(body);
  res.writeHead(code, { "content-type": "application/json", "content-length": Buffer.byteLength(s) });
  res.end(s);
};
const uuid = () => "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
  const r = (Math.random() * 16) | 0; return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
});
const tokenFor = (id) => Buffer.from(`${id}:${Date.now()}`).toString("base64url");
const userFromAuth = (req) => {
  const h = req.headers["authorization"] || "";
  const tok = h.replace(/^Bearer\s+/i, "");
  try { return Buffer.from(tok, "base64url").toString().split(":")[0]; } catch { return null; }
};

function computeInsights(sessions) {
  if (!sessions.length) {
    return { sleepScore: 0, timeAsleepMin: 0, snorePercent: 0, nights: 0, phases: [] };
  }
  const last = sessions[sessions.length - 1];
  const avg = (f) => Math.round(sessions.reduce((a, s) => a + (s[f] || 0), 0) / sessions.length);
  return {
    sleepScore: avg("sleepScore"),
    timeAsleepMin: last.minutesAsleep || 0,
    snorePercent: Math.round(last.snorePercent || 0),
    nights: sessions.length,
    phases: last.phases || [],
  };
}

const routes = {
  // --- Ory Kratos-style identity ---
  "POST /self-service/registration/api": (b) => {
    const id = uuid();
    db.users[id] = { id, email: b.email || "demo@example.com" };
    saveDb();
    return { session_token: tokenFor(id), identity: db.users[id] };
  },
  "POST /self-service/login/api": (b) => {
    let user = Object.values(db.users).find((u) => u.email === b.email);
    if (!user) { const id = uuid(); user = { id, email: b.email || "demo@example.com" }; db.users[id] = user; saveDb(); }
    return { session_token: tokenFor(user.id), identity: user };
  },
  "GET /sessions/whoami": (_b, req) => {
    const uid = userFromAuth(req);
    const u = uid && db.users[uid];
    return u ? { active: true, identity: u } : { active: false };
  },

  // --- remote config / dynamic paywall ---
  "GET /v1/config": () => ({
    features: { snoreDetection: true, sleepAid: true, wearCompanion: false, healthSync: true },
    experiments: { paywall_variant: "control" },
  }),
  "GET /v1/paywall": () => ({
    id: "dynamic-default",
    products: [
      { sku: "yearly", title: "Yearly", price: "$39.99", trialDays: 7, highlight: true },
      { sku: "monthly", title: "Monthly", price: "$6.99", trialDays: 0, highlight: false },
    ],
  }),

  // --- sleep-aid content catalog ---
  "GET /v1/sleep-aid": () => ({
    packages: [
      { id: "rain", title: "Rain on a tent", durationMin: 45, url: "" },
      { id: "waves", title: "Ocean waves", durationMin: 60, url: "" },
      { id: "story", title: "Bedtime story: The Lighthouse", durationMin: 25, url: "" },
    ],
  }),

  // --- session upload + listing ---
  "POST /v1/sessions": (b, req) => {
    const uid = userFromAuth(req) || "anon";
    const s = { id: uuid(), userId: uid, receivedAt: Date.now(), ...b };
    db.sessions.push(s);
    saveDb();
    return { id: s.id, status: "stored", nights: db.sessions.filter((x) => x.userId === uid).length };
  },
  "GET /v1/sessions": (_b, req) => {
    const uid = userFromAuth(req) || "anon";
    return { sessions: db.sessions.filter((s) => s.userId === uid) };
  },

  // --- insights computed from uploaded sessions ---
  "GET /v1/insights": (_b, req) => {
    const uid = userFromAuth(req) || "anon";
    const mine = db.sessions.filter((s) => s.userId === uid);
    return computeInsights(mine.length ? mine : db.sessions);
  },
};

http.createServer((req, res) => {
  let raw = "";
  req.on("data", (c) => (raw += c));
  req.on("end", () => {
    const key = `${req.method} ${req.url.split("?")[0]}`;
    const handler = routes[key];
    if (!handler) return json(res, 404, { error: "no mock for " + key, known: Object.keys(routes) });
    let body = {};
    try { body = raw ? JSON.parse(raw) : {}; } catch { /* ignore */ }
    try { json(res, 200, handler(body, req)); }
    catch (e) { json(res, 500, { error: String(e) }); }
  });
}).listen(8787, () => console.log("mock Sleep Cycle API on http://127.0.0.1:8787"));
