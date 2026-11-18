export const PLAYER_PREFERENCES_KEY = "fmp-player-preferences";
export const PLAYER_SPEEDS = Object.freeze([0.25, 0.5, 1, 2, 4]);
export const DEFAULT_PLAYER_PREFERENCES = Object.freeze({ autoplay: true, loop: true, follow: true, speed: 1 });

function browserStorage() {
  try { return globalThis.localStorage; } catch { return null; }
}

function normalizedPreferences(value) {
  return {
    autoplay: typeof value?.autoplay === "boolean" ? value.autoplay : DEFAULT_PLAYER_PREFERENCES.autoplay,
    loop: typeof value?.loop === "boolean" ? value.loop : DEFAULT_PLAYER_PREFERENCES.loop,
    follow: typeof value?.follow === "boolean" ? value.follow : DEFAULT_PLAYER_PREFERENCES.follow,
    speed: PLAYER_SPEEDS.includes(Number(value?.speed)) ? Number(value.speed) : DEFAULT_PLAYER_PREFERENCES.speed,
  };
}

export function loadPlayerPreferences(storage = browserStorage()) {
  try {
    const value = JSON.parse(storage?.getItem(PLAYER_PREFERENCES_KEY) ?? "null");
    return normalizedPreferences(value);
  } catch {
    return { ...DEFAULT_PLAYER_PREFERENCES };
  }
}

export function savePlayerPreferences(preferences, storage = browserStorage()) {
  try {
    storage?.setItem(PLAYER_PREFERENCES_KEY, JSON.stringify(normalizedPreferences(preferences)));
    return Boolean(storage);
  } catch {
    return false;
  }
}

export const playerPreferences = loadPlayerPreferences();
const preferenceListeners = new Set();

export function setPlayerPreference(key, value) {
  if (!Object.hasOwn(DEFAULT_PLAYER_PREFERENCES, key)) return false;
  const next = normalizedPreferences({ ...playerPreferences, [key]: value });
  if (next[key] !== value || playerPreferences[key] === value) return false;
  Object.assign(playerPreferences, next);
  savePlayerPreferences(playerPreferences);
  for (const listener of preferenceListeners) listener(playerPreferences, key);
  return true;
}

export function subscribePlayerPreferences(listener) {
  preferenceListeners.add(listener);
  return () => preferenceListeners.delete(listener);
}

function selectionBounds(selection, duration) {
  const from = Math.max(0, Math.min(duration, Number(selection?.from)));
  const to = Math.max(0, Math.min(duration, Number(selection?.to)));
  return Number.isFinite(from) && Number.isFinite(to) && to > from ? { from, to } : null;
}

export function playbackStartTime(time, duration, { loop = false, selection = null } = {}) {
  const end = Math.max(0, Number(duration) || 0);
  const current = Math.max(0, Math.min(end, Number(time) || 0));
  const range = loop ? selectionBounds(selection, end) : null;
  if (range && (current < range.from || current >= range.to)) return range.from;
  return current >= end ? 0 : current;
}

export function advancePlaybackTime(nextTime, duration, { loop = false, selection = null } = {}) {
  const end = Math.max(0, Number(duration) || 0);
  const range = loop ? selectionBounds(selection, end) : null;
  const boundary = range?.to ?? end;
  const start = range?.from ?? 0;
  const next = Math.max(0, Number(nextTime) || 0);
  if (next < boundary) return { time: next, ended: false };
  if (!loop || boundary <= start) return { time: boundary, ended: true };
  const span = boundary - start;
  return { time: start + ((next - boundary) % span), ended: false };
}

export function followScenarioForRun(run) {
  const scenarios = Array.isArray(run?.plan?.scenarios) ? run.plan.scenarios : [];
  const failed = new Set((Array.isArray(run?.results) ? run.results : [])
    .filter((result) => result?.outcome === "failed").map((result) => result.scenarioID));
  return scenarios.find((scenario) => failed.has(scenario?.id))?.id ?? scenarios[0]?.id ?? null;
}
