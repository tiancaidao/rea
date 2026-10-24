// Server-driven paywalls: which variant a user sees for a placement, and the
// module list the app renders for it. Defaults live in paywalls.json; the
// Firestore doc config/paywalls can override products, placements or single
// variants without a release.

const crypto = require("crypto");
const DEFAULTS = require("./paywalls.json");

const INTERVALS = [
  "never",
  "everyAppOpening",
  "everyDay",
  "everySecondDay",
  "everyThirdDay",
  "everyWeek",
];

function merge(base, override) {
  if (!override) return base;
  return {
    products: { ...base.products, ...(override.products || {}) },
    placements: { ...base.placements, ...(override.placements || {}) },
    variants: { ...base.variants, ...(override.variants || {}) },
  };
}

// Sticky bucket 0..99 for a subject in an experiment.
function bucket(experiment, subject) {
  const h = crypto
    .createHash("sha256")
    .update(`${experiment}:${subject}`)
    .digest();
  return h.readUInt32BE(0) % 100;
}

/**
 * Pick the variant for [placement]. [subject] is the uid, or the install id
 * before sign-in; [forced] (a variant id) is for previews and QA.
 * Returns null when the placement shows nothing.
 */
function choosePaywall(cfg, placement, subject, forced) {
  const p = cfg.placements[placement];
  if (!p) {
    const e = new Error(`unknown placement ${placement}`);
    e.status = 404;
    throw e;
  }
  let id = null;
  let b = null;
  if (forced) {
    if (!cfg.variants[forced]) {
      const e = new Error(`unknown variant ${forced}`);
      e.status = 404;
      throw e;
    }
    id = forced;
  } else {
    const variants = (p.variants || []).filter(
      (v) => cfg.variants[v.id] && v.weight > 0,
    );
    const total = variants.reduce((s, v) => s + v.weight, 0);
    if (total === 0) return null;
    b = bucket(p.experiment || placement, subject || "anonymous");
    let at = (b / 100) * total;
    for (const v of variants) {
      if (at < v.weight) {
        id = v.id;
        break;
      }
      at -= v.weight;
    }
    id = id || variants[variants.length - 1].id;
  }
  const variant = cfg.variants[id];
  const displayInterval = INTERVALS.includes(variant.displayInterval)
    ? variant.displayInterval
    : "never";
  const products = {};
  for (const o of variant.offers || []) {
    if (cfg.products[o.product]) products[o.product] = cfg.products[o.product];
  }
  return {
    placement,
    experiment: p.experiment || placement,
    bucket: b,
    variant: id,
    config: { ...variant, displayInterval },
    products,
  };
}

module.exports = { DEFAULTS, merge, bucket, choosePaywall, INTERVALS };
