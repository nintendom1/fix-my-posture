import test from "node:test";
import assert from "node:assert/strict";
import { advancePlaybackTime, DEFAULT_PLAYER_PREFERENCES, followScenarioForRun, loadPlayerPreferences,
  playbackStartTime, PLAYER_PREFERENCES_KEY, savePlayerPreferences } from "../public/player-controls.mjs";

test("autoplay, loop, and follow preferences default on and persist safely", () => {
  assert.deepEqual(loadPlayerPreferences(null), DEFAULT_PLAYER_PREFERENCES);
  const values = new Map();
  const storage = { getItem: (key) => values.get(key), setItem: (key, value) => values.set(key, value) };
  const preferences = loadPlayerPreferences(storage);
  assert.deepEqual(preferences, { autoplay: true, loop: true, follow: true, speed: 1 });
  preferences.autoplay = false;
  preferences.loop = false;
  preferences.follow = false;
  preferences.speed = 2;
  assert.equal(savePlayerPreferences(preferences, storage), true);
  assert.equal(values.has(PLAYER_PREFERENCES_KEY), true);
  assert.deepEqual(loadPlayerPreferences(storage), preferences);

  const blocked = { getItem() { throw new Error("storage blocked"); }, setItem() { throw new Error("storage blocked"); } };
  assert.deepEqual(loadPlayerPreferences(blocked), DEFAULT_PLAYER_PREFERENCES);
  assert.equal(savePlayerPreferences(preferences, blocked), false);
});

test("playback wraps the full recording or the selected range and stops with Loop off", () => {
  assert.deepEqual(advancePlaybackTime(10.25, 10, { loop: true }), { time: 0.25, ended: false });
  assert.deepEqual(advancePlaybackTime(5.25, 10, { loop: true, selection: { from: 2, to: 4 } }),
    { time: 3.25, ended: false });
  assert.deepEqual(advancePlaybackTime(5.25, 10, { loop: false, selection: { from: 2, to: 4 } }),
    { time: 5.25, ended: false });
  assert.deepEqual(advancePlaybackTime(10.25, 10, { loop: false, selection: { from: 2, to: 4 } }),
    { time: 10, ended: true });
  assert.equal(playbackStartTime(8, 10, { loop: true, selection: { from: 2, to: 4 } }), 2);
  assert.equal(playbackStartTime(3, 10, { loop: true, selection: { from: 2, to: 4 } }), 3);
});

test("follow opens the first failing scenario in plan order, then the first scenario", () => {
  const run = { plan: { scenarios: [{ id: "first" }, { id: "also-fails" }, { id: "passed" }] },
    results: [{ scenarioID: "also-fails", outcome: "failed" }, { scenarioID: "first", outcome: "failed" }] };
  assert.equal(followScenarioForRun(run), "first");
  assert.equal(followScenarioForRun({ plan: run.plan, results: [{ scenarioID: "passed", outcome: "passed" }] }), "first");
  assert.equal(followScenarioForRun({ plan: { scenarios: [] }, results: [] }), null);
});
