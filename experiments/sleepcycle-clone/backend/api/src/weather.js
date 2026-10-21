// Morning weather for the Journal, from Open-Meteo (free, no API key).
// Coordinates are rounded to ~10 km before lookup and caching, so the API
// never sees (or stores) a precise location.

const CACHE_MS = 30 * 60 * 1000;
const cache = new Map();

// WMO weather interpretation codes → short labels
const WMO = {
  0: 'Clear', 1: 'Mainly clear', 2: 'Partly cloudy', 3: 'Overcast', 45: 'Fog', 48: 'Fog',
  51: 'Drizzle', 53: 'Drizzle', 55: 'Drizzle', 61: 'Rain', 63: 'Rain', 65: 'Heavy rain',
  71: 'Snow', 73: 'Snow', 75: 'Heavy snow', 80: 'Showers', 81: 'Showers', 82: 'Heavy showers',
  95: 'Thunderstorm', 96: 'Thunderstorm', 99: 'Thunderstorm',
};

function round(v) {
  return Math.round(v * 10) / 10;
}

async function currentWeather(lat, lon, fetchImpl = fetch) {
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    const e = new Error('lat/lon required');
    e.status = 400;
    throw e;
  }
  const rl = round(lat), ro = round(lon);
  const key = `${rl},${ro}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.value;

  const url = `https://api.open-meteo.com/v1/forecast?latitude=${rl}&longitude=${ro}` +
    '&current=temperature_2m,weather_code&timezone=auto';
  const r = await fetchImpl(url);
  if (!r.ok) {
    const e = new Error(`weather upstream ${r.status}`);
    e.status = 502;
    throw e;
  }
  const j = await r.json();
  const tempC = j.current.temperature_2m;
  const code = j.current.weather_code;
  const value = {
    tempC,
    tempF: Math.round(tempC * 9 / 5 + 32),
    code,
    description: WMO[code] || 'Unknown',
    at: j.current.time,
  };
  cache.set(key, { at: Date.now(), value });
  return value;
}

module.exports = { currentWeather, _cache: cache };
