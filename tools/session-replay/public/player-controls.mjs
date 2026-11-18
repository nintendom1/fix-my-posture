// Binds the shared player preferences (lib/player.mjs) to this page: browser storage, other open tabs, and every
// Autoplay, Loop, Follow new, and speed control in the replay viewer and the Movement Lab player.
import { createPlayerPreferenceStore } from "../lib/player.mjs";

export { advancePlaybackTime, createFollowQueue, followBlocker, followsAddedEvent, followScenarioForRun, followWaitText,
  holdsAtTime, PLAYER_SPEEDS, playbackStartTime, seekCommandPlan } from "../lib/player.mjs";

function browserStorage() {
  try { return globalThis.localStorage; } catch { return null; }
}

const store = createPlayerPreferenceStore({ storage: browserStorage(),
  onStorage: (handler) => globalThis.addEventListener?.("storage", handler) });

export const playerPreferences = store.preferences;
export const setPlayerPreference = store.set;
export const subscribePlayerPreferences = store.subscribe;

/** Shows the current preferences on every player control under `root`. */
export function syncPlayerPreferenceControls(root = document) {
  for (const button of root.querySelectorAll("[data-player-toggle]")) {
    const on = playerPreferences[button.dataset.playerToggle] === true;
    button.classList.toggle("on", on);
    button.setAttribute("aria-pressed", String(on));
  }
  for (const button of root.querySelectorAll("[data-player-speed]")) {
    const on = Number(button.dataset.playerSpeed) === playerPreferences.speed;
    button.classList.toggle("on", on);
    button.setAttribute("aria-pressed", String(on));
  }
}

let controlsInstalled = false;

/** One click handler for every player control, including ones rendered later, kept in step with the preferences. */
export function installPlayerPreferenceControls(doc = document) {
  if (controlsInstalled) return;
  controlsInstalled = true;
  doc.addEventListener("click", (event) => {
    const toggle = event.target.closest?.("[data-player-toggle]");
    if (toggle) {
      const key = toggle.dataset.playerToggle;
      setPlayerPreference(key, !playerPreferences[key]);
      return;
    }
    const speed = event.target.closest?.("[data-player-speed]");
    if (speed) setPlayerPreference("speed", Number(speed.dataset.playerSpeed));
  });
  subscribePlayerPreferences(() => syncPlayerPreferenceControls(doc));
  syncPlayerPreferenceControls(doc);
}
