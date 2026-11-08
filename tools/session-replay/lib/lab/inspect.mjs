import { isSafeRunID } from "./runner.mjs";
import { createLabStore } from "./store.mjs";

const DEFAULT_LINE_LIMIT = 58; // inspectRun adds one run-summary line.
const DEFAULT_CHAR_LIMIT = 11_800;

export function parseWindow(value) {
  if (value === undefined) return null;
  const match = /^(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)$/.exec(value);
  if (!match) throw new Error("Window must be START-END using nonnegative seconds.");
  const from = Number(match[1]);
  const to = Number(match[2]);
  if (!Number.isFinite(from) || !Number.isFinite(to) || from > to) throw new Error("Window start must not exceed window end.");
  return { from, to };
}

export function filterRecords(records, window) {
  if (!window) return records;
  return records.filter((record) => Number.isFinite(record?.t) && record.t >= window.from && record.t <= window.to);
}

export function renderInspection({ scenario, result, records, window = null, full = false }) {
  const lines = [
    `${scenario.id} · ${result.outcome} · revision ${result.revision}`,
    `Evaluation: ${evaluationStatus(result)}`,
    `Expected (${Array.isArray(scenario.assertions) ? scenario.assertions.length : 0} assertions):`,
  ];
  const assertions = Array.isArray(scenario.assertions) ? scenario.assertions : [];
  if (assertions.length === 0) lines.push("  (no assertions)");
  else {
    const assertionResults = Array.isArray(result.assertionResults) ? result.assertionResults : [];
    const assertionLimit = full ? assertions.length : 8;
    for (let index = 0; index < Math.min(assertions.length, assertionLimit); index += 1) {
      const outcome = assertionResults.find((item) => item.assertionIndex === index);
      const detail = outcome?.detail ?? JSON.stringify(assertions[index]);
      lines.push(`  ${index + 1}. ${outcome ? `${outcome.passed ? "PASS" : "FAIL"} · ` : "NOT EVALUATED · "}${detail}`);
    }
    if (assertions.length > assertionLimit) lines.push(`  … ${assertions.length - assertionLimit} assertions omitted from expected detail`);
  }

  const invalidReasons = Array.isArray(result.invalidReasons) ? result.invalidReasons : [];
  lines.push(`Invalid reasons (${invalidReasons.length}):`);
  if (!invalidReasons.length) lines.push("  (none)");
  else {
    const reasonLimit = full ? invalidReasons.length : 4;
    invalidReasons.slice(0, reasonLimit).forEach((reason) => lines.push(`  ${String(reason)}`));
    if (invalidReasons.length > reasonLimit) lines.push(`  … ${invalidReasons.length - reasonLimit} reasons omitted`);
  }

  const observed = result.observed ?? {};
  lines.push("Observed:", `  reps=${observed.reps ?? "unknown"}; rejections=${observed.rejections?.length ?? 0}; signals=${observed.signals?.length ?? 0}; framingChanges=${observed.framingChanges?.length ?? 0}; cues=${observed.cues?.length ?? 0}`);
  for (const [key, label] of [["rejections", "rejection"], ["signals", "signal"], ["framingChanges", "framing"], ["cues", "cue"]]) {
    const values = Array.isArray(observed[key]) ? observed[key] : [];
    const valueLimit = full ? values.length : 3;
    values.slice(0, valueLimit).forEach((value) => lines.push(`  ${label}: ${String(value)}`));
    if (values.length > valueLimit) lines.push(`  … ${values.length - valueLimit} more ${label} values`);
  }

  const selected = filterRecords(records, window);
  lines.push(`Events${window ? ` in ${window.from}–${window.to}s` : ""} (${selected.length} records):`);
  const formatted = compactRecords(selected, full).filter(Boolean);
  lines.push(...(formatted.length ? formatted : ["  (none)"]));
  if (full) return lines.map(escapeNewlines).join("\n");
  return boundOutput(lines);
}

function escapeNewlines(line) {
  return String(line).replace(/\r\n|[\r\n\u2028\u2029]/g, "\\n");
}

function evaluationStatus(result) {
  if (result.outcome === "invalid") return "invalid (generation stopped before evaluation)";
  const assertions = Array.isArray(result.assertionResults) ? result.assertionResults : [];
  const failed = assertions.filter((assertion) => !assertion.passed).length;
  const inconclusive = assertions.filter((assertion) => /^Inconclusive:/.test(assertion.detail ?? "")).length;
  return `${result.outcome}; ${assertions.length - failed - inconclusive} passed, ${failed - inconclusive} failed, ${inconclusive} inconclusive`;
}

function compactRecords(records, full) {
  const frameRepTimes = new Set();
  for (const record of records) {
    if (record?.k !== "f") continue;
    for (const item of Array.isArray(record.out) ? record.out : []) {
      if (item?.rep && Number.isFinite(item.rep.ts)) frameRepTimes.add(item.rep.ts.toFixed(3));
    }
  }
  const lines = [];
  let previousFraming;
  let previousCounting;
  let previousSignals = new Set();
  for (const record of records) {
    if (full) {
      lines.push(`  ${JSON.stringify(record)}`);
      continue;
    }
    if (record?.k === "f") {
      const t = recordTime(record);
      for (const item of Array.isArray(record.out) ? record.out : []) {
        const rep = item?.rep;
        if (!rep || typeof rep !== "object") continue;
        const sides = Array.isArray(rep.sides) && rep.sides.length ? ` · ${rep.sides.join("+")}` : "";
        lines.push(`  ${t} rep completed${sides}`);
      }
      for (const rejection of Array.isArray(record.rej) ? record.rej : []) {
        lines.push(`  ${t} rejection ${rejection?.reason ?? "unknown"}`);
      }
      const activeSignals = new Set(Array.isArray(record.sig) ? record.sig.filter((value) => typeof value === "string") : []);
      const addedSignals = [...activeSignals].filter((signal) => !previousSignals.has(signal));
      for (const signal of addedSignals) lines.push(`  ${t} signal ${signal}`);
      previousSignals = activeSignals;
      if (record.fr && typeof record.fr.ok === "boolean") {
        const framing = record.fr.ok ? "reliable" : (record.fr.g ?? "unreliable");
        if (framing !== previousFraming) lines.push(`  ${t} framing ${framing}`);
        previousFraming = framing;
      }
      if (typeof record.cnt === "boolean" && record.cnt !== previousCounting) {
        lines.push(`  ${t} counting ${record.cnt}`);
        previousCounting = record.cnt;
      }
      continue;
    }
    const compact = compactRecord(record, frameRepTimes);
    if (compact) lines.push(compact);
  }
  return lines;
}

function compactRecord(record, frameRepTimes = new Set()) {
  const t = recordTime(record);
  if (record?.k === "e") {
    if (record.type === "rep" && Number.isFinite(record.ts) && frameRepTimes.has(record.ts.toFixed(3))) return "";
    return `  ${t} ${record.type ?? "event"}${record.text ? `: ${record.text}` : ""}`;
  }
  if (record?.k === "state") return `  ${t} state ${record.phase ?? "?"} reps=${record.reps ?? "?"} counting=${record.counting ?? "?"}`;
  if (record?.k === "pipe") return `  ${t} control ${record.control ?? "?"}`;
  return "";
}

function recordTime(record) {
  return Number.isFinite(record?.t) ? `${record.t.toFixed(2)}s` : "?s";
}

function boundOutput(lines) {
  const maxLines = DEFAULT_LINE_LIMIT;
  const maxChars = DEFAULT_CHAR_LIMIT;
  const maxLineChars = 240;
  const renderedLines = lines.map(escapeNewlines);
  const output = [];
  let characterCount = 0;
  let omitted = 0;
  let stoppedAt = renderedLines.length;
  for (let index = 0; index < renderedLines.length; index += 1) {
    let line = renderedLines[index];
    if (line.length > maxLineChars) line = `${line.slice(0, maxLineChars - 18)}… [line truncated]`;
    const cost = line.length + (output.length ? 1 : 0);
    if (output.length >= maxLines - 1 || characterCount + cost > maxChars - 80) {
      omitted = renderedLines.length - index;
      stoppedAt = index;
      break;
    }
    output.push(line);
    characterCount += cost;
  }
  if (omitted > 0) {
    let marker = `… ${omitted} more lines omitted; pass --full to expand`;
    if (stoppedAt < renderedLines.length) marker += ` (character budget ${maxChars})`;
    output.push(marker);
  }
  return output.join("\n");
}

export async function inspectRun({ root, runID, scenarioID, window = null, full = false }) {
  if (!isSafeRunID(runID)) throw new Error("Run id must be YYYYMMDD-HHMMSS-<safe suffix>; paths and traversal are rejected.");
  const store = createLabStore(root);
  const { plan, results, summary } = await store.readRun(runID);
  const selectedID = scenarioID ?? results.find((result) => result.outcome !== "passed")?.scenarioID ?? plan.scenarios[0]?.id;
  if (!selectedID) throw new Error("Run has no scenarios to inspect.");
  if (!/^[a-z0-9_-]{1,64}$/.test(selectedID)) throw new Error("Scenario id contains unsafe characters.");
  const scenario = plan.scenarios.find((item) => item.id === selectedID);
  const result = results.find((item) => item.scenarioID === selectedID);
  if (!scenario || !result) throw new Error(`Scenario '${selectedID}' is not in run ${runID}.`);
  const records = await store.readScenarioArtifact(runID, selectedID, "recording");
  const header = `Run ${runID} · ${summary.outcomes?.passed ?? 0}/${results.length} passed`;
  return `${header}\n${renderInspection({ scenario, result, records, window, full })}`;
}
