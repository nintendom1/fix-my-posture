import { recordsToFileText, Session, clock } from "../../lib/session.mjs";
import { num } from "../views.mjs";
import * as labViews from "./views.mjs";
import { applyLabSectionView, createCoveragePlaybackNavigator } from "./coverage.mjs";
import { createLabOpenHandler, createSelectionToken, installLabOpenCommandReceiver, labOpenRequestFromURL, runScenarioToOpen,
  sectionHref } from "./selection.mjs";
import { acknowledgeCommand, pageID, viewerEvents } from "../events.mjs";
import { advancePlaybackTime, createFollowQueue, followBlocker, followsAddedEvent, followWaitText, holdsAtTime,
  installPlayerPreferenceControls, playbackStartTime, playerPreferences, subscribePlayerPreferences } from "../player-controls.mjs";

const $ = (id) => document.getElementById(id);
const selectionTokens = createSelectionToken();
let runListRequest = 0;
const state = { runs: [], runID: null, run: null, scenarioID: null, activeView: null,
  playing: false, manualPaused: false, itemKey: null, t: 0, lastFrame: 0, loading: false, loaded: false };
let viewerStateSyncTimer = null;
// Set while the selected scenario has playback, so Claude's play and pause know whether this page can act.
let playLabPlayback = null;
let pauseLabPlayback = null;

function toast(message, duration = 3200) {
  const element = $("toast");
  element.textContent = message;
  element.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { element.hidden = true; }, duration);
}

function syncViewerState(immediate = false) {
  if (viewerStateSyncTimer && !immediate) return;
  clearTimeout(viewerStateSyncTimer);
  viewerStateSyncTimer = setTimeout(() => {
    viewerStateSyncTimer = null;
    if (state.activeView !== "runs" || !state.runID) return;
    void fetch("/api/viewer/state", { method: "POST", headers: { "content-type": "application/json", "x-fmp-replay": "1" },
      body: JSON.stringify({ kind: "labRun", runID: state.runID, scenarioID: state.scenarioID, t: state.t,
        playing: state.playing, loop: playerPreferences.loop, autoplay: playerPreferences.autoplay,
        follow: playerPreferences.follow, speed: playerPreferences.speed }) }).catch(() => {});
  }, immediate ? 0 : 400);
}

async function getJSON(url) {
  const response = await fetch(url);
  const result = await response.json().catch(() => null);
  if (!response.ok) throw new Error(result?.error ?? `${response.status} ${response.statusText}`);
  return result;
}

async function postLabJSON(url, body, confirmationToken = null) {
  const nonce = document.querySelector('meta[name="fmp-replay-nonce"]')?.content ?? "";
  const headers = { "content-type": "application/json", "x-fmp-replay": "1", "x-fmp-replay-nonce": nonce };
  if (confirmationToken) headers["x-fmp-lab-confirmation"] = confirmationToken;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify(body) });
  const result = await response.json().catch(() => null);
  if (!response.ok) throw new Error(result?.error ?? `${response.status} ${response.statusText}`);
  return result;
}

async function refreshScenario(runID, scenarioID) {
  await openRun(runID);
  if (state.runID === runID && state.run?.plan?.scenarios?.some((scenario) => scenario.id === scenarioID)) {
    await openScenario(scenarioID);
  }
}

async function saveReview(button) {
  const panel = button.closest("[data-lab-review-panel]");
  const reviewPanel = panel?.querySelector("[data-lab-review-message]");
  if (!panel) return;
  const note = panel.querySelector("[data-lab-review-note]")?.value?.trim() ?? "";
  if (!note) {
    if (reviewPanel) { reviewPanel.textContent = "Add a note describing what you verified."; reviewPanel.classList.add("error"); }
    return;
  }
  const runID = panel.dataset.labReviewRun;
  const scenarioID = panel.dataset.labReviewScenario;
  const revision = Number(panel.dataset.labReviewRevision);
  const status = button.dataset.labReviewAction;
  button.disabled = true;
  try {
    await postLabJSON("/api/lab/review", { runID, scenarioID, revision, status, note });
    await refreshScenario(runID, scenarioID);
    if (status === "needs-edit") await window.FMPLabEditor?.open({ runID, scenarioID });
  } catch (error) {
    if (reviewPanel) { reviewPanel.textContent = error?.message ?? String(error); reviewPanel.classList.add("error"); }
  } finally { button.disabled = false; }
}

async function promoteScenario(button) {
  const panel = button.closest("[data-lab-review-panel]");
  const message = panel?.querySelector("[data-lab-review-message]");
  if (!panel) return;
  const target = { runID: panel.dataset.labReviewRun, scenarioID: panel.dataset.labReviewScenario,
    revision: Number(panel.dataset.labReviewRevision) };
  const exerciseID = button.dataset.labPromoteExercise;
  const relativePath = `PostureAnalysisApp/Tests/Fixtures/MovementScenarios/approved/${exerciseID}/${target.scenarioID}.r${target.revision}.json`;
  const confirmed = window.confirm(`Write this synthetic scenario, its frozen assertions, and observed results to ${relativePath}? No recording frames will be included.`);
  if (!confirmed) return;
  button.disabled = true;
  try {
    const grant = await postLabJSON("/api/lab/promote/confirm-token", target);
    const code = window.prompt("Type the one-time 6-digit promotion code shown in the terminal running this viewer. It expires in 60 seconds.");
    if (code === null) return;
    await postLabJSON("/api/lab/promote", { ...target, confirmationCode: code.trim() }, grant.token);
    await refreshScenario(target.runID, target.scenarioID);
  } catch (error) {
    if (message) { message.textContent = error?.message ?? String(error); message.classList.add("error"); }
  } finally { button.disabled = false; }
}

function switchView(name, { updateURL = true } = {}) {
  const view = name === "recordings" || name === "coverage" ? name : "runs";
  const showRuns = view === "runs";
  if (state.activeView !== view) {
    state.activeView = view;
    state.playing = false;
    syncViewerState();
    selectionTokens.next();
    if (!showRuns) {
      runListRequest += 1;
      state.loading = false;
    }
  }
  if (updateURL && view !== "coverage") {
    const next = sectionHref(location.href, view);
    if (`${location.pathname}${location.search}${location.hash}` !== next) history.pushState(null, "", next);
  }
  if (view === "coverage") window.FMPLabCoverage?.activate();
  else window.FMPLabCoverage?.deactivate();
  applyLabSectionView(view, {
    navigation: document.querySelector(".lab-top"),
    labDashboard: $("labDashboard"),
    app: $("app"),
    labNote: $("labNote"),
    labRefresh: $("labRefresh"),
    layout: $("labDashboard").querySelector(".lab-layout"),
    coverageView: $("labCoverageView"),
    tabs: document.querySelectorAll("[data-lab-view]"),
  });
  if (showRuns) {
    window.FMPReplayViewer?.deactivate();
    if (!state.loaded) loadRuns();
    else if (state.runID && state.run) openScenario(state.scenarioID ?? state.run.plan.scenarios?.[0]?.id);
    else if (state.runID) openRun(state.runID);
  } else if (view === "recordings") {
    window.FMPReplayViewer?.activate();
  } else {
    window.FMPReplayViewer?.deactivate();
  }
}

function showError(target, error) {
  target.innerHTML = `<div class="lab-error">${labViews.renderRunCards([])}<span>${escapeText(error?.message ?? String(error))}</span></div>`;
}

function escapeText(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]);
}

// Explicit navigation (fmp_lab_open, URL, live command) wins over the list's default "open the first run".
let explicitNavigations = 0;

async function loadRuns() {
  if (state.loading) return;
  state.loading = true;
  const request = ++runListRequest;
  const list = $("labRunsList");
  list.innerHTML = `<div class="lab-loading">Loading runs…</div>`;
  try {
    const runs = await getJSON("/api/lab/runs");
    if (request !== runListRequest || state.activeView !== "runs") return;
    state.runs = runs;
    state.loaded = true;
    list.innerHTML = labViews.renderRunCards(state.runs, state.runID);
    if (explicitNavigations > 0) {
      // After any explicit navigation the list never auto-opens a run; the requested selection stays.
    } else if (state.runID && state.runs.some((run) => run.id === state.runID)) await openRun(state.runID);
    else if (state.runs.length) await openRun(state.runs[0].id);
    else {
      state.runID = null;
      state.run = null;
      $("labRunPane").hidden = true;
      $("labWelcome").hidden = false;
    }
  } catch (error) {
    if (request !== runListRequest || state.activeView !== "runs") return;
    state.loaded = false;
    showError(list, error);
  } finally {
    if (request === runListRequest) state.loading = false;
  }
}

/** Refreshes the run list without opening anything; Follow and reload use it so they always see new runs. */
async function refreshRunList() {
  const runs = await getJSON("/api/lab/runs");
  state.runs = runs;
  $("labRunsList").innerHTML = labViews.renderRunCards(state.runs, state.runID);
  return runs;
}

/**
 * Opens a run at the requested scenario, at the first failing one for Follow, or at the first one. A stale scenario id
 * falls back with a toast. `hold` opens paused at `timestamp` (an explicit keyframe), like `fmp_viewer_seek`.
 */
async function openRun(runID, { scenarioID = null, timestamp = null, follow = false, hold = false } = {}) {
  const request = selectionTokens.next();
  const wasPlaying = state.playing;
  state.playing = false;
  state.runID = runID;
  state.scenarioID = null;
  state.run = null;
  const isCurrent = () => selectionTokens.isCurrent(request) && state.runID === runID && state.activeView === "runs";
  try {
    const run = await getJSON(`/api/lab/runs/${encodeURIComponent(runID)}`);
    if (!isCurrent()) return;
    state.run = run;
    $("labRunsList").innerHTML = labViews.renderRunCards(state.runs, runID);
    $("labRunHeader").innerHTML = labViews.renderRunHeader(run);
    $("labScenarioNav").innerHTML = labViews.renderScenarioList(run.plan, run.results);
    $("labWelcome").hidden = true;
    $("labRunPane").hidden = false;
    const choice = runScenarioToOpen(run, { scenarioID, follow });
    if (choice.missing) toast(`Scenario ${choice.missing} isn't in this run; showing ${choice.scenarioID ?? "the run"} instead.`, 6000);
    if (choice.scenarioID) {
      await openScenario(choice.scenarioID, choice.missing ? { resumePlayback: wasPlaying }
        : { timestamp, resumePlayback: wasPlaying, hold });
    } else {
      state.itemKey = null;
      playLabPlayback = null;
      pauseLabPlayback = null;
      $("labScenarioDetail").innerHTML = `<div class="lab-empty">This run has no scenarios.</div>`;
      syncViewerState();
    }
    return state.run === run && state.runID === runID && state.activeView === "runs" ? run : null;
  } catch (error) {
    if (!isCurrent()) return;
    $("labRunPane").hidden = true;
    $("labWelcome").hidden = false;
    showError($("labRunsList"), error);
    return null;
  }
}

async function openScenario(scenarioID, { timestamp = null, resumePlayback = state.playing, hold = false } = {}) {
  const wasPlaying = resumePlayback;
  state.playing = false;
  const scenario = state.run?.plan?.scenarios?.find((item) => item.id === scenarioID);
  if (!scenario) return;
  playLabPlayback = null;
  pauseLabPlayback = null;
  const runID = state.runID;
  const run = state.run;
  const itemKey = `${runID}/${scenarioID}`;
  const changedItem = state.itemKey !== itemKey;
  if (changedItem) state.manualPaused = false;
  const request = selectionTokens.next();
  state.scenarioID = scenarioID;
  const isCurrent = () => selectionTokens.isCurrent(request) && state.runID === runID
    && state.run === run && state.scenarioID === scenarioID && state.activeView === "runs";
  const result = run.results.find((item) => item.scenarioID === scenarioID) ?? null;
  const panel = $("labScenarioDetail");
  panel.innerHTML = `<div class="lab-loading">Loading scenario…</div>`;
  $("labScenarioNav").innerHTML = labViews.renderScenarioList(run.plan, run.results, scenarioID);
  const base = `/api/lab/runs/${encodeURIComponent(runID)}/scenarios/${encodeURIComponent(scenarioID)}`;
  const [recording, reference] = result
    ? await Promise.all([
      getJSON(`${base}/recording`).catch(() => []),
      getJSON(`${base}/reference`).catch(() => []),
    ])
    : [[], []];
  if (!isCurrent()) return;
  panel.innerHTML = labViews.renderScenarioDetail({ plan: run.plan, scenario, result, recording, reference,
    player: playerPreferences });
  state.t = 0;
  let session = null;
  let referenceSession = null;
  if (recording.length) {
    try { session = Session.fromText(recordsToFileText(recording.map((record) => JSON.stringify(record)))); } catch { session = null; }
  }
  if (reference.length) {
    try { referenceSession = Session.fromText(recordsToFileText(reference.map((record) => JSON.stringify(record)))); } catch { referenceSession = null; }
  }
  bindScenarioPlayback(panel.querySelector(".lab-selected-scenario"), session, referenceSession, request, runID, scenarioID,
    { timestamp, changedItem, wasPlaying, hold });
  state.itemKey = itemKey;
  syncViewerState(true);
}

function bindScenarioPlayback(panel, session, referenceSession, request, runID, scenarioID, { timestamp, changedItem, wasPlaying, hold }) {
  const scrubber = panel.querySelector("[data-lab-scrubber]");
  if (!scrubber || !session?.frames?.length) return;
  const duration = Math.max(0, num(session.duration));
  const referenceStage = panel.querySelector('[data-lab-stage="reference"]');
  const modifiedStage = panel.querySelector('[data-lab-stage="modified"]');
  const playButton = panel.querySelector("[data-lab-play]");
  const isCurrent = () => selectionTokens.isCurrent(request) && state.runID === runID
    && state.scenarioID === scenarioID && state.activeView === "runs";

  function update(t) {
    state.t = Math.max(0, Math.min(duration, num(t)));
    scrubber.value = String(state.t);
    const clockNode = panel.querySelector("[data-lab-clock]");
    if (clockNode) clockNode.textContent = `${clock(state.t)} / ${clock(duration)}`;
    const playhead = panel.querySelector("[data-lab-playhead]");
    const timeline = panel.querySelector(".lab-timeline");
    if (playhead && timeline) {
      const labelWidth = Number.parseFloat(getComputedStyle(timeline).getPropertyValue("--lab-label-width")) || 104;
      const laneStart = labelWidth + 8;
      playhead.style.left = `${laneStart + (timeline.clientWidth - laneStart) * (duration > 0 ? state.t / duration : 0)}px`;
    }
    labViews.setPlaybackFrame(modifiedStage, session, state.t);
    labViews.setPlaybackFrame(referenceStage, referenceSession, state.t);
    syncViewerState();
  }

  function pause(manual = true) {
    state.playing = false;
    if (manual) state.manualPaused = true;
    playButton.textContent = "Play";
    syncViewerState(true);
  }

  function play(manual = true) {
    if (!isCurrent() || state.playing) return;
    if (manual) state.manualPaused = false;
    if (state.manualPaused) return;
    state.t = playbackStartTime(state.t, duration, { loop: playerPreferences.loop });
    update(state.t);
    state.playing = true;
    state.lastFrame = 0;
    playButton.textContent = "Pause";
    syncViewerState(true);
    requestAnimationFrame(tick);
  }

  function tick(now) {
    if (!state.playing || !isCurrent()) return;
    const delta = state.lastFrame ? (now - state.lastFrame) / 1000 : 0;
    state.lastFrame = now;
    const advanced = advancePlaybackTime(state.t + delta * playerPreferences.speed, duration, { loop: playerPreferences.loop });
    if (advanced.ended) {
      state.playing = false;
      playButton.textContent = "Play";
      update(advanced.time);
      syncViewerState();
      return;
    }
    update(advanced.time);
    requestAnimationFrame(tick);
  }

  playLabPlayback = play;
  pauseLabPlayback = pause;
  playButton.addEventListener("click", () => {
    if (state.playing) pause();
    else play();
  });
  scrubber.addEventListener("input", (event) => {
    if (event.isTrusted) pause();
    update(Number(scrubber.value));
  });
  panel.addEventListener("click", (event) => {
    const seek = event.target.closest("[data-lab-seek]");
    if (seek) {
      pause();
      update(Number(seek.dataset.labSeek));
      return;
    }
    const track = event.target.closest("[data-lab-track]");
    if (!track) return;
    const rect = track.getBoundingClientRect();
    if (rect.width <= 0) return;
    const fraction = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
    pause();
    update(fraction * duration);
  });
  update(timestamp ?? 0);
  if (hold) return;
  if (changedItem && playerPreferences.autoplay && !state.manualPaused) play(false);
  else if (!changedItem && wasPlaying && playerPreferences.autoplay && !state.manualPaused) play(false);
}

function seekCurrentPlayback({ runID, scenarioID, timestamp }) {
  if (state.activeView !== "runs" || state.runID !== runID || state.scenarioID !== scenarioID) return false;
  const article = [...$("labScenarioDetail").querySelectorAll(".lab-selected-scenario")]
    .find((item) => item.dataset.labScenarioId === scenarioID);
  const scrubber = article?.querySelector("[data-lab-scrubber]");
  if (!scrubber) return false;
  scrubber.step = "any";
  scrubber.value = String(Math.max(0, Math.min(num(scrubber.max), timestamp)));
  scrubber.dispatchEvent(new Event("input", { bubbles: true }));
  article.scrollIntoView?.({ block: "start", behavior: "smooth" });
  return true;
}

function activateLabRuns() {
  document.querySelector('[data-lab-view="runs"]')?.click();
  return state.activeView === "runs";
}

const navigateCoverageThumbnail = createCoveragePlaybackNavigator({
  activateRuns: activateLabRuns,
  // A keyframe link or command names a time, so the scenario opens paused there instead of autoplaying past it.
  loadRun: async (runID, scenarioID, timestamp) => {
    await openRun(runID, { scenarioID, timestamp, hold: holdsAtTime({ time: timestamp }) });
    return state.activeView === "runs" && state.runID === runID ? state.run : null;
  },
  selectScenario: async (runID, scenarioID, timestamp) => {
    if (state.activeView !== "runs" || state.runID !== runID
      || !state.run?.plan?.scenarios?.some((scenario) => scenario.id === scenarioID)) return false;
    if (state.itemKey === `${runID}/${scenarioID}` && (timestamp == null || Math.abs(state.t - timestamp) < 0.001)) return true;
    await openScenario(scenarioID, { timestamp, hold: holdsAtTime({ time: timestamp }) });
    return state.activeView === "runs" && state.runID === runID && state.scenarioID === scenarioID;
  },
  seek: seekCurrentPlayback,
});

const labOpenHandler = createLabOpenHandler({
  navigateToScenario: navigateCoverageThumbnail,
  navigateToRun: async ({ runID, scenarioID }) => {
    if (await activateLabRuns() === false) return false;
    const run = await openRun(runID, { scenarioID });
    if ((run?.id ?? run?.summary?.id) !== runID) return false;
    if (!scenarioID) return true;
    if (!run.plan?.scenarios?.some((scenario) => scenario.id === scenarioID)) return false;
    return state.activeView === "runs" && state.runID === runID && state.scenarioID === scenarioID;
  },
});

const handleLabOpenRequest = (request) => {
  explicitNavigations += 1;
  return labOpenHandler(request);
};

// The scenario editor reads `pageID` so the runs it starts come back marked as this page's own.
window.FMPLabDashboard = { navigateToScenario: navigateCoverageThumbnail, pageID };

async function reloadLab() {
  const runID = state.runID;
  const scenarioID = state.scenarioID;
  const timestamp = state.t;
  await refreshRunList();
  if (state.activeView === "runs" && runID && state.runs.some((run) => run.id === runID)) {
    await openRun(runID, { scenarioID, timestamp });
  }
}

function scenarioLabel(run, scenarioID) {
  const scenario = run?.plan?.scenarios?.find((item) => item.id === scenarioID);
  return scenario ? ` · ${scenario.name ?? scenario.id}` : "";
}

const runFollow = createFollowQueue({
  refresh: refreshRunList,
  following: () => playerPreferences.follow,
  blocked: () => followBlocker(document),
  open: async (item) => {
    explicitNavigations += 1;
    if (state.activeView !== "runs" && !activateLabRuns()) return;
    const run = await openRun(item.id, { follow: true });
    if (run) toast(`Loaded Movement Lab run: ${item.title ?? item.id}${scenarioLabel(run, state.scenarioID)}.`);
  },
  notify: ({ status, item, reason }) => toast(status === "waiting"
    ? `New Movement Lab run ready: ${item.title ?? item.id}. It opens ${followWaitText(reason)}.`
    : `New Movement Lab run available: ${item.title ?? item.id}.`, 6000),
});

/** Playback commands act only on a scenario that is showing playback; acting acknowledges. */
function handleDashboardControl(event) {
  if (event.action === "reload") {
    if (state.activeView === "runs") void reloadLab();
    else if (state.activeView === "coverage") window.FMPLabCoverage?.refresh();
    else return;
    acknowledgeCommand(event);
    return;
  }
  if (state.activeView !== "runs" || !playLabPlayback || !pauseLabPlayback) return;
  if (event.action === "play") playLabPlayback();
  else if (event.action === "pause") pauseLabPlayback();
  else if (event.action === "toggle") state.playing ? pauseLabPlayback() : playLabPlayback();
  else return;
  acknowledgeCommand(event);
}

async function handleDashboardEvent(message) {
  let event;
  try { event = JSON.parse(message.data); } catch { return; }
  if (event.type === "added" && event.kind === "labRun") {
    // A run this page's scenario editor started is already on screen there; only the list needs it.
    if (followsAddedEvent(event, { kind: "labRun", pageID })) void runFollow.add(event.id);
    else void refreshRunList().catch(() => {});
    return;
  }
  if (event.type !== "command") return;
  if (event.command === "control") handleDashboardControl(event);
  else if (event.command === "lab-open") acknowledgeCommand(event);
}

installLabOpenCommandReceiver(viewerEvents, handleLabOpenRequest);
viewerEvents.addEventListener("message", (message) => { void handleDashboardEvent(message); });
installPlayerPreferenceControls(document);
subscribePlayerPreferences(() => syncViewerState(true));

document.addEventListener("click", (event) => {
  const viewButton = event.target.closest("[data-lab-view]");
  if (viewButton) {
    switchView(viewButton.dataset.labView);
    return;
  }
  const runButton = event.target.closest("[data-lab-run]");
  if (runButton) { openRun(runButton.dataset.labRun); return; }
  const scenarioButton = event.target.closest("[data-lab-scenario]");
  if (scenarioButton && state.run) openScenario(scenarioButton.dataset.labScenario);
  const reviewButton = event.target.closest("[data-lab-review-action]");
  if (reviewButton) { event.preventDefault(); void saveReview(reviewButton); return; }
  const promoteButton = event.target.closest("[data-lab-promote]");
  if (promoteButton) { event.preventDefault(); void promoteScenario(promoteButton); }
});

$("labRefresh").addEventListener("click", () => {
  if (state.activeView === "coverage") window.FMPLabCoverage?.refresh();
  else loadRuns();
});

const initialLabOpen = labOpenRequestFromURL(location.search);
const directRecording = !initialLabOpen && (new URLSearchParams(location.search).has("session")
  || new URLSearchParams(location.search).get("view") === "recordings");
switchView(directRecording ? "recordings" : "runs", { updateURL: false });
if (initialLabOpen) void handleLabOpenRequest(initialLabOpen);

window.addEventListener("popstate", () => {
  const params = new URLSearchParams(location.search);
  const labTarget = labOpenRequestFromURL(location.search);
  if (labTarget) {
    switchView("runs", { updateURL: false });
    void handleLabOpenRequest(labTarget);
    return;
  }
  const recording = params.has("session") || params.get("view") === "recordings";
  switchView(recording ? "recordings" : "runs", { updateURL: false });
});

