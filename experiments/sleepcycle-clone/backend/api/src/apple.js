// App Store purchases: verify a StoreKit 2 signed transaction (JWS) without
// any App Store Connect secret. The JWS header carries the certificate chain
// (x5c): leaf → Apple intermediate → Apple Root CA - G3. We check each link,
// pin the root by its SHA-256 fingerprint, then check the ES256 signature
// with the leaf key and read the transaction.

const crypto = require('crypto');

// Apple Root CA - G3 (https://www.apple.com/certificateauthority/), SHA-256
const APPLE_ROOT_G3_SHA256 = (process.env.APPLE_ROOT_SHA256 ||
  '63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179').toLowerCase();

function fail(msg) {
  const e = new Error(msg);
  e.status = 400;
  return e;
}

const b64url = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

/**
 * Verify a StoreKit 2 JWS transaction and return its payload.
 * [rootSha256] is injectable for tests.
 */
function verifyTransaction(jws, { now = Date.now(), rootSha256 = APPLE_ROOT_G3_SHA256 } = {}) {
  const parts = String(jws || '').split('.');
  if (parts.length !== 3) throw fail('not a signed transaction');
  const header = JSON.parse(b64url(parts[0]).toString('utf8'));
  if (header.alg !== 'ES256' || !Array.isArray(header.x5c) || header.x5c.length < 3) {
    throw fail('unexpected transaction header');
  }
  const certs = header.x5c.map((c) => new crypto.X509Certificate(Buffer.from(c, 'base64')));
  const root = certs[certs.length - 1];
  const fp = crypto.createHash('sha256').update(root.raw).digest('hex');
  if (fp !== rootSha256) throw fail('transaction not signed by Apple');
  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].verify(certs[i + 1].publicKey)) throw fail('broken certificate chain');
    const from = Date.parse(certs[i].validFrom), to = Date.parse(certs[i].validTo);
    if (now < from || now > to) throw fail('certificate expired');
  }
  const ok = crypto.verify(
    'sha256',
    Buffer.from(`${parts[0]}.${parts[1]}`),
    { key: certs[0].publicKey, dsaEncoding: 'ieee-p1363' },
    b64url(parts[2]),
  );
  if (!ok) throw fail('bad transaction signature');
  return JSON.parse(b64url(parts[1]).toString('utf8'));
}

/** Premium status from a verified transaction payload. */
function premiumFrom(tx, { bundleId, now = Date.now() } = {}) {
  if (bundleId && tx.bundleId !== bundleId) throw fail('transaction is for another app');
  const expiry = tx.expiresDate || null;
  const active = !tx.revocationDate && (expiry == null || expiry > now);
  return {
    active,
    state: tx.revocationDate ? 'REVOKED' : active ? 'ACTIVE' : 'EXPIRED',
    productId: tx.productId || null,
    expiry,
    trial: tx.offerType === 1 && tx.offerDiscountType === 'FREE_TRIAL',
    store: 'app_store',
    originalTransactionId: tx.originalTransactionId || null,
    environment: tx.environment || null,
    verifiedAt: now,
  };
}

module.exports = { verifyTransaction, premiumFrom, APPLE_ROOT_G3_SHA256 };
