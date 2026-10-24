// StoreKit 2 transaction verification against a throwaway CA built with
// openssl (root → intermediate → leaf, P-256), pinned in place of Apple's.
const test = require("node:test");
const assert = require("node:assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");
const { verifyTransaction, premiumFrom } = require("../src/apple");

function makeChain() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "sk2-"));
  const o = (...a) => execFileSync("openssl", a, { cwd: dir, stdio: "pipe" });
  const ext = path.join(dir, "ca.ext");
  fs.writeFileSync(
    ext,
    "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign\n",
  );
  for (const n of ["root", "int", "leaf"])
    o(
      "ecparam",
      "-name",
      "prime256v1",
      "-genkey",
      "-noout",
      "-out",
      `${n}.key`,
    );
  o(
    "req",
    "-x509",
    "-new",
    "-key",
    "root.key",
    "-subj",
    "/CN=Test Root",
    "-days",
    "30",
    "-out",
    "root.pem",
  );
  o(
    "req",
    "-new",
    "-key",
    "int.key",
    "-subj",
    "/CN=Test Int",
    "-out",
    "int.csr",
  );
  o(
    "x509",
    "-req",
    "-in",
    "int.csr",
    "-CA",
    "root.pem",
    "-CAkey",
    "root.key",
    "-CAcreateserial",
    "-days",
    "30",
    "-extfile",
    ext,
    "-out",
    "int.pem",
  );
  o(
    "req",
    "-new",
    "-key",
    "leaf.key",
    "-subj",
    "/CN=Test Leaf",
    "-out",
    "leaf.csr",
  );
  o(
    "x509",
    "-req",
    "-in",
    "leaf.csr",
    "-CA",
    "int.pem",
    "-CAkey",
    "int.key",
    "-CAcreateserial",
    "-days",
    "30",
    "-out",
    "leaf.pem",
  );
  const der = (n) =>
    new crypto.X509Certificate(fs.readFileSync(path.join(dir, `${n}.pem`))).raw;
  const leafKey = crypto.createPrivateKey(
    fs.readFileSync(path.join(dir, "leaf.key")),
  );
  return {
    x5c: ["leaf", "int", "root"].map((n) => der(n).toString("base64")),
    rootRaw: der("root"),
    leafKey,
  };
}

const b64u = (b) => Buffer.from(b).toString("base64url");

function sign(chain, payload, key = chain.leafKey) {
  const h = b64u(JSON.stringify({ alg: "ES256", x5c: chain.x5c }));
  const p = b64u(JSON.stringify(payload));
  const sig = crypto.sign("sha256", Buffer.from(`${h}.${p}`), {
    key,
    dsaEncoding: "ieee-p1363",
  });
  return `${h}.${p}.${b64u(sig)}`;
}

let chain;
try {
  chain = makeChain();
} catch {
  chain = null;
}

test(
  "a StoreKit 2 transaction verifies against the pinned root",
  { skip: !chain && "openssl missing" },
  () => {
    const rootSha256 = crypto
      .createHash("sha256")
      .update(chain.rootRaw)
      .digest("hex");
    const now = Date.now();
    const tx = {
      bundleId: "com.matchlab.lullwake",
      productId: "premium_yearly",
      expiresDate: now + 7 * 864e5,
      offerType: 1,
      offerDiscountType: "FREE_TRIAL",
      originalTransactionId: "1000",
    };
    const jws = sign(chain, tx);
    const out = verifyTransaction(jws, { rootSha256 });
    assert.equal(out.productId, "premium_yearly");
    const p = premiumFrom(out, { bundleId: "com.matchlab.lullwake", now });
    assert.deepStrictEqual(
      [p.active, p.trial, p.store],
      [true, true, "app_store"],
    );
    assert.equal(
      premiumFrom({ ...tx, expiresDate: now - 1 }, { now }).active,
      false,
    );
    assert.equal(
      premiumFrom({ ...tx, revocationDate: now }, { now }).state,
      "REVOKED",
    );
    assert.throws(
      () => premiumFrom(tx, { bundleId: "com.other.app" }),
      /another app/,
    );
    // tampered payload, wrong root, wrong signer
    const [h, , s] = jws.split(".");
    assert.throws(
      () =>
        verifyTransaction(
          `${h}.${b64u(JSON.stringify({ ...tx, productId: "x" }))}.${s}`,
          { rootSha256 },
        ),
      /signature/,
    );
    assert.throws(() => verifyTransaction(jws), /not signed by Apple/);
    const other = crypto.generateKeyPairSync("ec", {
      namedCurve: "prime256v1",
    }).privateKey;
    assert.throws(
      () => verifyTransaction(sign(chain, tx, other), { rootSha256 }),
      /signature/,
    );
    assert.throws(() => verifyTransaction("abc"), /not a signed/);
  },
);
