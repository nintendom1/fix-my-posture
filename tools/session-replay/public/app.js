// FMP Session Replay viewer: state, interaction, and wiring. Markup comes from ./views.mjs, which escapes everything
// from a recording; the data model and exports live in ../lib/session.mjs.
import { Session, clock, renderExcerpt, PRESETS, RATES, estimateTokens } from "../lib/session.mjs";
import * as views from "./views.mjs";

const $ = (id) => document.getElementById(id);
const memory = {
  get(key, fallback) { try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; } },
  set(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* private window */ } },
};
const api = {
  async json(path, options = {}) {
    const response = await fetch(path, options);
    const body = await response.json().catch(() => null);
    if (!response.ok) throw new Error(body?.error ?? `${response.status} ${response.statusText}`);
    return body;
  },
  post(path, value, raw = false) {
    return api.json(path, { method: "POST", headers: { "Content-Type": "application/json", "X-FMP-Replay": "1" },
      body: raw ? value : JSON.stringify(value) });
  },
};

const FILTERS = {
  All: () => true,
  Issues: (item) => ["warn", "cue", "marker", "note"].includes(item.kind),
  Reps: (item) => item.kind === "rep" || item.kind === "analyzer",
  Voice: (item) => item.kind === "voice" || item.title.startsWith("Command"),
  Notes: (item) => item.kind === "note" || item.kind === "marker",
};
const SPEEDS = [0.25, 0.5, 1, 2, 4];
const CHANNELS = [
  ["positions", "Joint positions"], ["confidence", "Confidence"], ["low", "Below-floor joints"], ["framing", "Framing & counting"],
  ["readings", "Analyzer readings"], ["thresholds", "Threshold lines"], ["form", "Form values"], ["events", "Events"], ["tuning", "Exercise tuning"],
];

const state = {
  sessions: [],
  session: null,
  t: 0,
  playing: false,
  speed: 1,
  toggles: memory.get("fmp-replay-toggles", { hud: true, angles: true, thresholds: true, labels: false, trail: false, mirror: true }),
  filter: "All",
  selection: null,
  notes: [],
  series: null,
  editing: null,
  exportPreset: "rep",
  exportOptions: { ...PRESETS.rep },
  exportAnchor: 0,
  exportText: "",
  log: { items: [], current: -1 },
  renderedFrame: null,
};

const pct = (t) => `${(state.session ? t / Math.max(state.session.duration, 0.001) : 0) * 100}%`;

function toast(message, duration = 3200) {
  const element = $("toast");
  element.textContent = message;
  element.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { element.hidden = true; }, duration);
}

// MARK: - Loading

async function loadList(selectID) {
  state.sessions = await api.json("/api/sessions");
  $("sessionPicker").innerHTML = views.sessionOptions(state.sessions);
  $("emptyState").hidden = state.sessions.length > 0;
  const params = new URLSearchParams(location.search);
  const wanted = selectID ?? params.get("session") ?? memory.get("fmp-replay-session", null);
  const chosen = state.sessions.find((s) => s.id === wanted) ?? state.sessions[0];
  if (!chosen) return;
  await openSession(chosen.id, selectID ? 0 : Number(params.get("t") ?? memory.get(`fmp-replay-t-${chosen.id}`, 0)));
  // A link can open a range and the export, such as one Claude sends: ?session=…&t=13.3&from=12.3&to=15.4&export=1
  if (!selectID && params.has("from") && params.has("to")) {
    state.selection = { from: views.num(params.get("from")), to: views.num(params.get("to")) };
    render(true);
  }
  if (!selectID && params.get("export") === "1") openExport();
}

async function openSession(id, t = 0) {
  const response = await fetch(`/api/sessions/${encodeURIComponent(id)}/file`);
  if (!response.ok) { toast(`Couldn't open the recording (${response.status}).`); return; }
  const session = Session.fromText(await response.text());
  pause(false);
  state.session = session;
  state.selection = null;
  state.series = buildSeries(session);
  $("sessionPicker").value = id;
  memory.set("fmp-replay-session", id);
  history.replaceState(null, "", `?session=${encodeURIComponent(id)}`);
  const header = session.header;
  $("sessionInfo").textContent = `${String(header.startedAt ?? "").slice(0, 16).replace("T", " ")} · ${views.fmt(session.duration)}${session.isComplete ? "" : " · incomplete"}${session.skipped ? ` · ${session.skipped} unreadable` : ""}`;
  $("deviceInfo").textContent = `${header.device?.model ?? "iPhone"} · iOS ${header.device?.os ?? "?"} · Vision · ${session.jointOrder.length} joints · ${header.camera?.analysisHz ?? 10} Hz`;
  $("duration").textContent = views.fmt(session.duration);
  buildTimeline();
  await loadNotes();
  seek(Math.min(Math.max(0, views.num(t)), session.duration));
}

async function loadNotes() {
  if (!state.session) return;
  const document = await api.json(`/api/sessions/${encodeURIComponent(state.session.id)}/notes`).catch(() => ({ notes: [] }));
  state.notes = Array.isArray(document?.notes) ? document.notes : [];
  notesChanged();
}

async function importFile(file) {
  try {
    const result = await api.post("/api/import", await file.text(), true);
    toast(`Imported ${result.title}.`);
    await loadList(result.id);
  } catch (error) {
    toast(`Couldn't import ${file.name}: ${error.message}`, 6000);
  }
}

// MARK: - Timeline

function buildSeries(session) {
  const stride = Math.max(1, Math.ceil(session.frames.length / 3000));
  const sampled = session.frames.filter((_, index) => index % stride === 0);
  let low = -1;
  let high = 1;
  for (const frame of session.frames) {
    for (const side of ["left", "right"]) {
      const value = Number(frame.rd?.[side]?.signal);
      if (Number.isFinite(value)) { low = Math.min(low, value); high = Math.max(high, value); }
    }
  }
  const pad = (high - low) * 0.08;
  return { sampled, signalRange: [low - pad, high + pad] };
}

function buildTimeline() {
  const session = state.session;
  $("ticks").innerHTML = views.ticks(session);
  $("phaseLane").innerHTML = views.phaseLane(session);
  $("framingLane").innerHTML = views.framingLane(session);
  $("repLane").innerHTML = views.repLane(session);
  $("issueLane").innerHTML = views.issueLane(session);
  const charts = views.charts(session, state.series.sampled, state.series.signalRange);
  $("signalChart").innerHTML = charts.signal;
  $("angleChart").innerHTML = charts.angle;
  $("confidenceChart").innerHTML = charts.confidence;
}

/** Notes appear in three places; rebuild them, and the log, only when they change. */
function notesChanged() {
  if (!state.session) return;
  $("noteLane").innerHTML = views.noteLane(state.session, state.notes);
  $("notes").innerHTML = views.notesList(state.session, state.notes);
  buildLog();
}

function buildLog() {
  const notes = state.notes.map((note) => ({ t: views.num(note.t), kind: "note", title: note.author === "claude" ? "Claude's note" : "Your note", detail: note.text }));
  state.log.items = state.session.timeline.concat(notes).filter(FILTERS[state.filter]).sort((a, b) => a.t - b.t);
  state.log.current = -1;
  $("filters").innerHTML = views.filters(Object.keys(FILTERS), state.filter);
  $("log").innerHTML = views.logRows(state.log.items);
  updateLogHighlight(true);
}

/** Moves the log's current/future highlight, touching only the rows between the old and new positions. */
function updateLogHighlight(all = false) {
  const items = state.log.items;
  let current = -1;
  let low = 0;
  let high = items.length - 1;
  while (low <= high) {
    const mid = (low + high) >> 1;
    if (items[mid].t <= state.t + 0.001) { current = mid; low = mid + 1; } else { high = mid - 1; }
  }
  const previous = state.log.current;
  if (!all && current === previous) return;
  const rows = $("log").children;
  const first = all ? 0 : Math.max(0, Math.min(previous, current));
  const last = all ? rows.length - 1 : Math.min(rows.length - 1, Math.max(previous, current));
  for (let index = first; index <= last; index += 1) {
    rows[index].classList.toggle("current", index === current);
    rows[index].classList.toggle("future", index > current);
  }
  state.log.current = current;
}

// MARK: - Rendering

function seek(t) {
  if (!state.session) return;
  state.t = Math.max(0, Math.min(state.session.duration, views.num(t)));
  render();
  memory.set(`fmp-replay-t-${state.session.id}`, state.t);
  syncViewerState();
}

/** Cheap parts on every call; the stage and panel only when the frame (or a toggle) changes. */
function render(force = false) {
  const session = state.session;
  if (!session) return;
  $("playhead").style.left = pct(state.t);
  $("timeSmall").textContent = views.fmt(state.t);
  $("timeBig").textContent = views.fmt(state.t);
  $("playPause").textContent = state.playing ? "❚❚" : "▶";
  const selection = $("selection");
  selection.hidden = !state.selection;
  if (state.selection) {
    selection.style.left = pct(state.selection.from);
    selection.style.width = pct(state.selection.to - state.selection.from);
    $("selectionLabel").textContent = `selected ${clock(state.selection.from)}–${clock(state.selection.to)}`;
  } else {
    $("selectionLabel").textContent = "";
  }
  updateLogHighlight();
  const index = session.frameIndexAt(state.t);
  const key = `${index}|${state.toggles.trail ? Math.round(state.t * 10) : ""}`;
  if (!force && state.renderedFrame === key) return;
  state.renderedFrame = key;
  renderStage(index);
  renderPanel(index);
}

function glowFor(session, t, stateRecord) {
  const lost = session.losses.find((loss) => loss.start <= t && loss.end > t);
  if (stateRecord?.tip) return "#ffb547";
  if (stateRecord?.tilted) return "#ff8a4c";
  if (lost && /^exercising/.test(String(stateRecord?.phase ?? ""))) return "#ff5d73";
  return views.phaseColor(stateRecord?.phase);
}

function renderStage(index) {
  const session = state.session;
  const frame = session.frames[index];
  const [width, height] = (frame?.size ?? session.imageSize).map((value) => views.num(value, 1000));
  const stage = $("stage");
  stage.style.aspectRatio = `${width} / ${height}`;
  $("stageSVG").setAttribute("viewBox", `0 0 ${width} ${height}`);
  const stateRecord = session.stateAt(state.t);
  const glow = glowFor(session, state.t, stateRecord);
  stage.style.setProperty("--glow", glow);
  stage.style.setProperty("--glow-soft", `${glow}55`);
  const trail = state.toggles.trail
    ? [[session.frameAt(state.t - 0.5), 0.14], [session.frameAt(state.t - 0.25), 0.28]].filter(([past]) => past) : [];
  $("stageSVG").innerHTML = views.stageSVG(session, frame, { width, height, toggles: state.toggles, glow, trail });

  $("hud").hidden = !state.toggles.hud;
  if (state.toggles.hud) {
    const exercise = session.exerciseAt(state.t);
    $("hudSet").textContent = `${String(exercise?.name ?? "Workout").toUpperCase()} · SET ${stateRecord?.set ?? 1}`;
    $("hudReps").textContent = String(stateRecord?.reps ?? 0);
    const spoken = session.events.filter((e) => e.type === "speak" && e.t <= state.t && state.t - e.t < 3.5).at(-1);
    $("hudBanner").hidden = !spoken;
    if (spoken) $("hudBanner").textContent = String(spoken.text ?? "");
  }
}

function renderPanel(index) {
  const session = state.session;
  const frame = session.frames[index];
  const stateRecord = session.stateAt(state.t);
  $("frameLabel").textContent = `frame ${index + 1}/${session.frames.length}${frame?.seq != null ? ` · seq ${views.num(frame.seq)}` : ""}`;
  const glow = glowFor(session, state.t, stateRecord);
  $("stateChip").style.setProperty("--glow", glow);
  $("stateChip").style.setProperty("--glow-bg", `${glow}22`);
  $("stateLabel").textContent = String(stateRecord?.phase ?? "—");
  const phaseSpan = session.phaseSpans.find((span) => span.start <= state.t && span.end >= state.t);
  $("stateSince").textContent = phaseSpan ? `since ${clock(phaseSpan.start)}` : "";
  $("stats").innerHTML = views.stats(session, state.t, frame, stateRecord);
  $("checks").innerHTML = views.checks(session, index);
  $("readings").innerHTML = views.readings(frame);
  $("confidence").innerHTML = views.confidence(session, frame, state.t);
}

// MARK: - Interaction

function play() {
  if (!state.session) return;
  if (state.t >= state.session.duration) state.t = 0;
  state.playing = true;
  let last = performance.now();
  const tick = (now) => {
    if (!state.playing) return;
    const next = state.t + ((now - last) / 1000) * state.speed;
    last = now;
    if (next >= state.session.duration) { state.playing = false; seek(state.session.duration); return; }
    state.t = next;
    render();
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  render(true);
}

function pause(settle = true) {
  const wasPlaying = state.playing;
  state.playing = false;
  if (settle && wasPlaying) seek(state.t);
  else if (settle) render();
}

function stepFrame(direction) {
  const session = state.session;
  if (!session) return;
  pause(false);
  const index = Math.min(session.frames.length - 1, Math.max(0, session.frameIndexAt(state.t) + direction));
  seek(session.frames[index]?.t ?? state.t);
}

function jumpEvent(direction) {
  const items = state.log.items;
  const item = direction > 0 ? items.find((i) => i.t > state.t + 0.01) : [...items].reverse().find((i) => i.t < state.t - 0.01);
  if (item) { pause(false); seek(item.t); }
}

function timeFromPointer(event) {
  const rect = $("track").getBoundingClientRect();
  return Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width)) * (state.session?.duration ?? 0);
}

function setupTrack() {
  const track = $("track");
  let mode = null;
  let anchor = 0;
  track.addEventListener("pointerdown", (event) => {
    if (!state.session) return;
    const mark = event.target.closest("[data-t]");
    if (mark && !event.shiftKey) { pause(false); seek(Number(mark.dataset.t)); return; }
    track.setPointerCapture(event.pointerId);
    pause(false);
    if (event.shiftKey) {
      mode = "select";
      anchor = timeFromPointer(event);
      state.selection = { from: anchor, to: anchor };
    } else {
      mode = "scrub";
      seek(timeFromPointer(event));
    }
    render();
  });
  track.addEventListener("pointermove", (event) => {
    if (!mode) return;
    const t = timeFromPointer(event);
    if (mode === "scrub") seek(t);
    else { state.selection = { from: Math.min(anchor, t), to: Math.max(anchor, t) }; render(); }
  });
  track.addEventListener("pointerup", () => {
    if (mode === "select" && state.selection && state.selection.to - state.selection.from < 0.05) state.selection = null;
    mode = null;
    render();
    syncViewerState();
  });
}

let syncTimer;
function syncViewerState() {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(() => {
    if (!state.session) return;
    api.post("/api/viewer/state", { sessionId: state.session.id, title: state.session.title, t: state.t, selection: state.selection }).catch(() => {});
  }, 400);
}

// MARK: - Notes

function openNoteEditor(note) {
  pause();
  const range = state.selection;
  state.editing = note ?? { id: crypto.randomUUID(), t: range ? range.from : state.t, end: range ? range.to : null, text: "", author: "you" };
  $("noteTitle").textContent = `${note ? "Edit note" : "Note"} at ${state.editing.end != null ? `${clock(state.editing.t)}–${clock(state.editing.end)}` : clock(state.editing.t)}`;
  $("noteText").value = state.editing.text;
  $("noteDelete").hidden = !note;
  $("noteDialog").showModal();
  $("noteText").focus();
}

async function closeNoteEditor(action) {
  const note = state.editing;
  state.editing = null;
  if (!note || !state.session || action === "cancel" || !action) return;
  const text = $("noteText").value.trim();
  if (action === "save" && !text) return;
  try {
    const document = await api.post(`/api/sessions/${encodeURIComponent(state.session.id)}/notes`,
      action === "delete" ? { id: note.id, t: note.t, deleted: true } : { ...note, text });
    state.notes = document.notes;
    notesChanged();
  } catch (error) {
    toast(`Couldn't save the note: ${error.message}`, 6000);
  }
}

// MARK: - Export

/** The export's window is fixed when the dialog opens, so what is copied or sent is what the preview shows. */
function exportWindow() {
  const session = state.session;
  const choice = $("windowChoice").value;
  if (choice === "selection" && state.selection) return [state.selection.from, state.selection.to];
  if (choice === "exercise") {
    const span = session.exerciseSpans.find((s) => s.start <= state.exportAnchor && s.end >= state.exportAnchor) ?? { start: 0, end: session.duration };
    return [span.start, span.end];
  }
  if (choice === "all") return [0, session.duration];
  return [Math.max(0, state.exportAnchor - 8), Math.min(session.duration, state.exportAnchor + 2)];
}

function renderExportOptions() {
  $("presetButtons").innerHTML = Object.entries(PRESETS).map(([key, preset]) =>
    `<button type="button" class="${state.exportPreset === key ? "on" : ""}" data-preset="${key}">${views.esc(preset.label)}</button>`).join("")
    + `<button type="button" class="${state.exportPreset === "custom" ? "on" : ""}" disabled>Custom</button>`;
  $("rateChoice").innerHTML = RATES.map((rate) => `<option value="${rate}" ${state.exportOptions.rate === rate ? "selected" : ""}>${rate ? `${rate} Hz${rate === 5 ? " (every 0.2 s)" : rate === 10 ? " (every frame)" : ""}` : "Events only"}</option>`).join("");
  $("jointChoice").value = state.exportOptions.joints;
  $("channelChoices").innerHTML = CHANNELS.map(([key, label]) =>
    `<label><input type="checkbox" data-channel="${key}" ${state.exportOptions[key] ? "checked" : ""}> ${label}</label>`).join("");
  const [from, to] = exportWindow();
  state.exportText = renderExcerpt(state.session, { from, to, options: state.exportOptions, notes: state.notes });
  state.exportRange = [from, to];
  $("exportPreview").value = state.exportText;
  $("exportSize").textContent = `${state.exportText.length.toLocaleString()} chars · ~${estimateTokens(state.exportText).toLocaleString()} tokens`;
}

function openExport() {
  if (!state.session) return;
  pause();
  state.exportAnchor = state.t;
  $("windowChoice").value = state.selection ? "selection" : "around";
  $("windowChoice").querySelector("[value=selection]").disabled = !state.selection;
  $("exportStatus").textContent = "";
  renderExportOptions();
  $("exportDialog").showModal();
}

// MARK: - Wiring

function wire() {
  $("sessionPicker").addEventListener("change", (event) => openSession(event.target.value, memory.get(`fmp-replay-t-${event.target.value}`, 0)));
  $("fileInput").addEventListener("change", (event) => { const file = event.target.files?.[0]; if (file) importFile(file); event.target.value = ""; });
  document.addEventListener("dragover", (event) => event.preventDefault());
  document.addEventListener("drop", (event) => { event.preventDefault(); const file = event.dataTransfer?.files?.[0]; if (file) importFile(file); });

  for (const button of document.querySelectorAll("[data-toggle]")) {
    const key = button.dataset.toggle;
    button.classList.toggle("on", !!state.toggles[key]);
    button.addEventListener("click", () => {
      state.toggles[key] = !state.toggles[key];
      button.classList.toggle("on", state.toggles[key]);
      memory.set("fmp-replay-toggles", state.toggles);
      render(true);
    });
  }
  $("speeds").innerHTML = SPEEDS.map((speed) => `<button data-speed="${speed}" class="${speed === state.speed ? "on" : ""}">${speed}×</button>`).join("");
  $("speeds").addEventListener("click", (event) => {
    const speed = Number(event.target.dataset.speed);
    if (!speed) return;
    state.speed = speed;
    for (const button of $("speeds").children) button.classList.toggle("on", Number(button.dataset.speed) === speed);
  });
  $("playPause").addEventListener("click", () => (state.playing ? pause() : play()));
  $("stepBack").addEventListener("click", () => stepFrame(-1));
  $("stepFwd").addEventListener("click", () => stepFrame(1));
  $("prevEvent").addEventListener("click", () => jumpEvent(-1));
  $("nextEvent").addEventListener("click", () => jumpEvent(1));
  $("addNote").addEventListener("click", () => openNoteEditor());
  $("openExport").addEventListener("click", openExport);
  $("filters").addEventListener("click", (event) => { const name = event.target.dataset.filter; if (name && FILTERS[name]) { state.filter = name; buildLog(); } });
  for (const id of ["log", "notes"]) {
    $(id).addEventListener("click", (event) => {
      const edit = event.target.dataset.edit;
      if (edit) { openNoteEditor(state.notes.find((note) => note.id === edit)); return; }
      const row = event.target.closest("[data-t]");
      if (row) { pause(false); seek(Number(row.dataset.t)); }
    });
  }
  $("noteForm").addEventListener("submit", (event) => { event.preventDefault(); const action = event.submitter?.value; $("noteDialog").close(); closeNoteEditor(action); });
  $("noteDialog").addEventListener("cancel", () => { state.editing = null; });

  $("presetButtons").addEventListener("click", (event) => {
    const key = event.target.dataset.preset;
    if (!key || !PRESETS[key]) return;
    state.exportPreset = key;
    state.exportOptions = { ...PRESETS[key] };
    renderExportOptions();
  });
  for (const id of ["windowChoice", "rateChoice", "jointChoice"]) {
    $(id).addEventListener("change", () => {
      if (id !== "windowChoice") {
        state.exportOptions.rate = Number($("rateChoice").value);
        state.exportOptions.joints = $("jointChoice").value;
        state.exportPreset = "custom";
        state.exportOptions.label = "custom";
      }
      renderExportOptions();
    });
  }
  $("channelChoices").addEventListener("change", (event) => {
    const key = event.target.dataset.channel;
    if (!key) return;
    state.exportOptions[key] = event.target.checked;
    state.exportPreset = "custom";
    state.exportOptions.label = "custom";
    renderExportOptions();
  });
  $("exportCopy").addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(state.exportText);
      $("exportStatus").textContent = "Copied. Paste it into Claude Code.";
    } catch {
      $("exportStatus").textContent = "Couldn't copy; select the preview and copy it instead.";
    }
  });
  $("exportSave").addEventListener("click", () => {
    const [from, to] = state.exportRange;
    const link = document.createElement("a");
    link.href = URL.createObjectURL(new Blob([state.exportText], { type: "text/markdown" }));
    link.download = `fmp-excerpt-${state.session.id.slice(0, 8)}-${from.toFixed(1)}-${to.toFixed(1)}.md`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  });
  $("exportSend").addEventListener("click", async () => {
    const [from, to] = state.exportRange;
    try {
      const result = await api.post("/api/viewer/sent", { sessionId: state.session.id, title: state.session.title, from, to,
        preset: state.exportPreset, options: state.exportOptions, notes: state.notes, markdown: state.exportText });
      $("exportStatus").textContent = `Sent (~${result.tokens.toLocaleString()} tokens) to ${result.path}. Tell Claude: “look at what I sent”.`;
    } catch (error) {
      $("exportStatus").textContent = `Couldn't send: ${error.message}`;
    }
  });

  document.addEventListener("keydown", (event) => {
    if (/INPUT|TEXTAREA|SELECT/.test(event.target.tagName) || document.querySelector("dialog[open]")) return;
    if (event.key === " ") { event.preventDefault(); state.playing ? pause() : play(); }
    else if (event.key === "ArrowLeft") { event.preventDefault(); if (event.shiftKey) { pause(false); seek(state.t - 1); } else stepFrame(-1); }
    else if (event.key === "ArrowRight") { event.preventDefault(); if (event.shiftKey) { pause(false); seek(state.t + 1); } else stepFrame(1); }
    else if (event.key === "[") jumpEvent(-1);
    else if (event.key === "]") jumpEvent(1);
    else if (event.key === "n" || event.key === "N") { event.preventDefault(); openNoteEditor(); }
    else if (event.key === "e" || event.key === "E") { event.preventDefault(); openExport(); }
    else if (event.key === "Escape") { state.selection = null; render(); syncViewerState(); }
  });
  setupTrack();

  // Live link: the server relays commands, such as Claude moving the playhead, and note changes.
  const events = new EventSource("/api/events");
  events.onmessage = async (message) => {
    let event;
    try { event = JSON.parse(message.data); } catch { return; }
    if (event.type === "notes" && event.sessionId === state.session?.id) await loadNotes();
    if (event.type === "command" && event.command === "seek") {
      if (event.sessionId && event.sessionId !== state.session?.id) await openSession(String(event.sessionId), event.t ?? 0);
      pause(false);
      if (event.from != null && event.to != null) state.selection = { from: views.num(event.from), to: views.num(event.to) };
      seek(event.t ?? event.from ?? state.t);
      toast(event.note ? `Claude: ${event.note}` : `Claude moved to ${clock(views.num(event.t))}`, 6000);
    }
  };
}

wire();
loadList().catch((error) => toast(`Couldn't load recordings: ${error.message}`, 8000));
