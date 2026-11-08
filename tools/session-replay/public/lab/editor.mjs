import { Session, clock, recordsToFileText } from "../../lib/session.mjs";
import { esc, framingLane, num, phaseLane, repLane, stageSVG } from "../views.mjs";

const WIDTH = 1080;
const HEIGHT = 1920;
const PRESETS = [
  ["jointOffset", "Joint offset"], ["depthScale", "Depth / ROM"], ["asymmetry", "Asymmetry"],
  ["tempo", "Tempo"], ["pause", "Pause"], ["frameGap", "Frame gap"],
  ["dropout", "Dropout"], ["confidence", "Confidence"], ["framing", "Framing"],
];

function parseSession(records) {
  if (!Array.isArray(records) || !records.length) return null;
  try { return Session.fromText(recordsToFileText(records.map((record) => JSON.stringify(record)))); }
  catch { return null; }
}

function bodyHeight(session, frame) {
  const ys = session.jointOrder.map((name) => session.joint(frame, name)?.y).filter(Number.isFinite);
  return ys.length > 1 ? Math.max(1, Math.max(...ys) - Math.min(...ys)) : HEIGHT * 0.45;
}

function clamp(value, minimum, maximum) { return Math.min(maximum, Math.max(minimum, value)); }

/** Convert pointer movement to the schema's body-height displacement units. */
export function dragToJointOffset({ joint, deltaX, deltaY, height, peak, rise, fall, strength, duration, mode = "constrained" }) {
  if (![deltaX, deltaY, height, peak, rise, fall, strength, duration].every(Number.isFinite) || height <= 0
    || (mode !== "constrained" && mode !== "raw")) {
    throw new TypeError("Drag coordinates, influence controls, duration, and body height must be finite.");
  }
  const time = clamp(peak, 0, Math.max(0, duration));
  let dx = clamp(deltaX / height, -0.5, 0.5);
  let dy = clamp(deltaY / height, -0.5, 0.5);
  const maximumVector = mode === "constrained" ? 0.3 : 0.5;
  const magnitude = Math.hypot(dx, dy);
  if (magnitude > maximumVector) { dx *= maximumVector / magnitude; dy *= maximumVector / magnitude; }
  return { kind: "jointOffset", joints: [joint], dx, dy, peak: time,
    rise: clamp(rise, 0, Math.min(10, time)), fall: clamp(fall, 0, Math.min(10, duration - time)),
    strength: clamp(strength, 0, 1) };
}

function influence(time, mutation) {
  const peak = mutation.peak;
  if (time === peak) return mutation.strength;
  if (time < peak) {
    if (mutation.rise <= 0 || time < peak - mutation.rise) return 0;
    return mutation.strength * (0.5 - 0.5 * Math.cos(Math.PI * (time - peak + mutation.rise) / mutation.rise));
  }
  if (mutation.fall <= 0 || time > peak + mutation.fall) return 0;
  return mutation.strength * (0.5 + 0.5 * Math.cos(Math.PI * (time - peak) / mutation.fall));
}

function replaceJoint(frame, index, update) {
  const next = structuredClone(frame);
  for (const key of ["j", "lo", "est"]) {
    if (!Array.isArray(next[key])) continue;
    if (key === "j") {
      if (next.j[index]) next.j[index] = update(next.j[index], key);
    } else {
      next[key] = next[key].map((entry) => entry[0] === index ? update(entry, key) : entry);
    }
  }
  return next;
}

function selectedRep(session, time) {
  const state = session.stateAt(time);
  return Math.max(1, num(state?.reps) + 1);
}

/** Apply display-only edits to a stored sample; the Swift pipeline remains authoritative. */
export function previewFrame(session, frame, time, mutations, { rep = selectedRep(session, time) } = {}) {
  if (!frame) return null;
  let output = structuredClone(frame);
  const height = bodyHeight(session, frame);
  const standing = session.frames[0];
  const indices = new Map(session.jointOrder.map((name, index) => [name, index]));
  for (const mutation of mutations) {
    if (Array.isArray(mutation.reps) && !mutation.reps.includes(rep)) continue;
    if (mutation.kind === "frameGap" && time >= mutation.at && time < mutation.at + mutation.duration) {
      output = { ...output, j: [], lo: [], est: [] };
      continue;
    }
    if (["dropout", "confidence"].includes(mutation.kind) && time >= mutation.from && time < mutation.to) {
      for (const name of mutation.joints ?? []) {
        const index = indices.get(name);
        if (index === undefined) continue;
        if (mutation.kind === "dropout") {
          if (Array.isArray(output.j) && index < output.j.length) output.j[index] = null;
          output.lo = (output.lo ?? []).filter((entry) => entry?.[0] !== index);
          output.est = (output.est ?? []).filter((entry) => entry?.[0] !== index);
        } else {
          output = replaceJoint(output, index, (entry, key) => {
            const copy = [...entry];
            if (key === "j") copy[2] = mutation.value;
            else if (key === "lo") copy[3] = mutation.value;
            return copy;
          });
        }
      }
      continue;
    }
    if (mutation.kind === "jointOffset") {
      const amount = influence(time, mutation);
      if (amount <= 0) continue;
      for (const name of mutation.joints ?? []) {
        const index = indices.get(name);
        if (index === undefined) continue;
        output = replaceJoint(output, index, (entry, key) => {
          const copy = [...entry];
          const xIndex = key === "j" ? 0 : 1;
          const yIndex = xIndex + 1;
          copy[xIndex] = num(copy[xIndex]) + mutation.dx * height * amount;
          copy[yIndex] = num(copy[yIndex]) + mutation.dy * height * amount;
          return copy;
        });
      }
      continue;
    }
    if (mutation.kind === "depthScale") {
      for (const name of ["leftHip", "rightHip", "leftKnee", "rightKnee"]) {
        const index = indices.get(name);
        const base = standing && session.joint(standing, name);
        if (index === undefined || !base || base.y == null) continue;
        output = replaceJoint(output, index, (entry, key) => {
          const copy = [...entry];
          const yIndex = key === "j" ? 1 : 2;
          copy[yIndex] = base.y + (num(copy[yIndex]) - base.y) * mutation.scale;
          return copy;
        });
      }
      continue;
    }
    if (mutation.kind === "asymmetry") {
      const index = indices.get(`${mutation.side}Hip`);
      if (index !== undefined) output = replaceJoint(output, index, (entry, key) => {
        const copy = [...entry];
        const yIndex = key === "j" ? 1 : 2;
        copy[yIndex] = num(copy[yIndex]) + mutation.amount * height;
        return copy;
      });
      continue;
    }
    if (mutation.kind === "framing") {
      for (const name of session.jointOrder) {
        const index = indices.get(name);
        output = replaceJoint(output, index, (entry, key) => {
          const copy = [...entry];
          const xIndex = key === "j" ? 0 : 1;
          const yIndex = xIndex + 1;
          copy[xIndex] = WIDTH / 2 + (num(copy[xIndex]) - WIDTH / 2) * mutation.scale + mutation.offsetX * height;
          copy[yIndex] = HEIGHT / 2 + (num(copy[yIndex]) - HEIGHT / 2) * mutation.scale + mutation.offsetY * height;
          return copy;
        });
      }
    }
  }
  return output;
}

function htmlLane(label, content, marks = false) {
  return `<div class="lab-lane-row"><span class="lab-lane-name">${label}</span><div class="lab-lane${marks ? " marks" : ""}" data-editor-track>${content}</div></div>`;
}

function rejectionLane(session) {
  const duration = Math.max(num(session.duration), 0.001);
  return (session.rejections ?? []).map((item) => `<span class="lab-rejection-mark" style="left:${num(item.t) / duration * 100}%" title="${esc(item.text ?? "Rejected attempt")}">×</span>`).join("");
}

function cueLane(session) {
  const cues = (session.timeline ?? []).filter((item) => item.kind === "cue" || item.type === "cue");
  const duration = Math.max(num(session.duration), 0.001);
  return cues.map((item) => `<span class="diamond" style="left:${num(item.t) / duration * 100}%" title="${esc(item.title ?? item.detail ?? "Coaching cue")}"></span>`).join("");
}

function timeline(session) {
  const duration = Math.max(num(session.duration), 0.001);
  return `<div class="lab-timeline lab-editor-timeline" data-editor-duration="${duration}">
    <div class="lab-time-scale"><span>0:00</span><span>${esc(clock(duration))}</span></div>
    ${htmlLane("Phases", phaseLane(session))}${htmlLane("Rep events", repLane(session), true)}
    ${htmlLane("Rejections", rejectionLane(session), true)}${htmlLane("Tracking", framingLane(session))}
    ${htmlLane("Coaching cues", cueLane(session), true)}<span class="lab-shared-playhead" data-editor-playhead></span>
  </div>`;
}

function svgFor(session, frame, time, mutations, { editable = false, color = "#c9b3ff" } = {}) {
  const toggles = { mirror: true, hud: false, angles: false, thresholds: false, labels: false, trail: false };
  const eventSession = state.recordingSession ?? session;
  const pose = previewFrame(session, frame, time, mutations, { rep: selectedRep(eventSession, time) });
  const content = stageSVG(session, pose, { width: WIDTH, height: HEIGHT, toggles, glow: color });
  const hits = editable ? session.jointOrder.map((name) => {
    const joint = session.joint(pose, name);
    if (!joint || !Number.isFinite(joint.x) || !Number.isFinite(joint.y)) return "";
    return `<circle class="lab-editor-hit" data-editor-joint="${esc(name)}" cx="${WIDTH - joint.x}" cy="${joint.y}" r="36" aria-label="Drag ${esc(name)}"/>`;
  }).join("") : "";
  return `<svg viewBox="0 0 ${WIDTH} ${HEIGHT}" preserveAspectRatio="xMidYMid meet">${content}${hits}</svg>`;
}

function preset(kind, time, duration) {
  const at = clamp(time, 0, Math.max(0, duration));
  const until = Math.min(duration, at + 0.35);
  const from = Math.max(0, at - 0.35);
  switch (kind) {
    case "jointOffset": return { kind, joints: ["leftKnee"], dx: -0.04, dy: 0, peak: at,
      rise: Math.min(0.35, at), fall: Math.min(0.35, duration - at), strength: 1 };
    case "depthScale": return { kind, scale: 0.7 };
    case "asymmetry": return { kind, side: "left", amount: 0.06 };
    case "tempo": return { kind, scale: 1.2 };
    case "pause": return { kind, at, duration: Math.min(0.35, Math.max(0, duration - at)) };
    case "frameGap": return { kind, at: from, duration: Math.min(0.2, duration - from) };
    case "dropout": return { kind, joints: ["leftKnee"], from, to: until };
    case "confidence": return { kind, joints: ["leftKnee"], from, to: until, value: 0.3 };
    case "framing": return { kind, scale: 1.1, offsetX: 0.08, offsetY: 0 };
    default: return null;
  }
}

function mutationLabel(mutation) {
  if (mutation.kind === "jointOffset") return `${mutation.joints.join(", ")} offset · peak ${clock(mutation.peak)}`;
  if (mutation.kind === "depthScale") return `depth ×${mutation.scale}`;
  return mutation.kind;
}

export function editorMarkup() {
  const presetButtons = PRESETS.map(([kind, title]) => `<button type="button" class="button ghost" data-editor-preset="${kind}">${title}</button>`).join("");
  return `<section class="lab-editor-shell" id="labEditorShell" hidden><div class="lab-editor-card" role="dialog" aria-modal="true" aria-labelledby="labEditorTitle">
    <header class="lab-editor-header"><div><p class="lab-eyebrow">Movement Lab · developer editor</p><h2 id="labEditorTitle">Hybrid movement editor</h2><p data-editor-subtitle></p></div><button type="button" class="button ghost" data-editor-close>Close</button></header>
    <div class="lab-editor-preview-label"><b>Preview only.</b> Display edits approximate the stored pose samples. Saving always reruns the plan through Swift.</div>
    <div class="lab-editor-toolbar"><fieldset><legend>Mode</legend><label><input type="radio" name="editor-mode" value="constrained"> Constrained</label><label><input type="radio" name="editor-mode" value="raw"> Raw landmarks</label></fieldset>
      <fieldset><legend>Comparison</legend><label><input type="radio" name="editor-view" value="side-by-side"> Side by side</label><label><input type="radio" name="editor-view" value="overlay"> Overlay</label><label><input type="radio" name="editor-view" value="difference"> Difference</label></fieldset>
      <label class="lab-editor-control">Execution mode<select data-editor-execution><option value="pipeline">Pipeline</option><option value="coach">Coach</option></select></label>
      <div class="lab-editor-controls"><label>Rise (s)<input type="number" min="0" max="10" step="0.05" data-editor-rise value="0.35"></label><label>Fall (s)<input type="number" min="0" max="10" step="0.05" data-editor-fall value="0.35"></label><label>Strength<input type="number" min="0" max="1" step="0.05" data-editor-strength value="1"></label></div></div>
    <div class="lab-editor-preset-row">${presetButtons}</div><div class="lab-editor-mutation-list" data-editor-mutations></div>
    <div class="lab-editor-stage-grid" data-editor-stage-grid></div><div class="lab-editor-time-row"><span data-editor-clock>0:00 / 0:00</span><input type="range" min="0" max="1" step="0.033333" value="0" data-editor-scrubber aria-label="Select the keyframe to inspect and edit"><span data-editor-joint-label>Select a joint to drag</span></div>
    <div data-editor-timeline></div><div class="lab-editor-actions"><input class="lab-editor-note" type="text" maxlength="300" placeholder="Edit note for this revision" data-editor-note><button type="button" class="button primary" data-editor-save>Save and rerun in Swift</button><button type="button" class="button ghost" data-editor-open-run hidden>Open Swift rerun</button></div>
    <p class="lab-editor-message" data-editor-message role="status"></p></div></section>`;
}

const state = { shell: null, runID: null, sourcePlan: null, scenario: null, recording: null, reference: null,
  recordingSession: null, referenceSession: null, previewSession: null, time: 0, mutations: [], baseMutationCount: 0,
  previewMutation: null, mode: "constrained", executionMode: "pipeline", view: "side-by-side", drag: null,
  latestRunID: null, saveReady: true };

function showMessage(message, error = false) {
  const target = state.shell?.querySelector("[data-editor-message]");
  if (!target) return;
  target.textContent = message;
  target.classList.toggle("error", error);
}

async function requestJSON(fetcher, url, options = {}) {
  const response = await fetcher(url, options);
  const value = await response.json().catch(() => null);
  if (!response.ok) throw new Error(value?.error ?? `${response.status} ${response.statusText}`);
  return value;
}

async function getJSON(url) { return requestJSON(fetch, url); }

function currentMutations() {
  const visibleMutations = state.referenceSession ? state.mutations : state.mutations.slice(state.baseMutationCount);
  return state.previewMutation ? [...visibleMutations, state.previewMutation] : [...visibleMutations];
}

function timelineMarkup(session) { return session ? timeline(session) : `<p class="lab-muted">No stored timeline is available for this scenario.</p>`; }

function paint() {
  const root = state.shell;
  const session = state.previewSession;
  if (!root || !session) return;
  const eventSession = state.recordingSession ?? session;
  const duration = Math.max(0, num(session.duration));
  state.time = clamp(state.time, 0, duration);
  const frame = session.frameAt(state.time);
  const mutations = currentMutations();
  const referenceSession = state.referenceSession ?? state.recordingSession;
  const referenceFrame = referenceSession?.frameAt(state.time) ?? null;
  root.querySelector("[data-editor-subtitle]").textContent = `${state.scenario.id} · ${state.scenario.exercise} · revision ${state.scenario.revision} → ${state.scenario.revision + 1}`;
  root.querySelectorAll('input[name="editor-mode"]').forEach((input) => { input.checked = input.value === state.mode; });
  root.querySelectorAll('input[name="editor-view"]').forEach((input) => { input.checked = input.value === state.view; });
  root.querySelector("[data-editor-execution]").value = state.executionMode;
  const list = root.querySelector("[data-editor-mutations]");
  list.innerHTML = state.mutations.length ? state.mutations.map((mutation, index) => `<span class="lab-editor-mutation">${esc(mutationLabel(mutation))}<button type="button" data-editor-remove="${index}" aria-label="Remove ${esc(mutation.kind)}">×</button></span>`).join("") : "No mutations yet. Choose a preset or drag a joint.";
  const grid = root.querySelector("[data-editor-stage-grid]");
  grid.className = `lab-editor-stage-grid ${state.view}`;
  const referenceHTML = referenceFrame ? svgFor(referenceSession, referenceFrame, state.time, [], { color: "#c9b3ff" }) : "";
  const editedHTML = frame ? svgFor(session, frame, state.time, mutations, { editable: true, color: "#ffb547" }) : "";
  grid.innerHTML = `<div class="lab-editor-stage-panel"><h3>Reference ${state.referenceSession ? "· canonical" : "· stored sample"}</h3><div class="lab-editor-stage">${referenceHTML || "<p class=\"lab-no-playback\">No reference sample.</p>"}</div></div>
    <div class="lab-editor-stage-panel"><h3>Edited preview · drag a joint at the selected keyframe</h3><div class="lab-editor-stage" data-editor-stage>${editedHTML || "<p class=\"lab-no-playback\">No movement sample.</p>"}</div><svg class="lab-editor-overlay-reference" data-editor-overlay-reference viewBox="0 0 ${WIDTH} ${HEIGHT}" preserveAspectRatio="xMidYMid meet">${referenceFrame ? stageSVG(referenceSession, referenceFrame, { width: WIDTH, height: HEIGHT, toggles: { mirror: true, hud: false, angles: false, thresholds: false, labels: false, trail: false }, glow: "#c9b3ff" }) : ""}</svg><svg class="lab-editor-difference-reference" data-editor-difference-reference viewBox="0 0 ${WIDTH} ${HEIGHT}" preserveAspectRatio="xMidYMid meet">${referenceFrame ? stageSVG(referenceSession, referenceFrame, { width: WIDTH, height: HEIGHT, toggles: { mirror: true, hud: false, angles: false, thresholds: false, labels: false, trail: false }, glow: "#c9b3ff" }) : ""}</svg></div>`;
  const previewPanel = grid.querySelector(".lab-editor-stage-panel:last-child");
  const previewSVG = previewPanel.querySelector("[data-editor-stage] svg");
  if (previewSVG) previewSVG.dataset.editorPreview = "";
  root.querySelector("[data-editor-scrubber]").max = String(duration || 1);
  root.querySelector("[data-editor-scrubber]").value = String(state.time);
  root.querySelector("[data-editor-clock]").textContent = `${clock(state.time)} / ${clock(duration)}`;
  root.querySelector("[data-editor-timeline]").innerHTML = timelineMarkup(eventSession);
  const playhead = root.querySelector("[data-editor-playhead]");
  if (playhead) playhead.style.left = `${104 + (state.time / Math.max(duration, 0.001)) * 100}%`;
  root.querySelector("[data-editor-open-run]").hidden = !state.latestRunID;
  root.querySelector("[data-editor-save]").disabled = !state.saveReady;
}

function mutatePreset(kind) {
  const session = state.previewSession;
  const mutation = preset(kind, state.time, session.duration);
  if (mutation) state.mutations.push(mutation);
  paint();
}

function pointerPoint(svg, event) {
  if (svg?.createSVGPoint && svg.getScreenCTM()) {
    const point = svg.createSVGPoint();
    point.x = event.clientX;
    point.y = event.clientY;
    const converted = point.matrixTransform(svg.getScreenCTM().inverse());
    return { x: converted.x, y: converted.y };
  }
  const rect = svg.getBoundingClientRect();
  return { x: (event.clientX - rect.left) / rect.width * WIDTH, y: (event.clientY - rect.top) / rect.height * HEIGHT };
}

function applyDrag(event, final = false) {
  if (!state.drag) return;
  const svg = state.shell.querySelector("[data-editor-stage] svg");
  if (!svg) return;
  const point = pointerPoint(svg, event);
  const deltaX = state.drag.start.x - point.x;
  const deltaY = point.y - state.drag.start.y;
  const frame = state.previewSession.frameAt(state.time);
  const item = dragToJointOffset({ joint: state.drag.joint, deltaX, deltaY,
    height: bodyHeight(state.previewSession, frame), peak: state.time,
    rise: Number(state.shell.querySelector("[data-editor-rise]").value),
    fall: Number(state.shell.querySelector("[data-editor-fall]").value),
    strength: Number(state.shell.querySelector("[data-editor-strength]").value),
    duration: state.previewSession.duration, mode: state.mode });
  state.previewMutation = item;
  state.shell.querySelector("[data-editor-joint-label]").textContent = `${state.drag.joint} · peak ${clock(state.time)} · ${item.dx.toFixed(3)}, ${item.dy.toFixed(3)} body-heights`;
  if (final) {
    state.mutations.push(item);
    state.previewMutation = null;
    state.drag = null;
  }
  paint();
}

function bindEditor() {
  const root = state.shell;
  root.addEventListener("click", (event) => {
    const button = event.target.closest("button");
    if (!button) return;
    if (button.matches("[data-editor-close]")) root.hidden = true;
    else if (button.dataset.editorPreset) mutatePreset(button.dataset.editorPreset);
    else if (button.dataset.editorRemove !== undefined) {
      state.mutations.splice(Number(button.dataset.editorRemove), 1);
      paint();
    } else if (button.matches("[data-editor-save]")) void saveAndRerun(button);
    else if (button.matches("[data-editor-open-run]")) {
      const navigate = window.FMPLabDashboard?.navigateToScenario;
      if (state.latestRunID && typeof navigate === "function") {
        root.hidden = true;
        void navigate({ runID: state.latestRunID, scenarioID: state.scenario.id, timestamp: state.time });
      }
    }
  });
  root.addEventListener("change", (event) => {
    if (event.target.matches('input[name="editor-mode"]')) { state.mode = event.target.value; paint(); }
    if (event.target.matches('input[name="editor-view"]')) { state.view = event.target.value; paint(); }
    if (event.target.matches("[data-editor-execution]")) state.executionMode = event.target.value;
  });
  root.addEventListener("input", (event) => {
    if (event.target.matches("[data-editor-scrubber]")) { state.time = Number(event.target.value); paint(); }
  });
  const grid = root.querySelector("[data-editor-stage-grid]");
  grid.addEventListener("pointerdown", (event) => {
    const joint = event.target.closest?.("[data-editor-joint]");
    if (!joint) return;
    const svg = joint.ownerSVGElement;
    state.drag = { joint: joint.dataset.editorJoint, start: pointerPoint(svg, event) };
    grid.setPointerCapture?.(event.pointerId);
    event.preventDefault();
  });
  grid.addEventListener("pointermove", (event) => { if (state.drag) applyDrag(event); });
  grid.addEventListener("pointerup", (event) => { if (state.drag) applyDrag(event, true); });
  grid.addEventListener("pointercancel", () => { state.drag = null; state.previewMutation = null; paint(); });
  root.addEventListener("click", (event) => {
    const track = event.target.closest("[data-editor-track]");
    if (!track) return;
    const rect = track.getBoundingClientRect();
    if (rect.width > 0) {
      const timelineDuration = (state.recordingSession ?? state.previewSession).duration;
      state.time = clamp((event.clientX - rect.left) / rect.width, 0, 1) * timelineDuration;
      paint();
    }
  });
}

function mount() {
  if (state.shell) return;
  document.body.insertAdjacentHTML("beforeend", editorMarkup());
  state.shell = document.getElementById("labEditorShell");
  bindEditor();
}

/** Open an existing stored scenario in the editor from playback or the coverage matrix. */
export async function openEditor({ runID, scenarioID, timestamp = null } = {}) {
  if (typeof document === "undefined") return false;
  mount();
  showMessage("Loading stored movement and reference samples…");
  state.shell.hidden = false;
  state.latestRunID = null;
  try {
    const run = await getJSON(`/api/lab/runs/${encodeURIComponent(runID)}`);
    const scenario = run.plan?.scenarios?.find((item) => item.id === scenarioID);
    if (!scenario) throw new Error("The selected scenario is not in this run.");
    const base = `/api/lab/runs/${encodeURIComponent(runID)}/scenarios/${encodeURIComponent(scenarioID)}`;
    const [recording, reference] = await Promise.all([
      getJSON(`${base}/recording`).catch(() => []), getJSON(`${base}/reference`).catch(() => []),
    ]);
    const recordingSession = parseSession(recording);
    const referenceSession = parseSession(reference);
    const previewSession = referenceSession ?? recordingSession;
    if (!previewSession?.frames?.length) throw new Error("This scenario has no stored movement frames to edit.");
    state.runID = runID;
    state.sourcePlan = run.plan;
    state.scenario = scenario;
    state.recording = recording;
    state.reference = reference;
    state.recordingSession = recordingSession;
    state.referenceSession = referenceSession;
    state.previewSession = previewSession;
    state.mutations = structuredClone(scenario.mutations ?? []);
    state.baseMutationCount = referenceSession ? 0 : state.mutations.length;
    state.mode = scenario.mode === "raw" ? "raw" : "constrained";
    state.executionMode = run.executionMode === "coach" ? "coach" : "pipeline";
    state.view = "side-by-side";
    state.saveReady = true;
    const firstPeak = state.mutations.find((item) => Number.isFinite(item.peak))?.peak;
    const firstEvent = previewSession.reps?.[0]?.t ?? previewSession.duration / 2;
    state.time = Number.isFinite(timestamp) ? Number(timestamp) : Number.isFinite(firstPeak) ? firstPeak : firstEvent;
    paint();
    showMessage(referenceSession ? "Reference and stored movement loaded. Drag a joint or add a preset." : "No canonical reference artifact exists; preview uses the stored sample as its starting pose.");
    return true;
  } catch (error) {
    showMessage(error?.message ?? String(error), true);
    return false;
  }
}

export async function saveAndRerunRevision(context, { editNote, headers, fetcher = fetch,
  onSaved = () => {}, onRerun = () => {} } = {}) {
  if (!context?.scenario || !context?.sourcePlan || !context?.runID) throw new Error("Load a stored scenario before saving.");
  if (context.executionMode !== "pipeline" && context.executionMode !== "coach") {
    throw new Error("Choose pipeline or coach execution mode.");
  }
  const save = await requestJSON(fetcher, "/api/lab/scenarios", { method: "POST", headers,
    body: JSON.stringify({ sourceRunID: context.runID, sourceRevision: context.scenario.revision,
      scenarioID: context.scenario.id, mutations: context.mutations, mode: context.mode, editNote }) });
  onSaved(save);
  const rerun = await requestJSON(fetcher, "/api/lab/runs", { method: "POST", headers,
    body: JSON.stringify({ editID: save.editID, mode: context.executionMode }) });
  onRerun(rerun);
  const run = await requestJSON(fetcher, `/api/lab/runs/${encodeURIComponent(rerun.runID)}`);
  const scenario = run.plan?.scenarios?.find((item) => item.id === context.scenario.id);
  if (!scenario) throw new Error("The Swift rerun did not contain the edited scenario.");
  const base = `/api/lab/runs/${encodeURIComponent(rerun.runID)}/scenarios/${encodeURIComponent(scenario.id)}`;
  const [recording, reference] = await Promise.all([
    requestJSON(fetcher, `${base}/recording`), requestJSON(fetcher, `${base}/reference`).catch(() => []),
  ]);
  const recordingSession = parseSession(recording);
  const referenceSession = parseSession(reference);
  const previewSession = referenceSession ?? recordingSession;
  if (!previewSession?.frames?.length) throw new Error("The Swift rerun has no materialized frames to continue editing.");
  const mutations = structuredClone(scenario.mutations ?? []);
  return {
    ...context,
    runID: run.runID ?? rerun.runID,
    latestRunID: run.runID ?? rerun.runID,
    sourcePlan: run.plan,
    scenario,
    recording,
    reference,
    recordingSession,
    referenceSession,
    previewSession,
    mutations,
    baseMutationCount: referenceSession ? 0 : mutations.length,
    mode: scenario.mode === "raw" ? "raw" : "constrained",
    time: context.time,
  };
}

async function saveAndRerun(button) {
  if (!state.scenario || !state.sourcePlan || !state.saveReady) return;
  const note = state.shell.querySelector("[data-editor-note]").value.trim();
  if (!note) { showMessage("Add a short edit note before saving.", true); return; }
  button.disabled = true;
  state.latestRunID = null;
  state.saveReady = false;
  showMessage("Saving a new scenario revision…");
  const nonce = document.querySelector('meta[name="fmp-replay-nonce"]')?.content;
  const headers = { "content-type": "application/json", "x-fmp-replay": "1", "x-fmp-replay-nonce": nonce ?? "" };
  let revisionSaved = false;
  try {
    const updated = await saveAndRerunRevision({ runID: state.runID, sourcePlan: state.sourcePlan,
      scenario: state.scenario, mutations: state.mutations, mode: state.mode,
      executionMode: state.executionMode, time: state.time }, {
      editNote: note, headers,
      onSaved: (saved) => {
        revisionSaved = true;
        state.sourcePlan = saved.plan;
        state.scenario = saved.plan.scenarios.find((item) => item.id === state.scenario.id);
        showMessage(`Saved revision ${state.scenario.revision}; rerunning through Swift…`);
      },
      onRerun: (run) => {
        state.latestRunID = run.runID;
        state.runID = run.runID;
      },
    });
    Object.assign(state, updated);
    state.saveReady = true;
    showMessage(`Swift rerun complete · ${state.runID}. Samples reloaded for revision ${state.scenario.revision}.`);
    paint();
  } catch (error) {
    if (!revisionSaved) state.saveReady = true;
    showMessage(error?.message ?? String(error), true);
  } finally { button.disabled = !state.saveReady; }
}

if (typeof document !== "undefined") {
  document.addEventListener("click", (event) => {
    const button = event.target.closest?.("[data-lab-edit-run]");
    if (!button) return;
    event.preventDefault();
    void openEditor({ runID: button.dataset.labEditRun, scenarioID: button.dataset.labEditScenario });
  });
}

if (typeof window !== "undefined") window.FMPLabEditor = { open: openEditor };
