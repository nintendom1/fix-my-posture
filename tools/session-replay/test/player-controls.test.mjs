import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { advancePlaybackTime, createFollowQueue, createPlayerPreferenceStore, DEFAULT_PLAYER_PREFERENCES, followBlocker,
  followsAddedEvent, followScenarioForRun, holdsAtTime, loadPlayerPreferences, newestAddedItem, playbackStartTime,
  PLAYER_PREFERENCES_KEY, savePlayerPreferences, seekCommandPlan } from "../lib/player.mjs";

const appSource = () => readFile(new URL("../public/app.js", import.meta.url), "utf8");

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

test("the shared player module reads no browser storage on import, and the MCP imports no page module", async () => {
  const original = Object.getOwnPropertyDescriptor(globalThis, "localStorage");
  let reads = 0;
  Object.defineProperty(globalThis, "localStorage", { configurable: true, get() { reads += 1; return null; } });
  try {
    await import("../lib/player.mjs?import-probe");
  } finally {
    if (original) Object.defineProperty(globalThis, "localStorage", original);
    else delete globalThis.localStorage;
  }
  assert.equal(reads, 0);
  const mcpSource = await readFile(new URL("../mcp.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(mcpSource, /from "\.\/public\//);
});

test("a tab adopts preferences another tab saves instead of overwriting them", () => {
  const values = new Map();
  const storage = { getItem: (key) => values.get(key) ?? null, setItem: (key, value) => values.set(key, value) };
  const storageHandlers = new Map();
  const tab = (name) => createPlayerPreferenceStore({ storage, onStorage: (handler) => storageHandlers.set(name, handler) });
  const first = tab("first");
  const second = tab("second");
  const heard = [];
  first.subscribe((preferences, key) => heard.push([key, preferences.speed]));

  assert.equal(second.set("speed", 0.25), true);
  // The browser fires `storage` only in the other tabs.
  storageHandlers.get("first")({ key: PLAYER_PREFERENCES_KEY });
  assert.equal(first.preferences.speed, 0.25);
  assert.deepEqual(heard, [["speed", 0.25]]);
  storageHandlers.get("first")({ key: "fmp-replay-toggles" });
  assert.equal(heard.length, 1, "other keys are ignored");

  assert.equal(first.set("loop", false), true);
  assert.deepEqual(loadPlayerPreferences(storage), { autoplay: true, loop: false, follow: true, speed: 0.25 },
    "the first tab's save keeps the second tab's speed");
  assert.equal(first.set("speed", 3), false, "only the listed speeds are accepted");
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

test("a seek that plays without a range starts at t, outside an older selection", () => {
  const selection = { from: 2, to: 4 };
  const outside = seekCommandPlan({ t: 8, play: true }, { selection, duration: 10 });
  assert.deepEqual(outside, { t: 8, selection: null, play: true, loopSelection: false });
  assert.equal(playbackStartTime(outside.t, 10, { loop: true, selection: outside.selection }), 8);
  assert.deepEqual(seekCommandPlan({ t: 3.5, play: true }, { selection, duration: 10 }).selection, selection,
    "a time inside the selection keeps looping it");
  assert.deepEqual(seekCommandPlan({ t: 8 }, { selection, duration: 10 }).selection, selection,
    "a paused seek keeps the selection, as before");
  assert.equal(seekCommandPlan({ t: 99 }, { duration: 10 }).t, 10);
});

test("a seek that plays a range loops it for that play without changing the Loop preference", async () => {
  const ranged = seekCommandPlan({ t: 3, from: 2, to: 4, play: true }, { duration: 10 });
  assert.deepEqual(ranged, { t: 3, selection: { from: 2, to: 4 }, play: true, loopSelection: true });
  const loopPreference = false;
  assert.deepEqual(advancePlaybackTime(4.25, 10, { loop: loopPreference || ranged.loopSelection, selection: ranged.selection }),
    { time: 2.25, ended: false });
  assert.equal(seekCommandPlan({ t: 3, from: 2, to: 4 }, { duration: 10 }).loopSelection, false);
  assert.equal(seekCommandPlan({ t: 3, from: 4, to: 2, play: true }, { duration: 10 }).loopSelection, false);

  const source = await appSource();
  assert.doesNotMatch(source, /setPlayerPreference\("loop"/, "a Claude seek never saves Loop");
  assert.match(source, /seekCommandPlan\(event, \{ selection: state\.selection/, "the seek handler uses the plan");
});

test("a time without a range opens paused there; a range or no time autoplays", () => {
  assert.equal(holdsAtTime({ time: 1.25 }), true);
  assert.equal(holdsAtTime({ time: 0 }), true);
  assert.equal(holdsAtTime({ time: "13.3" }), true);
  assert.equal(holdsAtTime({ time: 3, range: { from: 2, to: 4 } }), false);
  assert.equal(holdsAtTime({ time: null }), false);
  assert.equal(holdsAtTime({}), false);
});

test("follow opens the first failing scenario in plan order, then the first scenario", () => {
  const run = { plan: { scenarios: [{ id: "first" }, { id: "also-fails" }, { id: "passed" }] },
    results: [{ scenarioID: "also-fails", outcome: "failed" }, { scenarioID: "first", outcome: "failed" }] };
  assert.equal(followScenarioForRun(run), "first");
  assert.equal(followScenarioForRun({ plan: run.plan, results: [{ scenarioID: "passed", outcome: "passed" }] }), "first");
  assert.equal(followScenarioForRun({ plan: { scenarios: [] }, results: [] }), null);
});

test("Follow skips runs this page started and handles every other new item", () => {
  const event = (fields) => ({ type: "added", kind: "labRun", id: "20261117-120000-ab12", ...fields });
  assert.equal(followsAddedEvent(event({ startedBy: "page-a" }), { kind: "labRun", pageID: "page-a" }), false);
  assert.equal(followsAddedEvent(event({ startedBy: "page-b" }), { kind: "labRun", pageID: "page-a" }), true);
  assert.equal(followsAddedEvent(event({}), { kind: "labRun", pageID: "page-a" }), true);
  assert.equal(followsAddedEvent(event({}), { kind: "recording", pageID: "page-a" }), false);
  assert.equal(followsAddedEvent({ type: "command", kind: "labRun", id: "x" }, { kind: "labRun" }), false);
});

test("Follow opens only the newest of the items that arrive together, whatever order they arrive in", async () => {
  const list = [{ id: "newest", title: "Newest" }, { id: "middle", title: "Middle" }, { id: "oldest", title: "Oldest" }];
  for (const order of [["oldest", "newest", "middle"], ["newest", "oldest"]]) {
    const opened = [];
    let refreshes = 0;
    const queue = createFollowQueue({ refresh: async () => { refreshes += 1; return list; },
      open: async (item) => { opened.push(item.id); }, wait: async () => {} });
    await Promise.all(order.map((id) => queue.add(id)));
    assert.deepEqual(opened, ["newest"], `arrival order ${order.join(", ")}`);
    assert.equal(refreshes, 1, "one list refresh per batch");
  }
  assert.equal(newestAddedItem(list, ["oldest", "middle"])?.id, "middle");
  assert.equal(newestAddedItem(list, ["missing"]), null);
});

test("an item added while another opens is followed after it", async () => {
  let release;
  const gate = new Promise((resolve) => { release = resolve; });
  const opened = [];
  const queue = createFollowQueue({ refresh: async () => [{ id: "second" }, { id: "first" }],
    open: async (item) => { opened.push(item.id); if (item.id === "first") await gate; }, wait: async () => {} });
  const firstBatch = queue.add("first");
  while (!opened.length) await new Promise((resolve) => setImmediate(resolve));
  const secondBatch = queue.add("second");
  release();
  await Promise.all([firstBatch, secondBatch]);
  assert.deepEqual(opened, ["first", "second"]);
});

test("with Follow off, the list refreshes and the notice names the new item from it", async () => {
  const notices = [];
  const queue = createFollowQueue({ refresh: async () => [{ id: "new-run", title: "New run" }, { id: "open-run", title: "Open run" }],
    open: async () => assert.fail("Follow is off"), notify: (notice) => notices.push(notice), following: () => false,
    wait: async () => {} });
  await queue.add("new-run");
  assert.deepEqual(notices.map((notice) => [notice.status, notice.item.title]), [["available", "New run"]]);
});

test("Follow waits while something is in progress and then opens the newest item", async () => {
  let blocker = "dialog";
  let waits = 0;
  const notices = [];
  const opened = [];
  const queue = createFollowQueue({ refresh: async () => [{ id: "b", title: "B" }, { id: "a", title: "A" }],
    open: async (item) => { opened.push(item.id); }, notify: (notice) => notices.push(notice), blocked: () => blocker,
    wait: async () => {
      waits += 1;
      if (waits === 3) void queue.add("b");
      if (waits === 5) blocker = null;
    } });
  await queue.add("a");
  assert.deepEqual(opened, ["b"], "nothing opens while blocked, and the newer arrival wins");
  assert.deepEqual(notices.map((notice) => [notice.status, notice.item.id, notice.reason]),
    [["waiting", "a", "dialog"], ["waiting", "b", "dialog"]], "each waiting item is announced once");
});

test("Follow waits for open dialogs, the scenario editor, and unsaved review notes", async () => {
  const page = ({ dialog = false, editorHidden = true, notes = [], active = null } = {}) => ({
    activeElement: active,
    querySelector: (selector) => (selector === "dialog[open]" && dialog ? {} : null),
    getElementById: (id) => (id === "labEditorShell" ? { hidden: editorHidden } : null),
    querySelectorAll: (selector) => (selector === "[data-lab-review-note]" ? notes : []),
  });
  const note = { value: "saved note", defaultValue: "saved note" };
  assert.equal(followBlocker(page({ notes: [note] })), null);
  assert.equal(followBlocker(page({ dialog: true })), "dialog");
  assert.equal(followBlocker(page({ editorHidden: false })), "editor");
  assert.equal(followBlocker(page({ notes: [note], active: note })), "review");
  assert.equal(followBlocker(page({ notes: [{ value: "saved note, then more", defaultValue: "saved note" }] })), "review");

  const source = await appSource();
  assert.match(source, /blocked: \(\) => followBlocker\(document\)/, "recording Follow checks the page first");
  assert.match(source, /api\.post\(`\/api\/sessions\/\$\{encodeURIComponent\(sessionID\)\}\/notes`/,
    "a note saves to the recording it was opened on");
  assert.match(source, /const \{ session, notes \} = state\.exportSource;/, "Send to Claude names the exported recording");
  assert.doesNotMatch(source, /preservePlayback/, "opening the export pauses playback");
});
