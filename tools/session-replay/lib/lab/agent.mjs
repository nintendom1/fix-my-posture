import { validatePlan } from "./plan.mjs";
import { chooseKeyframe } from "./keyframe.mjs";
import { isSafeRunID } from "./runner.mjs";

export const MCP_MAX_PLAN_BYTES = 1024 * 1024;
export const MCP_FULL_TRACE_BYTE_CAP = 256 * 1024;
export const MCP_INSPECT_LINE_CAP = 60;
export const MCP_PLAN_VALIDATION_BYTE_CAP = 8 * 1024;
export const MCP_PLAN_VALIDATION_ISSUE_LIMIT = 20;
export const MCP_INTENT_MAX_LENGTH = 1000;
export const MCP_FOLLOW_UP_REASON_MAX_LENGTH = 500;

/** Mark an agent-authored plan, retain one explicit intention per scenario, and attach follow-up lineage. */
export function prepareAgentPlan(input, { parentRunID, followUpReason } = {}) {
  const encoded = JSON.stringify(input);
  if (typeof encoded !== "string") throw new Error("Plan must be JSON-serializable.");
  if (Buffer.byteLength(encoded, "utf8") > MCP_MAX_PLAN_BYTES) {
    throw new Error(`Plan exceeds the MCP limit of ${MCP_MAX_PLAN_BYTES} bytes.`);
  }
  const plan = JSON.parse(encoded);
  if (!plan || typeof plan !== "object" || Array.isArray(plan)) throw new Error("Plan must be a JSON object.");
  const hasParent = parentRunID !== undefined;
  const hasReason = followUpReason !== undefined;
  if (hasParent !== hasReason) throw new Error("parentRunID and followUpReason must be supplied together.");
  plan.author = "agent";
  if (Array.isArray(plan.scenarios)) {
    for (const scenario of plan.scenarios) {
      if (!scenario || typeof scenario !== "object" || Array.isArray(scenario)) continue;
      scenario.author = "agent";
      const intent = typeof scenario.intent === "string" && scenario.intent.trim()
        ? scenario.intent.trim() : scenario.purpose;
      if (typeof intent !== "string" || intent.trim().length === 0) {
        throw new Error(`Scenario '${scenario.id ?? "?"}' needs a nonempty intent or purpose.`);
      }
      if (intent.length > MCP_INTENT_MAX_LENGTH) {
        throw new Error(`Scenario '${scenario.id ?? "?"}' intent exceeds ${MCP_INTENT_MAX_LENGTH} characters.`);
      }
      scenario.intent = intent;
    }
  }
  if (hasParent) {
    if (typeof parentRunID !== "string" || !/^\d{8}-\d{6}-[a-zA-Z0-9]{4,12}$/.test(parentRunID)) {
      throw new Error("parentRunID must be a safe Movement Lab run id.");
    }
    if (typeof followUpReason !== "string" || !followUpReason.trim()) throw new Error("followUpReason must be a nonempty note.");
    if (followUpReason.length > MCP_FOLLOW_UP_REASON_MAX_LENGTH) {
      throw new Error(`followUpReason exceeds ${MCP_FOLLOW_UP_REASON_MAX_LENGTH} characters.`);
    }
    const reason = followUpReason.trim();
    if (typeof plan.purpose !== "string" || !plan.purpose.trim()) throw new Error("Plan needs a nonempty purpose before it can be marked as a follow-up.");
    plan.parentRunID = parentRunID;
    plan.followUpReason = reason;
    plan.purpose = `${plan.purpose.trim()} · Follow-up of ${parentRunID}: ${reason}`;
  } else {
    delete plan.parentRunID;
    delete plan.followUpReason;
  }
  if (Buffer.byteLength(JSON.stringify(plan), "utf8") > MCP_MAX_PLAN_BYTES) {
    throw new Error(`Prepared plan exceeds the MCP limit of ${MCP_MAX_PLAN_BYTES} bytes.`);
  }
  const errors = validatePlan(plan);
  if (errors.length) throw new Error(formatPlanValidationErrors(errors));
  return plan;
}

/** Keep invalid-plan feedback useful without allowing a malformed batch to flood MCP output. */
export function formatPlanValidationErrors(errors, {
  byteCap = MCP_PLAN_VALIDATION_BYTE_CAP,
  issueLimit = MCP_PLAN_VALIDATION_ISSUE_LIMIT,
} = {}) {
  const issues = Array.isArray(errors) ? errors : [];
  const lines = [`Invalid Movement Lab plan: ${issues.length} validation issues.`];
  let shown = 0;
  for (const issue of issues.slice(0, issueLimit)) {
    const next = [...lines, `- ${String(issue)}`];
    const omitted = issues.length - shown - 1;
    if (omitted > 0) next.push(`… ${omitted} additional issues omitted.`);
    if (Buffer.byteLength(next.join("\n"), "utf8") > byteCap) break;
    lines.push(`- ${String(issue)}`);
    shown += 1;
  }
  const omitted = issues.length - shown;
  if (omitted > 0) lines.push(`… ${omitted} additional issues omitted.`);
  return lines.join("\n");
}

/** Compact summary shape shared with the CLI runner's summary text. */
export function formatAgentRun(result) {
  const lines = String(result.text).split("\n");
  const last = lines.pop() ?? "";
  lines.push(`${last} · run ${result.runID}`);
  return lines.join("\n");
}

export function formatAgentManifest(manifest, { categories, mutationBounds }) {
  const presets = Array.isArray(manifest?.presets) ? manifest.presets : [];
  const validPresets = presets.filter((entry) => typeof entry?.id === "string" && /^[a-z0-9_-]{1,64}$/.test(entry.id));
  const exercises = [...new Set(validPresets.flatMap((entry) => Array.isArray(entry.plan?.scenarios)
    ? entry.plan.scenarios.map((scenario) => scenario?.exercise).filter((id) => typeof id === "string") : []))].sort();
  return JSON.stringify({
    exercises,
    categories,
    mutationKinds: mutationBounds,
    presetIDs: validPresets.map((entry) => entry.id),
  });
}

export function labOpenCommand(runID, scenarioID, timestamp) {
  return { command: "lab-open", runID, ...(scenarioID ? { scenarioID } : {}), ...(Number.isFinite(timestamp) ? { timestamp } : {}) };
}

export async function resolveLabOpenTarget(store, runID, scenarioID) {
  if (!isSafeRunID(runID)) throw new Error("Invalid Movement Lab run id.");
  const run = await store.readRun(runID);
  if (!scenarioID) return { run, timestamp: undefined };
  const scenario = run.plan.scenarios.find((item) => item.id === scenarioID);
  if (!scenario) throw new Error(`Scenario '${scenarioID}' is not in run ${runID}.`);
  const recording = await store.readScenarioArtifact(runID, scenarioID, "recording");
  let reference = [];
  try { reference = await store.readScenarioArtifact(runID, scenarioID, "reference"); }
  catch (error) { if (error?.status !== 404) throw error; }
  const timestamp = chooseKeyframe(scenario, recording, reference).timestamp;
  if (!Number.isFinite(timestamp)) throw new Error(`Scenario '${scenarioID}' has no stored keyframe.`);
  return { run, scenario, timestamp };
}

export async function openLabDashboard({ store, runID, scenarioID, baseURL, ensureViewer, openURL, sendCommand }) {
  const target = await resolveLabOpenTarget(store, runID, scenarioID);
  await ensureViewer();
  const params = new URLSearchParams({ labRun: runID });
  if (scenarioID) params.set("labScenario", scenarioID);
  if (Number.isFinite(target.timestamp)) params.set("labTime", String(target.timestamp));
  const url = `${baseURL}?${params}`;
  await openURL(url);
  const command = labOpenCommand(runID, scenarioID, target.timestamp);
  const response = await sendCommand(command);
  if (response === undefined || response === null) throw new Error("The local viewer server did not accept the run-selection command.");
  return { ...target, command, url, delivered: response.delivered ?? 0 };
}

export function assertBoundedInspection(text, { full = false, byteCap = MCP_FULL_TRACE_BYTE_CAP } = {}) {
  if (full) {
    const bytes = Buffer.byteLength(text, "utf8");
    if (bytes > byteCap) throw new Error(`Full trace is ${bytes} bytes; the MCP cap is ${byteCap}. Request a bounded window.`);
    return text;
  }
  const lines = text.split("\n").length;
  if (lines > MCP_INSPECT_LINE_CAP) throw new Error(`Bounded inspection has ${lines} lines; the MCP limit is ${MCP_INSPECT_LINE_CAP}. Request a smaller window.`);
  return text;
}
