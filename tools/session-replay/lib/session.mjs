// Reads FMP workout recordings (schema fmp.workout-session/1) and renders excerpts for a chat with Claude.
// Shared by the browser viewer and the local server; plain ES module, no dependencies.
// Format: docs/diagnostics.md. A recording is a JSON array with one record per line (older ones are JSON Lines).

export const SCHEMA = "fmp.workout-session/1";

/** Skeleton lines, as `BodyPose.connections` in the app. */
export const BONES = [
  ["leftEar", "leftEye"], ["leftEye", "nose"], ["nose", "rightEye"], ["rightEye", "rightEar"], ["nose", "neck"],
  ["leftShoulder", "neck"], ["neck", "rightShoulder"], ["leftShoulder", "rightShoulder"],
  ["leftShoulder", "leftHip"], ["rightShoulder", "rightHip"], ["leftHip", "rightHip"], ["leftHip", "root"],
  ["rightHip", "root"], ["neck", "root"],
  ["leftShoulder", "leftElbow"], ["leftElbow", "leftWrist"], ["rightShoulder", "rightElbow"], ["rightElbow", "rightWrist"],
  ["leftHip", "leftKnee"], ["leftKnee", "leftAnkle"], ["rightHip", "rightKnee"], ["rightKnee", "rightAnkle"],
];

/** "LS" for leftShoulder, "RW" for rightWrist; the same names the app's text report uses. */
export function shortJoint(name) {
  const named = { nose: "Nose", neck: "Neck", root: "Root", leftEye: "LEye", rightEye: "REye", leftEar: "LEar", rightEar: "REar" };
  if (named[name]) return named[name];
  const side = name.startsWith("left") ? "L" : name.startsWith("right") ? "R" : "";
  return side + name.replace(/^left|^right/, "").charAt(0);
}

/** One line's record text, without the array brackets or the comma between records; null for a line with none. */
export function recordText(line) {
  let text = line.trim();
  if (text.startsWith(",")) text = text.slice(1);
  if (text.endsWith(",")) text = text.slice(0, -1);
  return text.startsWith("{") ? text : null;
}

/** Every record in a recording's text. A record cut short by a crash is skipped and counted. */
export function parseRecords(text) {
  const records = [];
  let skipped = 0;
  for (const line of text.split("\n")) {
    const record = recordText(line);
    if (record === null) continue;
    try {
      records.push(JSON.parse(record));
    } catch {
      skipped += 1;
    }
  }
  return { records, skipped };
}

/** The same records as a closed recording file: a JSON array, one record per line. */
export function recordsToFileText(lines) {
  return lines.length ? "[\n" + lines.join(",\n") + "\n]\n" : "[\n]\n";
}

/** Rewrites any recording text (JSON array or older JSON Lines, closed or not) as a closed JSON array file. */
export function normalizeFileText(text) {
  const lines = [];
  for (const line of text.split("\n")) {
    const record = recordText(line);
    if (record === null) continue;
    try {
      JSON.parse(record);
      lines.push(record);
    } catch {
      // A record cut short is dropped.
    }
  }
  return recordsToFileText(lines);
}

function lastAtOrBefore(sorted, t, key = (item) => item.t) {
  let low = 0;
  let high = sorted.length - 1;
  let found = -1;
  while (low <= high) {
    const mid = (low + high) >> 1;
    if (key(sorted[mid]) <= t) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return found;
}

/** A recording, ready to replay: frames, state, events, segments for the timeline, and lookups by time. */
export class Session {
  constructor(records, { skipped = 0 } = {}) {
    this.skipped = skipped;
    this.header = records.find((record) => record.k === "header") ?? {};
    this.jointOrder = this.header.jointOrder ?? [];
    this.exercises = this.header.exercises ?? {};
    this.frames = [];
    this.states = [];
    this.pipes = [];
    this.events = [];
    this.markers = [];
    this.deviceNotes = [];
    this.end = null;
    let size = null;
    for (const record of records) {
      switch (record.k) {
        case "f":
          size = record.wh ?? size;
          record.size = size;
          this.frames.push(record);
          break;
        case "state": this.states.push(record); break;
        case "pipe": this.pipes.push(record); break;
        case "e": this.events.push(record); break;
        case "marker": this.markers.push(record); break;
        case "note": this.deviceNotes.push(record); break;
        case "end": this.end = record; break;
        default: break;
      }
    }
    const lastTimes = [this.frames.at(-1)?.t, this.states.at(-1)?.t, this.events.at(-1)?.t, this.end?.t].filter((t) => t != null);
    this.duration = lastTimes.length ? Math.max(...lastTimes) : 0;
    this.imageSize = size ?? [1080, 1920];
    this.exerciseSpans = this.#spans(this.pipes.filter((p) => p.control === "exercise" && p.exercise),
      (p) => p.exercise);
    this.phaseSpans = this.#spans(this.states, (s) => s.phase);
    this.framingSpans = this.#framingSpans();
    this.losses = this.#losses();
    this.timeline = this.#timeline();
  }

  static fromText(text) {
    const { records, skipped } = parseRecords(text);
    return new Session(records, { skipped });
  }

  get id() { return this.header.id ?? "unknown"; }
  /** The Saved Set's name, or the exercises done. */
  get title() {
    if (this.header.plan?.name) return this.header.plan.name;
    const names = [...new Set(this.exerciseSpans.map((span) => this.exercises[span.label]?.name ?? span.label))];
    return names.join(", ") || "Workout";
  }
  get isComplete() { return this.end != null; }

  /** Spans of constant value from records sorted by time, covering the recording. */
  #spans(records, value) {
    const spans = [];
    for (const record of records) {
      const label = value(record);
      if (spans.length && spans.at(-1).label === label) continue;
      if (spans.length) spans.at(-1).end = record.t;
      spans.push({ start: record.t, end: this.duration, label });
    }
    return spans;
  }

  /** Framing spans from framing events, split whenever reliability or guidance changes. `wasReliable` marks a span
   * that is not reliable after tracking had been reliable: a tracking loss. */
  #framingSpans() {
    const spans = [{ start: 0, end: this.duration, ok: false, wasReliable: false, guidance: null }];
    let everReliable = false;
    for (const event of this.events) {
      if (event.type !== "framing" || !event.framing) continue;
      const ok = event.framing.ok === true;
      const guidance = event.framing.g ?? null;
      const current = spans.at(-1);
      if (ok === current.ok && guidance === current.guidance) continue;
      current.end = event.t;
      if (ok) everReliable = true;
      spans.push({ start: event.t, end: this.duration, ok, wasReliable: !ok && everReliable, guidance });
    }
    return spans.filter((span) => span.end > span.start);
  }

  /** Each tracking loss from losing reliability to getting it back, with the guidance shown along the way. */
  #losses() {
    const losses = [];
    for (const span of this.framingSpans) {
      if (span.ok || !span.wasReliable) continue;
      const last = losses.at(-1);
      if (last && last.end === span.start) {
        last.end = span.end;
        if (span.guidance && !last.guidances.includes(span.guidance)) last.guidances.push(span.guidance);
      } else {
        losses.push({ start: span.start, end: span.end, guidances: span.guidance ? [span.guidance] : [] });
      }
    }
    return losses;
  }

  /** The event log: what happened, in order, with a kind for coloring and filtering. */
  #timeline() {
    const items = [];
    const add = (t, kind, title, detail = "") => items.push({ t, kind, title, detail });
    for (const event of this.events) {
      switch (event.type) {
        case "command":
          add(event.t, "command", `Command: ${event.command}`, event.source === "voice" ? `voice${event.phrase ? ` · “${event.phrase}”` : ""}` : "touch");
          break;
        case "rep":
          // The analyzer's event, before the coach accepts it; counted reps come from the state below.
          add(event.t, "analyzer", "Analyzer rep", `sides ${(event.sides ?? []).join("+")}, epoch ${event.epoch}`);
          break;
        case "speak": add(event.t, "voice", event.muted ? "Coach (muted)" : "Coach says", `“${event.text}”`); break;
        case "tip": add(event.t, "cue", `Tip: ${event.cue}`, event.text ? `“${event.text}”` : ""); break;
        case "tilt": add(event.t, "warn", event.tilted ? "Phone tilted" : "Phone upright"); break;
        case "camera.interrupted": case "camera.failed": case "app.background": case "interruptionBegan":
          add(event.t, "warn", event.type, event.message ?? "");
          break;
        case "camera.running": case "app.foreground": case "interruptionEnded": case "opened":
          add(event.t, "info", event.type);
          break;
        default: break;
      }
    }
    let previous = null;
    for (const span of this.framingSpans) {
      // The opening span, before any framing result, says nothing.
      if (span.start === 0 && !span.ok && !span.guidance) continue;
      if (span.ok) add(span.start, "info", "Tracking reliable");
      else if (previous && !previous.ok && previous.wasReliable === span.wasReliable) add(span.start, "info", "Guidance", span.guidance ?? "none");
      else add(span.start, span.wasReliable ? "warn" : "info", span.wasReliable ? "Tracking lost" : "Not tracking", span.guidance ?? "");
      previous = span;
    }
    let last = null;
    for (const state of this.states) {
      if (last && state.phase !== last.phase) add(state.t, "set", `Phase: ${state.phase}`, state.ex ? `${state.ex} · set ${state.set}` : "");
      if (last && state.reps > last.reps) add(state.t, "rep", `Rep ${state.reps}`, state.sideReps ? `L ${state.sideReps.left} · R ${state.sideReps.right}` : "");
      else if (last && state.sideReps && last.sideReps && state.reps === last.reps
        && (state.sideReps.left !== last.sideReps.left || state.sideReps.right !== last.sideReps.right)) {
        add(state.t, "analyzer", "Side rep, count unchanged", `L ${state.sideReps.left} · R ${state.sideReps.right}`);
      }
      if (last && state.counting !== last.counting && state.counting !== undefined) add(state.t, "info", state.counting ? "Counting on" : "Counting off");
      last = state;
    }
    for (const marker of this.markers) {
      const note = this.deviceNotes.filter((n) => n.markerID === marker.id).at(-1)?.text ?? marker.text;
      add(marker.heardAt ?? marker.t, "marker", `Marker (${marker.source})`, note ? `“${note}”` : "");
    }
    return items.sort((a, b) => a.t - b.t);
  }

  frameIndexAt(t) { return Math.max(0, lastAtOrBefore(this.frames, t)); }
  frameAt(t) { return this.frames[this.frameIndexAt(t)] ?? null; }
  stateAt(t) { return this.states[lastAtOrBefore(this.states, t)] ?? null; }
  exerciseIDAt(t) {
    const index = lastAtOrBefore(this.exerciseSpans, t, (span) => span.start);
    return (this.exerciseSpans[index] ?? this.exerciseSpans[0])?.label ?? null;
  }
  exerciseAt(t) { return this.exercises[this.exerciseIDAt(t)] ?? null; }

  /** The exercise's focus joints in joint order, or every joint. */
  focusJoints(t) {
    const focus = new Set(this.exerciseAt(t)?.focus ?? []);
    return focus.size ? this.jointOrder.filter((name) => focus.has(name)) : [...this.jointOrder];
  }

  /** The joints framing checks in a frame: the required ones plus the strongest alternative set, as framing picks
   * whichever alternative is fully visible. */
  requiredJoints(frame, t = frame?.t ?? 0) {
    const exercise = this.exerciseAt(t);
    if (!exercise) return [];
    const required = exercise.required ?? [];
    const alternatives = exercise.anyOfRequired ?? [];
    if (!alternatives.length) return [...required];
    let best = alternatives[0];
    let bestScore = -1;
    for (const alternative of alternatives) {
      const score = this.minConfidence(frame, alternative) ?? 0;
      if (score > bestScore) { best = alternative; bestScore = score; }
    }
    return [...new Set([...required, ...best])];
  }

  /** The weakest joint framing needs in a frame, and its confidence (0 when missing). */
  weakestRequired(frame) {
    let weakest = null;
    for (const name of this.requiredJoints(frame)) {
      const joint = this.joint(frame, name);
      const value = joint?.kind === "seen" || joint?.kind === "low" ? joint.c : joint?.kind === "est" ? 1 : 0;
      if (!weakest || value < weakest.value) weakest = { name, value, kind: joint?.kind ?? "missing" };
    }
    return weakest;
  }

  /** The state in force at `t`, with the counting flag and framing of the frame there. */
  snapshotAt(t) {
    const state = this.stateAt(t);
    const frame = this.frameAt(t);
    return { state, frame, exerciseID: this.exerciseIDAt(t) };
  }

  /** A joint in one frame: its position and confidence, and whether it was seen, below the floor, or estimated. */
  joint(frame, name) {
    const index = this.jointOrder.indexOf(name);
    if (index < 0 || !frame) return null;
    const estimated = (frame.est ?? []).find((entry) => entry[0] === index);
    if (estimated) return { name, x: estimated[1], y: estimated[2], c: null, kind: "est" };
    const seen = frame.j?.[index];
    if (seen) return { name, x: seen[0], y: seen[1], c: seen[2], kind: "seen" };
    const low = (frame.lo ?? []).find((entry) => entry[0] === index);
    if (low) return { name, x: low[1], y: low[2], c: low[3], kind: "low" };
    return { name, x: null, y: null, c: null, kind: "missing" };
  }

  /** The lowest confidence among `joints` in a frame; a missing joint counts as 0. */
  minConfidence(frame, joints) {
    let lowest = 1;
    for (const name of joints) {
      const joint = this.joint(frame, name);
      lowest = Math.min(lowest, joint?.kind === "seen" || joint?.kind === "low" ? joint.c : joint?.kind === "est" ? 1 : 0);
    }
    return joints.length ? lowest : null;
  }
}

// MARK: - Excerpts for Claude

export const PRESETS = {
  rep: {
    label: "Rep counting", rate: 5, joints: "focus", positions: true, confidence: true, low: true,
    readings: true, thresholds: true, framing: true, form: false, events: true, tuning: true,
  },
  tracking: {
    label: "Tracking & framing", rate: 5, joints: "all", positions: true, confidence: true, low: true,
    readings: false, thresholds: false, framing: true, form: false, events: true, tuning: false,
  },
  form: {
    label: "Form cue", rate: 5, joints: "focus", positions: true, confidence: false, low: false,
    readings: true, thresholds: false, framing: false, form: true, events: true, tuning: true,
  },
  flow: {
    label: "Session flow", rate: 0, joints: "none", positions: false, confidence: false, low: false,
    readings: false, thresholds: false, framing: false, form: false, events: true, tuning: false,
  },
};

export const RATES = [10, 5, 2, 1, 0];

export function clock(seconds, tenths = true) {
  const total = Math.max(0, seconds);
  const minutes = Math.floor(total / 60);
  const rest = total - minutes * 60;
  return tenths ? `${minutes}:${rest.toFixed(1).padStart(4, "0")}` : `${minutes}:${String(Math.floor(rest)).padStart(2, "0")}`;
}

/** A rough token count for a chat model: about 3.6 characters per token for this kind of text. */
export function estimateTokens(text) {
  return Math.ceil(text.length / 3.6);
}

function number(value, places = 2) {
  if (value == null || Number.isNaN(value)) return "";
  const fixed = Number(value).toFixed(places);
  return fixed.includes(".") ? fixed.replace(/0+$/, "").replace(/\.$/, "") : fixed;
}

/** The frames to show between `from` and `to`: about `rate` per second, plus any frame where framing (reliability or
 * guidance) changes or the analyzer reports a rep. */
export function sampleFrames(session, from, to, rate) {
  if (!rate) return [];
  const start = Math.max(0, session.frameIndexAt(from));
  const picked = [];
  let lastTime = -Infinity;
  let lastFraming;
  for (let index = start; index < session.frames.length; index += 1) {
    const frame = session.frames[index];
    if (frame.t < from) continue;
    if (frame.t > to) break;
    const framing = frame.fr ? `${frame.fr.ok}|${frame.fr.g ?? ""}` : undefined;
    const changed = framing !== undefined && framing !== lastFraming;
    if (framing !== undefined) lastFraming = framing;
    const hasRep = (frame.out ?? []).some((event) => event.rep);
    if (changed || hasRep || frame.t >= lastTime + 1 / rate - 0.02) {
      picked.push(frame);
      lastTime = frame.t;
    }
  }
  return picked;
}

/**
 * Markdown for a chat: what the window is, the notes in it, the exercise's tuning, the events, and a frame table
 * as CSV. `options` is a preset with any overrides; `notes` are viewer notes `{t, end?, text, author}`.
 */
export function renderExcerpt(session, { from = 0, to = session.duration, options = PRESETS.rep, notes = [], title } = {}) {
  const lines = [];
  const name = title ?? session.title;
  const started = session.header.startedAt ? session.header.startedAt.slice(0, 16).replace("T", " ") : "";
  lines.push(`# FMP replay excerpt · ${name}${started ? ` · ${started}` : ""}`);
  lines.push(`Recording ${session.id} · window ${clock(from)}–${clock(to)} (${(to - from).toFixed(1)} s) · `
    + (options.rate ? `${options.rate} Hz` : "events only") + ` · ${options.label ?? "custom"}`);
  const framing = session.header.framing ?? {};
  lines.push(`Joints are unmirrored image pixels (${session.imageSize.join("×")}, origin top-left). `
    + `Framing needs required joints at ≥${framing.minimumConfidence ?? 0.4} for ${framing.reliableAfter ?? 0.6} s and drops `
    + `after ${framing.unreliableAfter ?? 0.3} s missing; joints under ${session.header.confidenceFloor ?? 0.3} are dropped before analysis.`);

  const inWindow = (t) => t >= from && t <= to;
  const windowNotes = notes.filter((note) => inWindow(note.t) || (note.end != null && note.t <= to && note.end >= from));
  const windowMarkers = session.markers.filter((marker) => inWindow(marker.heardAt ?? marker.t));
  if (windowNotes.length || windowMarkers.length) {
    lines.push("", "## Notes");
    for (const note of windowNotes) {
      const span = note.end != null ? `${clock(note.t)}–${clock(note.end)}` : clock(note.t);
      lines.push(`- ${span} (${note.author ?? "you"}): ${note.text}`);
    }
    for (const marker of windowMarkers) {
      const text = session.deviceNotes.filter((n) => n.markerID === marker.id).at(-1)?.text ?? marker.text;
      lines.push(`- ${clock(marker.heardAt ?? marker.t)} (marker on phone, ${marker.source})${text ? `: ${text}` : ""}`);
    }
  }

  const exerciseIDs = [...new Set(session.exerciseSpans.filter((s) => s.start <= to && s.end >= from).map((s) => s.label))];
  if (exerciseIDs.length) {
    lines.push("", "## Exercise");
    for (const id of exerciseIDs) {
      const exercise = session.exercises[id] ?? {};
      const required = (exercise.required ?? []).map(shortJoint).join(" ") || "none";
      const anyOf = (exercise.anyOfRequired ?? []).map((set) => set.map(shortJoint).join(" "));
      lines.push(`${id} (${exercise.cameraView ?? "?"}): required ${required}${anyOf.length ? `; or one of [${anyOf.join("] [")}]` : ""}`);
      if (options.tuning && exercise.configuration) {
        lines.push("tuning: " + Object.keys(exercise.configuration).sort()
          .map((key) => `${key}=${exercise.configuration[key]}`).join(" "));
      }
    }
  }

  const { state: start, frame: startFrame, exerciseID: startExercise } = session.snapshotAt(from);
  lines.push("", "## State at the window start");
  if (start) {
    const sides = start.sideReps ? ` (L ${start.sideReps.left}, R ${start.sideReps.right})` : "";
    lines.push(`phase ${start.phase} · exercise ${startExercise ?? start.ex ?? "none"} · set ${start.set}${start.side ? ` ${start.side}` : ""}`
      + ` · reps ${start.reps}${sides} · counting ${start.counting ? "on" : "off"}${start.epoch != null ? ` · analyzer epoch ${start.epoch}` : ""}`
      + ` · framing ${startFrame?.fr ? (startFrame.fr.ok ? "reliable" : `lost${startFrame.fr.g ? ` (${startFrame.fr.g})` : ""}`) : "unknown"}`
      + `${start.tilted ? " · phone tilted" : ""}${start.tip ? ` · tip ${start.tip}` : ""}`);
  } else {
    lines.push("Before the first state record.");
  }

  if (options.events) {
    const pipeline = session.pipes.filter((pipe) => inWindow(pipe.t)).map((pipe) => ({
      t: pipe.t, title: `Pipeline: ${pipe.control}`,
      detail: pipe.control === "counting" ? (pipe.counting ? "on" : "off")
        : pipe.control === "exercise" ? `${pipe.exercise ?? "none"}, epoch ${pipe.epoch}`
        : pipe.control === "resetAnalyzer" ? `epoch ${pipe.epoch}` : pipe.control === "sessionPhase" ? pipe.phase : "",
    }));
    const events = session.timeline.filter((item) => inWindow(item.t)).concat(pipeline).sort((a, b) => a.t - b.t);
    lines.push("", `## Events (${events.length})`);
    for (const item of events) lines.push(`${clock(item.t)} ${item.title}${item.detail ? ` — ${item.detail}` : ""}`);
  }

  const frames = sampleFrames(session, from, to, options.rate);
  if (frames.length) {
    // Every exercise in the window brings its focus joints; an exercise column says which one each row belongs to.
    const focus = new Set(exerciseIDs.flatMap((id) => session.exercises[id]?.focus ?? []));
    const joints = options.joints === "all" ? session.jointOrder
      : options.joints === "focus" ? (focus.size ? session.jointOrder.filter((name) => focus.has(name)) : session.focusJoints(from)) : [];
    const multipleExercises = exerciseIDs.length > 1;
    const columns = ["t"];
    if (multipleExercises) columns.push("ex");
    if (options.framing) columns.push("frm", "cnt", "g");
    for (const joint of joints) columns.push(shortJoint(joint));
    const sides = ["left", "right"];
    if (options.readings) for (const side of sides) columns.push(`${side[0].toUpperCase()}.sig`, `${side[0].toUpperCase()}.elb`, `${side[0].toUpperCase()}.zone`);
    if (options.thresholds) for (const side of sides) columns.push(`${side[0].toUpperCase()}.startY`, `${side[0].toUpperCase()}.topY`, `${side[0].toUpperCase()}.lock`);
    if (options.form) columns.push("signals", "form");
    columns.push("rep");
    lines.push("", `## Frames (${frames.length} rows, CSV)`);
    const legend = [];
    if (joints.length) {
      legend.push(`joint cells are "${options.confidence ? "conf " : ""}${options.positions ? "x y" : ""}"`.replace(/ "$/, "\"")
        + (options.low ? `; "lo…" is below the floor` : "") + `; "est" is estimated past the frame edge; "-" not seen`);
    }
    if (options.readings) legend.push("sig is the exercise's main signal, elb the 2D elbow (or knee) angle");
    if (legend.length) lines.push(`Legend: ${legend.join("; ")}.`);
    lines.push(columns.join(","));
    for (const frame of frames) {
      const row = [number(frame.t, 2)];
      if (multipleExercises) row.push(session.exerciseIDAt(frame.t) ?? "");
      if (options.framing) row.push(frame.fr ? (frame.fr.ok ? "ok" : "LOST") : "", frame.cnt ? 1 : 0, frame.fr?.g ?? "");
      for (const joint of joints) row.push(jointCell(session.joint(frame, joint), options));
      if (options.readings) {
        for (const side of sides) {
          const reading = frame.rd?.[side];
          row.push(number(reading?.signal, 3), number(reading?.elbow, 0), reading?.zone ?? "");
        }
      }
      if (options.thresholds) {
        for (const side of sides) {
          const threshold = frame.th?.[side];
          row.push(number(threshold?.start?.[1], 0), number(threshold?.top?.[1], 0),
            threshold ? (threshold.locked ? 1 : 0) : "");
        }
      }
      if (options.form) {
        row.push((frame.sig ?? []).join("|"), Object.entries(frame.fv ?? {}).map(([k, v]) => `${k}=${v}`).join(";"));
      }
      row.push((frame.out ?? []).some((event) => event.rep) ? "REP" : "");
      lines.push(row.map(csv).join(","));
    }
  }
  return lines.join("\n") + "\n";
}

function jointCell(joint, options) {
  if (!joint || joint.kind === "missing") return "-";
  const position = options.positions && joint.x != null ? `${Math.round(joint.x)} ${Math.round(joint.y)}` : "";
  if (joint.kind === "est") return `est${position ? ` ${position}` : ""}`;
  if (joint.kind === "low" && !options.low) return "-";
  const confidence = options.confidence ? number(joint.c, 2).replace(/^0\./, ".") : "";
  const prefix = joint.kind === "low" ? "lo" : "";
  return [prefix + confidence, position].filter(Boolean).join(" ") || (joint.kind === "low" ? "lo" : "seen");
}

function csv(value) {
  const text = String(value ?? "");
  return /[",\n]/.test(text) ? `"${text.replace(/"/g, "\"\"")}"` : text;
}

/** Notes sidecar (`<id>.notes.json`) helpers, shared by the server and tests. */
export const NOTES_SCHEMA = "fmp.session-notes/1";

export function emptyNotes(sessionId) {
  return { schema: NOTES_SCHEMA, sessionId, notes: [] };
}

/** Adds or replaces a note by id; a note with `deleted: true` is removed. Returns a new notes document. */
export function applyNote(document, note, now = new Date().toISOString()) {
  const notes = document.notes.filter((existing) => existing.id !== note.id);
  if (!note.deleted) {
    const previous = document.notes.find((existing) => existing.id === note.id);
    notes.push({
      id: note.id,
      t: Number(note.t),
      end: note.end == null ? null : Number(note.end),
      text: String(note.text ?? ""),
      author: note.author === "claude" ? "claude" : "you",
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    });
  }
  notes.sort((a, b) => a.t - b.t);
  return { ...document, notes };
}
