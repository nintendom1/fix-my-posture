// HTML and SVG builders for the replay viewer. Every string from a recording or a note goes through `esc`, and every
// number through `num`, because recordings can come from anywhere (a shared file) and the viewer has write access
// to the local server. Pure functions: tests call them directly with hostile input.
import { BONES, shortJoint, clock } from "../lib/session.mjs";

export const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" })[c]);
/** A finite number, or `fallback`. */
export const num = (value, fallback = 0) => {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
};
const fixed = (value, places) => num(value).toFixed(places);
const confidenceText = (value) => fixed(value, 2).replace(/^0\./, ".");

export const PHASE_COLORS = [
  [/^exercising/, "#3ddc97"], [/^ready/, "#9b7bff"], [/^resting/, "#5aa9ff"], [/^paused/, "#ffb547"],
  [/^changingExercise/, "#c9b3ff"], [/^(exerciseComplete|ended)/, "#c9b3ff"], [/.*/, "#8f87a3"],
];
export const KIND_COLORS = { info: "#8f87a3", voice: "#9b7bff", set: "#ece8f4", rep: "#3ddc97", analyzer: "#2b9e6d", cue: "#ffb547", warn: "#ff5d73", marker: "#ffb547", note: "#c9b3ff" };
export const phaseColor = (phase) => PHASE_COLORS.find(([pattern]) => pattern.test(String(phase ?? "")))[1];

export function fmt(t) {
  const value = Math.max(0, num(t));
  const minutes = Math.floor(value / 60);
  return `${minutes}:${(value - minutes * 60).toFixed(2).padStart(5, "0")}`;
}

const at = (session, t) => `${(num(t) / Math.max(num(session.duration), 0.001)) * 100}%`;

export function sessionOptions(sessions) {
  return sessions.map((s) => {
    const when = s.startedAt && !Number.isNaN(Date.parse(s.startedAt))
      ? new Date(s.startedAt).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }) : "";
    const markers = num(s.markerCount);
    const notes = num(s.noteCount);
    const extras = [markers ? `${markers} marker${markers === 1 ? "" : "s"}` : "", notes ? `${notes} note${notes === 1 ? "" : "s"}` : "",
      s.isComplete ? "" : "incomplete"].filter(Boolean).join(", ");
    return `<option value="${esc(s.id)}">${esc(s.title)} · ${esc(when)}${extras ? ` · ${esc(extras)}` : ""}</option>`;
  }).join("");
}

export function ticks(session) {
  const duration = Math.max(num(session.duration), 0.001);
  const step = [1, 2, 5, 10, 15, 30, 60, 120, 300].find((s) => duration / s <= 14) ?? 600;
  let out = "";
  for (let t = 0; t <= duration; t += step) out += `<span style="left:${at(session, t)}">${esc(clock(t, false))}</span>`;
  return out;
}

function segment(session, span, color, label, title) {
  const width = num(span.end) - num(span.start);
  const wide = width / Math.max(num(session.duration), 0.001) > 0.06;
  return `<div class="seg" style="left:${at(session, span.start)};width:${at(session, width)};color:${color};border-color:${color};background:${color}26" title="${esc(title)}">${wide ? esc(label) : ""}</div>`;
}

export function phaseLane(session) {
  return session.phaseSpans.map((span) => segment(session, span, phaseColor(span.label), span.label,
    `${span.label} ${clock(num(span.start))}–${clock(num(span.end))}`)).join("");
}

export function framingLane(session) {
  return session.framingSpans.map((span) => {
    const color = span.ok ? "#3ddc97" : span.wasReliable ? "#ff5d73" : "#6f6884";
    const label = span.ok ? "Reliable" : span.wasReliable ? "Lost" : "Not tracking";
    return segment(session, span, color, label, `${label}${span.guidance ? ` (${span.guidance})` : ""} ${clock(num(span.start))}–${clock(num(span.end))}`);
  }).join("");
}

/** A numbered mark for each rep the coach counted, a small dot for a rep on one side that left the count unchanged,
 * and a red × for an analyzer rep the coach didn't count. */
export function repLane(session) {
  return session.reps.map((rep) => {
    const title = esc(`${clock(num(rep.t))} · sides ${rep.sides.join("+")} · ${rep.outcome === "notCounted" ? `not counted${rep.reason ? `: ${rep.reason}` : ""}` : rep.outcome === "oneSide" ? "one side, count unchanged" : `rep ${rep.count}${rep.outcome === "completedSet" ? ", set complete" : ""}`}`);
    if (rep.outcome === "counted" || rep.outcome === "completedSet") {
      return `<span class="mark" data-t="${num(rep.t)}" style="left:${at(session, rep.t)};background:rgba(61,220,151,.18);color:#3ddc97" title="${title}">${num(rep.count)}</span>`;
    }
    if (rep.outcome === "oneSide") return `<span class="analyzer-dot" data-t="${num(rep.t)}" style="left:${at(session, rep.t)}" title="${title}"></span>`;
    return `<span class="mark" data-t="${num(rep.t)}" style="left:${at(session, rep.t)};background:#ff5d73;color:#fff" title="${title}">×</span>`;
  }).join("");
}

export function issueLane(session) {
  return session.timeline.filter((item) => ["warn", "cue"].includes(item.kind)).map((item) =>
    `<span class="diamond" data-t="${num(item.t)}" style="left:${at(session, item.t)};background:${KIND_COLORS[item.kind]}" title="${esc(`${clock(num(item.t))} ${item.title} ${item.detail}`)}"></span>`).join("");
}

export function noteLane(session, notes) {
  const pins = notes.map((note) => `<span class="pin" data-t="${num(note.t)}" style="left:${at(session, note.t)};background:${note.author === "claude" ? "#7fd8ff" : "#c9b3ff"}" title="${esc(`${clock(num(note.t))} ${note.text}`)}"></span>`);
  const markers = session.markers.map((marker) => {
    const t = num(marker.heardAt ?? marker.t);
    return `<span class="pin" data-t="${t}" style="left:${at(session, t)};background:#ffb547" title="${esc(`Marker ${clock(t)} ${marker.text ?? ""}`)}"></span>`;
  });
  return pins.concat(markers).join("");
}

/** A polyline path in a 0–1000 wide chart; gaps where `y` gives nothing. */
export function chartPath(session, frames, height, y) {
  let d = "";
  let open = false;
  const duration = Math.max(num(session.duration), 0.001);
  for (const frame of frames) {
    const value = y(frame);
    if (value == null || !Number.isFinite(value)) { open = false; continue; }
    d += `${open ? "L" : "M"}${((num(frame.t) / duration) * 1000).toFixed(1)} ${Math.min(height, Math.max(0, value)).toFixed(1)}`;
    open = true;
  }
  return d;
}

const line = (y, color, dash) => `<line x1="0" x2="1000" y1="${fixed(y, 1)}" y2="${fixed(y, 1)}" stroke="${color}" stroke-dasharray="${dash}" vector-effect="non-scaling-stroke"/>`;
const curve = (d, color, extra = "") => `<path d="${d}" fill="none" stroke="${color}" stroke-width="1.5" vector-effect="non-scaling-stroke"${extra}/>`;

export function charts(session, frames, signalRange) {
  const [low, high] = signalRange;
  const span = high - low || 1;
  const signal = (side) => (frame) => { const v = frame.rd?.[side]?.signal; return v == null ? null : 64 - ((num(v) - low) / span) * 64; };
  const angle = (side) => (frame) => { const v = frame.rd?.[side]?.elbow; return v == null ? null : 64 - (num(v) / 180) * 64; };
  const floor = num(session.header.framing?.minimumConfidence, 0.4);
  const confidence = chartPath(session, frames, 40, (frame) => {
    const weakest = session.weakestRequired(frame);
    return weakest ? 40 - num(weakest.value) * 40 : null;
  });
  return {
    signal: line(64 - ((0 - low) / span) * 64, "rgba(255,255,255,.15)", "4 4")
      + curve(chartPath(session, frames, 64, signal("left")), "#7fd8ff") + curve(chartPath(session, frames, 64, signal("right")), "#ff9ec0", ` opacity=".85"`),
    angle: [90, 150].map((a) => line(64 - a / 180 * 64, "rgba(255,255,255,.12)", "4 4")).join("")
      + curve(chartPath(session, frames, 64, angle("left")), "#7fd8ff") + curve(chartPath(session, frames, 64, angle("right")), "#ff9ec0", ` opacity=".85"`),
    confidence: line(40 - floor * 40, "rgba(255,93,115,.6)", "4 4") + line(40 - 0.3 * 40, "rgba(255,93,115,.3)", "2 4")
      + `<path d="${confidence}${confidence ? "L1000 40L0 40Z" : ""}" fill="rgba(201,179,255,.12)" stroke="#c9b3ff" stroke-width="1.5" vector-effect="non-scaling-stroke"/>`,
  };
}

function bones(session, frame, X, unit, focus, color, styled) {
  let out = "";
  for (const [a, b] of BONES) {
    const ja = session.joint(frame, a);
    const jb = session.joint(frame, b);
    if (!ja || !jb || ja.x == null || jb.x == null) continue;
    const isFocus = focus.has(a) && focus.has(b);
    const weak = ja.kind === "low" || jb.kind === "low";
    const estimated = ja.kind === "est" || jb.kind === "est";
    const stroke = !styled ? color : weak ? "#ff5d73" : isFocus ? color : "rgba(236,232,244,.45)";
    const dash = styled && (weak || estimated) ? `${unit * 3} ${unit * 4}` : "none";
    out += `<line x1="${X(ja.x)}" y1="${num(ja.y)}" x2="${X(jb.x)}" y2="${num(jb.y)}" stroke="${stroke}" stroke-width="${unit * (isFocus ? 4 : 2.5)}" stroke-linecap="round" stroke-dasharray="${dash}"/>`;
  }
  return out;
}

/** The stage's SVG content at a frame. `trail` holds earlier frames to draw faintly. */
export function stageSVG(session, frame, { width, height, toggles, glow, trail = [] }) {
  const mirror = toggles.mirror;
  const X = (x) => { const v = num(x); return mirror ? width - v : v; };
  const unit = width / 300;
  const focus = new Set(session.focusJoints(num(frame?.t)));
  const minimum = num(session.header.framing?.minimumConfidence, 0.4);
  let out = `<g opacity=".05">${Array.from({ length: 9 }, (_, i) => `<line x1="${(i + 1) * width / 10}" x2="${(i + 1) * width / 10}" y1="0" y2="${height}" stroke="#fff"/>`).join("")}${Array.from({ length: 13 }, (_, i) => `<line y1="${(i + 1) * height / 14}" y2="${(i + 1) * height / 14}" x1="0" x2="${width}" stroke="#fff"/>`).join("")}</g>`;
  for (const [past, opacity] of trail) out += `<g opacity="${opacity}">${bones(session, past, X, unit, focus, "#c9b3ff", false)}</g>`;
  if (!frame) return out;
  if (toggles.thresholds) {
    for (const side of ["left", "right"]) {
      const lines = frame.th?.[side];
      if (!lines) continue;
      for (const [key, color, label] of [["start", "#7fd8ff", "Start ↓"], ["top", "#3ddc97", "Top ↑"]]) {
        const coordinates = lines[key];
        if (!Array.isArray(coordinates) || coordinates.length < 4) continue;
        const [x1, y1, x2, y2] = coordinates.map((value) => num(value));
        const confirmed = lines.confirmed === key;
        out += `<line x1="${X(x1)}" y1="${y1}" x2="${X(x2)}" y2="${y2}" stroke="${color}" stroke-width="${unit * 2}" stroke-linecap="round" stroke-dasharray="${confirmed ? "none" : `${unit * 6} ${unit * 4}`}" opacity="${confirmed ? 1 : 0.7}"/>`;
        out += `<text x="${X(x2) + (mirror ? -unit * 4 : unit * 4)}" y="${y2 + unit * 3}" fill="${color}" font-size="${unit * 8}" font-family="JetBrains Mono, monospace" text-anchor="${mirror ? "end" : "start"}">${side === "left" ? "L" : "R"} ${label}</text>`;
      }
    }
  }
  out += bones(session, frame, X, unit, focus, glow, true);
  for (const name of session.jointOrder) {
    const joint = session.joint(frame, name);
    if (!joint || joint.x == null) continue;
    const isFocus = focus.has(name);
    const radius = unit * (isFocus ? 4 : /Eye|Ear/.test(name) ? 2.2 : 3);
    const cx = X(joint.x);
    const cy = num(joint.y);
    if (joint.kind === "seen") {
      out += `<circle cx="${cx}" cy="${cy}" r="${radius}" fill="${num(joint.c) < minimum ? "#ffb547" : "#ece8f4"}" stroke="rgba(14,11,22,.8)" stroke-width="${unit * 1.5}"/>`;
    } else {
      const color = joint.kind === "est" ? "#c9b3ff" : "#ff5d73";
      out += `<circle cx="${cx}" cy="${cy}" r="${radius}" fill="#0e0b16" stroke="${color}" stroke-width="${unit * 1.5}" stroke-dasharray="${joint.kind === "est" ? `${unit * 2} ${unit * 2}` : "none"}"/>`;
    }
    if (toggles.labels && !/Eye|Ear/.test(name)) {
      const right = cx >= width / 2;
      const value = joint.kind === "seen" ? ` ${confidenceText(joint.c)}` : joint.kind === "low" ? ` lo${confidenceText(joint.c)}` : " est";
      out += `<text x="${cx + (right ? unit * 6 : -unit * 6)}" y="${cy + unit * 2}" fill="#a49cb8" font-size="${unit * 6.5}" font-family="JetBrains Mono, monospace" text-anchor="${right ? "start" : "end"}">${esc(shortJoint(name))}${value}</text>`;
    }
  }
  if (toggles.angles) {
    for (const side of ["left", "right"]) {
      const reading = frame.rd?.[side];
      const elbow = session.joint(frame, `${side}Elbow`);
      if (!reading || !elbow || elbow.x == null) continue;
      const x = X(elbow.x) + (X(elbow.x) >= width / 2 ? 1 : -1) * unit * 22;
      const y = num(elbow.y);
      const color = side === "left" ? "#7fd8ff" : "#ff9ec0";
      out += `<g><rect x="${x - unit * 15}" y="${y - unit * 6.5}" width="${unit * 30}" height="${unit * 13}" rx="${unit * 6.5}" fill="rgba(14,11,22,.8)" stroke="${color}" stroke-width="${unit}"/>`
        + `<text x="${x}" y="${y + unit * 3}" fill="${color}" font-size="${unit * 8}" font-weight="700" font-family="JetBrains Mono, monospace" text-anchor="middle">${Math.round(num(reading.elbow))}°</text></g>`;
    }
  }
  return out;
}

export function stats(session, t, frame, state) {
  const exerciseID = session.exerciseIDAt(t);
  const reps = state ? `${num(state.reps)}${state.sideReps ? ` (L${num(state.sideReps.left)} R${num(state.sideReps.right)})` : ""}` : "—";
  return [["Exercise", session.exercises[exerciseID]?.name ?? exerciseID ?? "—"], ["Set", state?.set ?? "—"],
    ["Reps", reps], ["Counting", frame?.cnt ? "on" : "off"]]
    .map(([k, v]) => `<div class="stat"><span class="k">${esc(k)}</span><span class="v" title="${esc(v)}">${esc(v)}</span></div>`).join("");
}

export function checks(session, index) {
  const frame = session.frames[index];
  const minimum = num(session.header.framing?.minimumConfidence, 0.4);
  const weakest = session.weakestRequired(frame);
  // The analyzer's gap rule uses capture timestamps (`ts`), not when the coach handled the frame.
  const previous = session.frames[index - 1];
  const gap = previous && frame?.ts != null && previous.ts != null ? num(frame.ts) - num(previous.ts) : null;
  const maximumGap = num(session.exerciseAt(num(frame?.t))?.configuration?.maximumSampleGap, 0.28);
  const pitchLimit = num(session.header.constants?.tiltedPitch, 15);
  const row = (name, ok, value, limit) => {
    const status = ok == null ? "na" : ok ? "pass" : "fail";
    return `<div class="check"><span class="${status}">${ok == null ? "–" : ok ? "✓" : "✗"}</span><span>${esc(name)}</span><span class="v ${status}">${esc(value)}</span><span class="lim">${esc(limit)}</span></div>`;
  };
  return [
    row("Required joints", weakest ? num(weakest.value) >= minimum : null,
      weakest ? `${shortJoint(weakest.name)} ${weakest.kind === "missing" ? "missing" : fixed(weakest.value, 2)}` : "—", `≥ ${minimum.toFixed(2)}`),
    row("Framing reliable", frame?.fr ? frame.fr.ok === true : null, frame?.fr ? (frame.fr.ok ? "yes" : frame.fr.g ?? "no") : "—", ""),
    row("Camera frame gap", gap == null ? null : gap <= maximumGap, gap == null ? "—" : `${gap.toFixed(2)} s`, `≤ ${maximumGap} s`),
    row("Phone pitch", frame?.pitch == null ? null : Math.abs(num(frame.pitch)) <= pitchLimit, frame?.pitch == null ? "—" : `${fixed(frame.pitch, 1)}°`, `≤ ${pitchLimit}°`),
  ].join("");
}

export function readings(frame) {
  const rows = [];
  for (const side of ["left", "right"]) {
    const reading = frame?.rd?.[side];
    const lines = frame?.th?.[side];
    if (!reading && !lines) continue;
    const start = Array.isArray(lines?.start) ? Math.round(num(lines.start[1])) : "–";
    const top = Array.isArray(lines?.top) ? Math.round(num(lines.top[1])) : "–";
    rows.push(`<span class="${side}">${side === "left" ? "L" : "R"}</span>`
      + `<span>${reading ? esc(`${fixed(reading.signal, 3)} · ${Math.round(num(reading.elbow))}° · ${reading.zone ?? ""}`) : "—"}</span>`
      + `<span class="muted">${lines ? esc(`start ${start} · top ${top}${lines.locked ? " · locked" : ""}${lines.confirmed ? ` · at ${lines.confirmed}` : ""}`) : ""}</span>`);
  }
  const form = Object.entries(frame?.fv ?? {}).map(([k, v]) => `${k} ${v}`).join("  ");
  const signals = (Array.isArray(frame?.sig) ? frame.sig : []).join(", ");
  if (!rows.length && !form) return `<span class="muted" style="grid-column: span 3">No analyzer readings at this frame.</span>`;
  return `<span class="head"></span><span class="head">signal · angle · zone</span><span class="head">threshold lines (px)</span>${rows.join("")}`
    + (form ? `<span class="head">form</span><span style="grid-column: span 2">${esc(form)}</span>` : "")
    + (signals ? `<span class="head">signals</span><span style="grid-column: span 2" class="fail">${esc(signals)}</span>` : "");
}

export function confidence(session, frame, t) {
  const focus = new Set(session.focusJoints(t));
  const minimum = num(session.header.framing?.minimumConfidence, 0.4);
  return session.jointOrder.map((name) => {
    const joint = session.joint(frame, name);
    const value = joint?.c == null ? null : num(joint.c);
    const low = joint?.kind === "low" || joint?.kind === "missing" || (value != null && value < minimum);
    const label = joint?.kind === "missing" || !joint ? "--" : joint.kind === "est" ? "est" : joint.kind === "low" ? `lo${confidenceText(value)}` : fixed(value, 2);
    return `<div class="conf-row${low ? " low" : ""}${focus.has(name) ? " focus" : ""}" title="${esc(shortJoint(name))}"><span class="name">${esc(name)}</span><span class="bar"><span style="width:${Math.round((value ?? 0) * 100)}%"></span></span><span class="num">${esc(label)}</span></div>`;
  }).join("");
}

/** Viewer notes and the phone's markers, in time order. */
export function noteItems(session, notes) {
  return notes.map((note) => ({ ...note, device: false }))
    .concat(session.markers.map((marker) => ({
      t: num(marker.heardAt ?? marker.t), device: true, author: `phone, ${marker.source}`,
      text: session.deviceNotes.filter((n) => n.markerID === marker.id).at(-1)?.text ?? marker.text ?? "(no note)",
    })))
    .sort((a, b) => num(a.t) - num(b.t));
}

export function notesList(session, notes) {
  const items = noteItems(session, notes);
  if (!items.length) return `<span class="muted small">No notes yet. Press N at a moment, or shift-drag a range first.</span>`;
  return items.map((note) => {
    const span = note.end != null ? `${clock(num(note.t))}–${clock(num(note.end))}` : clock(num(note.t));
    const kind = note.device ? "device" : note.author === "claude" ? "claude" : "";
    return `<div class="note ${kind}" data-t="${num(note.t)}"><span class="ts">${esc(span)}</span><span class="text">${esc(note.text)}<br><span class="who">${esc(note.author ?? "you")}</span></span>${note.device ? "" : `<button class="mini" data-edit="${esc(note.id)}">Edit</button>`}</div>`;
  }).join("");
}

export function filters(names, current) {
  return names.map((name) => `<button class="${current === name ? "on" : ""}" data-filter="${esc(name)}">${esc(name)}</button>`).join("");
}

export function logRows(items) {
  return items.map((item, index) =>
    `<div class="log-item" data-index="${index}" data-t="${num(item.t)}"><span class="ts">${esc(clock(num(item.t)))}</span><span class="dot" style="background:${KIND_COLORS[item.kind] ?? "#8f87a3"}"></span><div><div class="title">${esc(item.title)}</div>${item.detail ? `<div class="detail">${esc(item.detail)}</div>` : ""}</div></div>`).join("");
}
