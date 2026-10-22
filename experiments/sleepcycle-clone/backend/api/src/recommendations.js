// Personal recommendations from the user's recent nights (the original's
// insights / recommendations feed). Pure functions so they can be unit-tested
// without Firestore. Each recommendation has a stable id the app can dismiss.

const { DAY } = require('./insights');

const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);

function sd(xs) {
  if (xs.length < 2) return 0;
  const m = mean(xs);
  return Math.sqrt(mean(xs.map((x) => (x - m) ** 2)));
}

/** Minutes after 18:00 local time, so evening→morning times share one axis. */
function clock(ms, tz) {
  const d = new Date(ms + tz * 60000);
  return (((d.getUTCHours() - 18 + 24) % 24) * 60) + d.getUTCMinutes();
}

function asleepMin(n) {
  const phases = (n.session && n.session.phases) || [];
  return (phases.filter((p) => p.phase !== 'awake').length * 30) / 60;
}

/**
 * @param nights  the user's nights (Firestore docs), any order
 * @param nowMs   reference time
 * @param tz      user's UTC offset in minutes
 * @param goalMin sleep goal in minutes, or null
 * @returns {{nights:number, items:Array<{id,title,body,priority}>}}
 */
function recommendations(nights, nowMs, tz = 0, goalMin = null) {
  const recent = nights
    .filter((n) => n.wokeUp > nowMs - 14 * DAY && n.wokeUp <= nowMs)
    .sort((a, b) => a.wokeUp - b.wokeUp);
  const items = [];
  if (recent.length < 3) {
    items.push({ id: 'track-more', priority: 1, title: 'Keep tracking',
      body: 'Track at least three nights and we can start giving you personal advice.' });
    return { nights: recent.length, items };
  }
  const bed = recent.map((n) => clock(n.session.startedAt, tz));
  const asleep = recent.map(asleepMin);
  const quality = recent.map((n) => n.session.sleepScore);
  const snore = recent.map((n) => n.snoreMinutes || 0);
  const light = recent.map((n) => n.lightLux).filter((v) => typeof v === 'number');
  const alert = recent.map((n) => n.alertness).filter(Boolean);

  const bedSd = sd(bed);
  if (bedSd > 45) {
    items.push({ id: 'regular-bedtime', priority: 3, title: 'Go to bed at the same time',
      body: `Your bedtime moved by about ${Math.round(bedSd)} minutes over the last two weeks. A steadier bedtime is one of the quickest ways to better sleep.` });
  }
  const avgAsleep = mean(asleep);
  const target = goalMin || 7 * 60;
  if (avgAsleep < target - 30) {
    const short = Math.round(target - avgAsleep);
    items.push({ id: 'more-sleep', priority: 3, title: 'You are short on sleep',
      body: `You sleep about ${Math.floor(avgAsleep / 60)} h ${Math.round(avgAsleep % 60)} min a night, ${short} minutes under ${goalMin ? 'your goal' : 'the 7 hours most adults need'}. Try going to bed ${Math.min(60, Math.ceil(short / 15) * 15)} minutes earlier.` });
  }
  if (mean(snore) > 30) {
    items.push({ id: 'snoring', priority: 2, title: 'You snore quite a lot',
      body: 'Sleeping on your side, less alcohol in the evening and a clear nose can all reduce snoring. Listen to your clips in the Journal.' });
  }
  if (light.length >= 3 && mean(light) > 5) {
    items.push({ id: 'dark-room', priority: 2, title: 'Make your bedroom darker',
      body: `Your bedroom averaged ${mean(light).toFixed(1)} lux overnight. Blackout curtains or covering small lights helps deeper sleep.` });
  }
  if (alert.length >= 2) {
    const rt = mean(alert.map((a) => a.rt));
    const best = recent.filter((n) => n.alertness && n.alertness.rt < rt).map(asleepMin);
    if (best.length) {
      items.push({ id: 'alertness-sleep', priority: 1, title: 'Sleep drives your alertness',
        body: `On your sharpest mornings you had slept about ${Math.round(mean(best) / 60 * 10) / 10} hours.` });
    }
  }
  const q = mean(quality);
  if (!items.length || q >= 80) {
    items.push({ id: 'keep-it-up', priority: 0, title: 'Nice work',
      body: `Your sleep quality averaged ${Math.round(q)}% over ${recent.length} nights. Keep your routine going.` });
  }
  items.sort((a, b) => b.priority - a.priority);
  return { nights: recent.length, items };
}

module.exports = { recommendations };
