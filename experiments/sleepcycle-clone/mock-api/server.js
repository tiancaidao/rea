/*
 * Mock backend for the Sleep Cycle-style client rebuild.
 *
 * Endpoint shape is modelled on the reverse-engineered app
 * (com.northcube.sleepcycle): an Ory-style identity surface, a session upload
 * service ("teratron"), an insights service ("syndicate"), and remote config.
 * It returns plausible fake data so the client can be built and run before any
 * real server exists. No real Sleep Cycle endpoints are contacted.
 *
 *   node server.js      # listens on :8787
 */
const http = require("http");

const json = (res, code, body) => {
  const s = JSON.stringify(body);
  res.writeHead(code, { "content-type": "application/json", "content-length": Buffer.byteLength(s) });
  res.end(s);
};
const uuid = () => "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
  const r = (Math.random() * 16) | 0; return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
});

const sessions = []; // in-memory uploaded sleep sessions

const routes = {
  // --- Ory Kratos-style identity (auth.sleepcycle.com / client-auth.sdk...) ---
  "GET /sessions/whoami": () => ({ id: uuid(), identity: { id: uuid(), traits: { email: "demo@example.com" } } }),
  "POST /self-service/login/api": () => ({ session_token: "mock-" + uuid(), session: { active: true } }),

  // --- remote config / dynamic paywall (resources.sdk.sleepcycle.com) ---
  "GET /v1/config": () => ({
    features: { snoreDetection: true, sleepAid: true, wearCompanion: false },
    experiments: { paywall_variant: "control" },
  }),
  "GET /v1/paywall": () => ({
    id: "dynamic-default",
    products: [
      { sku: "yearly", price: "$39.99", trialDays: 7 },
      { sku: "monthly", price: "$6.99", trialDays: 0 },
    ],
  }),

  // --- session upload ("teratron") ---
  "POST /v1/sessions": (body) => {
    const s = { id: uuid(), receivedAt: Date.now(), ...body };
    sessions.push(s);
    return { id: s.id, status: "stored" };
  },
  "GET /v1/sessions": () => ({ sessions }),

  // --- insights ("syndicate") ---
  "GET /v1/insights": () => ({
    sleepScore: 78,
    timeAsleepMin: 431,
    snorePercent: 12,
    phases: [
      { t: 0, phase: "awake" }, { t: 15, phase: "light" }, { t: 60, phase: "deep" },
      { t: 150, phase: "rem" }, { t: 210, phase: "light" }, { t: 420, phase: "awake" },
    ],
  }),
};

http.createServer((req, res) => {
  let raw = "";
  req.on("data", c => (raw += c));
  req.on("end", () => {
    const key = `${req.method} ${req.url.split("?")[0]}`;
    const handler = routes[key];
    if (!handler) return json(res, 404, { error: "no mock for " + key, known: Object.keys(routes) });
    let body = {};
    try { body = raw ? JSON.parse(raw) : {}; } catch { /* ignore */ }
    json(res, 200, handler(body));
  });
}).listen(8787, () => console.log("mock Sleep Cycle API on http://127.0.0.1:8787"));
