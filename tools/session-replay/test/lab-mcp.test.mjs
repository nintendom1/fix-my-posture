import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { arrayText, ID } from "./fixtures.mjs";
import { formatSummary } from "../lib/lab/runner.mjs";
import { inspectRun } from "../lib/lab/inspect.mjs";
import { MCP_FULL_TRACE_BYTE_CAP, MCP_MAX_PLAN_BYTES, MCP_PLAN_VALIDATION_BYTE_CAP, MCP_PLAN_VALIDATION_ISSUE_LIMIT,
  assertBoundedInspection, formatPlanValidationErrors, labOpenCommand,
  openLabDashboard, prepareAgentPlan, resolveLabOpenTarget } from "../lib/lab/agent.mjs";
import { SCENARIO_CATEGORIES, MUTATION_BOUNDS } from "../lib/lab/plan.mjs";
import { renderRunHeader } from "../public/lab/views.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MCP_PATH = path.resolve(HERE, "../mcp.mjs");
const CLI_PATH = path.resolve(HERE, "../lab.mjs");
const REPO_ROOT = path.resolve(HERE, "../../..");
const RUN_ID = /^\d{8}-\d{6}-[a-zA-Z0-9]{4,12}$/;

function samplePlan(id = "canonical-fail") {
  return {
    schemaVersion: 1,
    id: "agent-air-squat",
    title: "Agent Air Squat",
    purpose: "Check the expected rep count.",
    author: "developer",
    createdAt: "2026-11-08T12:00:00Z",
    scenarios: [{
      id,
      exercise: "air_squat",
      category: "canonical",
      purpose: "Verify a canonical repetition intention.",
      canonicalRevision: "guide-fnv1a-test",
      seed: "42",
      reps: 1,
      mode: "raw",
      mutations: [],
      assertions: [{ kind: "repCount", equals: 1 }],
      revision: 1,
    }],
  };
}

function fakeXcodebuildSource() {
  return `#!/usr/bin/env node
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
const plan = {
  schemaVersion: 1, id: "air-squat-preset", title: "Air Squat", purpose: "Canonical Air Squat sample.",
  author: "developer", createdAt: "2026-11-08T12:00:00Z",
  scenarios: [{ id: "canonical-fail", exercise: "air_squat", category: "canonical",
    purpose: "Verify one canonical Air Squat repetition.", canonicalRevision: "guide-fnv1a-test", seed: "42",
    reps: 1, mode: "raw", mutations: [], assertions: [{ kind: "repCount", equals: 1 }], revision: 1 }],
};
if (process.env.FMP_LAB_PRESETS_OUT) {
  mkdirSync(path.dirname(process.env.FMP_LAB_PRESETS_OUT), { recursive: true });
  writeFileSync(process.env.FMP_LAB_PRESETS_OUT, JSON.stringify({ presets: [{ id: "air_squat", plan }] }));
} else {
  if (process.env.FMP_LAB_MCP_TEST_DELAY === "1") {
    const active = path.join(path.dirname(process.env.FMP_LAB_OUT), ".mcp-lab-active");
    try { closeSync(openSync(active, "wx")); }
    catch (error) { if (error.code === "EEXIST") writeFileSync(active + ".overlap", "overlap"); else throw error; }
    await new Promise((resolve) => setTimeout(resolve, 100));
    try { unlinkSync(active); } catch { /* Another concurrent fake run may have already removed it. */ }
  }
  const planValue = JSON.parse(readFileSync(process.env.FMP_LAB_PLAN, "utf8"));
  const out = process.env.FMP_LAB_OUT;
  const results = planValue.scenarios.map((scenario) => ({ scenarioID: scenario.id, revision: scenario.revision,
    outcome: "failed", observed: { reps: 0, rejections: [], signals: [], framingChanges: [], cues: [] },
    assertionResults: [{ assertionIndex: 0, passed: false, detail: "expected one rep; observed zero" }], invalidReasons: [] }));
  const counts = { passed: 0, failed: results.length, inconclusive: 0, invalid: 0, notRun: 0 };
  mkdirSync(path.join(out, "scenarios"), { recursive: true });
  writeFileSync(path.join(out, "plan.json"), JSON.stringify(planValue));
  writeFileSync(path.join(out, "results.json"), JSON.stringify(results));
  writeFileSync(path.join(out, "summary.json"), JSON.stringify({ outcomes: counts, elapsedSeconds: 1.25 }));
  for (const scenario of planValue.scenarios) {
    const large = scenario.id === "large-trace";
    const jointOrder = ["leftHip", "rightHip"];
    const frames = [0, 1, 2].map((t) => ({ k: "f", t, j: [[0, t === 1 ? 120 : 100, 1], [0, t === 1 ? 120 : 100, 1]],
      out: [], rej: [], sig: [], cnt: true }));
    const events = Array.from({ length: large ? 300 : 90 }, (_, index) => ({ k: "e", t: index / 100,
      type: "synthetic", text: large ? "x".repeat(1200) : "event " + index }));
    const records = [{ k: "header", title: "Synthetic Movement Lab", jointOrder }, ...frames, ...events];
    writeFileSync(path.join(out, "scenarios", scenario.id + ".json"), JSON.stringify(records));
    writeFileSync(path.join(out, "scenarios", scenario.id + ".reference.json"), JSON.stringify(records));
  }
}
`;
}

async function start({ root: givenRoot, seedSession = true, detectOverlap = false } = {}) {
  const root = givenRoot ?? await mkdtemp(path.join(tmpdir(), "fmp-lab-mcp-"));
  const bin = path.join(root, "fake-bin");
  await mkdir(bin, { recursive: true });
  const xcodebuild = path.join(bin, "xcodebuild");
  await writeFile(xcodebuild, fakeXcodebuildSource(), { mode: 0o755 });
  if (seedSession) {
    const sessions = path.join(root, "diagnostics", "sessions");
    await mkdir(sessions, { recursive: true });
    await writeFile(path.join(sessions, `${ID}.json`), arrayText());
  }
  const env = { ...process.env, FMP_REPLAY_ROOT: root, FMP_REPLAY_PORT: "1", PATH: `${bin}:${process.env.PATH ?? ""}` };
  if (detectOverlap) env.FMP_LAB_MCP_TEST_DELAY = "1";
  const child = spawn(process.execPath, [MCP_PATH], { env, stdio: ["pipe", "pipe", "pipe"] });
  const pending = new Map();
  const errors = [];
  child.stderr.on("data", (chunk) => errors.push(chunk.toString("utf8")));
  createInterface({ input: child.stdout }).on("line", (line) => {
    const message = JSON.parse(line);
    const resolve = pending.get(message.id);
    if (resolve) { pending.delete(message.id); resolve(message); }
  });
  let nextID = 1;
  const request = (method, params = {}) => new Promise((resolve, reject) => {
    const id = nextID++;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`Timed out waiting for ${method}`)); }, 30_000);
    pending.set(id, (message) => { clearTimeout(timer); resolve(message); });
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  });
  const call = async (name, args = {}) => {
    const response = await request("tools/call", { name, arguments: args });
    if (response.error) return { text: response.error.message, isError: true, protocolError: true, code: response.error.code };
    const result = response.result ?? {};
    return { text: result.content?.[0]?.text ?? "", isError: result.isError === true, protocolError: false };
  };
  const stop = async () => {
    const closed = new Promise((resolve) => child.once("close", resolve));
    child.kill("SIGTERM");
    await closed;
    if (!givenRoot) await rm(root, { recursive: true, force: true });
  };
  return { root, request, call, stop, errors };
}

function runCLI(planPath, env) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [CLI_PATH, "run", planPath, "--mode", "pipeline"], { cwd: REPO_ROOT, env });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.once("error", reject);
    child.once("close", (code) => code === 0 ? resolve(stdout.trim()) : reject(new Error(stderr || `CLI exited ${code}`)));
  });
}

function withoutRunID(text) {
  return text.replace(/ · run \d{8}-\d{6}-[a-zA-Z0-9]{4,12}$/, "");
}

test("agent plan preparation records authorship, scenario intent, and paired follow-up lineage", () => {
  const prepared = prepareAgentPlan(samplePlan(), { parentRunID: "20261108-120000-ab12", followUpReason: "Check a boundary." });
  assert.equal(prepared.author, "agent");
  assert.equal(prepared.scenarios[0].author, "agent");
  assert.equal(prepared.scenarios[0].intent, prepared.scenarios[0].purpose);
  assert.equal(prepared.parentRunID, "20261108-120000-ab12");
  assert.equal(prepared.followUpReason, "Check a boundary.");
  assert.match(renderRunHeader({ plan: prepared, summary: { exerciseIDs: ["air_squat"], outcomes: {} } }), /Check a boundary/);
  assert.throws(() => prepareAgentPlan(samplePlan(), { parentRunID: "../outside" }), /supplied together|safe Movement Lab run id/);
  const nearLimit = samplePlan();
  const initialBytes = Buffer.byteLength(JSON.stringify(nearLimit), "utf8");
  nearLimit.title = "x".repeat(MCP_MAX_PLAN_BYTES - initialBytes + nearLimit.title.length - 1);
  assert.equal(Buffer.byteLength(JSON.stringify(nearLimit), "utf8"), MCP_MAX_PLAN_BYTES - 1);
  assert.throws(() => prepareAgentPlan(nearLimit), /Prepared plan exceeds the MCP limit/);
});

test("agent response helpers enforce inspect bounds and create dashboard command targets", () => {
  assert.equal(assertBoundedInspection("a\nb"), "a\nb");
  assert.throws(() => assertBoundedInspection(Array(62).fill("x").join("\n")), /MCP limit is 60/);
  assert.throws(() => assertBoundedInspection("x".repeat(MCP_FULL_TRACE_BYTE_CAP + 1), { full: true }), /MCP cap/);
  assert.deepEqual(labOpenCommand("20261108-120000-ab12", "canonical-fail", 1.25), {
    command: "lab-open", runID: "20261108-120000-ab12", scenarioID: "canonical-fail", timestamp: 1.25,
  });
  const longValidation = formatPlanValidationErrors(Array.from({ length: 30 }, () => "🚦".repeat(500)));
  assert.ok(Buffer.byteLength(longValidation, "utf8") <= MCP_PLAN_VALIDATION_BYTE_CAP);
  assert.match(longValidation, /additional issues omitted/);
});

test("run navigation resolves the selected scenario's stored keyframe through the lab store", async () => {
  const runID = "20261108-120000-ab12";
  const scenario = samplePlan().scenarios[0];
  const records = [
    { k: "header", jointOrder: ["leftHip", "rightHip"] },
    { k: "f", t: 0, j: [[0, 100, 1], [0, 100, 1]] },
    { k: "f", t: 1.25, j: [[0, 130, 1], [0, 130, 1]] },
    { k: "f", t: 2, j: [[0, 110, 1], [0, 110, 1]] },
  ];
  const store = {
    async readRun(id) { assert.equal(id, runID); return { plan: { scenarios: [scenario] } }; },
    async readScenarioArtifact(id, scenarioID, artifact) {
      assert.equal(id, runID);
      assert.equal(scenarioID, scenario.id);
      if (artifact === "recording") return records;
      const missing = new Error("reference missing");
      missing.status = 404;
      throw missing;
    },
  };
  const target = await resolveLabOpenTarget(store, runID, scenario.id);
  assert.equal(target.timestamp, 1.25);
  await assert.rejects(resolveLabOpenTarget(store, runID, "missing"), /is not in run/);
  await assert.rejects(resolveLabOpenTarget(store, "../outside"), /Invalid Movement Lab run id/);
});

test("dashboard open launches the requested deep link and sends its keyframe over the viewer command channel", async () => {
  const runID = "20261108-120000-ab12";
  const scenario = samplePlan().scenarios[0];
  const records = [
    { k: "header", jointOrder: ["leftHip", "rightHip"] },
    { k: "f", t: 0, j: [[0, 100, 1], [0, 100, 1]] },
    { k: "f", t: 1.25, j: [[0, 130, 1], [0, 130, 1]] },
  ];
  const store = {
    async readRun() { return { plan: { scenarios: [scenario] } }; },
    async readScenarioArtifact(_runID, _scenarioID, artifact) {
      if (artifact === "recording") return records;
      const missing = new Error("reference missing");
      missing.status = 404;
      throw missing;
    },
  };
  const calls = [];
  const result = await openLabDashboard({ store, runID, scenarioID: scenario.id, baseURL: "http://127.0.0.1:4317/",
    ensureViewer: async () => calls.push("ensure"),
    openURL: async (url) => calls.push(url),
    sendCommand: async (command) => { calls.push(command); return { delivered: 2 }; },
  });
  assert.equal(result.timestamp, 1.25);
  assert.equal(result.delivered, 2);
  assert.deepEqual(calls.slice(0, 1), ["ensure"]);
  assert.match(calls[1], /labRun=20261108-120000-ab12/);
  assert.match(calls[1], /labScenario=canonical-fail/);
  assert.match(calls[1], /labTime=1.25/);
  assert.deepEqual(calls[2], { command: "lab-open", runID, scenarioID: "canonical-fail", timestamp: 1.25 });
});

test("Movement Lab MCP exposes strict schemas while preserving existing recording tools", async () => {
  const { request, call, stop } = await start();
  try {
    const listed = (await request("tools/list")).result.tools;
    const names = listed.map((tool) => tool.name);
    assert.deepEqual(names.slice(-4), ["fmp_lab_manifest", "fmp_lab_run", "fmp_lab_inspect", "fmp_lab_open"]);
    assert.equal(names.includes("fmp_list_sessions"), true);
    for (const tool of listed.slice(-4)) assert.equal(tool.inputSchema.additionalProperties, false, tool.name);
    const runSchema = listed.find((tool) => tool.name === "fmp_lab_run").inputSchema;
    assert.equal(runSchema.properties.plan.additionalProperties, false);
    assert.equal(runSchema.properties.plan.properties.scenarios.items.additionalProperties, false);
    assert.equal(runSchema.properties.plan.properties.scenarios.items.properties.mutations.items.additionalProperties, false);
    assert.equal((await call("fmp_lab_manifest", { extra: true })).protocolError, true);
    assert.equal((await call("fmp_lab_run", { plan: samplePlan() })).code, -32602, "mode is required by the schema");
    assert.equal((await call("fmp_lab_run", { plan: samplePlan(), mode: "other" })).protocolError, true);
    assert.equal((await call("fmp_lab_run", { plan: samplePlan(), preset: "air_squat", mode: "pipeline" })).isError, true);
    const unexpectedPlanField = samplePlan();
    unexpectedPlanField.extra = true;
    assert.equal((await call("fmp_lab_run", { plan: unexpectedPlanField, mode: "pipeline" })).protocolError, true);
    const unexpectedMutationField = samplePlan();
    unexpectedMutationField.scenarios[0].mutations = [{ kind: "tempo", scale: 1, extra: true }];
    assert.equal((await call("fmp_lab_run", { plan: unexpectedMutationField, mode: "pipeline" })).protocolError, true);
    assert.equal((await call("fmp_lab_inspect", { runID: "../outside" })).protocolError, true);
    assert.equal((await call("fmp_lab_inspect", { runID: "20261108-120000-ab12", window: { from: 0, to: 121 } })).protocolError, true);
    assert.equal((await call("fmp_lab_inspect", { runID: "20261108-120000-ab12", window: { from: 0 } })).protocolError, true);
    assert.equal((await call("fmp_lab_inspect", { runID: "20261108-120000-ab12", window: { from: 0, to: 1, extra: true } })).protocolError, true);
    assert.equal((await call("fmp_lab_open", { runID: "latest" })).protocolError, true);

    const oversized = samplePlan();
    oversized.scenarios[0].mutations = Array.from({ length: 40_000 }, () => ({ kind: "tempo", scale: 1 }));
    const tooLarge = await call("fmp_lab_run", { plan: oversized, mode: "pipeline" });
    assert.equal(tooLarge.protocolError, false);
    assert.equal(tooLarge.isError, true);
    assert.match(tooLarge.text, /MCP limit/);

    const malformed = samplePlan();
    malformed.scenarios[0].seed = "18446744073709551616";
    const invalidPlan = await call("fmp_lab_run", { plan: malformed, mode: "pipeline" });
    assert.equal(invalidPlan.isError, true);
    assert.match(invalidPlan.text, /scenarios\[0\]\.seed: must be a base-10 UInt64 string/);

    const hugeInvalid = samplePlan();
    hugeInvalid.scenarios = Array.from({ length: 200 }, (_, scenarioIndex) => ({
      ...samplePlan(`invalid-${scenarioIndex}`).scenarios[0],
      mutations: Array.from({ length: 100 }, () => ({ kind: "jointOffset" })),
    }));
    const boundedErrors = await call("fmp_lab_run", { plan: hugeInvalid, mode: "pipeline" });
    assert.equal(boundedErrors.isError, true);
    assert.match(boundedErrors.text, /140000 validation issues/);
    assert.match(boundedErrors.text, /scenarios\[0\]\.mutations\[0\]\.joints/);
    assert.equal(boundedErrors.text.split("\n").filter((line) => line.startsWith("- ")).length, MCP_PLAN_VALIDATION_ISSUE_LIMIT);
    assert.match(boundedErrors.text, /139980 additional issues omitted/);
    assert.ok(Buffer.byteLength(boundedErrors.text, "utf8") <= MCP_PLAN_VALIDATION_BYTE_CAP);

    const unknown = await call("fmp_lab_run", { preset: "unknown", mode: "pipeline" });
    assert.equal(unknown.isError, true);
    assert.match(unknown.text, /Unknown built-in preset/);

    const legacy = await call("fmp_list_sessions");
    assert.equal(legacy.isError, false);
    assert.match(legacy.text, new RegExp(ID));
  } finally {
    await stop();
  }
});

test("canonical Air Squat manifest-run-inspect flow is compact, measured, and shares CLI summary formatting", async (t) => {
  const server = await start();
  try {
    const manifestResult = await server.call("fmp_lab_manifest");
    assert.equal(manifestResult.isError, false);
    const manifest = JSON.parse(manifestResult.text);
    assert.deepEqual(manifest.exercises, ["air_squat"]);
    assert.deepEqual(manifest.categories, SCENARIO_CATEGORIES);
    assert.deepEqual(Object.keys(manifest.mutationKinds), Object.keys(MUTATION_BOUNDS));
    assert.deepEqual(manifest.presetIDs, ["air_squat"]);

    const runResult = await server.call("fmp_lab_run", { preset: "air_squat", mode: "pipeline" });
    assert.equal(runResult.isError, false);
    assert.equal(runResult.text.split("\n").length, 2, "one scenario line and totals");
    assert.match(runResult.text, /canonical-fail: failed/);
    const runID = runResult.text.match(/ · run (\d{8}-\d{6}-[a-zA-Z0-9]{4,12})$/)?.[1];
    assert.ok(runID);

    const inspection = await server.call("fmp_lab_inspect", { runID, window: { from: 0, to: 1.5 } });
    assert.equal(inspection.isError, false);
    assert.ok(inspection.text.split("\n").length <= 60);
    assert.ok(Buffer.byteLength(inspection.text, "utf8") <= 12_000);

    const outputBytes = [manifestResult.text, runResult.text, inspection.text]
      .map((text) => Buffer.byteLength(text, "utf8"));
    t.diagnostic(`Canonical Air Squat MCP sample: 3 tool calls; output bytes manifest=${outputBytes[0]}, run=${outputBytes[1]}, inspect=${outputBytes[2]}, total=${outputBytes.reduce((sum, value) => sum + value, 0)}.`);
  } finally {
    await server.stop();
  }
});

test("the same plan gets the same summary through CLI and MCP", async () => {
  const server = await start({ seedSession: false });
  const cliRoot = path.join(REPO_ROOT, "diagnostics", "movement-lab", "runs");
  let cliRunDir;
  try {
    const plan = prepareAgentPlan(samplePlan());
    const planPath = path.join(server.root, "parity-plan.json");
    await writeFile(planPath, JSON.stringify(plan));
    const childEnv = { ...process.env, FMP_REPLAY_ROOT: server.root,
      PATH: `${path.join(server.root, "fake-bin")}:${process.env.PATH ?? ""}` };
    const cliText = await runCLI(planPath, childEnv);
    const cliRunID = cliText.match(/ · run (\d{8}-\d{6}-[a-zA-Z0-9]{4,12})$/)?.[1];
    assert.ok(cliRunID, `CLI output included a run id: ${cliText}`);
    cliRunDir = path.join(cliRoot, cliRunID);

    const runResult = await server.call("fmp_lab_run", { plan, mode: "pipeline" });
    assert.equal(runResult.isError, false);
    assert.ok(runResult.text.match(/ · run \d{8}-\d{6}-[a-zA-Z0-9]{4,12}$/));
    assert.equal(withoutRunID(runResult.text), withoutRunID(cliText));
  } finally {
    if (cliRunDir) await rm(cliRunDir, { recursive: true, force: true });
    await server.stop();
  }
});

test("follow-up run stores visible lineage and full traces are complete or refused by byte size", async () => {
  const { root, call, stop } = await start({ seedSession: false });
  try {
    const first = await call("fmp_lab_run", { plan: samplePlan(), mode: "pipeline" });
    const parentRunID = first.text.match(/ · run (\d{8}-\d{6}-[a-zA-Z0-9]{4,12})$/)?.[1];
    assert.ok(parentRunID);
    const followup = await call("fmp_lab_run", { plan: samplePlan(), mode: "coach", parentRunID,
      followUpReason: "Recheck the smallest valid boundary." });
    const followRunID = followup.text.match(/ · run (\d{8}-\d{6}-[a-zA-Z0-9]{4,12})$/)?.[1];
    assert.ok(followRunID);
    const stored = JSON.parse(await readFile(path.join(root, "diagnostics", "movement-lab", "runs", followRunID, "plan.json"), "utf8"));
    assert.equal(stored.parentRunID, parentRunID);
    assert.equal(stored.followUpReason, "Recheck the smallest valid boundary.");
    assert.match(stored.purpose, /Recheck the smallest valid boundary/);
    assert.equal(stored.author, "agent");
    assert.equal(stored.scenarios[0].intent, stored.scenarios[0].purpose);
    const missingScenario = await call("fmp_lab_open", { runID: followRunID, scenarioID: "missing-scenario" });
    assert.equal(missingScenario.isError, true);
    assert.match(missingScenario.text, /is not in run/);

    const large = await call("fmp_lab_run", { plan: samplePlan("large-trace"), mode: "pipeline" });
    const largeRunID = large.text.match(/ · run (\d{8}-\d{6}-[a-zA-Z0-9]{4,12})$/)?.[1];
    assert.ok(largeRunID);
    const artifact = path.join(root, "diagnostics", "movement-lab", "runs", largeRunID, "scenarios", "large-trace.json");
    const manyShortRecords = Array.from({ length: 4_500 }, (_, index) => ({ k: "e", t: index / 30, type: "sample" }));
    await writeFile(artifact, JSON.stringify(manyShortRecords));
    const full = await call("fmp_lab_inspect", { runID: largeRunID, full: true });
    assert.equal(full.isError, false);
    assert.ok(Buffer.byteLength(full.text, "utf8") <= MCP_FULL_TRACE_BYTE_CAP);
    assert.ok(full.text.split("\n").length > 4_000, "full output must not use the CLI line limit");
    assert.equal(full.text.match(/\"type\":\"sample\"/g)?.length, manyShortRecords.length, "every short record must be present");

    await writeFile(artifact, JSON.stringify([{ k: "e", t: 1, type: "oversized", text: "x".repeat(300_000) }]));
    const oversizedFull = await call("fmp_lab_inspect", { runID: largeRunID, full: true });
    assert.equal(oversizedFull.isError, true);
    const size = Number(oversizedFull.text.match(/Full trace is (\d+) bytes/)?.[1]);
    const completeTrace = await inspectRun({ root, runID: largeRunID, scenarioID: "large-trace", full: true });
    assert.ok(size > MCP_FULL_TRACE_BYTE_CAP, `error should report full rendered size, got ${oversizedFull.text}`);
    assert.equal(size, Buffer.byteLength(completeTrace, "utf8"), "error reports the untruncated rendered size");
    assert.doesNotMatch(oversizedFull.text, /x{100}/, "an oversized full trace must be refused, not returned truncated");
  } finally {
    await stop();
  }
});

test("MCP batches its Swift runner calls one at a time", async () => {
  const { root, call, stop } = await start({ seedSession: false, detectOverlap: true });
  try {
    const [first, second] = await Promise.all([
      call("fmp_lab_run", { plan: samplePlan("first-run"), mode: "pipeline" }),
      call("fmp_lab_run", { plan: samplePlan("second-run"), mode: "coach" }),
    ]);
    assert.equal(first.isError, false);
    assert.equal(second.isError, false);
    await new Promise((resolve) => setTimeout(resolve, 30));
    assert.equal(await readFile(path.join(root, "diagnostics", "movement-lab", "runs", ".mcp-lab-active.overlap"), "utf8").catch(() => null), null);
  } finally {
    await stop();
  }
});

test("the MCP entry points and tool list contain no fixture-write path", async () => {
  const [server, helper] = await Promise.all([
    readFile(MCP_PATH, "utf8"), readFile(new URL("../lib/lab/agent.mjs", import.meta.url), "utf8"),
  ]);
  assert.equal(/promote/i.test(server + helper), false);
  const mcp = await start({ seedSession: false });
  try {
    const names = (await mcp.request("tools/list")).result.tools.map((tool) => tool.name);
    assert.equal(names.some((name) => /promote/i.test(name)), false);
  } finally { await mcp.stop(); }
});

test("the shared summary function retains one bounded line per non-passing scenario", () => {
  const results = Array.from({ length: 200 }, (_, index) => ({ scenarioID: `scenario-${index}`, outcome: "failed",
    observed: { reps: 0 }, assertionResults: [{ passed: false, detail: "🧘".repeat(1000) }], invalidReasons: [] }));
  const summary = formatSummary(results, { outcomes: { failed: 200 }, elapsedSeconds: 1 });
  assert.equal(summary.split("\n").length, 201);
  assert.ok(summary.split("\n").every((line) => Buffer.byteLength(line, "utf8") <= 240));
});
