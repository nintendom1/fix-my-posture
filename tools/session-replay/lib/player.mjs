// Player and Follow logic shared by the replay viewer, the Movement Lab player, the MCP server, and the tests. It has
// no side effects at import: public/player-controls.mjs binds it to the page's storage, other tabs, and controls.

export const PLAYER_PREFERENCES_KEY = "fmp-player-preferences";
export const PLAYER_SPEEDS = Object.freeze([0.25, 0.5, 1, 2, 4]);
export const DEFAULT_PLAYER_PREFERENCES = Object.freeze({ autoplay: true, loop: true, follow: true, speed: 1 });
const PREFERENCE_KEYS = Object.keys(DEFAULT_PLAYER_PREFERENCES);

export function normalizedPreferences(value) {
  return {
    autoplay: typeof value?.autoplay === "boolean" ? value.autoplay : DEFAULT_PLAYER_PREFERENCES.autoplay,
    loop: typeof value?.loop === "boolean" ? value.loop : DEFAULT_PLAYER_PREFERENCES.loop,
    follow: typeof value?.follow === "boolean" ? value.follow : DEFAULT_PLAYER_PREFERENCES.follow,
    speed: PLAYER_SPEEDS.includes(Number(value?.speed)) ? Number(value.speed) : DEFAULT_PLAYER_PREFERENCES.speed,
  };
}

export function loadPlayerPreferences(storage) {
  try {
    const value = JSON.parse(storage?.getItem(PLAYER_PREFERENCES_KEY) ?? "null");
    return normalizedPreferences(value);
  } catch {
    return { ...DEFAULT_PLAYER_PREFERENCES };
  }
}

export function savePlayerPreferences(preferences, storage) {
  try {
    storage?.setItem(PLAYER_PREFERENCES_KEY, JSON.stringify(normalizedPreferences(preferences)));
    return Boolean(storage);
  } catch {
    return false;
  }
}

/**
 * The preferences every player on a page shares. `onStorage` subscribes to the browser's `storage` events, so a change
 * made in another tab is adopted here instead of being overwritten by this tab's next save.
 */
export function createPlayerPreferenceStore({ storage = null, onStorage = null } = {}) {
  const preferences = loadPlayerPreferences(storage);
  const listeners = new Set();
  const notify = (key) => { for (const listener of listeners) listener(preferences, key); };

  onStorage?.((event) => {
    if (event?.key !== PLAYER_PREFERENCES_KEY && event?.key !== null) return;
    const next = loadPlayerPreferences(storage);
    const changed = PREFERENCE_KEYS.filter((key) => preferences[key] !== next[key]);
    if (!changed.length) return;
    Object.assign(preferences, next);
    notify(changed.length === 1 ? changed[0] : null);
  });

  return {
    preferences,
    set(key, value) {
      if (!Object.hasOwn(DEFAULT_PLAYER_PREFERENCES, key)) return false;
      const next = normalizedPreferences({ ...preferences, [key]: value });
      if (next[key] !== value || preferences[key] === value) return false;
      Object.assign(preferences, next);
      savePlayerPreferences(preferences, storage);
      notify(key);
      return true;
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}

function selectionBounds(selection, duration) {
  if (selection?.from == null || selection?.to == null) return null;
  const from = Math.max(0, Math.min(duration, Number(selection.from)));
  const to = Math.max(0, Math.min(duration, Number(selection.to)));
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

/** A link or command that names a time without a range opens paused there, like `fmp_viewer_seek`; others autoplay. */
export function holdsAtTime({ time = null, range = null } = {}) {
  return time != null && time !== "" && Number.isFinite(Number(time)) && range == null;
}

/**
 * What a Claude seek does to the replay viewer. A range replaces the selection, and with `play` it loops for this
 * play only (`loopSelection`), leaving the saved Loop preference alone. Without a range, `play` starts at `t`, so a
 * selection that doesn't contain `t` is dropped rather than pulling playback back into it.
 */
export function seekCommandPlan(command, { selection = null, duration = 0, current = 0 } = {}) {
  const end = Math.max(0, Number(duration) || 0);
  const play = command?.play === true;
  const hasRange = command?.from != null && command?.to != null;
  const range = hasRange ? selectionBounds(command, end) : null;
  const requested = Number(command?.t ?? command?.from ?? current);
  const t = Math.max(0, Math.min(end, Number.isFinite(requested) ? requested : 0));
  let kept = hasRange ? range : selectionBounds(selection, end);
  if (!hasRange && play && kept && (t < kept.from || t >= kept.to)) kept = null;
  return { t, selection: kept, play, loopSelection: play && range != null };
}

export function followScenarioForRun(run) {
  const scenarios = Array.isArray(run?.plan?.scenarios) ? run.plan.scenarios : [];
  const failed = new Set((Array.isArray(run?.results) ? run.results : [])
    .filter((result) => result?.outcome === "failed").map((result) => result.scenarioID));
  return scenarios.find((scenario) => failed.has(scenario?.id))?.id ?? scenarios[0]?.id ?? null;
}

/** Whether an event announces new work of `kind` that Follow should handle; runs this page started don't count. */
export function followsAddedEvent(event, { kind, pageID = null } = {}) {
  return event?.type === "added" && event.kind === kind && typeof event.id === "string" && event.id !== ""
    && (pageID == null || event.startedBy !== pageID);
}

/** The newest of the added ids, from a list that is already sorted newest first. */
export function newestAddedItem(items, ids) {
  const wanted = ids instanceof Set ? ids : new Set(ids ?? []);
  return (Array.isArray(items) ? items : []).find((item) => wanted.has(item?.id)) ?? null;
}

/** Something on the page Follow must not replace: an open dialog, the scenario editor, or an unsaved review note. */
export function followBlocker(doc) {
  if (!doc) return null;
  if (doc.querySelector("dialog[open]")) return "dialog";
  const editor = doc.getElementById("labEditorShell");
  if (editor && !editor.hidden) return "editor";
  for (const note of doc.querySelectorAll("[data-lab-review-note]")) {
    if (note === doc.activeElement || note.value !== note.defaultValue) return "review";
  }
  return null;
}

const FOLLOW_WAIT_TEXT = Object.freeze({
  dialog: "when you close the dialog",
  editor: "when you close the scenario editor",
  review: "after you save the review note",
});

export function followWaitText(reason) {
  return FOLLOW_WAIT_TEXT[reason] ?? "when the page is free";
}

/**
 * Follow for one kind of item. Ids added together (one server poll) settle for `settleMs`; then the list refreshes
 * once and only the newest added item opens, so a batch never races to show an older one. With Follow off, the list
 * still refreshes and `notify` reports what arrived. While `blocked()` names something in progress, the newest item
 * waits, checked every `retryMs`, and opens once it clears.
 */
export function createFollowQueue({ refresh, open, notify = () => {}, following = () => true, blocked = () => null,
  settleMs = 250, retryMs = 500, wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)) }) {
  const pending = new Set();
  let waiting = null;
  let draining = null;

  async function drain() {
    await wait(settleMs);
    while (pending.size || waiting) {
      if (pending.size) {
        const ids = new Set(pending);
        pending.clear();
        const item = newestAddedItem(await refresh(), ids);
        if (item && following()) waiting = { item, notified: false };
        else if (item) notify({ status: "available", item, count: ids.size });
        continue;
      }
      if (!following()) { waiting = null; break; }
      const reason = blocked();
      if (reason) {
        if (!waiting.notified) notify({ status: "waiting", item: waiting.item, reason });
        waiting.notified = true;
        await wait(retryMs);
        continue;
      }
      const { item } = waiting;
      waiting = null;
      await open(item);
    }
  }

  function schedule() {
    draining ??= drain().catch(() => {}).finally(() => {
      draining = null;
      if (pending.size) schedule();
    });
    return draining;
  }

  return {
    add(id) {
      if (typeof id === "string" && id) pending.add(id);
      return schedule();
    },
  };
}
