#!/usr/bin/env node
// MCP server (stdio) that lets Claude Code work with FMP workout recordings: pull them from the iPhone, get an
// overview, query any window at any rate, read what the viewer sent, add notes, and move the open viewer.
// Registered in the repository's .mcp.json. Node 20 or later, no dependencies. Everything stays on this Mac.
//
// Recordings are read straight from diagnostics/sessions/; the viewer's server (tools/session-replay/server.mjs) is
// used only for live work: moving the playhead, and saving notes so an open viewer shows them at once.

import { spawn, execFile } from "node:child_process";
import { realpathSync } from "node:fs";
import { rm } from "node:fs/promises";
import { createInterface } from "node:readline";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createStore, StoreError } from "./lib/store.mjs";
import { PRESETS, renderExcerpt, sampleFrames, clock, estimateTokens, shortJoint } from "./lib/session.mjs";
import { createFreshRunDirectory, emitPresetManifest, runPlan } from "./lib/lab/runner.mjs";
import { inspectRun } from "./lib/lab/inspect.mjs";
import { createLabStore } from "./lib/lab/store.mjs";
import { MCP_FULL_TRACE_BYTE_CAP, MCP_MAX_PLAN_BYTES, assertBoundedInspection, formatAgentManifest,
  formatAgentRun, openLabDashboard, prepareAgentPlan } from "./lib/lab/agent.mjs";
import { MUTATION_BOUNDS, SCENARIO_CATEGORIES, SWIFT_LANDMARK_NAMES } from "./lib/lab/plan.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = process.env.FMP_REPLAY_ROOT ?? path.resolve(here, "../..");
const PORT = Number(process.env.FMP_REPLAY_PORT ?? 4317);
const BASE = `http://127.0.0.1:${PORT}/`;
const MAX_ROWS = Number(process.env.FMP_REPLAY_MAX_ROWS ?? 300);
const MAX_CHARS = 60_000;
const MAX_MCP_MESSAGE_BYTES = 2 * 1024 * 1024;
const REQUEST_TIMEOUT = 2000;
const SUPPORTED_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"];
const store = createStore(ROOT);
const labStore = createLabStore(ROOT);
const canonicalRoot = (() => { try { return realpathSync(ROOT); } catch { return ROOT; } })();

// MARK: - Tools

const session = { type: "string", description: "Recording id, its first 8 characters, or \"latest\" (the default)." };
const time = { type: ["number", "string"], description: "Seconds from the start of the recording, or \"m:ss.s\"." };
const rangeSchema = (limits) => ({ type: "number", minimum: limits[0], maximum: limits[1] });
const repetitionSelector = { type: "array", maxItems: 120, items: { type: "integer", minimum: 1, maximum: 120 } };
const jointsSchema = { type: "array", minItems: 1, items: { type: "string", enum: SWIFT_LANDMARK_NAMES } };
const mutationInputSchema = {
  type: "object", required: ["kind"], additionalProperties: false,
  properties: {
    kind: { type: "string", enum: Object.keys(MUTATION_BOUNDS) }, joints: jointsSchema,
    dx: rangeSchema(MUTATION_BOUNDS.jointOffset.dx), dy: rangeSchema(MUTATION_BOUNDS.jointOffset.dy),
    peak: rangeSchema(MUTATION_BOUNDS.jointOffset.peak), rise: rangeSchema(MUTATION_BOUNDS.jointOffset.rise),
    fall: rangeSchema(MUTATION_BOUNDS.jointOffset.fall), strength: rangeSchema(MUTATION_BOUNDS.jointOffset.strength),
    scale: rangeSchema(MUTATION_BOUNDS.depthScale.scale), reps: repetitionSelector,
    side: { type: "string", enum: MUTATION_BOUNDS.asymmetry.side }, amount: rangeSchema(MUTATION_BOUNDS.asymmetry.amount),
    at: rangeSchema(MUTATION_BOUNDS.pause.at), duration: rangeSchema(MUTATION_BOUNDS.pause.duration),
    from: rangeSchema(MUTATION_BOUNDS.dropout.from), to: rangeSchema(MUTATION_BOUNDS.dropout.to),
    value: rangeSchema(MUTATION_BOUNDS.confidence.value), offsetX: rangeSchema(MUTATION_BOUNDS.framing.offsetX),
    offsetY: rangeSchema(MUTATION_BOUNDS.framing.offsetY),
  },
};
const assertionInputSchema = {
  type: "object", required: ["kind"], additionalProperties: false,
  properties: {
    kind: { type: "string", enum: ["repCount", "rejection", "formSignal", "framing", "spokenCue"] },
    equals: { type: "integer", minimum: 0 }, min: { type: "integer", minimum: 0 }, max: { type: "integer", minimum: 0 },
    reasonContains: { type: "string", maxLength: 1000 }, countMin: { type: "integer", minimum: 0 },
    id: { type: "string", maxLength: 128 }, present: { type: "boolean" }, state: { type: "string", maxLength: 128 },
    reached: { type: "boolean" }, textContains: { type: "string", maxLength: 1000 },
  },
};
const scenarioInputSchema = {
  type: "object", additionalProperties: false,
  required: ["id", "exercise", "category", "purpose", "canonicalRevision", "seed", "reps", "mode", "mutations", "assertions", "revision"],
  properties: {
    id: { type: "string", maxLength: 64, pattern: "^[a-z0-9_-]{1,64}$" }, exercise: { type: "string", minLength: 1, maxLength: 64 },
    category: { type: "string", enum: SCENARIO_CATEGORIES }, purpose: { type: "string", minLength: 1, maxLength: 2000 },
    canonicalRevision: { type: "string", minLength: 1, maxLength: 128 }, seed: { type: "string", minLength: 1, maxLength: 20, pattern: "^\\d+$" },
    reps: { type: "integer", minimum: 1, maximum: 120 }, mode: { type: "string", enum: ["constrained", "raw"] },
    mutations: { type: "array", items: mutationInputSchema }, assertions: { type: "array", items: assertionInputSchema },
    revision: { type: "integer", minimum: 1 }, parentRevision: { type: "integer", minimum: 1 },
    author: { type: "string", enum: ["agent", "developer"] }, intent: { type: "string", minLength: 1, maxLength: 1000 },
    editNote: { type: "string", maxLength: 300 }, assertionChangeReason: { type: "string", maxLength: 300 },
    editedBy: { type: "string", enum: ["agent", "developer"] },
  },
};
const planInputSchema = {
  type: "object", additionalProperties: false,
  required: ["schemaVersion", "id", "title", "purpose", "author", "createdAt", "scenarios"],
  properties: {
    schemaVersion: { type: "integer", enum: [1] }, id: { type: "string", maxLength: 64, pattern: "^[a-z0-9_-]{1,64}$" },
    title: { type: "string", minLength: 1, maxLength: 500 }, purpose: { type: "string", minLength: 1, maxLength: 2000 },
    author: { type: "string", enum: ["agent", "developer"] }, createdAt: { type: "string", minLength: 1, maxLength: 64 },
    scenarios: { type: "array", maxItems: 200, items: scenarioInputSchema },
  },
};

const TOOLS = [
  {
    name: "fmp_pull_device",
    description: "Copy every workout recording from the connected iPhone into diagnostics/sessions/ (runs `make diagnostics`). The phone must be connected or paired and unlocked.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "fmp_list_sessions",
    description: "List recordings on this Mac, newest first: id, title, start, length, frames, markers, notes.",
    inputSchema: { type: "object", properties: { limit: { type: "integer", minimum: 1, maximum: 100 } } },
  },
  {
    name: "fmp_session_overview",
    description: "Summarize one recording without frame data (about 1–2k tokens): device, exercises and tuning, phases, displayed reps vs analyzer rep events, every tracking loss with its guidance, markers, notes, and issues, plus suggested windows to query. Start here.",
    inputSchema: { type: "object", properties: { session } },
  },
  {
    name: "fmp_query",
    description: "Render a window of a recording as Markdown with a CSV frame table: notes in the window, tuning, the state at the window start, events, and per-frame joints and analyzer readings. Keep windows short (a rep is 2–4 s); more than 300 frame rows need allowLarge.",
    inputSchema: {
      type: "object",
      required: ["from", "to"],
      properties: {
        session, from: time, to: time,
        preset: { type: "string", enum: Object.keys(PRESETS), description: "rep (default): joints, readings, thresholds; tracking: all joints and confidence; form: form values; flow: events only." },
        rate: { type: "number", enum: [10, 5, 2, 1, 0], description: "Frames per second; 10 is every analyzed frame, 0 events only." },
        joints: { type: "string", enum: ["focus", "all", "none"] },
        include: {
          type: "object", description: "Override the preset's channels.",
          properties: Object.fromEntries(["positions", "confidence", "low", "readings", "thresholds", "framing", "form", "events", "tuning"].map((key) => [key, { type: "boolean" }])),
        },
        allowLarge: { type: "boolean", description: "Allow more than 300 frame rows." },
      },
    },
  },
  {
    name: "fmp_events",
    description: "List timeline events (commands, phases, displayed reps, analyzer rep events, tracking, coach speech, tips, markers, notes), optionally in a window and of some kinds.",
    inputSchema: {
      type: "object",
      properties: { session, from: time, to: time,
        kinds: { type: "array", items: { type: "string", enum: ["command", "set", "rep", "analyzer", "info", "warn", "voice", "cue", "marker", "note"] } } },
    },
  },
  {
    name: "fmp_viewer_selection",
    description: "What the user sent from the replay viewer with \"Send to Claude\" (the excerpt they chose), and where the open viewer is now: recording, playhead, and selection.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "fmp_viewer_seek",
    description: "Move the user's open replay viewer to a time, optionally selecting a range and showing a short message, so they can see the frame you're describing.",
    inputSchema: { type: "object", required: ["t"], properties: { session, t: time, from: time, to: time, note: { type: "string", maxLength: 300 } } },
  },
  {
    name: "fmp_add_note",
    description: "Add a note from Claude at a time (or range) of a recording. It appears in the viewer's notes and in later excerpts.",
    inputSchema: { type: "object", required: ["t", "text"], properties: { session, t: time, end: time, text: { type: "string", maxLength: 2000 } } },
  },
  {
    name: "fmp_open_viewer",
    description: "Open the replay viewer in the user's browser, starting its local server if needed, optionally at a recording, time, and range, with the export open.",
    inputSchema: { type: "object", properties: { session, t: time, from: time, to: time, export: { type: "boolean" } } },
  },
  {
    name: "fmp_lab_manifest",
    description: "Return the compact Movement Lab exercise, category, mutation-bound, and preset manifest.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "fmp_lab_run",
    description: "Validate and run one synthetic Movement Lab plan or preset through the shared Swift runner. Each scenario is recorded as agent-authored with an intent note.",
    inputSchema: {
      type: "object", required: ["mode"], additionalProperties: false,
      oneOf: [
        { required: ["plan"], not: { required: ["preset"] } },
        { required: ["preset"], not: { required: ["plan"] } },
      ],
      allOf: [{ oneOf: [
        { required: ["parentRunID", "followUpReason"] },
        { not: { anyOf: [{ required: ["parentRunID"] }, { required: ["followUpReason"] }] } },
      ] }],
      properties: {
        plan: { ...planInputSchema, description: `Movement Lab plan JSON, maximum ${MCP_MAX_PLAN_BYTES} UTF-8 bytes.` },
        preset: { type: "string", minLength: 1, maxLength: 64, pattern: "^[a-z0-9_-]{1,64}$" },
        mode: { type: "string", enum: ["pipeline", "coach"] },
        parentRunID: { type: "string", pattern: "^\\d{8}-\\d{6}-[a-zA-Z0-9]{4,12}$" },
        followUpReason: { type: "string", minLength: 1, maxLength: 500 },
      },
    },
  },
  {
    name: "fmp_lab_inspect",
    description: "Inspect one stored Movement Lab scenario. Ordinary output is at most 60 lines; full traces require full=true and fit within a hard byte cap.",
    inputSchema: {
      type: "object", required: ["runID"], additionalProperties: false,
      properties: {
        runID: { type: "string", pattern: "^\\d{8}-\\d{6}-[a-zA-Z0-9]{4,12}$" },
        scenarioID: { type: "string", pattern: "^[a-z0-9_-]{1,64}$" },
        window: { type: "object", additionalProperties: false, required: ["from", "to"], properties: {
          from: { type: "number", minimum: 0, maximum: 120 }, to: { type: "number", minimum: 0, maximum: 120 },
        } },
        full: { type: "boolean" },
      },
    },
  },
  {
    name: "fmp_lab_open",
    description: "Open the local Movement Lab dashboard at a run or a scenario's stored keyframe using the viewer command channel.",
    inputSchema: {
      type: "object", required: ["runID"], additionalProperties: false,
      properties: {
        runID: { type: "string", pattern: "^\\d{8}-\\d{6}-[a-zA-Z0-9]{4,12}$" },
        scenarioID: { type: "string", pattern: "^[a-z0-9_-]{1,64}$" },
      },
    },
  },
];

class ToolError extends Error {}

function seconds(value, name) {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const match = String(value).trim().match(/^(?:(\d+):)?(\d+(?:\.\d+)?)$/);
  if (!match) throw new ToolError(`${name} should be seconds or m:ss.s, not ${JSON.stringify(value)}.`);
  return Number(match[1] ?? 0) * 60 + Number(match[2]);
}

async function resolveSession(value) {
  const sessions = await store.listSessions();
  if (!sessions.length) throw new ToolError("No recordings in diagnostics/sessions/. Call fmp_pull_device with the iPhone connected.");
  if (!value || value === "latest") return sessions[0];
  const wanted = String(value).toLowerCase();
  const matches = sessions.filter((s) => s.id.toLowerCase().startsWith(wanted));
  if (matches.length === 1) return matches[0];
  throw new ToolError(matches.length ? `"${value}" matches ${matches.length} recordings; give more of the id.` : `No recording matches "${value}".`);
}

/** A request to this checkout's viewer server: its body, or undefined when no server (or a stalled one) answers. */
async function request(route, options = {}) {
  try {
    const response = await fetch(BASE + route, { ...options, signal: AbortSignal.timeout(REQUEST_TIMEOUT),
      headers: { "Content-Type": "application/json", "X-FMP-Replay": "1", ...(options.headers ?? {}) } });
    const body = await response.json().catch(() => null);
    if (!response.ok) throw new ToolError(body?.error ?? `${response.status} ${response.statusText}`);
    return body;
  } catch (error) {
    if (error instanceof ToolError) throw error;
    return undefined;
  }
}

/** "ours" when the server on the port serves this checkout, "other" when it serves another one, or "none". */
async function viewerStatus() {
  let identity;
  try {
    identity = await request("api/identity");
  } catch {
    // Something answers on the port but isn't this version of the viewer's server.
    return "other";
  }
  if (identity === undefined) return "none";
  return identity?.app === "fmp-replay" && identity.root === canonicalRoot ? "ours" : "other";
}

/** Live calls go only to this checkout's server, so notes and seeks never land in another copy of the repository. */
async function viewer(route, options = {}) {
  const status = await viewerStatus();
  if (status === "other") {
    throw new ToolError(`Port ${PORT} is serving the replay viewer for another checkout. Stop it, or set FMP_REPLAY_PORT for this one.`);
  }
  return status === "ours" ? request(route, options) : undefined;
}

async function ensureViewerServer() {
  const status = await viewerStatus();
  if (status === "ours") return false;
  if (status === "other") throw new ToolError(`Port ${PORT} is serving the replay viewer for another checkout.`);
  const child = spawn(process.execPath, [path.join(here, "server.mjs")], {
    detached: true, stdio: "ignore", env: { ...process.env, FMP_REPLAY_ROOT: ROOT, FMP_REPLAY_PORT: String(PORT) },
  });
  child.unref();
  const deadline = Date.now() + 4000;
  while (Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 100));
    if (await viewerStatus() === "ours") return true;
  }
  throw new ToolError(`The viewer's server didn't start on ${BASE}.`);
}

function durationLabel(seconds) {
  return clock(seconds, false);
}

async function overview(id) {
  const summary = await resolveSession(id);
  const s = await store.readSession(summary.id);
  const notes = (await store.notesFor(summary.id)).notes;
  const header = s.header;
  const lines = [];
  lines.push(`FMP recording ${s.id} · ${s.title} · ${header.startedAt ?? "?"} · ${durationLabel(s.duration)} · ${s.frames.length} frames`
    + `${s.end?.seqGaps ? ` (${s.end.seqGaps} more never reached the coach)` : ""} · ${s.isComplete ? `ended: ${s.end.reason}` : "incomplete"}`);
  lines.push(`Device: ${header.device?.model ?? "?"} iOS ${header.device?.os ?? "?"} · app ${header.app?.version ?? "?"} (${header.app?.build ?? "?"}, ${header.app?.configuration ?? "?"})`);
  const framing = header.framing ?? {};
  lines.push(`Framing needs required joints ≥${framing.minimumConfidence ?? 0.4} for ${framing.reliableAfter ?? 0.6} s; unreliable after ${framing.unreliableAfter ?? 0.3} s missing; joints under ${header.confidenceFloor ?? 0.3} are dropped.`);
  lines.push("", "Exercises");
  for (const exerciseID of [...new Set(s.exerciseSpans.map((span) => span.label))]) {
    const exercise = s.exercises[exerciseID] ?? {};
    const spans = s.exerciseSpans.filter((span) => span.label === exerciseID).map((span) => `${clock(span.start)}–${clock(span.end)}`).join(", ");
    const anyOf = (exercise.anyOfRequired ?? []).map((set) => set.map(shortJoint).join(" "));
    lines.push(`- ${exerciseID} (${exercise.cameraView ?? "?"}) ${spans}: required ${(exercise.required ?? []).map(shortJoint).join(" ") || "none"}`
      + `${anyOf.length ? ` or one of [${anyOf.join("] [")}]` : ""}; focus ${(exercise.focus ?? []).map(shortJoint).join(" ")}`);
    if (exercise.configuration) {
      lines.push(`  tuning: ${Object.keys(exercise.configuration).sort().map((key) => `${key}=${exercise.configuration[key]}`).join(" ")}`);
    }
  }
  lines.push("", "Phases");
  lines.push(s.phaseSpans.map((span) => `${span.label} ${clock(span.start)}–${clock(span.end)}`).join(" · "));
  const counted = s.reps.filter((rep) => rep.outcome === "counted" || rep.outcome === "completedSet");
  const oneSide = s.reps.filter((rep) => rep.outcome === "oneSide");
  const dropped = s.reps.filter((rep) => rep.outcome === "notCounted");
  lines.push("", `Reps: ${s.reps.length} analyzer rep events; ${counted.length} counted`
    + `${counted.length ? ` (${counted.slice(0, 60).map((rep) => `#${rep.count}${rep.outcome === "completedSet" ? " completing the set" : ""} at ${clock(rep.t)}`).join(", ")})` : ""}`
    + `${oneSide.length ? `; ${oneSide.length} on one side only (count unchanged)` : ""}`
    + `${dropped.length ? `; ${dropped.length} NOT counted (${dropped.slice(0, 20).map((rep) => `${clock(rep.t)}${rep.reason ? ` ${rep.reason}` : ""}`).join(", ")})` : ""}`);
  if (s.rejections.length) {
    lines.push("", `Attempts the analyzer let go (${s.rejections.length})`);
    for (const rejection of s.rejections.slice(0, 40)) {
      lines.push(`- ${clock(rejection.t)}${rejection.side ? ` ${rejection.side}` : ""}: ${rejection.text}`);
    }
    if (s.rejections.length > 40) lines.push(`(the first 40 of ${s.rejections.length})`);
  }
  lines.push("", `Tracking losses (${s.losses.length})`);
  if (s.losses.length > 60) lines.push(`(the first 60 of ${s.losses.length})`);
  for (const loss of s.losses.slice(0, 60)) {
    lines.push(`- ${clock(loss.start)}–${clock(loss.end)} (${(loss.end - loss.start).toFixed(1)} s)${loss.guidances.length ? `: ${loss.guidances.join(" → ")}` : ""}`);
  }
  const markers = s.markers.map((marker) => {
    const text = s.deviceNotes.filter((n) => n.markerID === marker.id).at(-1)?.text ?? marker.text;
    return `- ${clock(marker.heardAt ?? marker.t)} marker on phone (${marker.source})${text ? `: ${text}` : ""}`;
  });
  const viewerNotes = notes.map((note) => `- ${note.end != null ? `${clock(note.t)}–${clock(note.end)}` : clock(note.t)} note (${note.author}): ${note.text}`);
  lines.push("", `Markers and notes (${markers.length + viewerNotes.length})`);
  lines.push(...(markers.length + viewerNotes.length ? [...markers, ...viewerNotes] : ["none"]));
  const issues = s.timeline.filter((item) => item.kind === "cue" || (item.kind === "warn" && item.title !== "Tracking lost"));
  lines.push("", `Other issues (${issues.length})`);
  lines.push(...(issues.length ? issues.slice(0, 40).map((item) => `- ${clock(item.t)} ${item.title}${item.detail ? `: ${item.detail}` : ""}`) : ["none"]));
  const windows = [
    ...s.losses.slice(0, 3).map((loss) => [Math.max(0, loss.start - 1), Math.min(s.duration, loss.end + 1), "tracking"]),
    ...s.markers.slice(0, 3).map((marker) => [Math.max(0, (marker.heardAt ?? marker.t) - 8), Math.min(s.duration, (marker.heardAt ?? marker.t) + 2), "rep"]),
    ...notes.slice(0, 3).map((note) => [Math.max(0, note.t - 3), Math.min(s.duration, (note.end ?? note.t) + 2), "rep"]),
  ];
  if (windows.length) {
    lines.push("", "Suggested queries");
    for (const [from, to, preset] of windows) {
      lines.push(`- fmp_query session=${s.id.slice(0, 8)} from=${from.toFixed(1)} to=${to.toFixed(1)} preset=${preset}`);
    }
  }
  return lines.join("\n");
}

async function query(args) {
  const summary = await resolveSession(args.session);
  const s = await store.readSession(summary.id);
  const from = Math.max(0, seconds(args.from, "from"));
  const to = Math.min(s.duration, seconds(args.to, "to"));
  if (!(to > from)) throw new ToolError(`The window ${from}–${to} is empty; the recording is ${s.duration.toFixed(1)} s long.`);
  const options = { ...(PRESETS[args.preset ?? "rep"] ?? PRESETS.rep) };
  if (args.rate != null) options.rate = Number(args.rate);
  if (args.joints) options.joints = args.joints;
  for (const [key, value] of Object.entries(args.include ?? {})) options[key] = Boolean(value);
  if (args.rate != null || args.joints || args.include) options.label = "custom";
  const rows = sampleFrames(s, from, to, options.rate).length;
  if (rows > MAX_ROWS && !args.allowLarge) {
    throw new ToolError(`That window has ${rows} frame rows at ${options.rate} Hz. Narrow it, lower the rate, or pass allowLarge.`);
  }
  const notes = (await store.notesFor(summary.id)).notes;
  const text = renderExcerpt(s, { from, to, options, notes });
  if (text.length > MAX_CHARS && !args.allowLarge) {
    throw new ToolError(`That excerpt is about ${estimateTokens(text)} tokens. Narrow the window, lower the rate, or pass allowLarge.`);
  }
  return text;
}

async function events(args) {
  const summary = await resolveSession(args.session);
  const s = await store.readSession(summary.id);
  const from = seconds(args.from, "from") ?? 0;
  const to = seconds(args.to, "to") ?? s.duration;
  const notes = (await store.notesFor(summary.id)).notes.map((note) => ({ t: note.t, kind: "note", title: `Note (${note.author})`, detail: note.text }));
  const kinds = new Set(args.kinds ?? []);
  const items = s.timeline.concat(notes).filter((item) => item.t >= from && item.t <= to && (!kinds.size || kinds.has(item.kind)))
    .sort((a, b) => a.t - b.t);
  const lines = [`${items.length} events in ${s.id.slice(0, 8)} ${clock(from)}–${clock(to)}`];
  for (const item of items.slice(0, 400)) lines.push(`${clock(item.t)} [${item.kind}] ${item.title}${item.detail ? ` — ${item.detail}` : ""}`);
  if (items.length > 400) lines.push(`… ${items.length - 400} more; narrow the window.`);
  return lines.join("\n");
}

async function selection() {
  const state = await viewer("api/viewer/state");
  const sent = (await viewer("api/viewer/sent")) ?? await store.readOutbox();
  const lines = [];
  if (state === undefined) lines.push("The viewer's server isn't running (fmp_open_viewer starts it).");
  else if (!state?.sessionId) lines.push(`The viewer's server is running with ${state?.viewers ?? 0} open viewer(s), and no recording reported yet.`);
  else {
    lines.push(`Open viewer: ${state.title ?? state.sessionId} (${state.sessionId}) at ${clock(Number(state.t ?? 0))}`
      + `${state.selection ? `, selected ${clock(state.selection.from)}–${clock(state.selection.to)}` : ", nothing selected"}; ${state.viewers ?? 0} viewer(s) open.`);
  }
  if (sent?.markdown) {
    const markdown = sent.markdown.length > MAX_CHARS
      ? `${sent.markdown.slice(0, MAX_CHARS)}\n… (cut at ${MAX_CHARS} characters; the whole excerpt is in diagnostics/outbox/latest.md)` : sent.markdown;
    lines.push("", `Last sent from the viewer (${sent.sentAt ?? "time unknown"}, ${sent.title ?? sent.sessionId ?? ""} ${sent.from != null ? `${clock(sent.from)}–${clock(sent.to)}` : ""}):`, "", markdown);
  } else {
    lines.push("Nothing has been sent from the viewer yet.");
  }
  return lines.join("\n");
}

async function seek(args) {
  const summary = await resolveSession(args.session);
  const command = { command: "seek", sessionId: summary.id, t: seconds(args.t, "t"), from: seconds(args.from, "from"), to: seconds(args.to, "to"), note: args.note ?? null };
  const result = await viewer("api/viewer/command", { method: "POST", body: JSON.stringify(command) });
  if (result === undefined) throw new ToolError("The replay viewer isn't open. Call fmp_open_viewer first.");
  if (!result.delivered) return `The viewer's server is running but no viewer is open; call fmp_open_viewer with t=${command.t}.`;
  return `Moved ${result.delivered} open viewer(s) to ${clock(command.t)} in ${summary.title}${command.from != null ? `, selecting ${clock(command.from)}–${clock(command.to)}` : ""}.`;
}

async function addNote(args) {
  const summary = await resolveSession(args.session);
  const text = String(args.text ?? "").trim();
  if (!text) throw new ToolError("A note needs text.");
  const note = { id: crypto.randomUUID(), t: seconds(args.t, "t"), end: seconds(args.end, "end"), text, author: "claude" };
  // Through the viewer's server when it runs, so open viewers show the note at once. Saving by id is idempotent, so
  // if the server times out after saving, saving again directly can't duplicate the note.
  const saved = (await viewer(`api/sessions/${summary.id}/notes`, { method: "POST", body: JSON.stringify(note) })) ?? await store.saveNote(summary.id, note);
  return `Added Claude's note at ${clock(note.t)} to ${summary.title}; it has ${saved.notes.length} note(s).`;
}

async function openViewer(args) {
  const started = await ensureViewerServer();
  const params = new URLSearchParams();
  if (args.session) params.set("session", (await resolveSession(args.session)).id);
  for (const key of ["t", "from", "to"]) if (args[key] != null) params.set(key, String(seconds(args[key], key)));
  if (args.export) params.set("export", "1");
  const url = `${BASE}${params.size ? `?${params}` : ""}`;
  spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
  return `${started ? "Started the viewer's server and opened" : "Opened"} ${url}`;
}

let presetManifestPromise = null;
let labQueue = Promise.resolve();

function enqueueLab(operation) {
  const pending = labQueue.then(operation, operation);
  labQueue = pending.then(() => undefined, () => undefined);
  return pending;
}

async function presetManifest() {
  if (!presetManifestPromise) {
    presetManifestPromise = (async () => {
      const runDir = await createFreshRunDirectory(ROOT);
      try { return await emitPresetManifest({ root: ROOT, runDir }); }
      finally { await rm(runDir, { recursive: true, force: true }); }
    })();
  }
  try { return await presetManifestPromise; }
  catch (error) { presetManifestPromise = null; throw error; }
}

async function labManifest() {
  return enqueueLab(async () => formatAgentManifest(await presetManifest(), {
    categories: SCENARIO_CATEGORIES, mutationBounds: MUTATION_BOUNDS,
  }));
}

async function labRun(args) {
  return enqueueLab(async () => {
    const hasPlan = Object.hasOwn(args, "plan");
    const hasPreset = Object.hasOwn(args, "preset");
    if (hasPlan === hasPreset) throw new ToolError("Supply exactly one of plan or preset.");
    let sourcePlan = args.plan;
    if (hasPreset) {
      const manifest = await presetManifest();
      const entry = manifest.presets.find((item) => item?.id === args.preset);
      if (!entry?.plan) throw new ToolError(`Unknown built-in preset '${args.preset}'.`);
      sourcePlan = entry.plan;
    }
    if (args.parentRunID !== undefined) {
      try { await labStore.readRun(args.parentRunID); }
      catch (error) { throw new ToolError(`Follow-up parent run is unavailable: ${error.message}`); }
    }
    let plan;
    try { plan = prepareAgentPlan(sourcePlan, args); }
    catch (error) { throw new ToolError(error.message); }
    const result = await runPlan({ root: ROOT, inputPlan: plan, mode: args.mode });
    return formatAgentRun(result);
  });
}

async function labInspect(args) {
  if (args.window && args.window.from > args.window.to) throw new ToolError("window.from must not exceed window.to.");
  const output = await inspectRun({ root: ROOT, runID: args.runID, scenarioID: args.scenarioID,
    window: args.window ?? null, full: args.full === true });
  try { return assertBoundedInspection(output, { full: args.full === true, byteCap: MCP_FULL_TRACE_BYTE_CAP }); }
  catch (error) { throw new ToolError(error.message); }
}

function openURL(url) {
  return new Promise((resolve, reject) => {
    const child = spawn("open", [url], { detached: true, stdio: "ignore" });
    child.once("error", reject);
    child.once("spawn", () => { child.unref(); resolve(); });
  });
}

async function labOpen(args) {
  let result;
  try {
    result = await openLabDashboard({ store: labStore, runID: args.runID, scenarioID: args.scenarioID,
      baseURL: BASE, ensureViewer: ensureViewerServer, openURL,
      sendCommand: (command) => viewer("api/viewer/command", { method: "POST", body: JSON.stringify(command) }) });
  } catch (error) { throw new ToolError(error.message); }
  const target = args.scenarioID ? `scenario ${args.scenarioID} at ${clock(result.timestamp)}` : `run ${args.runID}`;
  return `Opened the Movement Lab dashboard for ${target}; sent the viewer command to ${result.delivered} connected viewer(s).`;
}

// Calls while a pull runs share it; separate pulls (another session, or `make diagnostics`) are refused by the script.
let pulling = null;
function pull() {
  pulling ??= runPull().finally(() => { pulling = null; });
  return pulling;
}

function runPull() {
  return new Promise((resolve, reject) => {
    execFile("bash", [path.join(ROOT, "scripts", "diagnostics", "pull.sh")], { cwd: ROOT, timeout: 240_000, maxBuffer: 4 * 1024 * 1024 },
      (error, stdout, stderr) => {
        const output = `${stdout}${stderr}`.trim();
        if (error) reject(new ToolError(output || error.message));
        else resolve(output || "Pulled.");
      });
  });
}

const HANDLERS = {
  fmp_pull_device: pull,
  fmp_list_sessions: async (args) => {
    const sessions = (await store.listSessions()).slice(0, args.limit ?? 20);
    if (!sessions.length) return "No recordings in diagnostics/sessions/. Call fmp_pull_device with the iPhone connected.";
    return sessions.map((s) => `${s.id}  ${s.startedAt ?? "?"}  ${s.title}  ${s.frameCount} frames  ${s.markerCount} markers  ${s.noteCount} notes${s.isComplete ? "" : "  incomplete"}`).join("\n");
  },
  fmp_session_overview: (args) => overview(args.session),
  fmp_query: query,
  fmp_events: events,
  fmp_viewer_selection: selection,
  fmp_viewer_seek: seek,
  fmp_add_note: addNote,
  fmp_open_viewer: openViewer,
  fmp_lab_manifest: labManifest,
  fmp_lab_run: labRun,
  fmp_lab_inspect: labInspect,
  fmp_lab_open: labOpen,
};

// MARK: - Arguments

/** Checks arguments against a tool's input schema (the subset these tools use); returns a problem or null. */
function invalidArguments(schema, args) {
  if (args === null || typeof args !== "object" || Array.isArray(args)) return "arguments must be an object";
  for (const key of schema.required ?? []) {
    if (args[key] === undefined || args[key] === null) return `${key} is required`;
  }
  for (const [key, value] of Object.entries(args)) {
    const property = schema.properties?.[key];
    if (!property) return `unknown argument ${key}`;
    if (value === null || value === undefined) continue;
    const types = [property.type].flat();
    const matches = types.some((type) => (type === "integer" ? Number.isInteger(value) : type === "number" ? typeof value === "number" && Number.isFinite(value)
      : type === "array" ? Array.isArray(value) : type === "object" ? typeof value === "object" && !Array.isArray(value) : typeof value === type));
    if (!matches) return `${key} must be ${types.join(" or ")}`;
    if (property.enum && !property.enum.includes(value)) return `${key} must be one of ${property.enum.join(", ")}`;
    if (property.maxLength != null && typeof value === "string" && value.length > property.maxLength) return `${key} is longer than ${property.maxLength} characters`;
    if (property.minLength != null && typeof value === "string" && value.length < property.minLength) return `${key} is shorter than ${property.minLength} characters`;
    if (property.pattern != null && typeof value === "string" && !(new RegExp(property.pattern).test(value))) return `${key} has an invalid format`;
    if (property.minimum != null && typeof value === "number" && value < property.minimum) return `${key} must be at least ${property.minimum}`;
    if (property.maximum != null && typeof value === "number" && value > property.maximum) return `${key} must be at most ${property.maximum}`;
    if (property.minItems != null && Array.isArray(value) && value.length < property.minItems) return `${key} must contain at least ${property.minItems} items`;
    if (property.maxItems != null && Array.isArray(value) && value.length > property.maxItems) return `${key} must contain at most ${property.maxItems} items`;
    if (property.type === "array" && property.items && Array.isArray(value)) {
      for (let index = 0; index < value.length; index += 1) {
        const item = value[index];
        const itemType = [property.items.type].flat();
        if (itemType.length && !itemType.some((type) => (type === "integer" ? Number.isInteger(item) : type === "number" ? typeof item === "number" && Number.isFinite(item)
          : type === "object" ? item !== null && typeof item === "object" && !Array.isArray(item) : typeof item === type))) {
          return `${key}[${index}] must be ${itemType.join(" or ")}`;
        }
        if (property.items.enum && !property.items.enum.includes(item)) {
          return `${key}[${index}] may contain only ${property.items.enum.join(", ")}`;
        }
        if (property.items.type === "object" && property.items.properties) {
          const inner = invalidArguments(property.items, item);
          if (inner) return `${key}[${index}]: ${inner}`;
        }
      }
    }
    if (property.type === "object" && property.properties) {
      const inner = invalidArguments(property, value);
      if (inner) return `${key}: ${inner}`;
    }
  }
  return null;
}

// MARK: - JSON-RPC over stdio

function reply(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

async function handle(message) {
  const { id, method, params } = message;
  const respond = (result) => { if (id !== undefined) reply({ jsonrpc: "2.0", id, result }); };
  const fail = (code, text) => { if (id !== undefined) reply({ jsonrpc: "2.0", id, error: { code, message: text } }); };
  switch (method) {
    case "initialize":
      return respond({
        protocolVersion: SUPPORTED_VERSIONS.includes(params?.protocolVersion) ? params.protocolVersion : SUPPORTED_VERSIONS[0],
        capabilities: { tools: {} },
        serverInfo: { name: "fmp-replay", version: "1.0.0" },
        instructions: "FMP workout recordings from the user's iPhone. Start with fmp_session_overview, then fmp_query short windows. For synthetic Movement Lab work, start with fmp_lab_manifest, batch via fmp_lab_run, and inspect only non-passing or inconclusive cases. Recordings are a real person's body data: never paste them into commits, issues, or PRs unless the developer asks.",
      });
    case "notifications/initialized":
    case "notifications/cancelled":
      return undefined;
    case "ping":
      return respond({});
    case "tools/list":
      return respond({ tools: TOOLS });
    case "tools/call": {
      const name = params?.name;
      if (typeof name !== "string" || !Object.hasOwn(HANDLERS, name)) return fail(-32602, `Unknown tool ${name}.`);
      const args = params.arguments ?? {};
      const problem = invalidArguments(TOOLS.find((tool) => tool.name === name).inputSchema, args);
      if (problem) return fail(-32602, `Invalid arguments for ${name}: ${problem}.`);
      try {
        const text = String(await HANDLERS[name](args));
        return respond({ content: [{ type: "text", text }] });
      } catch (error) {
        const known = error instanceof ToolError || error instanceof StoreError;
        return respond({ content: [{ type: "text", text: known ? error.message : `Failed: ${error?.message ?? error}` }], isError: true });
      }
    }
    default:
      return fail(-32601, `Method not found: ${method}`);
  }
}

const input = createInterface({ input: process.stdin });
input.on("line", (line) => {
  if (!line.trim()) return;
  if (Buffer.byteLength(line, "utf8") > MAX_MCP_MESSAGE_BYTES) {
    reply({ jsonrpc: "2.0", id: null, error: { code: -32600, message: `Request exceeds ${MAX_MCP_MESSAGE_BYTES} bytes.` } });
    return;
  }
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    reply({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
    return;
  }
  handle(message).catch((error) => process.stderr.write(`fmp-replay: ${error?.stack ?? error}\n`));
});
