const test = require("node:test");
const assert = require("node:assert");
const { weeklyReport, noteEffects, DAY } = require("../src/insights");

const MON = Date.UTC(2026, 9, 19); // Monday 19 Oct 2026

function night(
  dayOffset,
  score,
  { notes = [], bedHour = 23, asleepEpochs = 840 } = {},
) {
  const wokeUp = MON + dayOffset * DAY + 7 * 3600e3;
  const startedAt = MON + (dayOffset - 1) * DAY + bedHour * 3600e3;
  const phases = Array.from({ length: 960 }, (_, i) => ({
    t: i,
    phase: i < 960 - asleepEpochs ? "awake" : "light",
  }));
  return {
    wokeUp,
    notes,
    snoreMinutes: 10,
    session: { startedAt, endedAt: wokeUp, sleepScore: score, phases },
  };
}

test("averages, previous-week comparison and best night", () => {
  const nights = [
    night(-5, 60),
    night(-4, 70),
    night(0, 80),
    night(1, 90),
    night(2, 85),
  ];
  const r = weeklyReport(nights, MON);
  assert.equal(r.weekStart, "2026-10-19");
  assert.equal(r.nights, 3);
  assert.equal(r.avgQuality, 85);
  assert.equal(r.previous.avgQuality, 65);
  assert.equal(r.avgAsleepMin, 420);
  assert.equal(r.bestNight.quality, 90);
  assert.match(r.highlights[0], /up 20 points/);
});

test("steady bedtimes score high regularity, scattered ones lower", () => {
  const steady = weeklyReport([night(0, 80), night(1, 80), night(2, 80)], MON);
  const scattered = weeklyReport(
    [night(0, 80, { bedHour: 21 }), night(1, 80, { bedHour: 2 }), night(2, 80)],
    MON,
  );
  assert.equal(steady.regularity, 100);
  assert.ok(scattered.regularity < steady.regularity);
});

test("sleep-note effects compare nights with and without a note", () => {
  const e = noteEffects([
    night(0, 60, { notes: ["Alcohol"] }),
    night(1, 90),
    night(2, 88),
  ]);
  assert.deepStrictEqual(e[0], {
    note: "Alcohol",
    with: 60,
    without: 89,
    delta: -29,
  });
});

test("empty week asks for nights", () => {
  const r = weeklyReport([], MON);
  assert.equal(r.nights, 0);
  assert.match(r.highlights[0], /Track a few nights/);
});
