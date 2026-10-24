// Minimal in-memory stand-in for the slice of Firestore the API uses
// (doc get/set/update, collection().where().get(), runTransaction), so the
// routes can be tested without the emulators.

function makeDb(initial = {}) {
  const docs = new Map(Object.entries(initial));
  const snap = (path) => ({
    exists: docs.has(path),
    id: path.split("/").pop(),
    data: () => (docs.has(path) ? structuredClone(docs.get(path)) : undefined),
  });
  const merge = (a, b) => {
    const out = { ...a };
    for (const [k, v] of Object.entries(b)) {
      out[k] =
        v &&
        typeof v === "object" &&
        !Array.isArray(v) &&
        a &&
        typeof a[k] === "object"
          ? merge(a[k], v)
          : v;
    }
    return out;
  };
  const doc = (path) => ({
    path,
    get: async () => snap(path),
    set: async (data, opts = {}) => {
      docs.set(
        path,
        opts.merge ? merge(docs.get(path) || {}, data) : structuredClone(data),
      );
    },
    update: async (data) => {
      if (!docs.has(path))
        throw Object.assign(new Error("not found"), { code: 404 });
      docs.set(path, merge(docs.get(path), data));
    },
  });
  const collection = (path) => {
    const filters = [];
    const q = {
      where(field, op, value) {
        filters.push([field, op, value]);
        return q;
      },
      async get() {
        const prefix = `${path}/`;
        const ok = (d) =>
          filters.every(
            ([f, op, v]) =>
              ({
                ">=": d[f] >= v,
                "<": d[f] < v,
                "<=": d[f] <= v,
                ">": d[f] > v,
                "==": d[f] === v,
              })[op],
          );
        const out = [...docs.keys()]
          .filter(
            (k) =>
              k.startsWith(prefix) && !k.slice(prefix.length).includes("/"),
          )
          .map(snap)
          .filter((s) => ok(s.data()));
        return { docs: out, size: out.length };
      },
      doc: (id) => doc(`${path}/${id}`),
    };
    return q;
  };
  return {
    docs,
    doc,
    collection,
    async runTransaction(fn) {
      // serialised: good enough for tests
      const tx = {
        get: (ref) => ref.get(),
        set: (ref, data, opts) => ref.set(data, opts),
        update: (ref, data) => ref.update(data),
      };
      return fn(tx);
    },
  };
}

const fakeAuth = {
  claims: {},
  async verifyIdToken(t) {
    if (!t.startsWith("uid:")) throw new Error("bad token");
    return { uid: t.slice(4) };
  },
  async setCustomUserClaims(uid, c) {
    this.claims[uid] = c;
  },
};

module.exports = { makeDb, fakeAuth };
