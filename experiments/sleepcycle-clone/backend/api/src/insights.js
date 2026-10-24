// Weekly report computed from a user's nights (the Journal's weekly report).
// Pure functions so they can be unit-tested without Firestore.

const DAY = 24 * 60 * 60 * 1000;

const mean = (xs) =>
  xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;

function stddev(xs) {
  if (xs.length < 2) return 0;
  const m = mean(xs);
  return Math.sqrt(mean(xs.map((x) => (x - m) ** 2)));
}

/** Minutes since 18:00 local-ish, so bedtimes around midnight sort on one axis. */
function clockMinutes(ms, tzOffsetMin = 0) {
  const d = new Date(ms + tzOffsetMin * 60000);
  return ((d.getUTCHours() - 18 + 24) % 24) * 60 + d.getUTCMinutes();
}

function asleepMinutes(n) {
  const phases = (n.session && n.session.phases) || [];
  return Math.round(
    (phases.filter((p) => p.phase !== "awake").length * 30) / 60,
  );
}

function summarize(nights, tzOffsetMin) {
  const q = nights.map((n) => n.session.sleepScore);
  const asleep = nights.map(asleepMinutes);
  const bed = nights.map((n) => clockMinutes(n.session.startedAt, tzOffsetMin));
  const wake = nights.map((n) => clockMinutes(n.session.endedAt, tzOffsetMin));
  return {
    nights: nights.length,
    avgQuality: q.length ? Math.round(mean(q)) : null,
    avgAsleepMin: asleep.length ? Math.round(mean(asleep)) : null,
    avgSnoreMin: nights.length
      ? Math.round(mean(nights.map((n) => n.snoreMinutes || 0)))
      : null,
    // regularity: 100 when bed & wake times never move, falling with spread
    regularity: nights.length
      ? Math.max(0, Math.round(100 - (stddev(bed) + stddev(wake)) / 2))
      : null,
  };
}

/** Average quality on nights with vs. without each sleep note (min 1 each). */
function noteEffects(nights) {
  const all = new Set(nights.flatMap((n) => n.notes || []));
  const out = [];
  for (const note of all) {
    const withN = nights
      .filter((n) => (n.notes || []).includes(note))
      .map((n) => n.session.sleepScore);
    const without = nights
      .filter((n) => !(n.notes || []).includes(note))
      .map((n) => n.session.sleepScore);
    if (withN.length && without.length) {
      out.push({
        note,
        with: Math.round(mean(withN)),
        without: Math.round(mean(without)),
        delta: Math.round(mean(withN) - mean(without)),
      });
    }
  }
  return out.sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta));
}

/**
 * @param nights all nights in [weekStart - 7d, weekStart + 7d) (Night JSON as the app stores it)
 * @param weekStartMs start of the report week (UTC ms)
 */
function weeklyReport(nights, weekStartMs, tzOffsetMin = 0) {
  const inRange = (a, b) => nights.filter((n) => n.wokeUp >= a && n.wokeUp < b);
  const week = inRange(weekStartMs, weekStartMs + 7 * DAY);
  const prev = inRange(weekStartMs - 7 * DAY, weekStartMs);
  const cur = summarize(week, tzOffsetMin);
  const before = summarize(prev, tzOffsetMin);
  const best = week.reduce(
    (b, n) => (!b || n.session.sleepScore > b.session.sleepScore ? n : b),
    null,
  );
  const highlights = [];
  if (cur.nights === 0) {
    highlights.push("Track a few nights this week to get your report.");
  } else {
    if (before.avgQuality != null) {
      const d = cur.avgQuality - before.avgQuality;
      highlights.push(
        d >= 0
          ? `Quality up ${d} points on last week.`
          : `Quality down ${-d} points on last week.`,
      );
    }
    if (cur.regularity != null) {
      highlights.push(
        cur.regularity >= 80
          ? "Your bed and wake times were steady — keep it up."
          : "Bed and wake times moved around; a steadier rhythm usually helps quality.",
      );
    }
    const eff = noteEffects(week)[0];
    if (eff && Math.abs(eff.delta) >= 5) {
      highlights.push(
        `Nights with "${eff.note}" scored ${Math.abs(eff.delta)} points ${eff.delta > 0 ? "higher" : "lower"}.`,
      );
    }
  }
  return {
    weekStart: new Date(weekStartMs).toISOString().slice(0, 10),
    ...cur,
    previous: before,
    bestNight: best
      ? { wokeUp: best.wokeUp, quality: best.session.sleepScore }
      : null,
    noteEffects: noteEffects(week),
    highlights,
  };
}

module.exports = { weeklyReport, noteEffects, summarize, clockMinutes, DAY };
