import { isDeepStrictEqual } from "node:util";
import { validatePlan } from "./plan.mjs";

const SCENARIO_ID = /^[a-z0-9_-]{1,64}$/;

export class RevisionError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

/** Create a validated plan containing a new immutable revision of one scenario. */
export function buildScenarioRevision({ plan, scenarioID, mutations, mode, editNote, assertions,
  assertionChangeReason } = {}) {
  const sourceErrors = validatePlan(plan);
  if (sourceErrors.length) throw new RevisionError(`Invalid source plan:\n${sourceErrors.join("\n")}`);
  if (typeof scenarioID !== "string" || !SCENARIO_ID.test(scenarioID)) {
    throw new RevisionError("Scenario id must use 1–64 lowercase letters, digits, '_' or '-'.");
  }
  if (!Array.isArray(mutations)) throw new RevisionError("mutations must be an array.");
  if (mutations.length > 128) throw new RevisionError("A scenario revision may contain at most 128 mutations.");
  if (mode !== "constrained" && mode !== "raw") throw new RevisionError("mode must be constrained or raw.");
  if (typeof editNote !== "string" || !editNote.trim()) throw new RevisionError("editNote must explain this revision.");
  if (editNote.trim().length > 300) throw new RevisionError("editNote must be 300 characters or fewer.");

  const revisedPlan = structuredClone(plan);
  const source = revisedPlan.scenarios.find((scenario) => scenario.id === scenarioID);
  if (!source) throw new RevisionError(`Scenario '${scenarioID}' was not found in the plan.`);
  const originalAssertions = structuredClone(source.assertions);
  const assertionsChanged = assertions !== undefined && !isDeepStrictEqual(assertions, originalAssertions);
  if (assertions !== undefined && !Array.isArray(assertions)) throw new RevisionError("assertions must be an array.");
  if (Array.isArray(assertions) && assertions.length > 128) throw new RevisionError("A scenario revision may contain at most 128 assertions.");
  if (assertionsChanged && (typeof assertionChangeReason !== "string" || !assertionChangeReason.trim())) {
    throw new RevisionError("Changing frozen assertions requires an assertionChangeReason.");
  }
  if (assertionsChanged && typeof assertionChangeReason === "string" && assertionChangeReason.trim().length > 300) {
    throw new RevisionError("assertionChangeReason must be 300 characters or fewer.");
  }

  const parentRevision = source.revision;
  if (parentRevision >= Number.MAX_SAFE_INTEGER) throw new RevisionError("Scenario revision cannot be incremented safely.");
  source.parentRevision = parentRevision;
  source.revision = parentRevision + 1;
  source.mode = mode;
  source.mutations = structuredClone(mutations);
  source.assertions = assertionsChanged ? structuredClone(assertions) : originalAssertions;
  source.editNote = editNote.trim();
  if (assertionsChanged) source.assertionChangeReason = assertionChangeReason.trim();
  else delete source.assertionChangeReason;
  source.editedBy = "developer";
  revisedPlan.author = "developer";

  const errors = validatePlan(revisedPlan);
  if (errors.length) throw new RevisionError(`Invalid revised plan:\n${errors.join("\n")}`);
  return revisedPlan;
}

/** Convert a stage-space drag to body-height units and keep its influence inside the sequence. */
export function jointOffsetFromDrag({ joint, deltaX, deltaY, bodyHeight, peak, rise, fall, strength = 1, duration,
  mode = "constrained" } = {}) {
  const finite = [deltaX, deltaY, bodyHeight, peak, rise, fall, strength, duration].every(Number.isFinite);
  if (!finite || typeof joint !== "string" || !joint || bodyHeight <= 0 || duration < 0
    || (mode !== "constrained" && mode !== "raw")) {
    throw new RevisionError("Drag values and body height must be finite and valid.");
  }
  const end = Math.min(120, Math.max(0, duration));
  const selectedTime = Math.min(end, Math.max(0, peak));
  const boundedRise = Math.min(10, selectedTime, Math.max(0, rise));
  const boundedFall = Math.min(10, end - selectedTime, Math.max(0, fall));
  const clampOffset = (value) => Math.min(0.5, Math.max(-0.5, value));
  let dx = clampOffset(deltaX / bodyHeight);
  let dy = clampOffset(deltaY / bodyHeight);
  const maximumVector = mode === "constrained" ? 0.3 : 0.5;
  const magnitude = Math.hypot(dx, dy);
  if (magnitude > maximumVector) { dx *= maximumVector / magnitude; dy *= maximumVector / magnitude; }
  return {
    kind: "jointOffset",
    joints: [joint],
    dx,
    dy,
    peak: selectedTime,
    rise: boundedRise,
    fall: boundedFall,
    strength: Math.min(1, Math.max(0, strength)),
  };
}

/** Raised-cosine local influence for the editor's explicitly labelled approximate preview. */
export function jointOffsetInfluence(time, mutation) {
  if (!Number.isFinite(time) || !mutation || !Number.isFinite(mutation.peak)) return 0;
  const peak = mutation.peak;
  const strength = Math.min(1, Math.max(0, Number.isFinite(mutation.strength) ? mutation.strength : 0));
  if (time === peak) return strength;
  if (time < peak) {
    const rise = Number.isFinite(mutation.rise) ? mutation.rise : 0;
    if (rise <= 0 || time < peak - rise) return 0;
    const progress = (time - (peak - rise)) / rise;
    return strength * (0.5 - 0.5 * Math.cos(Math.PI * progress));
  }
  const fall = Number.isFinite(mutation.fall) ? mutation.fall : 0;
  if (fall <= 0 || time > peak + fall) return 0;
  const progress = (time - peak) / fall;
  return strength * (0.5 + 0.5 * Math.cos(Math.PI * progress));
}
