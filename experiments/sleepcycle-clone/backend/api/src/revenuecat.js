// RevenueCat: the app buys through the RevenueCat SDK (App Store and Google
// Play), RevenueCat validates the receipts, and this service mirrors the
// "premium" entitlement into users/{uid}.premium. The RevenueCat app user id
// is the Firebase uid.

const ENTITLEMENT = "premium";
const API = "https://api.revenuecat.com/v1";

const anonymous = (id) => !id || String(id).startsWith("$RCAnonymousID:");

/** Premium status from a REST v1 subscriber object. */
function premiumFromSubscriber(subscriber, { now = Date.now() } = {}) {
  const ent = ((subscriber && subscriber.entitlements) || {})[ENTITLEMENT];
  if (!ent) return { active: false, source: "store", verifiedAt: now };
  const expiry = ent.expires_date ? Date.parse(ent.expires_date) : null;
  const sub = (subscriber.subscriptions || {})[ent.product_identifier] || {};
  return {
    active: expiry === null || expiry > now,
    source: "store",
    productId: ent.product_identifier || null,
    expiry,
    trial: sub.period_type === "trial",
    store: sub.store || null,
    verifiedAt: now,
  };
}

/** Premium status from a webhook event, when no REST key is configured. */
function premiumFromEvent(ev, { now = Date.now() } = {}) {
  const ids =
    ev.entitlement_ids || (ev.entitlement_id ? [ev.entitlement_id] : []);
  const has = ids.includes(ENTITLEMENT);
  const expiry = ev.expiration_at_ms || null;
  const ended = ev.type === "EXPIRATION" || (expiry !== null && expiry <= now);
  return {
    active: has && !ended,
    source: "store",
    productId: (ev.product_id || "").split(":")[0] || null,
    expiry,
    trial: ev.period_type === "TRIAL",
    store: ev.store || null,
    verifiedAt: now,
  };
}

/** The Firebase uids an event is about (anonymous RevenueCat ids skipped). */
function eventUids(ev) {
  const ids =
    ev.type === "TRANSFER"
      ? [...(ev.transferred_from || []), ...(ev.transferred_to || [])]
      : [ev.app_user_id, ev.original_app_user_id, ...(ev.aliases || [])];
  return [...new Set(ids.filter((id) => !anonymous(id)))];
}

/** GET /v1/subscribers/{uid} with the secret API key. */
async function fetchSubscriber(uid, { apiKey, fetchImpl = fetch }) {
  const r = await fetchImpl(`${API}/subscribers/${encodeURIComponent(uid)}`, {
    headers: { authorization: `Bearer ${apiKey}`, accept: "application/json" },
  });
  if (!r.ok) throw new Error(`RevenueCat ${r.status}`);
  return (await r.json()).subscriber;
}

module.exports = {
  ENTITLEMENT,
  premiumFromSubscriber,
  premiumFromEvent,
  eventUids,
  fetchSubscriber,
};
