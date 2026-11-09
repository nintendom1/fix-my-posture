import { recordsToFileText, Session, clock } from "../../lib/session.mjs";
import * as replay from "../views.mjs";
import { installCoverageView } from "./coverage.mjs";

const OUTCOMES = ["passed", "failed", "inconclusive", "invalid", "notRun"];
const statusClass = (status) => status === "not tested" ? "not-tested" : status.replace(/[^a-z-]/g, "-");

export function statusForScenario(scenario, result) {
  if (!result) return "planned";
  if (result.outcome === "notRun") return "not tested";
  return OUTCOMES.includes(result.outcome) ? result.outcome : "invalid";
}

function statusBadges(status) {
  const executed = status !== "planned" && status !== "not tested";
  return `${executed ? '<span class="lab-status executed">executed</span>' : ""}<span class="lab-status ${statusClass(status)}">${replay.esc(status)}</span>`;
}

function dateLabel(value) {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) return "time unknown";
  return new Date(value).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}

function countsLine(counts = {}) {
  return [
    ["passed", counts.passed ?? 0], ["failed", counts.failed ?? 0],
    ["inconclusive", counts.inconclusive ?? 0], ["invalid", counts.invalid ?? 0],
  ].map(([label, count]) => `<span class="lab-count ${label}"><b>${replay.num(count)}</b> ${label}</span>`).join("");
}

export function renderRunCards(runs, selectedID = null) {
  if (!runs.length) return `<div class="lab-empty"><strong>No Movement Lab runs yet.</strong><span>Run <code>make lab</code> to create a synthetic run.</span></div>`;
  return runs.map((run) => {
    const progress = `${replay.num(run.evaluatedCount)}/${replay.num(run.scenarioCount)} scenarios evaluated`;
    const exercises = (Array.isArray(run.exerciseIDs) ? run.exerciseIDs : []).join(", ") || "Exercise unknown";
    const active = run.id === selectedID ? " selected" : "";
    return `<button type="button" class="lab-run-card${active}" data-lab-run="${replay.esc(run.id)}">
      <span class="lab-run-top"><strong>${replay.esc(run.title ?? run.id)}</strong><span class="lab-run-date">${replay.esc(dateLabel(run.createdAt))}</span></span>
      <span class="lab-run-sub">${replay.esc(exercises)} · ${replay.esc(progress)}</span>
      <span class="lab-counts">${countsLine(run.outcomes)}</span>
    </button>`;
  }).join("");
}

export function mutationDescription(mutations) {
  if (!Array.isArray(mutations) || !mutations.length) return "Canonical motion";
  return mutations.map((mutation) => {
    if (!mutation || typeof mutation !== "object") return "Unknown mutation";
    switch (mutation.kind) {
      case "jointOffset":
        return `${(mutation.joints ?? []).join(", ")} offset (${mutation.dx ?? 0}, ${mutation.dy ?? 0}) · peak ${mutation.peak ?? "?"}s`;
      case "depthScale": return `Depth ×${mutation.scale ?? "?"}${mutation.reps ? ` · reps ${mutation.reps.join(", ")}` : ""}`;
      case "asymmetry": return `${mutation.side ?? "?"} asymmetry ${mutation.amount ?? "?"}`;
      case "tempo": return `Tempo ×${mutation.scale ?? "?"}${mutation.reps ? ` · reps ${mutation.reps.join(", ")}` : ""}`;
      case "pause": return `Pause ${mutation.duration ?? "?"}s at ${mutation.at ?? "?"}s`;
      case "frameGap": return `Frame gap ${mutation.duration ?? "?"}s at ${mutation.at ?? "?"}s`;
      case "dropout": return `Missing landmarks: ${(mutation.joints ?? []).join(", ")} · ${mutation.from ?? "?"}–${mutation.to ?? "?"}s`;
      case "confidence": return `Confidence ${mutation.value ?? "?"} · ${(mutation.joints ?? []).join(", ")}`;
      case "framing": return `Framing ×${mutation.scale ?? "?"} · offset ${mutation.offsetX ?? 0}, ${mutation.offsetY ?? 0}`;
      default: return String(mutation.kind ?? "Unknown mutation");
    }
  }).join("; ");
}

export function assertionDescription(assertion) {
  if (!assertion || typeof assertion !== "object") return "Unknown expectation";
  switch (assertion.kind) {
    case "repCount":
      if (assertion.equals != null) return `Rep count = ${assertion.equals}`;
      return `Rep count ${assertion.min ?? "0"}–${assertion.max ?? "∞"}`;
    case "rejection": return `At least ${assertion.countMin} rejection(s) containing “${assertion.reasonContains}”`;
    case "formSignal": return `Form signal ${assertion.id} ${assertion.present ? "present" : "absent"}`;
    case "framing": return `Framing ${assertion.state} ${assertion.reached ? "reached" : "not reached"}`;
    case "spokenCue": return `Spoken cue containing “${assertion.textContains}” ${assertion.present ? "present" : "absent"}`;
    default: return String(assertion.kind ?? "Unknown expectation");
  }
}

export function renderScenarioList(plan, results, selectedID = null) {
  const resultMap = new Map(results.map((result) => [result.scenarioID, result]));
  return (plan.scenarios ?? []).map((scenario) => {
    const result = resultMap.get(scenario.id);
    const status = statusForScenario(scenario, result);
    const expected = (scenario.assertions ?? []).map(assertionDescription).join("; ") || "No frozen assertions";
    return `<button type="button" class="lab-scenario-card${scenario.id === selectedID ? " selected" : ""}" data-lab-scenario="${replay.esc(scenario.id)}">
      <span class="lab-scenario-card-top"><strong>${replay.esc(scenario.name ?? scenario.title ?? scenario.id)}</strong><span class="lab-status-group">${statusBadges(status)}</span></span>
      <span class="lab-scenario-purpose">${replay.esc(scenario.purpose ?? "No stated purpose.")}</span>
      <span class="lab-scenario-meta"><b>Mutation</b> ${replay.esc(mutationDescription(scenario.mutations))}</span>
      <span class="lab-scenario-meta"><b>Expected</b> ${replay.esc(expected)}</span>
      <span class="lab-scenario-meta"><b>By</b> ${replay.esc(scenario.author ?? plan.author ?? "unknown")}</span>
    </button>`;
  }).join("");
}

export function renderRunHeader(run) {
  const { plan, summary } = run;
  const exerciseNames = (summary.exerciseIDs ?? []).join(", ") || "Exercise unknown";
  const provenance = plan.author ?? "unknown";
  const guideRevision = summary.guideRevisions ? Object.values(summary.guideRevisions).join(", ") : "not recorded";
  return `<div class="lab-run-heading">
    <div><p class="lab-eyebrow">Selected run · ${replay.esc(dateLabel(summary.createdAt))}</p><h2>${replay.esc(plan.title ?? summary.title ?? summary.id)}</h2>
      <p>${replay.esc(plan.purpose ?? "No run purpose recorded.")}</p></div>
    <div class="lab-run-facts"><span><b>Exercise</b>${replay.esc(exerciseNames)}</span><span><b>Provenance</b>${replay.esc(provenance)}</span>
      <span><b>Completion</b>${replay.num(summary.evaluatedCount)}/${replay.num(summary.scenarioCount)} evaluated · ${replay.num(summary.plannedCount)} planned</span>
      <span><b>Plan created</b>${replay.esc(dateLabel(summary.planCreatedAt))}</span>
      <span><b>Outcomes</b>${countsLine(summary.outcomes)}</span><span><b>Guide</b>${replay.esc(guideRevision)}</span></div>
  </div>`;
}

function statusForAssertion(result, scenarioResult) {
  const item = (scenarioResult?.assertionResults ?? []).find((value) => value.assertionIndex === result);
  if (!scenarioResult || !item) return "planned";
  if (/^Inconclusive:/.test(item.detail ?? "")) return "inconclusive";
  return item.passed ? "passed" : "failed";
}

function timeOf(record) {
  return Number.isFinite(record?.t) ? record.t : null;
}

function failureTime(assertion, assertionResult, records) {
  const frames = records.filter((record) => record?.k === "f" && timeOf(record) != null);
  const fallback = timeOf(frames.at(-1)) ?? 0;
  const expectation = assertion ?? {};
  let found = null;
  if (expectation.kind === "rejection") {
    found = frames.find((record) => Array.isArray(record.rej)
      && record.rej.some((item) => String(item?.reason ?? "").includes(expectation.reasonContains ?? "")));
  } else if (expectation.kind === "formSignal") {
    found = frames.find((record) => Array.isArray(record.sig) && record.sig.includes(expectation.id));
  } else if (expectation.kind === "framing") {
    found = frames.find((record) => {
      const state = record.fr?.ok ? "reliable" : record.fr?.g ?? "unreliable";
      return state === expectation.state;
    });
  } else if (expectation.kind === "spokenCue") {
    const event = records.find((record) => record?.k === "e" && record.type === "speak"
      && String(record.text ?? "").toLowerCase().includes(String(expectation.textContains ?? "").toLowerCase()));
    found = event;
  } else if (expectation.kind === "repCount") {
    found = [...frames].reverse().find((record) => Array.isArray(record.out) && record.out.some((item) => item?.rep));
  }
  return timeOf(found) ?? fallback;
}

function failureLinks(scenario, result, records) {
  if (!result || result.outcome !== "failed") return "";
  const results = Array.isArray(result.assertionResults) ? result.assertionResults : [];
  return results.filter((item) => item.passed === false && !/^Inconclusive:/.test(item.detail ?? "")).map((item) => {
    const assertion = scenario.assertions?.[item.assertionIndex];
    const t = failureTime(assertion, item, records);
    return `<button type="button" class="lab-failure-link" data-lab-seek="${replay.num(t)}">Seek to ${replay.esc(clock(t))} · ${replay.esc(assertionDescription(assertion))}</button>`;
  }).join("");
}

function expectedObserved(scenario, result) {
  const assertions = Array.isArray(scenario.assertions) ? scenario.assertions : [];
  if (!assertions.length) return `<p class="lab-muted">No frozen assertions.</p>`;
  const assertionResults = Array.isArray(result?.assertionResults) ? result.assertionResults : [];
  return assertions.map((assertion, index) => {
    const observation = assertionResults.find((item) => item.assertionIndex === index);
    const status = statusForAssertion(index, result);
    return `<div class="lab-assertion ${statusClass(status)}"><span class="lab-status ${statusClass(status)}">${replay.esc(status)}</span>
      <span><b>Expected</b>${replay.esc(assertionDescription(assertion))}</span>
      <span><b>Observed</b>${replay.esc(observation?.detail ?? "Not tested")}</span></div>`;
  }).join("");
}

function observedSummary(result, status) {
  const observed = result?.observed ?? {};
  const list = (value) => Array.isArray(value) && value.length ? value.map((item) => String(item)).join(", ") : "none";
  const facts = [
    ["Reps", observed.reps ?? "unknown"],
    ["Rejections", list(observed.rejections)], ["Signals", list(observed.signals)],
    ["Framing", list(observed.framingChanges)], ["Cues", list(observed.cues)],
  ];
  return facts.map(([label, value]) => `<span><b>${label}</b>${typeof value === "number" ? replay.num(value) : replay.esc(value)}</span>`).join("");
}

function invalidReasons(result) {
  const reasons = Array.isArray(result?.invalidReasons) ? result.invalidReasons : [];
  if (!reasons.length) return "";
  return `<div class="lab-invalid-reasons"><b>Why this scenario is invalid</b><ul>${reasons.map((reason) => `<li>${replay.esc(reason)}</li>`).join("")}</ul></div>`;
}

function countingLane(session) {
  const frames = session.frames ?? [];
  const duration = Math.max(replay.num(session.duration), 0.001);
  let current = false;
  let start = 0;
  const segments = [];
  for (const frame of frames) {
    const next = frame.cnt === true;
    const t = Math.max(0, replay.num(frame.t));
    if (next !== current) {
      segments.push(`<span class="lab-count-segment ${current ? "on" : "off"}" style="left:${start / duration * 100}%;width:${Math.max(0, t - start) / duration * 100}%"></span>`);
      start = t;
      current = next;
    }
  }
  segments.push(`<span class="lab-count-segment ${current ? "on" : "off"}" style="left:${start / duration * 100}%;width:${Math.max(0, duration - start) / duration * 100}%"></span>`);
  return segments.join("");
}

function rejectionLane(session) {
  return (session.rejections ?? []).map((rejection) => {
    const title = `${clock(replay.num(rejection.t))} · ${rejection.side ? `${rejection.side}: ` : ""}${rejection.text ?? "attempt not counted"}`;
    return `<button type="button" class="lab-rejection-mark" data-lab-seek="${replay.num(rejection.t)}" style="left:${replay.num(rejection.t) / Math.max(replay.num(session.duration), 0.001) * 100}%" title="${replay.esc(title)}">×</button>`;
  }).join("");
}

function repOnlyLane(session) {
  return replay.repLane({ ...session, rejections: [] });
}

function timeline(session) {
  const duration = Math.max(replay.num(session.duration), 0.001);
  const lanes = [
    ["Phase", "lane", replay.phaseLane(session)], ["Reps", "lane marks", repOnlyLane(session)],
    ["Rejections", "lane marks", rejectionLane(session)], ["Framing", "lane", replay.framingLane(session)],
    ["Counting", "lane", countingLane(session)],
  ];
  return `<div class="lab-timeline" data-lab-duration="${duration}">
    <div class="lab-time-scale"><span>0:00</span><span>${replay.esc(clock(duration))}</span></div>
    ${lanes.map(([label, classes, html]) => `<div class="lab-lane-row"><span class="lab-lane-name">${label}</span><div class="lab-lane ${classes}" data-lab-track>${html}</div></div>`).join("")}
    <span class="lab-shared-playhead" data-lab-playhead></span>
  </div>`;
}

function parseSession(records) {
  if (!Array.isArray(records) || records.length === 0) return null;
  try { return Session.fromText(recordsToFileText(records.map((record) => JSON.stringify(record)))); }
  catch { return null; }
}

export function renderScenarioDetail({ plan, scenario, result = null, recording = [], reference = [] }) {
  const status = statusForScenario(scenario, result);
  const session = parseSession(recording);
  const referenceSession = parseSession(reference);
  const authorship = scenario.author ?? plan.author ?? "unknown";
  const mutation = mutationDescription(scenario.mutations);
  const expectedHTML = expectedObserved(scenario, result);
  const links = failureLinks(scenario, result, recording);
  const hasPlayback = session?.frames.length > 0;
  const referenceText = referenceSession?.frames.length ? "Canonical reference" : "Reference unavailable";
  return `<article class="lab-selected-scenario" data-lab-scenario-id="${replay.esc(scenario.id)}" data-lab-status="${replay.esc(status)}">
    <header class="lab-scenario-heading"><div><p class="lab-eyebrow">${replay.esc(scenario.category ?? "scenario")} · revision ${replay.num(scenario.revision)}</p>
      <h3>${replay.esc(scenario.name ?? scenario.title ?? scenario.id)}</h3><p>${replay.esc(scenario.purpose ?? "No stated purpose.")}</p></div>
      <div class="lab-status-group">${statusBadges(status)}</div></header>
    <div class="lab-intent"><span><b>Intended mutation</b>${replay.esc(mutation)}</span><span><b>Expected behavior</b>${replay.esc((scenario.assertions ?? []).map(assertionDescription).join("; ") || "No frozen assertions")}</span>
      <span><b>Provenance</b>${replay.esc(authorship)}${scenario.parentRevision != null ? ` · follows revision ${replay.num(scenario.parentRevision)}` : ""}</span></div>
    <section class="lab-playback" data-lab-duration="${replay.num(session?.duration)}">
      <div class="lab-stage-pair">
        <div class="lab-stage-panel"><h4>${referenceText}</h4><div class="lab-stage" data-lab-stage="reference"><svg viewBox="0 0 1080 1920" preserveAspectRatio="xMidYMid meet"></svg></div></div>
        <div class="lab-stage-panel"><h4>Modified movement</h4><div class="lab-stage" data-lab-stage="modified"><svg viewBox="0 0 1080 1920" preserveAspectRatio="xMidYMid meet"></svg></div></div>
      </div>
      ${hasPlayback ? `<div class="lab-player-controls"><button type="button" class="button" data-lab-play>Play</button><span class="mono" data-lab-clock>0:00.00 / ${replay.esc(clock(session.duration))}</span>
        <input type="range" min="0" max="${replay.num(session.duration)}" step="0.033333" value="0" data-lab-scrubber aria-label="Scrub synchronized reference and modified motion"></div>
        ${timeline(session)}
        ${links ? `<div class="lab-failure-links"><b>Failure moments</b>${links}</div>` : ""}`
        : `<div class="lab-no-playback">${status === "planned" || status === "not tested" ? `This scenario is ${replay.esc(status)}; no execution recording is available.` : "No materialized frames are available for this scenario."}</div>`}
    </section>
    <section class="lab-expected-observed"><h4>Expected vs. observed</h4><div class="lab-assertions">${expectedHTML}</div>
      ${invalidReasons(result)}<div class="lab-observed"><strong>Observed summary</strong>${observedSummary(result, status)}</div></section>
  </article>`;
}

export function setPlaybackFrame(container, session, t, { toggles = { mirror: true, hud: false, angles: true, thresholds: true, labels: false, trail: false } } = {}) {
  if (!container || !session?.frames?.length) return;
  const index = session.frameIndexAt(t);
  const frame = session.frames[index];
  if (!frame) return;
  const [width, height] = (frame.size ?? session.imageSize).map((value) => replay.num(value, 1000));
  const stage = container.querySelector("svg");
  const wrapper = container.closest(".lab-stage");
  wrapper.style.aspectRatio = `${width} / ${height}`;
  stage.setAttribute("viewBox", `0 0 ${width} ${height}`);
  stage.innerHTML = replay.stageSVG(session, frame, { width, height, toggles, glow: replay.phaseColor(session.stateAt(t)?.phase) });
}

if (typeof document !== "undefined") installCoverageView();

