import { promises as fs, constants as fsConstants } from "node:fs";
import path from "node:path";
import { isSafeRunID } from "./runner.mjs";

export const MAX_LAB_FILE_BYTES = 32 * 1024 * 1024;
const OUTCOMES = ["passed", "failed", "inconclusive", "invalid", "notRun"];
const SCENARIO_ID = /^[a-z0-9_-]{1,64}$/;

export class LabStoreError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

function runTimestamp(runID) {
  const match = /^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})-/.exec(runID);
  if (!match) return null;
  const [, year, month, day, hour, minute, second] = match;
  const timestamp = `${year}-${month}-${day}T${hour}:${minute}:${second}.000Z`;
  const date = new Date(timestamp);
  return Number.isNaN(date.getTime()) || date.toISOString() !== timestamp ? null : timestamp;
}

function missing(error, file) {
  if (error?.code === "ENOENT" || error?.code === "ENOTDIR") {
    return new LabStoreError(404, `Movement Lab artifact not found: ${path.basename(file)}.`);
  }
  return error;
}

export function createLabStore(root, { maxFileBytes = MAX_LAB_FILE_BYTES } = {}) {
  const runsRelative = ["diagnostics", "movement-lab", "runs"];

  async function canonicalRoot() {
    try { return await fs.realpath(root); }
    catch (error) { throw missing(error, root); }
  }

  async function resolvePath(components, { directory = false, missingAllowed = false } = {}) {
    const base = await canonicalRoot();
    let current = base;
    let finalStat;
    for (let index = 0; index < components.length; index += 1) {
      const component = components[index];
      if (typeof component !== "string" || component === "" || component === "." || component === ".." || path.isAbsolute(component)) {
        throw new LabStoreError(400, "Invalid Movement Lab path.");
      }
      current = path.join(current, component);
      let stat;
      try { stat = await fs.lstat(current); }
      catch (error) {
        if (missingAllowed && (error?.code === "ENOENT" || error?.code === "ENOTDIR")) return null;
        throw missing(error, current);
      }
      if (index < components.length - 1 && !stat.isDirectory()) {
        throw new LabStoreError(404, "Movement Lab artifact path is not a directory.");
      }
      let resolved;
      try { resolved = await fs.realpath(current); }
      catch (error) { throw missing(error, current); }
      if (!isWithin(base, resolved)) throw new LabStoreError(403, "Movement Lab artifact resolves outside the repository root.");
      finalStat = stat;
    }
    if (directory && !finalStat?.isDirectory()) throw new LabStoreError(404, "Movement Lab run directory not found.");
    if (!directory && !finalStat?.isFile()) throw new LabStoreError(404, "Movement Lab artifact is not a regular file.");
    return { file: current, stat: finalStat };
  }

  async function readBytes(components) {
    const resolved = await resolvePath(components);
    if (resolved.stat.size > maxFileBytes) throw new LabStoreError(413, `Movement Lab file exceeds ${maxFileBytes} bytes.`);
    let handle;
    try {
      handle = await fs.open(resolved.file, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0));
      const openedStat = await handle.stat();
      if (!openedStat.isFile()) throw new LabStoreError(404, "Movement Lab artifact is not a regular file.");
      if (openedStat.size > maxFileBytes) throw new LabStoreError(413, `Movement Lab file exceeds ${maxFileBytes} bytes.`);
      const bytes = await handle.readFile();
      if (bytes.byteLength > maxFileBytes) throw new LabStoreError(413, `Movement Lab file exceeds ${maxFileBytes} bytes.`);
      return bytes;
    } catch (error) {
      throw missing(error, resolved.file);
    } finally {
      await handle?.close();
    }
  }

  async function readJSON(components) {
    const bytes = await readBytes(components);
    try { return JSON.parse(bytes.toString("utf8")); }
    catch { throw new LabStoreError(422, `Invalid JSON in ${components.at(-1)}.`); }
  }

  async function runDirectory(runID) {
    if (!isSafeRunID(runID)) throw new LabStoreError(400, "Invalid Movement Lab run id.");
    return resolvePath([...runsRelative, runID], { directory: true });
  }

  function makeSummary(runID, plan, storedSummary, results) {
    const scenarios = Array.isArray(plan.scenarios) ? plan.scenarios : [];
    const resultsByID = new Map(results.filter((item) => typeof item?.scenarioID === "string").map((item) => [item.scenarioID, item]));
    const storedOutcomes = storedSummary?.outcomes ?? {};
    const outcomes = Object.fromEntries(OUTCOMES.map((outcome) => {
      const value = storedOutcomes[outcome];
      const count = Number.isInteger(value) && value >= 0
        ? value
        : results.filter((result) => result?.outcome === outcome).length;
      return [outcome, count];
    }));
    const exerciseIDs = [...new Set(scenarios.map((scenario) => scenario?.exercise).filter((value) => typeof value === "string"))];
    const evaluatedCount = results.filter((result) => result?.outcome !== "notRun").length;
    const plannedCount = scenarios.filter((scenario) => !resultsByID.has(scenario?.id)).length;
    return {
      ...storedSummary,
      id: runID,
      title: typeof plan.title === "string" ? plan.title : runID,
      createdAt: runTimestamp(runID),
      planCreatedAt: typeof plan.createdAt === "string" ? plan.createdAt : null,
      exerciseIDs,
      scenarioCount: scenarios.length,
      evaluatedCount,
      plannedCount,
      outcomes,
    };
  }

  async function readRun(runID) {
    await runDirectory(runID);
    const prefix = [...runsRelative, runID];
    const [plan, storedSummary, results] = await Promise.all([
      readJSON([...prefix, "plan.json"]),
      readJSON([...prefix, "summary.json"]),
      readJSON([...prefix, "results.json"]),
    ]);
    if (!plan || !Array.isArray(plan.scenarios)) throw new LabStoreError(422, "Movement Lab plan has no scenarios array.");
    if (!Array.isArray(results)) throw new LabStoreError(422, "Movement Lab results must be an array.");
    return { plan, summary: makeSummary(runID, plan, storedSummary, results), results };
  }

  async function listRuns() {
    const directory = await resolvePath(runsRelative, { directory: true, missingAllowed: true }).catch((error) => {
      if (error instanceof LabStoreError && error.status === 404) return null;
      throw error;
    });
    if (!directory) return [];
    let entries;
    try { entries = await fs.readdir(directory.file, { withFileTypes: true }); }
    catch (error) { throw missing(error, directory.file); }
    const summaries = [];
    for (const entry of entries) {
      if (!entry.isDirectory() || !isSafeRunID(entry.name)) continue;
      try {
        const run = await readRun(entry.name);
        summaries.push(run.summary);
      } catch (error) {
        if (error instanceof LabStoreError && error.status === 403) continue;
        // A partial or malformed run is not presented as a complete dashboard entry.
      }
    }
    return summaries.sort((first, second) => second.id.localeCompare(first.id));
  }

  async function readScenarioArtifact(runID, scenarioID, artifact) {
    await runDirectory(runID);
    if (typeof scenarioID !== "string" || !SCENARIO_ID.test(scenarioID)) {
      throw new LabStoreError(400, "Invalid Movement Lab scenario id.");
    }
    const filename = artifact === "recording" ? `${scenarioID}.json`
      : artifact === "reference" ? `${scenarioID}.reference.json` : null;
    if (!filename) throw new LabStoreError(404, "Unknown Movement Lab artifact.");
    const result = await readJSON([...runsRelative, runID, "scenarios", filename]);
    if (!Array.isArray(result)) throw new LabStoreError(422, "Movement Lab scenario artifact must be an array.");
    return result;
  }

  return { root, listRuns, readRun, readScenarioArtifact };
}
