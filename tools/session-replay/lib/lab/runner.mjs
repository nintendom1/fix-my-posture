import { spawn } from "node:child_process";
import { readFile, mkdir, lstat, realpath, writeFile } from "node:fs/promises";
import path from "node:path";
import { createHash, randomBytes } from "node:crypto";
import { validatePlan, validatePlanText } from "./plan.mjs";

export const DEFAULT_SIMULATOR = "343F77B5-4F5B-41D7-99DB-9372183E6046";
export const BATCH_TEST = "testEnvironmentPlanWritesBatchArtifacts";
export const EMIT_PRESETS_TEST = "testEmitBuiltInPresetsManifest";
export const MAX_PLAN_BYTES = 5 * 1024 * 1024;
export const XCODEBUILD_TIMEOUT_MS = 20 * 60 * 1000;
export const XCODEBUILD_TERM_GRACE_MS = 1500;
export const XCODEBUILD_KILL_WAIT_MS = 500;
const BUILTIN_PRESET_IDS = new Set(["air_squat"]);

export function createRunID(now = new Date(), suffix = randomBytes(3).toString("hex")) {
  const stamp = [now.getUTCFullYear(), String(now.getUTCMonth() + 1).padStart(2, "0"),
    String(now.getUTCDate()).padStart(2, "0")].join("") + "-" +
    [String(now.getUTCHours()).padStart(2, "0"), String(now.getUTCMinutes()).padStart(2, "0"),
      String(now.getUTCSeconds()).padStart(2, "0")].join("");
  return `${stamp}-${suffix}`;
}

export function isSafeRunID(value) {
  return typeof value === "string" && /^\d{8}-\d{6}-[a-zA-Z0-9]{4,12}$/.test(value);
}

export function buildXcodebuildArgs({ testName = BATCH_TEST, sim = DEFAULT_SIMULATOR } = {}) {
  if (!/^[A-Fa-f0-9-]{16,40}$/.test(sim)) throw new Error("Simulator id must be a UUID.");
  const allowed = new Set([BATCH_TEST, EMIT_PRESETS_TEST]);
  if (!allowed.has(testName)) throw new Error("Movement Lab test selector is not allowlisted.");
  return [
    "test", "-project", "PostureAnalysisApp.xcodeproj", "-scheme", "PostureAnalysisApp",
    "-destination", `platform=iOS Simulator,id=${sim}`,
    "-derivedDataPath", "build/agents/lab", "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO",
    `-only-testing:PostureAnalysisAppTests/MovementLabTests/${testName}`,
  ];
}

export function formatSummary(results, summary) {
  const lines = [];
  for (const result of results) {
    if (result.outcome === "passed") continue;
    const count = result.observed?.reps;
    const observed = count == null ? "reps unknown" : `reps ${count}`;
    const reasons = Array.isArray(result.invalidReasons) ? result.invalidReasons : [];
    const assertion = result.assertionResults?.find((item) => !item.passed)?.detail;
    lines.push(`${result.scenarioID}: ${result.outcome} · ${observed}${assertion ? ` · ${assertion}` : ""}${reasons.length ? ` · ${reasons.join("; ")}` : ""}`);
  }
  const counts = summary?.outcomes ?? Object.fromEntries(["passed", "failed", "inconclusive", "invalid", "notRun"].map((name) => [name, results.filter((result) => result.outcome === name).length]));
  const total = results.length;
  const elapsed = Number.isFinite(summary?.elapsedSeconds) ? `${summary.elapsedSeconds.toFixed(2)}s` : "time unknown";
  lines.push(`total ${total} · passed ${counts.passed ?? 0} · failed ${counts.failed ?? 0} · inconclusive ${counts.inconclusive ?? 0} · invalid ${counts.invalid ?? 0} · notRun ${counts.notRun ?? 0} · ${elapsed}`);
  return lines.join("\n");
}

export function invokeXcodebuild(args, { cwd, env = process.env, timeoutMs = XCODEBUILD_TIMEOUT_MS,
  termGraceMs = XCODEBUILD_TERM_GRACE_MS, killWaitMs = XCODEBUILD_KILL_WAIT_MS } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn("xcodebuild", args, { cwd, env, shell: false, detached: process.platform !== "win32",
      stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let settled = false;
    let killedAfterGrace = false;
    let termTimer;
    let hardTimer;
    const retain = (old, chunk) => (old + chunk.toString("utf8")).slice(-64_000);
    child.stdout.on("data", (chunk) => { stdout = retain(stdout, chunk); });
    child.stderr.on("data", (chunk) => { stderr = retain(stderr, chunk); });
    const finish = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(termTimer);
      clearTimeout(hardTimer);
      if (error) reject(error); else resolve(result);
    };
    const signalProcessGroup = (signal) => {
      try {
        if (child.pid && process.platform !== "win32") process.kill(-child.pid, signal);
        else child.kill(signal);
      } catch {
        try { child.kill(signal); } catch { /* The process already exited. */ }
      }
    };
    const timer = setTimeout(() => {
      timedOut = true;
      signalProcessGroup("SIGTERM");
      termTimer = setTimeout(() => {
        signalProcessGroup("SIGKILL");
        killedAfterGrace = true;
        child.stdout.destroy();
        child.stderr.destroy();
        hardTimer = setTimeout(() => finish(new Error(`xcodebuild exceeded ${Math.round(timeoutMs / 1000)} seconds`)), killWaitMs);
      }, termGraceMs);
    }, timeoutMs);
    child.once("error", (error) => finish(error));
    child.once("close", (code, signal) => {
      if (timedOut) {
        if (killedAfterGrace) finish(new Error(`xcodebuild exceeded ${Math.round(timeoutMs / 1000)} seconds`));
        return;
      }
      if (code !== 0) {
        const tail = `${stdout}\n${stderr}`.split("\n").filter(Boolean).slice(-18).join("\n");
        return finish(new Error(`xcodebuild failed (${code ?? signal ?? "unknown"})${tail ? `\n${tail}` : ""}`));
      }
      finish(null, { code, stdout, stderr });
    });
  });
}

async function execute(args, config, runner) {
  if (runner) return runner(args, config);
  return invokeXcodebuild(args, config);
}

function runnerEnvironment(base, values) {
  const env = { ...base };
  for (const [key, value] of Object.entries(values)) {
    env[key] = value;
    env[`TEST_RUNNER_${key}`] = value;
  }
  return env;
}

export async function emitPresetManifest({ root, runDir, sim = DEFAULT_SIMULATOR, runner }) {
  const safeRunDir = await validateRunDirectory(root, runDir);
  const manifestPath = path.join(safeRunDir, "presets.json");
  try {
    await lstat(manifestPath);
    throw new Error(`Movement Lab refuses to overwrite existing artifact ${manifestPath}.`);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const env = runnerEnvironment(process.env, { FMP_LAB_PRESETS_OUT: manifestPath });
  await execute(buildXcodebuildArgs({ testName: EMIT_PRESETS_TEST, sim }),
    { cwd: root, env, timeoutMs: XCODEBUILD_TIMEOUT_MS }, runner);
  let manifest;
  try { manifest = JSON.parse(await readFile(manifestPath, "utf8")); }
  catch { throw new Error("Swift preset manifest was not written by the Movement Lab test."); }
  if (!Array.isArray(manifest.presets)) throw new Error("Swift preset manifest has no presets array.");
  return manifest;
}

async function gitCommand(root, args, { ignoreFailure = false } = {}) {
  try {
    const child = spawn("git", args, { cwd: root, shell: false, stdio: ["ignore", "pipe", "ignore"] });
    const chunks = [];
    child.stdout.on("data", (chunk) => chunks.push(chunk));
    const status = await new Promise((resolve, reject) => {
      child.once("error", reject);
      child.once("close", resolve);
    });
    if (status !== 0 && !ignoreFailure) throw new Error(`git ${args[0]} failed`);
    return Buffer.concat(chunks);
  } catch (error) {
    if (ignoreFailure) return Buffer.alloc(0);
    throw error;
  }
}

export async function gitIdentity(root) {
  let buildRevision = "unknown";
  try {
    const head = (await gitCommand(root, ["rev-parse", "--short", "HEAD"])).toString("utf8").trim();
    if (/^[0-9a-f]{4,16}$/i.test(head)) buildRevision = head;
  } catch { return { buildRevision, executionRevision: "unknown" }; }
  const status = await gitCommand(root, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], { ignoreFailure: true });
  if (status.length === 0) return { buildRevision, executionRevision: buildRevision };
  const hash = createHash("sha256").update(status);
  hash.update(await gitCommand(root, ["diff", "HEAD", "--binary"], { ignoreFailure: true }));
  const untracked = (await gitCommand(root, ["ls-files", "--others", "--exclude-standard", "-z"], { ignoreFailure: true }))
    .toString("utf8").split("\0").filter(Boolean).sort();
  for (const relative of untracked) {
    hash.update(relative);
    try { hash.update(await readFile(path.join(root, relative))); } catch { /* The status name still identifies it. */ }
  }
  return { buildRevision, executionRevision: `${buildRevision}+dirty-${hash.digest("hex").slice(0, 12)}` };
}

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

async function ensureDirectoryComponents(root, components) {
  let current = root;
  for (const component of components) {
    current = path.join(current, component);
    try { await mkdir(current); }
    catch (error) { if (error.code !== "EEXIST") throw error; }
    const stat = await lstat(current);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`Unsafe Movement Lab directory component: ${current}`);
    if (await realpath(current) !== current) throw new Error(`Movement Lab directory resolves outside its path: ${current}`);
  }
  return current;
}

export async function createFreshRunDirectory(root, runID = createRunID()) {
  if (!isSafeRunID(runID)) throw new Error("Run id must be YYYYMMDD-HHMMSS-<safe suffix>; paths and traversal are rejected.");
  const canonicalRoot = await realpath(root);
  const runs = await ensureDirectoryComponents(canonicalRoot, ["diagnostics", "movement-lab", "runs"]);
  const runDir = path.join(runs, runID);
  try { await mkdir(runDir); }
  catch (error) {
    if (error.code === "EEXIST") throw new Error(`Movement Lab refuses to reuse existing run directory ${runDir}.`);
    throw error;
  }
  const stat = await lstat(runDir);
  if (!stat.isDirectory() || stat.isSymbolicLink() || await realpath(runDir) !== runDir) {
    throw new Error(`Unsafe Movement Lab run directory: ${runDir}`);
  }
  return runDir;
}

async function validateRunDirectory(root, runDir) {
  if (!path.isAbsolute(runDir)) throw new Error("Movement Lab run directory must be absolute.");
  const canonicalRoot = await realpath(root);
  const expectedRuns = path.join(canonicalRoot, "diagnostics", "movement-lab", "runs");
  const resolved = path.resolve(runDir);
  if (path.dirname(resolved) !== expectedRuns || !isSafeRunID(path.basename(resolved)) || !isWithin(canonicalRoot, resolved)) {
    throw new Error("Movement Lab output must be diagnostics/movement-lab/runs/<safe-run-id> inside the repository.");
  }
  let current = canonicalRoot;
  for (const component of path.relative(canonicalRoot, resolved).split(path.sep)) {
    current = path.join(current, component);
    const stat = await lstat(current);
    if (!stat.isDirectory() || stat.isSymbolicLink() || await realpath(current) !== current) {
      throw new Error(`Unsafe Movement Lab output path component: ${current}`);
    }
  }
  return resolved;
}

export async function runPlan({ root, planPath, presetID, sim = DEFAULT_SIMULATOR, mode = "pipeline",
  now = new Date(), suffix, runner } = {}) {
  if (mode !== "pipeline" && mode !== "coach") throw new Error("Mode must be pipeline or coach.");
  const runID = createRunID(now, suffix);
  if (!isSafeRunID(runID)) throw new Error("Generated run id contains unsafe characters.");
  let actualPlanPath = planPath;
  let plan;
  if (presetID === undefined) {
    if (typeof planPath !== "string" || planPath.length === 0) throw new Error("Provide a plan JSON path or --preset.");
    const bytes = await readFile(planPath);
    if (bytes.byteLength > MAX_PLAN_BYTES) throw new Error(`Plan exceeds ${MAX_PLAN_BYTES} bytes.`);
    const checked = validatePlanText(bytes.toString("utf8"));
    if (checked.errors.length) throw new Error(`Invalid Movement Lab plan:\n${checked.errors.join("\n")}`);
    plan = checked.plan;
  } else if (!BUILTIN_PRESET_IDS.has(presetID)) {
    throw new Error(`Unknown built-in preset '${presetID}'.`);
  }

  const runDir = await createFreshRunDirectory(root, runID);
  if (presetID !== undefined) {
    const manifest = await emitPresetManifest({ root, runDir, sim, runner });
    const entry = manifest.presets.find((item) => item?.id === presetID);
    if (!entry) throw new Error(`Unknown built-in preset '${presetID}'.`);
    plan = entry.plan;
    const errors = (await import("./plan.mjs")).validatePlan(plan);
    if (errors.length) throw new Error(`Built-in preset is invalid:\n${errors.join("\n")}`);
    actualPlanPath = path.join(runDir, "preset-plan.json");
    await writeFile(actualPlanPath, `${JSON.stringify(plan, null, 2)}\n`, { flag: "wx" });
  }

  const { buildRevision, executionRevision } = await gitIdentity(root);
  const env = runnerEnvironment(process.env, {
    FMP_LAB_PLAN: path.resolve(actualPlanPath), FMP_LAB_OUT: runDir, FMP_LAB_MODE: mode,
    FMP_LAB_BUILD_REVISION: buildRevision, FMP_LAB_EXECUTION_REVISION: executionRevision,
  });
  await execute(buildXcodebuildArgs({ sim }), { cwd: root, env, timeoutMs: XCODEBUILD_TIMEOUT_MS }, runner);
  const results = JSON.parse(await readFile(path.join(runDir, "results.json"), "utf8"));
  const summary = JSON.parse(await readFile(path.join(runDir, "summary.json"), "utf8"));
  if (!Array.isArray(results)) throw new Error("Movement Lab results.json is not an array.");
  return { runID, runDir, results, summary, text: formatSummary(results, summary), plan };
}
