const CATEGORIES = Object.freeze([
  "canonical", "depth_rom", "alignment", "timing", "tracking", "session_framing",
]);
const STATUSES = Object.freeze(["passed", "failed", "inconclusive", "invalid", "not tested", "planned"]);

function scenarioKey(scenario) {
  return `${scenario.id}\u0000${scenario.revision}`;
}

function runTime(run) {
  const date = Date.parse(run?.summary?.createdAt ?? run?.createdAt ?? "");
  if (Number.isFinite(date)) return date;
  const match = /^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-/.exec(String(run?.id ?? ""));
  if (!match) return null;
  const [, year, month, day, hour, minute, second] = match;
  const inferred = Date.parse(`${year}-${month}-${day}T${hour}:${minute}:${second}Z`);
  return Number.isFinite(inferred) ? inferred : null;
}

function newer(candidate, previous) {
  if (!previous) return true;
  const first = runTime(candidate);
  const second = runTime(previous);
  if (first != null && second != null && first !== second) return first > second;
  return String(candidate?.id ?? "").localeCompare(String(previous?.id ?? "")) >= 0;
}

function resultStatus(result) {
  if (!result) return "planned";
  if (result.outcome === "notRun") return "not tested";
  return ["passed", "failed", "inconclusive", "invalid"].includes(result.outcome) ? result.outcome : "invalid";
}

function countsFor(scenarios) {
  return Object.fromEntries(STATUSES.map((status) => [status, scenarios.filter((item) => item.status === status).length]));
}

function aggregateStatus(scenarios) {
  if (!scenarios.length) return "not tested";
  const statuses = new Set(scenarios.map((item) => item.status));
  return statuses.size === 1 ? scenarios[0].status : "mixed";
}

/** Build a scenario coverage matrix from stored Movement Lab runs and their plans. */
export function buildCoverageModel(runs = []) {
  const definitions = new Map();
  const results = new Map();

  for (const run of runs) {
    const plan = run?.plan ?? {};
    const runID = typeof run?.id === "string" ? run.id : run?.summary?.id;
    if (typeof runID !== "string") continue;
    for (const scenario of Array.isArray(plan.scenarios) ? plan.scenarios : []) {
      if (typeof scenario?.id !== "string" || !Number.isInteger(scenario.revision)) continue;
      const key = scenarioKey(scenario);
      const candidate = { scenario, run, runID };
      if (newer(run, definitions.get(key)?.run)) definitions.set(key, candidate);
    }

    const planScenarios = new Map((Array.isArray(plan.scenarios) ? plan.scenarios : [])
      .filter((scenario) => typeof scenario?.id === "string" && Number.isInteger(scenario.revision))
      .map((scenario) => [scenario.id, scenario]));
    for (const result of Array.isArray(run.results) ? run.results : []) {
      if (typeof result?.scenarioID !== "string") continue;
      const scenario = planScenarios.get(result.scenarioID);
      const revision = Number.isInteger(result.revision) ? result.revision : scenario?.revision;
      if (!Number.isInteger(revision)) continue;
      const key = scenarioKey({ id: result.scenarioID, revision });
      const candidate = { result, run, runID };
      if (newer(run, results.get(key)?.run)) results.set(key, candidate);
    }
  }

  const scenarios = [...definitions.entries()].map(([key, definition]) => {
    const latestResult = results.get(key);
    const scenario = definition.scenario;
    return {
      id: scenario.id,
      revision: scenario.revision,
      exercise: scenario.exercise,
      category: scenario.category,
      purpose: scenario.purpose,
      canonicalRevision: scenario.canonicalRevision,
      // Keyframe selection needs the rep count to place selective-depth mutations on the right repetition.
      reps: Number.isInteger(scenario.reps) ? scenario.reps : null,
      mutations: Array.isArray(scenario.mutations) ? scenario.mutations : [],
      assertions: Array.isArray(scenario.assertions) ? scenario.assertions : [],
      status: resultStatus(latestResult?.result),
      sourceRunID: definition.runID,
      resultRunID: latestResult?.runID ?? null,
      artifactRunIDs: [...new Set([definition.runID, latestResult?.runID].filter(Boolean))],
    };
  }).sort((a, b) => a.exercise.localeCompare(b.exercise) || a.category.localeCompare(b.category)
    || a.id.localeCompare(b.id) || a.revision - b.revision);

  const exercises = [...new Set(scenarios.map((item) => item.exercise).filter((item) => typeof item === "string"))].sort();
  const cells = exercises.flatMap((exercise) => CATEGORIES.map((category) => {
    const items = scenarios.filter((scenario) => scenario.exercise === exercise && scenario.category === category);
    return { exercise, category, scenarios: items, counts: countsFor(items), status: aggregateStatus(items) };
  }));
  return { label: "Scenario coverage", categories: [...CATEGORIES], statuses: [...STATUSES], exercises, scenarios, cells };
}
