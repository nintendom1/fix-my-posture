import { recordsToFileText, Session, clock } from "../../lib/session.mjs";
import { num, esc, stageSVG } from "../views.mjs";
import { chooseKeyframe } from "../../lib/lab/keyframe.mjs";

const SVG_WIDTH = 1080;
const SVG_HEIGHT = 1920;
const TOGGLES = { mirror: true, hud: false, angles: false, thresholds: false, labels: false, trail: false };

function scenarioKey(scenario) { return `${scenario.id}\u0000${scenario.revision}`; }
function scenarioDOMKey(scenario) { return `${encodeURIComponent(scenario.id)}|${scenario.revision}`; }
function cellKey(exercise, category) { return `${encodeURIComponent(exercise)}|${category}`; }
function humanize(value) { return String(value ?? "unknown").replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase()); }
function statusClass(value) { return String(value ?? "unknown").replace(/[^a-z-]/g, "-"); }

function parseSession(records) {
  if (!Array.isArray(records) || !records.length) return null;
  try { return Session.fromText(recordsToFileText(records.map((record) => JSON.stringify(record)))); }
  catch { return null; }
}

function highlightSVG(session, frame, joints, { mirror = true } = {}) {
  const names = new Set(Array.isArray(joints) ? joints : []);
  return [...names].map((name) => {
    const joint = session.joint(frame, name);
    if (!joint || !Number.isFinite(joint.x) || !Number.isFinite(joint.y)) return "";
    const x = mirror ? SVG_WIDTH - joint.x : joint.x;
    return `<circle class="coverage-joint-highlight" cx="${num(x)}" cy="${num(joint.y)}" r="34" fill="rgba(255,181,71,.12)" stroke="#ffb547" stroke-width="10"/>`;
  }).join("");
}

function miniSVG(session, frame, joints) {
  const skeleton = stageSVG(session, frame, {
    width: SVG_WIDTH, height: SVG_HEIGHT, toggles: TOGGLES, glow: "#c9b3ff",
  });
  return `<svg class="coverage-mini-svg" viewBox="0 0 ${SVG_WIDTH} ${SVG_HEIGHT}" role="img" aria-label="Recorded pose keyframe">${skeleton}${highlightSVG(session, frame, joints)}</svg>`;
}

/** Render stored reference and mutated frames at one consistent scale and viewpoint. */
export function renderCoverageThumbnail(scenario, recording, reference = []) {
  const keyframe = chooseKeyframe(scenario, recording, reference);
  const session = parseSession(recording);
  const referenceSession = parseSession(reference);
  const frame = session?.frames?.[keyframe.frameIndex] ?? null;
  const referenceFrame = referenceSession?.frames?.[keyframe.referenceIndex] ?? null;
  if (!frame) {
    return { keyframe, html: `<div class="coverage-no-frame">No stored materialized keyframe is available for this scenario.</div>` };
  }
  const runID = esc(scenario.playbackRunID ?? scenario.sourceRunID ?? scenario.artifactRunIDs?.[0] ?? "");
  const scenarioID = esc(scenario.id);
  const timestamp = num(keyframe.timestamp);
  const descriptor = esc(keyframe.descriptor);
  const referenceMarkup = referenceFrame
    ? `<span class="coverage-mini-panel"><small>Reference</small>${miniSVG(referenceSession, referenceFrame, keyframe.affectedJoints)}</span>`
    : "";
  const comparisonLabel = referenceFrame ? "Reference compared with mutation" : "Stored mutation frame";
  const columns = referenceFrame ? 2 : 1;
  return {
    keyframe,
    html: `<button type="button" class="coverage-thumbnail" data-lab-seek-run="${runID}" data-lab-seek-scenario="${scenarioID}" data-lab-seek-time="${timestamp}" aria-label="Open ${scenarioID} at ${descriptor}">
      <span class="coverage-mini-pair" style="--coverage-mini-columns:${columns}" aria-label="${esc(comparisonLabel)}">
        ${referenceMarkup}<span class="coverage-mini-panel"><small>${referenceFrame ? "Mutated" : "Keyframe"}</small>${miniSVG(session, frame, keyframe.affectedJoints)}</span>
      </span>
      <span class="coverage-thumbnail-caption"><b>${descriptor}</b><span>${esc(clock(timestamp))} · ${esc(keyframe.annotation)}</span></span>
    </button>`,
  };
}

function mutationSummary(scenario) {
  const mutation = scenario.mutations?.[0];
  if (!mutation) return "Canonical motion";
  if (mutation.kind === "jointOffset") return `${(mutation.joints ?? []).join(", ")} offset`;
  if (mutation.kind === "depthScale") return `Depth ×${mutation.scale}`;
  if (mutation.kind === "asymmetry") return `${mutation.side} asymmetry`;
  if (mutation.kind === "tempo") return `Tempo ×${mutation.scale}`;
  if (mutation.kind === "pause") return `Pause at ${mutation.at} s`;
  if (mutation.kind === "frameGap") return `Frame gap at ${mutation.at} s`;
  if (mutation.kind === "dropout") return `Missing ${(mutation.joints ?? []).join(", ")}`;
  if (mutation.kind === "confidence") return `Confidence ${(mutation.joints ?? []).join(", ")}`;
  if (mutation.kind === "framing") return `Framing ×${mutation.scale}`;
  return String(mutation.kind ?? "Mutation");
}

/** Build one safely escaped scenario card, including a seek control when a keyframe exists. */
export function renderCoverageScenarioRow(scenario, { thumbnailHTML = "" } = {}) {
  const domKey = esc(scenarioDOMKey(scenario));
  return `<article class="coverage-scenario" data-coverage-row="${domKey}">
    <div class="coverage-scenario-info"><div class="coverage-scenario-heading"><h4>${esc(scenario.id)} <span>rev ${num(scenario.revision)}</span></h4><span class="lab-status ${statusClass(scenario.status)}">${esc(scenario.status)}</span></div>
      <p>${esc(scenario.purpose ?? "No stated purpose.")}</p><div class="coverage-scenario-meta"><span>${esc(mutationSummary(scenario))}</span><span>scenario coverage · ${esc(scenario.exercise)}</span></div>
      ${scenario.sourceRunID ? `<button type="button" class="button ghost coverage-edit-button" data-lab-edit-run="${esc(scenario.sourceRunID)}" data-lab-edit-scenario="${esc(scenario.id)}">Edit movement</button>` : ""}</div>
    <div class="coverage-thumb-slot" data-coverage-scenario="${domKey}">${thumbnailHTML || `<div class="coverage-thumb-loading">Loading stored keyframe…</div>`}</div>
  </article>`;
}

function countSummary(counts) {
  return Object.entries(counts ?? {}).filter(([, value]) => value > 0)
    .map(([status, value]) => `<span class="coverage-count ${statusClass(status)}"><b>${num(value)}</b> ${esc(status)}</span>`).join("")
    || `<span class="coverage-count">0 scenarios</span>`;
}

function filteredScenarios(cell, status) {
  return status === "all" ? cell.scenarios : cell.scenarios.filter((scenario) => scenario.status === status);
}

function renderCell(cell, status, expanded) {
  const matches = filteredScenarios(cell, status);
  const key = cellKey(cell.exercise, cell.category);
  const noScenarios = cell.scenarios.length === 0;
  if (noScenarios && status !== "all" && status !== "not tested") {
    return `<div class="coverage-cell filtered-away" aria-hidden="true"></div>`;
  }
  const className = noScenarios ? "not-tested" : matches.length ? statusClass(cell.status) : "filtered-empty";
  const summary = noScenarios ? "not tested" : matches.length ? cell.status : "No matching scenarios";
  const count = noScenarios ? "0 scenarios" : `${matches.length} of ${cell.scenarios.length} scenarios`;
  return `<div class="coverage-cell ${className}">
    <button type="button" class="coverage-cell-toggle" data-coverage-cell="${esc(key)}" aria-expanded="${expanded}" ${noScenarios ? "disabled" : ""}>
      <span class="coverage-cell-status">${esc(summary)}</span><span class="coverage-cell-count">${esc(count)}</span>
      ${matches.length ? `<span class="coverage-cell-counts">${countSummary(countsFor(matches))}</span>` : ""}
    </button>
  </div>`;
}

function countsFor(scenarios) {
  const result = {};
  for (const scenario of scenarios) result[scenario.status] = (result[scenario.status] ?? 0) + 1;
  return result;
}

/** Render the exercises × categories matrix. */
export function renderCoverageMatrix(model, { exercise = "all", category = "all", status = "all", expanded = new Set() } = {}) {
  const exercises = model.exercises.filter((value) => exercise === "all" || value === exercise);
  const categories = model.categories.filter((value) => category === "all" || value === category);
  if (!exercises.length) return `<div class="lab-empty">No scenarios match these filters.</div>`;
  return `<div class="coverage-matrix-scroll"><div class="coverage-matrix${categories.length === 1 ? " one-category" : ""}" style="--coverage-category-count:${categories.length}">
    <div class="coverage-matrix-head"><span>Exercise</span>${categories.map((item) => `<span>${esc(humanize(item))}</span>`).join("")}</div>
    ${exercises.map((item) => `<div class="coverage-matrix-row"><h3>${esc(humanize(item))}</h3>${categories.map((kind) => {
      const cell = model.cells.find((candidate) => candidate.exercise === item && candidate.category === kind)
        ?? { exercise: item, category: kind, scenarios: [], counts: {}, status: "not tested" };
      return renderCell(cell, status, expanded.has(cellKey(item, kind)));
    }).join("")}${categories.map((kind) => {
      const cell = model.cells.find((candidate) => candidate.exercise === item && candidate.category === kind)
        ?? { exercise: item, category: kind, scenarios: [], counts: {}, status: "not tested" };
      const key = cellKey(item, kind);
      const matches = filteredScenarios(cell, status);
      if (!expanded.has(key) || !matches.length) return "";
      return `<section class="coverage-drilldown"><h4>${esc(humanize(kind))} · ${matches.length} scenario${matches.length === 1 ? "" : "s"}</h4>
        <div class="coverage-scenario-list">${matches.map((scenario) => renderCoverageScenarioRow(scenario)).join("")}</div></section>`;
    }).join("")}</div>`).join("")}
  </div></div>`;
}

/** Delegate a thumbnail click to the existing playback flow with its exact time. */
export function bindCoverageSeekHandler(root, seek) {
  root.addEventListener("click", (event) => {
    const button = event.target.closest?.("[data-lab-seek-run]");
    if (!button) return;
    event.preventDefault?.();
    void seek({ runID: button.dataset.labSeekRun, scenarioID: button.dataset.labSeekScenario,
      timestamp: num(button.dataset.labSeekTime) });
  });
}

/** Sequence run loading, scenario selection, and seek so stale dashboard DOM cannot satisfy navigation. */
export function createCoveragePlaybackNavigator({ activateRuns, loadRun, selectScenario, seek }) {
  return async ({ runID, scenarioID, timestamp }) => {
    if (typeof runID !== "string" || typeof scenarioID !== "string" || !Number.isFinite(Number(timestamp))) return false;
    if (await activateRuns() === false) return false;
    const run = await loadRun(runID);
    const loadedRunID = run?.id ?? run?.summary?.id;
    if (loadedRunID !== runID || !run.plan?.scenarios?.some((scenario) => scenario.id === scenarioID)) return false;
    if (await selectScenario(runID, scenarioID) === false) return false;
    return Boolean(await seek({ runID, scenarioID, timestamp: Number(timestamp) }));
  };
}

async function getJSON(url) {
  const response = await fetch(url);
  const value = await response.json().catch(() => null);
  if (!response.ok) throw new Error(value?.error ?? `${response.status} ${response.statusText}`);
  return value;
}

async function loadArtifacts(scenario) {
  for (const runID of scenario.artifactRunIDs ?? [scenario.sourceRunID]) {
    if (!runID) continue;
    const base = `/api/lab/runs/${encodeURIComponent(runID)}/scenarios/${encodeURIComponent(scenario.id)}`;
    const [recording, reference] = await Promise.all([
      getJSON(`${base}/recording`).catch(() => []), getJSON(`${base}/reference`).catch(() => []),
    ]);
    if (recording.length) return { recording, reference, runID };
  }
  return { recording: [], reference: [], runID: null };
}

function installView() {
  const dashboard = document.getElementById("labDashboard");
  const layout = dashboard?.querySelector(".lab-layout");
  const tabs = dashboard?.querySelector(".lab-view-tabs");
  if (!dashboard || !layout || !tabs || dashboard.querySelector("#labCoverageView")) return null;
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = "Scenario coverage";
  button.dataset.labCoverageToggle = "true";
  button.setAttribute("aria-current", "false");
  tabs.insertBefore(button, tabs.querySelector('[data-lab-view="recordings"]'));
  const view = document.createElement("main");
  view.id = "labCoverageView";
  view.className = "lab-coverage-view";
  view.hidden = true;
  view.innerHTML = `<header class="coverage-header"><div><p class="lab-eyebrow">Movement Lab</p><h1>Scenario coverage</h1><p>Stored scenario results grouped by exercise and category. This is scenario coverage, not code coverage.</p></div>
    <div class="coverage-filters"><label>Exercise<select id="coverageExercise"><option value="all">All exercises</option></select></label>
      <label>Category<select id="coverageCategory"><option value="all">All categories</option></select></label>
      <label>Status<select id="coverageStatus"><option value="all">All statuses</option></select></label></div></header>
    <div id="coverageMessage" class="coverage-message" role="status">Loading stored scenario plans…</div>
    <div id="coverageMatrix"></div>`;
  layout.insertAdjacentElement("afterend", view);
  return { dashboard, layout, tabs, button, view };
}

/** Install the browser view from the already-loaded lab views module. */
export function installCoverageView() {
  if (typeof document === "undefined") return;
  const elements = installView();
  if (!elements) return;
  const { dashboard, layout, button, view } = elements;
  let model = null;
  let active = false;
  let request = 0;
  const expanded = new Set();
  const artifactCache = new Map();
  const exerciseSelect = view.querySelector("#coverageExercise");
  const categorySelect = view.querySelector("#coverageCategory");
  const statusSelect = view.querySelector("#coverageStatus");
  const matrix = view.querySelector("#coverageMatrix");
  const message = view.querySelector("#coverageMessage");

  function updateTabs() {
    button.classList.toggle("active", active);
    button.setAttribute("aria-current", active ? "page" : "false");
    for (const tab of dashboard.querySelectorAll("[data-lab-view]")) {
      tab.classList.toggle("active", false);
      tab.setAttribute("aria-current", "false");
    }
  }

  function deactivate() {
    if (!active) return;
    active = false;
    request += 1;
    view.hidden = true;
    layout.hidden = false;
    updateTabs();
  }

  async function fetchModel() {
    const token = ++request;
    message.textContent = "Loading stored scenario plans…";
    try {
      model = await getJSON("/api/lab/coverage");
      if (!active || request !== token) return;
      exerciseSelect.innerHTML = `<option value="all">All exercises</option>${model.exercises.map((item) => `<option value="${esc(item)}">${esc(humanize(item))}</option>`).join("")}`;
      categorySelect.innerHTML = `<option value="all">All categories</option>${model.categories.map((item) => `<option value="${esc(item)}">${esc(humanize(item))}</option>`).join("")}`;
      statusSelect.innerHTML = `<option value="all">All statuses</option>${model.statuses.map((item) => `<option value="${esc(item)}">${esc(item)}</option>`).join("")}`;
      message.textContent = model.scenarios.length ? `${model.scenarios.length} scenario revisions · scenario coverage` : "No stored Movement Lab scenarios yet.";
      paint();
    } catch (error) {
      if (!active || request !== token) return;
      message.textContent = error?.message ?? String(error);
      matrix.innerHTML = "";
    }
  }

  async function seekScenario(selection) {
    const navigate = window.FMPLabDashboard?.navigateToScenario;
    if (typeof navigate !== "function") return false;
    try { return await navigate(selection); }
    catch { return false; }
  }

  function paint() {
    if (!model) return;
    const token = ++request;
    const filters = { exercise: exerciseSelect.value, category: categorySelect.value,
      status: statusSelect.value, expanded };
    matrix.innerHTML = renderCoverageMatrix(model, filters);
    const slots = [...matrix.querySelectorAll("[data-coverage-scenario]")];
    for (const slot of slots) {
      const scenario = model.scenarios.find((item) => scenarioDOMKey(item) === slot.dataset.coverageScenario);
      if (!scenario) continue;
      const key = `${scenarioKey(scenario)}\u0000${scenario.artifactRunIDs.join(",")}`;
      if (!artifactCache.has(key)) artifactCache.set(key, loadArtifacts(scenario));
      artifactCache.get(key).then(({ recording, reference, runID }) => {
        if (!active || request !== token || !slot.isConnected) return;
        const rendered = renderCoverageThumbnail({ ...scenario, playbackRunID: runID }, recording, reference);
        slot.innerHTML = rendered.html;
      }).catch(() => {
        if (active && request === token && slot.isConnected) slot.innerHTML = `<div class="coverage-no-frame">Stored keyframe unavailable.</div>`;
      });
    }
  }

  bindCoverageSeekHandler(view, seekScenario);
  view.addEventListener("click", (event) => {
    const cell = event.target.closest("[data-coverage-cell]");
    if (!cell || cell.disabled) return;
    event.preventDefault();
    const key = cell.dataset.coverageCell;
    if (expanded.has(key)) expanded.delete(key); else expanded.add(key);
    paint();
  });
  for (const select of [exerciseSelect, categorySelect, statusSelect]) select.addEventListener("change", paint);
  document.addEventListener("click", (event) => {
    if (event.target.closest?.("[data-lab-coverage-toggle]")) {
      event.preventDefault();
      event.stopImmediatePropagation();
      active = true;
      layout.hidden = true;
      view.hidden = false;
      document.getElementById("app").hidden = true;
      updateTabs();
      if (!model) fetchModel(); else paint();
      return;
    }
    if (event.target.closest?.("[data-lab-view]")) deactivate();
  });
  document.getElementById("labRefresh")?.addEventListener("click", () => { if (active) fetchModel(); });
}
