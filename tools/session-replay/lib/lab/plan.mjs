import { readFileSync } from "node:fs";

const ID = /^[a-z0-9_-]{1,64}$/;
const UINT64_MAX = 18446744073709551615n;
export const SCENARIO_CATEGORIES = Object.freeze(["canonical", "depth_rom", "alignment", "timing", "tracking", "session_framing"]);
const CATEGORIES = new Set(SCENARIO_CATEGORIES);
export const MINIMUM_COMPOSITE_DEPTH_SCALE = 1 / 16;
export const MAXIMUM_COMPOSITE_DEPTH_SCALE = 16;
const bounds = (lower, upper) => Object.freeze([lower, upper]);
export const MUTATION_BOUNDS = Object.freeze({
  jointOffset: Object.freeze({ joints: "LandmarkType[]", dx: bounds(-0.5, 0.5), dy: bounds(-0.5, 0.5), peak: bounds(0, 120), rise: bounds(0, 10), fall: bounds(0, 10), strength: bounds(0, 1) }),
  depthScale: Object.freeze({ scale: bounds(0.3, 2), reps: "optional one-based repetition numbers" }),
  asymmetry: Object.freeze({ side: Object.freeze(["left", "right"]), amount: bounds(-0.5, 0.5) }),
  tempo: Object.freeze({ scale: bounds(0.3, 2), reps: "optional one-based repetition numbers" }),
  pause: Object.freeze({ at: bounds(0, 120), duration: bounds(0, 10) }),
  frameGap: Object.freeze({ at: bounds(0, 120), duration: bounds(0, 10) }),
  dropout: Object.freeze({ joints: "LandmarkType[]", from: bounds(0, 120), to: bounds(0, 120), intervalMaximum: 10 }),
  confidence: Object.freeze({ joints: "LandmarkType[]", from: bounds(0, 120), to: bounds(0, 120), value: bounds(0, 1), intervalMaximum: 10 }),
  framing: Object.freeze({ scale: bounds(0.3, 2), offsetX: bounds(-0.5, 0.5), offsetY: bounds(-0.5, 0.5) }),
});

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
function boundedNumber(errors, value, path, limits) {
  number(errors, value, path, limits[0], limits[1]);
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
function interval(errors, from, to, path, duration, kind) {
  const limits = MUTATION_BOUNDS[kind];
  boundedNumber(errors, from, `${path}.from`, limits.from);
  boundedNumber(errors, to, `${path}.to`, limits.to);
  if (finiteNumber(from) && finiteNumber(to)) {
    if (from > to) issue(errors, `${path}.to`, "must be at or after from");
    else if (to - from > limits.intervalMaximum) issue(errors, `${path}.to`, `interval duration must not exceed ${limits.intervalMaximum} seconds`);
    if (finiteNumber(duration) && to > duration) issue(errors, `${path}.to`, "must be within the output sequence");
  }
}
function mutation(errors, value, path, reps, sequenceDuration) {
  if (!object(value)) { issue(errors, path, "must be an object"); return; }
  const kind = value.kind;
  if (typeof kind !== "string" || !Object.hasOwn(MUTATION_BOUNDS, kind)) { issue(errors, `${path}.kind`, "is not a supported mutation kind"); return; }
  switch (kind) {
    case "jointOffset":
      joints(errors, value.joints, `${path}.joints`);
      boundedNumber(errors, value.dx, `${path}.dx`, MUTATION_BOUNDS.jointOffset.dx);
      boundedNumber(errors, value.dy, `${path}.dy`, MUTATION_BOUNDS.jointOffset.dy);
      boundedNumber(errors, value.peak, `${path}.peak`, MUTATION_BOUNDS.jointOffset.peak);
      boundedNumber(errors, value.rise, `${path}.rise`, MUTATION_BOUNDS.jointOffset.rise);
      boundedNumber(errors, value.fall, `${path}.fall`, MUTATION_BOUNDS.jointOffset.fall);
      boundedNumber(errors, value.strength, `${path}.strength`, MUTATION_BOUNDS.jointOffset.strength);
      if (finiteNumber(value.rise) && finiteNumber(value.peak) && value.peak - value.rise < 0) issue(errors, `${path}.rise`, "influence start must be inside the output sequence");
      if (finiteNumber(value.peak) && finiteNumber(value.fall) && value.peak + value.fall > sequenceDuration) issue(errors, `${path}.fall`, "influence end must be inside the output sequence");
      break;
    case "depthScale":
    case "tempo":
      boundedNumber(errors, value.scale, `${path}.scale`, MUTATION_BOUNDS[kind].scale);
      repsSelector(errors, value.reps, `${path}.reps`, reps);
      break;
    case "asymmetry":
      if (value.side !== "left" && value.side !== "right") issue(errors, `${path}.side`, "must be left or right");
      boundedNumber(errors, value.amount, `${path}.amount`, MUTATION_BOUNDS.asymmetry.amount);
      break;
    case "pause":
      boundedNumber(errors, value.at, `${path}.at`, MUTATION_BOUNDS.pause.at);
      boundedNumber(errors, value.duration, `${path}.duration`, MUTATION_BOUNDS.pause.duration);
      break;
    case "frameGap":
      boundedNumber(errors, value.at, `${path}.at`, MUTATION_BOUNDS.frameGap.at);
      boundedNumber(errors, value.duration, `${path}.duration`, MUTATION_BOUNDS.frameGap.duration);
      if (finiteNumber(value.at) && finiteNumber(value.duration) && value.at + value.duration > sequenceDuration) issue(errors, `${path}.duration`, "frame-gap end must be at or before the output sequence end");
      break;
    case "dropout":
      joints(errors, value.joints, `${path}.joints`);
      interval(errors, value.from, value.to, path, sequenceDuration, kind);
      break;
    case "confidence":
      joints(errors, value.joints, `${path}.joints`);
      interval(errors, value.from, value.to, path, sequenceDuration, kind);
      boundedNumber(errors, value.value, `${path}.value`, MUTATION_BOUNDS.confidence.value);
      break;
    case "framing":
      boundedNumber(errors, value.scale, `${path}.scale`, MUTATION_BOUNDS.framing.scale);
      boundedNumber(errors, value.offsetX, `${path}.offsetX`, MUTATION_BOUNDS.framing.offsetX);
      boundedNumber(errors, value.offsetY, `${path}.offsetY`, MUTATION_BOUNDS.framing.offsetY);
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
