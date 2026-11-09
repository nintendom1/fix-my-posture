import { recordsToFileText, Session, clock } from "../../lib/session.mjs";
import { num } from "../views.mjs";
import * as labViews from "./views.mjs";
import { applyLabSectionView, createCoveragePlaybackNavigator } from "./coverage.mjs";
import { createLabOpenHandler, createSelectionToken, installLabOpenCommandReceiver, labOpenRequestFromURL, sectionHref } from "./selection.mjs";

const $ = (id) => document.getElementById(id);
const selectionTokens = createSelectionToken();
let runListRequest = 0;
const state = { runs: [], runID: null, run: null, scenarioID: null, activeView: null,
  playing: false, t: 0, lastFrame: 0, loading: false, loaded: false };

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

async function openRun(runID) {
  const request = selectionTokens.next();
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
    const firstScenario = run.plan.scenarios?.[0];
    if (firstScenario) await openScenario(firstScenario.id);
    else $("labScenarioDetail").innerHTML = `<div class="lab-empty">This run has no scenarios.</div>`;
    return state.run === run && state.runID === runID && state.activeView === "runs" ? run : null;
  } catch (error) {
    if (!isCurrent()) return;
    $("labRunPane").hidden = true;
    $("labWelcome").hidden = false;
    showError($("labRunsList"), error);
    return null;
  }
}

async function openScenario(scenarioID) {
  state.playing = false;
  const scenario = state.run?.plan?.scenarios?.find((item) => item.id === scenarioID);
  if (!scenario) return;
  const runID = state.runID;
  const run = state.run;
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
  panel.innerHTML = labViews.renderScenarioDetail({ plan: run.plan, scenario, result, recording, reference });
  state.t = 0;
  let session = null;
  let referenceSession = null;
  if (recording.length) {
    try { session = Session.fromText(recordsToFileText(recording.map((record) => JSON.stringify(record)))); } catch { session = null; }
  }
  if (reference.length) {
    try { referenceSession = Session.fromText(recordsToFileText(reference.map((record) => JSON.stringify(record)))); } catch { referenceSession = null; }
  }
  bindScenarioPlayback(panel.querySelector(".lab-selected-scenario"), session, referenceSession, request, runID, scenarioID);
}

function bindScenarioPlayback(panel, session, referenceSession, request, runID, scenarioID) {
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
  }

  function tick(now) {
    if (!state.playing || !isCurrent()) return;
    const delta = state.lastFrame ? (now - state.lastFrame) / 1000 : 0;
    state.lastFrame = now;
    const next = state.t + delta;
    if (next >= duration) {
      state.playing = false;
      playButton.textContent = "Play";
      update(duration);
      return;
    }
    update(next);
    requestAnimationFrame(tick);
  }

  playButton.addEventListener("click", () => {
    if (state.playing) {
      state.playing = false;
      playButton.textContent = "Play";
      return;
    }
    if (state.t >= duration) update(0);
    state.playing = true;
    state.lastFrame = 0;
    playButton.textContent = "Pause";
    requestAnimationFrame(tick);
  });
  scrubber.addEventListener("input", () => update(Number(scrubber.value)));
  panel.addEventListener("click", (event) => {
    const seek = event.target.closest("[data-lab-seek]");
    if (seek) {
      state.playing = false;
      playButton.textContent = "Play";
      update(Number(seek.dataset.labSeek));
      return;
    }
    const track = event.target.closest("[data-lab-track]");
    if (!track) return;
    const rect = track.getBoundingClientRect();
    if (rect.width <= 0) return;
    const fraction = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
    state.playing = false;
    playButton.textContent = "Play";
    update(fraction * duration);
  });
  update(0);
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
  loadRun: async (runID) => {
    await openRun(runID);
    return state.activeView === "runs" && state.runID === runID ? state.run : null;
  },
  selectScenario: async (runID, scenarioID) => {
    if (state.activeView !== "runs" || state.runID !== runID
      || !state.run?.plan?.scenarios?.some((scenario) => scenario.id === scenarioID)) return false;
    await openScenario(scenarioID);
    return state.activeView === "runs" && state.runID === runID && state.scenarioID === scenarioID;
  },
  seek: seekCurrentPlayback,
});

const labOpenHandler = createLabOpenHandler({
  navigateToScenario: navigateCoverageThumbnail,
  navigateToRun: async ({ runID, scenarioID }) => {
    if (await activateLabRuns() === false) return false;
    const run = await openRun(runID);
    if ((run?.id ?? run?.summary?.id) !== runID) return false;
    if (!scenarioID) return true;
    if (!run.plan?.scenarios?.some((scenario) => scenario.id === scenarioID)) return false;
    await openScenario(scenarioID);
    return state.activeView === "runs" && state.runID === runID && state.scenarioID === scenarioID;
  },
});

const handleLabOpenRequest = (request) => {
  explicitNavigations += 1;
  return labOpenHandler(request);
};

window.FMPLabDashboard = { navigateToScenario: navigateCoverageThumbnail };

const dashboardEvents = new EventSource("/api/events");
installLabOpenCommandReceiver(dashboardEvents, handleLabOpenRequest);

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

