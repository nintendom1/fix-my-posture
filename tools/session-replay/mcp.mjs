#!/usr/bin/env node
// MCP server (stdio) that lets Claude Code work with FMP workout recordings: pull them from the iPhone, get an
// overview, query any window at any rate, read what the viewer sent, add notes, and move the open viewer.
// Registered in the repository's .mcp.json. Node 20 or later, no dependencies. Everything stays on this Mac.
//
// Recordings are read straight from diagnostics/sessions/; the viewer's server (tools/session-replay/server.mjs) is
// used only for live work: moving the playhead, and saving notes so an open viewer shows them at once.

import { spawn, execFile } from "node:child_process";
import { realpathSync } from "node:fs";
import { createInterface } from "node:readline";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createStore, StoreError } from "./lib/store.mjs";
import { PRESETS, renderExcerpt, sampleFrames, clock, estimateTokens, shortJoint } from "./lib/session.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = process.env.FMP_REPLAY_ROOT ?? path.resolve(here, "../..");
const PORT = Number(process.env.FMP_REPLAY_PORT ?? 4317);
const BASE = `http://127.0.0.1:${PORT}/`;
const MAX_ROWS = Number(process.env.FMP_REPLAY_MAX_ROWS ?? 300);
const MAX_CHARS = 60_000;
const REQUEST_TIMEOUT = 2000;
const SUPPORTED_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"];
const store = createStore(ROOT);
const canonicalRoot = (() => { try { return realpathSync(ROOT); } catch { return ROOT; } })();

// MARK: - Tools

const session = { type: "string", description: "Recording id, its first 8 characters, or \"latest\" (the default)." };
const time = { type: ["number", "string"], description: "Seconds from the start of the recording, or \"m:ss.s\"." };

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
    if (property.minimum != null && typeof value === "number" && value < property.minimum) return `${key} must be at least ${property.minimum}`;
    if (property.maximum != null && typeof value === "number" && value > property.maximum) return `${key} must be at most ${property.maximum}`;
    if (property.items?.enum && Array.isArray(value) && value.some((item) => !property.items.enum.includes(item))) {
      return `${key} may contain only ${property.items.enum.join(", ")}`;
    }
    if (property.type === "object" && property.properties) {
      const inner = invalidArguments({ properties: property.properties }, value);
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
        instructions: "FMP workout recordings from the user's iPhone. Start with fmp_session_overview, then fmp_query short windows. Recordings are a real person's body data: never paste them into commits, issues, or PRs unless the developer asks.",
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
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    reply({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
    return;
  }
  handle(message).catch((error) => process.stderr.write(`fmp-replay: ${error?.stack ?? error}\n`));
});
