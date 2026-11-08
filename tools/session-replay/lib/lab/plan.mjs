import { readFileSync } from "node:fs";

const ID = /^[a-z0-9_-]{1,64}$/;
const UINT64_MAX = 18446744073709551615n;
const CATEGORIES = new Set(["canonical", "depth_rom", "alignment", "timing", "tracking", "session_framing"]);
export const MINIMUM_COMPOSITE_DEPTH_SCALE = 1 / 16;
export const MAXIMUM_COMPOSITE_DEPTH_SCALE = 16;

export function landmarkNamesFromSwiftSource(source) {
  const body = /(?:public\s+)?enum\s+LandmarkType\b[^\{]*\{([\s\S]*?)^\}/m.exec(source)?.[1];
  if (!body) throw new Error("LandmarkType.swift does not contain a parseable LandmarkType enum.");
  const names = [...body.matchAll(/^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)\b/gm)].map((match) => match[1]);
  if (!names.length) throw new Error("LandmarkType.swift has no case declarations.");
  return names;
}

const LANDMARK_SOURCE_URL = new URL("../../../../PostureAnalysisApp/Models/LandmarkType.swift", import.meta.url);
export const SWIFT_LANDMARK_NAMES = Object.freeze(landmarkNamesFromSwiftSource(readFileSync(LANDMARK_SOURCE_URL, "utf8")));
const JOINTS = new Set(SWIFT_LANDMARK_NAMES);

function issue(errors, path, message) { errors.push(`${path}: ${message}`); }
function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function finiteNumber(value) { return typeof value === "number" && Number.isFinite(value); }
function number(errors, value, path, lower, upper) {
  if (!finiteNumber(value)) issue(errors, path, "must be a finite number");
  else if (lower !== undefined && (value < lower || value > upper)) issue(errors, path, `must be between ${lower} and ${upper}`);
}
function text(errors, value, path, nonempty = true) {
  if (typeof value !== "string" || (nonempty && value.trim().length === 0)) issue(errors, path, nonempty ? "must be a nonempty string" : "must be a string");
}
function bool(errors, value, path) { if (typeof value !== "boolean") issue(errors, path, "must be a boolean"); }
function id(errors, value, path) {
  if (typeof value !== "string" || !ID.test(value)) issue(errors, path, "must use 1–64 lowercase ASCII letters, digits, '_' or '-'");
}
function repsSelector(errors, selected, path, reps) {
  if (selected === undefined) return;
  if (!Array.isArray(selected)) { issue(errors, path, "must be an array of one-based repetition numbers"); return; }
  if (!selected.length) issue(errors, path, "must not be empty when supplied");
  const seen = new Set();
  selected.forEach((rep, index) => {
    if (!Number.isInteger(rep) || rep < 1 || rep > reps) issue(errors, `${path}[${index}]`, `must be within 1...${reps}`);
    if (seen.has(rep)) issue(errors, `${path}[${index}]`, "must not duplicate a repetition number");
    seen.add(rep);
  });
}
function joints(errors, affected, path) {
  if (!Array.isArray(affected) || !affected.length) { issue(errors, path, "must contain at least one joint"); return; }
  const seen = new Set();
  affected.forEach((joint, index) => {
    if (typeof joint !== "string" || !JOINTS.has(joint)) issue(errors, `${path}[${index}]`, "is not a LandmarkType name");
    if (seen.has(joint)) issue(errors, `${path}[${index}]`, "must not duplicate a joint");
    seen.add(joint);
  });
}
function interval(errors, from, to, path, duration) {
  number(errors, from, `${path}.from`, 0, 120);
  number(errors, to, `${path}.to`, 0, 120);
  if (finiteNumber(from) && finiteNumber(to)) {
    if (from > to) issue(errors, `${path}.to`, "must be at or after from");
    else if (to - from > 10) issue(errors, `${path}.to`, "interval duration must not exceed 10 seconds");
    if (finiteNumber(duration) && to > duration) issue(errors, `${path}.to`, "must be within the output sequence");
  }
}
function mutation(errors, value, path, reps, sequenceDuration) {
  if (!object(value)) { issue(errors, path, "must be an object"); return; }
  const kind = value.kind;
  const allowed = new Set(["jointOffset", "depthScale", "asymmetry", "tempo", "pause", "frameGap", "dropout", "confidence", "framing"]);
  if (typeof kind !== "string" || !allowed.has(kind)) { issue(errors, `${path}.kind`, "is not a supported mutation kind"); return; }
  switch (kind) {
    case "jointOffset":
      joints(errors, value.joints, `${path}.joints`);
      number(errors, value.dx, `${path}.dx`, -0.5, 0.5);
      number(errors, value.dy, `${path}.dy`, -0.5, 0.5);
      number(errors, value.peak, `${path}.peak`, 0, sequenceDuration);
      number(errors, value.rise, `${path}.rise`, 0, 10);
      number(errors, value.fall, `${path}.fall`, 0, 10);
      number(errors, value.strength, `${path}.strength`, 0, 1);
      if (finiteNumber(value.rise) && finiteNumber(value.peak) && value.peak - value.rise < 0) issue(errors, `${path}.rise`, "influence start must be inside the output sequence");
      if (finiteNumber(value.peak) && finiteNumber(value.fall) && value.peak + value.fall > sequenceDuration) issue(errors, `${path}.fall`, "influence end must be inside the output sequence");
      break;
    case "depthScale":
    case "tempo":
      number(errors, value.scale, `${path}.scale`, 0.3, 2);
      repsSelector(errors, value.reps, `${path}.reps`, reps);
      break;
    case "asymmetry":
      if (value.side !== "left" && value.side !== "right") issue(errors, `${path}.side`, "must be left or right");
      number(errors, value.amount, `${path}.amount`, -0.5, 0.5);
      break;
    case "pause":
      number(errors, value.at, `${path}.at`, 0, 120);
      number(errors, value.duration, `${path}.duration`, 0, 10);
      break;
    case "frameGap":
      number(errors, value.at, `${path}.at`, 0, sequenceDuration);
      number(errors, value.duration, `${path}.duration`, 0, 10);
      if (finiteNumber(value.at) && finiteNumber(value.duration) && value.at + value.duration > sequenceDuration) issue(errors, `${path}.duration`, "frame-gap end must be at or before the output sequence end");
      break;
    case "dropout":
      joints(errors, value.joints, `${path}.joints`);
      interval(errors, value.from, value.to, path, sequenceDuration);
      break;
    case "confidence":
      joints(errors, value.joints, `${path}.joints`);
      interval(errors, value.from, value.to, path, sequenceDuration);
      number(errors, value.value, `${path}.value`, 0, 1);
      break;
    case "framing":
      number(errors, value.scale, `${path}.scale`, 0.3, 2);
      number(errors, value.offsetX, `${path}.offsetX`, -0.5, 0.5);
      number(errors, value.offsetY, `${path}.offsetY`, -0.5, 0.5);
      break;
  }
}

function compositeDepthScale(errors, mutations, path, reps) {
  if (!Number.isInteger(reps) || reps < 1 || reps > 120) return;
  for (let rep = 1; rep <= reps; rep += 1) {
    let scale = 1;
    for (let index = 0; index < mutations.length; index += 1) {
      const item = mutations[index];
      if (!object(item) || item.kind !== "depthScale" || !finiteNumber(item.scale)) continue;
      if (item.reps !== undefined && (!Array.isArray(item.reps) || !item.reps.includes(rep))) continue;
      scale *= item.scale;
      if (!Number.isFinite(scale) || scale < MINIMUM_COMPOSITE_DEPTH_SCALE || scale > MAXIMUM_COMPOSITE_DEPTH_SCALE) {
        issue(errors, `${path}.mutations[${index}].scale`, `composite depth scale for repetition ${rep} must stay between ${MINIMUM_COMPOSITE_DEPTH_SCALE} and ${MAXIMUM_COMPOSITE_DEPTH_SCALE}`);
        break;
      }
    }
  }
}
function assertion(errors, value, path) {
  if (!object(value)) { issue(errors, path, "must be an object"); return; }
  switch (value.kind) {
    case "repCount": {
      const present = ["equals", "min", "max"].filter((field) => value[field] !== undefined);
      if (!present.length) issue(errors, path, "repCount needs equals or at least one of min/max");
      if (value.equals !== undefined && (value.min !== undefined || value.max !== undefined)) issue(errors, path, "repCount must use equals or a min/max range, not both");
      for (const field of present) {
        const numberValue = value[field];
        if (!Number.isInteger(numberValue) || numberValue < 0) issue(errors, `${path}.${field}`, "must be a nonnegative integer");
      }
      if (Number.isInteger(value.min) && Number.isInteger(value.max) && value.min > value.max) issue(errors, `${path}.min`, "must not exceed max");
      break;
    }
    case "rejection":
      text(errors, value.reasonContains, `${path}.reasonContains`);
      if (!Number.isInteger(value.countMin) || value.countMin < 0) issue(errors, `${path}.countMin`, "must be a nonnegative integer");
      break;
    case "formSignal":
      text(errors, value.id, `${path}.id`); bool(errors, value.present, `${path}.present`); break;
    case "framing":
      text(errors, value.state, `${path}.state`); bool(errors, value.reached, `${path}.reached`); break;
    case "spokenCue":
      text(errors, value.textContains, `${path}.textContains`); bool(errors, value.present, `${path}.present`); break;
    default: issue(errors, `${path}.kind`, "is not a supported assertion kind");
  }
}

export function validatePlan(plan) {
  const errors = [];
  if (!object(plan)) return ["$: must be a JSON object"];
  if (plan.schemaVersion !== 1) issue(errors, "schemaVersion", "must be 1");
  id(errors, plan.id, "id");
  text(errors, plan.title, "title");
  text(errors, plan.purpose, "purpose");
  if (plan.author !== "agent" && plan.author !== "developer") issue(errors, "author", "must be agent or developer");
  text(errors, plan.createdAt, "createdAt");
  if (typeof plan.createdAt === "string" && (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$/.test(plan.createdAt) || !Number.isFinite(Date.parse(plan.createdAt)))) {
    issue(errors, "createdAt", "must be an ISO 8601 date-time with a time-zone offset");
  }
  if (!Array.isArray(plan.scenarios)) { issue(errors, "scenarios", "must be an array"); return errors; }
  if (plan.scenarios.length > 200) issue(errors, "scenarios", "must contain no more than 200 scenarios");
  const ids = new Set();
  plan.scenarios.forEach((scenario, index) => {
    const path = `scenarios[${index}]`;
    if (!object(scenario)) { issue(errors, path, "must be an object"); return; }
    id(errors, scenario.id, `${path}.id`);
    if (ids.has(scenario.id)) issue(errors, `${path}.id`, `duplicates scenario id ${scenario.id}`);
    ids.add(scenario.id);
    text(errors, scenario.exercise, `${path}.exercise`);
    if (typeof scenario.category !== "string" || !CATEGORIES.has(scenario.category)) issue(errors, `${path}.category`, "is not a supported category");
    text(errors, scenario.purpose, `${path}.purpose`);
    text(errors, scenario.canonicalRevision, `${path}.canonicalRevision`);
    if (typeof scenario.seed !== "string" || !/^\d+$/.test(scenario.seed) || BigInt(scenario.seed || "0") > UINT64_MAX) {
      issue(errors, `${path}.seed`, "must be a base-10 UInt64 string");
    }
    if (!Number.isInteger(scenario.reps) || scenario.reps < 1 || scenario.reps > 120) issue(errors, `${path}.reps`, "must be an integer from 1 through 120");
    if (scenario.mode !== "constrained" && scenario.mode !== "raw") issue(errors, `${path}.mode`, "must be constrained or raw");
    if (!Number.isInteger(scenario.revision) || scenario.revision < 1) issue(errors, `${path}.revision`, "must be a positive integer");
    if (scenario.parentRevision !== undefined && (!Number.isInteger(scenario.parentRevision) || scenario.parentRevision < 1 || scenario.parentRevision >= scenario.revision)) issue(errors, `${path}.parentRevision`, "must be positive and earlier than revision");
    if (!Array.isArray(scenario.mutations)) issue(errors, `${path}.mutations`, "must be an array");
    if (!Array.isArray(scenario.assertions)) issue(errors, `${path}.assertions`, "must be an array");
    const mutations = Array.isArray(scenario.mutations) ? scenario.mutations : [];
    // Bounds all output-clock inputs conservatively before Swift computes the guide-specific timeline.
    const duration = 120;
    mutations.forEach((item, mutationIndex) => mutation(errors, item, `${path}.mutations[${mutationIndex}]`, scenario.reps, duration));
    compositeDepthScale(errors, mutations, path, scenario.reps);
    (Array.isArray(scenario.assertions) ? scenario.assertions : []).forEach((item, assertionIndex) => assertion(errors, item, `${path}.assertions[${assertionIndex}]`));
  });
  return errors;
}

export function validatePlanText(text) {
  let plan;
  try { plan = JSON.parse(text); } catch (error) { return { plan: null, errors: [`$: invalid JSON (${error.message})`] }; }
  return { plan, errors: validatePlan(plan) };
}
