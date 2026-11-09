import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { createServer } from "../server.mjs";
import { buildScenarioRevision, jointOffsetFromDrag, jointOffsetInfluence } from "../lib/lab/revisions.mjs";
import { dragToJointOffset, editorMarkup, previewFrame, saveAndRerunRevision } from "../public/lab/editor.mjs";
import { renderScenarioDetail } from "../public/lab/views.mjs";
import { renderCoverageScenarioRow } from "../public/lab/coverage.mjs";
import { Session, recordsToFileText } from "../lib/session.mjs";

const SOURCE_PLAN = Object.freeze({
  schemaVersion: 1,
  id: "editor-plan",
  title: "Editor test plan",
  purpose: "Exercise saved edits.",
  author: "developer",
  createdAt: "2026-11-08T12:00:00Z",
  scenarios: [{
    id: "squat-case", exercise: "air_squat", category: "canonical", purpose: "Baseline squat.",
    canonicalRevision: "guide-fnv1a-test", seed: "9007199254740993", reps: 3, mode: "raw",
    mutations: [], assertions: [{ kind: "repCount", equals: 3 }], revision: 1,
  }],
});
const SOURCE_RUN_ID = "20261108-110000-a1b2";

function validPlan() { return structuredClone(SOURCE_PLAN); }

async function pageNonce(server) {
  const page = await request(server, { url: "/" });
  assert.equal(page.status, 200);
  return /name="fmp-replay-nonce" content="([^"]+)"/.exec(page.body)?.[1];
}

function request(server, { method = "GET", url, host = "127.0.0.1", replayHeader = null, nonce = null,
  body: requestBody, contentLength = true } = {}) {
  return new Promise((resolve) => {
    const req = new EventEmitter();
    req.method = method;
    req.url = url;
    req.headers = { host };
    req.destroy = () => { req.destroyed = true; };
    if (requestBody !== undefined && contentLength) req.headers["content-length"] = String(Buffer.byteLength(requestBody));
    if (replayHeader != null) req.headers["x-fmp-replay"] = replayHeader;
    if (nonce != null) req.headers["x-fmp-replay-nonce"] = nonce;
    const res = {
      status: null, headers: null, body: null,
      writeHead(status, headers) { this.status = status; this.headers = headers; },
      end(data) { this.body = Buffer.isBuffer(data) ? data.toString("utf8") : String(data ?? ""); resolve(this); },
    };
    server.emit("request", req, res);
    if (requestBody !== undefined) {
      queueMicrotask(() => {
        req.emit("data", Buffer.isBuffer(requestBody) ? requestBody : Buffer.from(requestBody));
        req.emit("end");
      });
    }
  });
}

function editBody(overrides = {}) {
  return JSON.stringify({ sourceRunID: SOURCE_RUN_ID, sourceRevision: 1, plan: validPlan(), scenarioID: "squat-case",
    mutations: [{ kind: "depthScale", scale: 0.7 }], mode: "constrained",
    editNote: "Reduce squat depth for comparison.", ...overrides });
}

function post(server, url, data, nonce, extras = {}) {
  return request(server, { method: "POST", url, replayHeader: "1", nonce, body: JSON.stringify(data), ...extras });
}

async function fakeRun(root, planPath, runID) {
  const plan = JSON.parse(await readFile(planPath, "utf8"));
  const runDir = path.join(root, "diagnostics", "movement-lab", "runs", runID);
  const scenariosDir = path.join(runDir, "scenarios");
  await mkdir(scenariosDir, { recursive: true });
  await writeFile(path.join(runDir, "plan.json"), JSON.stringify(plan));
  await writeFile(path.join(runDir, "results.json"), JSON.stringify(plan.scenarios.map((scenario) => ({
    scenarioID: scenario.id, revision: scenario.revision, outcome: "notRun", observed: {}, assertionResults: [],
  }))));
  await writeFile(path.join(runDir, "summary.json"), JSON.stringify({ outcomes: { notRun: plan.scenarios.length } }));
  const records = await readSyntheticRecording();
  for (const scenario of plan.scenarios) {
    await writeFile(path.join(scenariosDir, `${scenario.id}.json`), JSON.stringify(records));
    await writeFile(path.join(scenariosDir, `${scenario.id}.reference.json`), JSON.stringify(records));
  }
  return { runID, summary: { outcomes: { notRun: plan.scenarios.length } } };
}

async function readSyntheticRecording() {
  return JSON.parse(await readFile(new URL("./fixtures/lab-session-recording.json", import.meta.url), "utf8"));
}

async function writeStoredRun(root, runID, plan) {
  const planPath = path.join(root, `.source-${runID}.json`);
  await writeFile(planPath, JSON.stringify(plan));
  try { await fakeRun(root, planPath, runID); }
  finally { await rm(planPath, { force: true }); }
}

test("revision building increments lineage, preserves frozen assertions, and validates edits", () => {
  const plan = validPlan();
  const frozen = structuredClone(plan.scenarios[0].assertions);
  const revised = buildScenarioRevision({ plan, scenarioID: "squat-case", mutations: [{ kind: "depthScale", scale: 0.7 }],
    mode: "constrained", editNote: "Reduce the depth." });
  assert.equal(revised.scenarios[0].id, "squat-case");
  assert.equal(revised.scenarios[0].revision, 2);
  assert.equal(revised.scenarios[0].parentRevision, 1);
  assert.equal(revised.scenarios[0].editNote, "Reduce the depth.");
  assert.deepEqual(revised.scenarios[0].assertions, frozen);
  assert.deepEqual(plan.scenarios[0].assertions, frozen);
  assert.throws(() => buildScenarioRevision({ plan, scenarioID: "squat-case", mutations: [], mode: "raw",
    editNote: "Change expected count.", assertions: [{ kind: "repCount", equals: 2 }] }), /assertionChangeReason/);
  const changed = buildScenarioRevision({ plan, scenarioID: "squat-case", mutations: [], mode: "raw",
    editNote: "Review new expected count.", assertions: [{ kind: "repCount", equals: 2 }],
    assertionChangeReason: "The exercise target changed in the test plan." });
  assert.equal(changed.scenarios[0].assertionChangeReason, "The exercise target changed in the test plan.");
  assert.deepEqual(plan.scenarios[0].assertions, frozen, "building another revision must leave the source assertions frozen");
  assert.throws(() => buildScenarioRevision({ plan, scenarioID: "squat-case", mutations: [{ kind: "depthScale", scale: 3 }],
    mode: "raw", editNote: "Invalid depth." }), /scenarios\[0\]\.mutations\[0\]\.scale/);
});

test("joint drag peaks at the selected keyframe and clamps its local influence to sequence bounds", () => {
  const values = { joint: "leftKnee", deltaX: 80, deltaY: -40, bodyHeight: 400, peak: 2, rise: 9,
    fall: 9, strength: 0.8, duration: 3 };
  const mutation = jointOffsetFromDrag(values);
  assert.equal(mutation.peak, 2);
  assert.equal(mutation.dx, 0.2);
  assert.equal(mutation.dy, -0.1);
  assert.equal(mutation.rise, 2);
  assert.equal(mutation.fall, 1);
  assert.equal(jointOffsetInfluence(2, mutation), 0.8);
  assert.equal(jointOffsetInfluence(0, mutation), 0);
  assert.equal(jointOffsetInfluence(3, mutation), 0);
  assert.ok(jointOffsetInfluence(1, mutation) >= 0 && jointOffsetInfluence(1, mutation) <= 0.8);
  const constrained = jointOffsetFromDrag({ ...values, deltaX: 400, deltaY: 400, mode: "constrained" });
  const raw = jointOffsetFromDrag({ ...values, deltaX: 400, deltaY: 400, mode: "raw" });
  assert.ok(Math.hypot(constrained.dx, constrained.dy) <= 0.3);
  assert.ok(Math.hypot(raw.dx, raw.dy) > 0.3 && Math.hypot(raw.dx, raw.dy) <= Math.sqrt(0.5));
  const browserMutation = dragToJointOffset({ joint: "leftKnee", deltaX: 40, deltaY: 20, height: 400,
    peak: 1.25, rise: 4, fall: 4, strength: 1, duration: 2 });
  assert.equal(browserMutation.peak, 1.25);
  assert.equal(browserMutation.rise, 1.25);
  assert.equal(browserMutation.fall, 0.75);
  const browserConstrainedMutation = dragToJointOffset({ joint: "leftKnee", deltaX: 400, deltaY: 400, height: 400,
    peak: 1.25, rise: 0.2, fall: 0.2, strength: 1, duration: 2, mode: "constrained" });
  assert.ok(Math.hypot(browserConstrainedMutation.dx, browserConstrainedMutation.dy) <= 0.3);
  const browserRawMutation = dragToJointOffset({ joint: "leftKnee", deltaX: 400, deltaY: 400, height: 400,
    peak: 1.25, rise: 0.2, fall: 0.2, strength: 1, duration: 2, mode: "raw" });
  assert.ok(Math.hypot(browserRawMutation.dx, browserRawMutation.dy) > 0.3);
});

test("editor preview edits the selected frame locally and honors repetition selectors", async () => {
  const records = JSON.parse(await readFile(new URL("./fixtures/lab-session-recording.json", import.meta.url), "utf8"));
  const session = Session.fromText(recordsToFileText(records.map((record) => JSON.stringify(record))));
  const frame = session.frames.find((item) => session.joint(item, "leftKnee")?.x != null);
  assert.ok(frame);
  const jointIndex = session.jointOrder.indexOf("leftKnee");
  const original = session.joint(frame, "leftKnee");
  const offset = { kind: "jointOffset", joints: ["leftKnee"], dx: 0.1, dy: 0, peak: frame.t, rise: 0.2, fall: 0.2, strength: 1 };
  const shifted = previewFrame(session, frame, frame.t, [offset]);
  assert.notEqual(session.joint(shifted, "leftKnee").x, original.x);
  const untouched = previewFrame(session, frame, frame.t, [{ ...offset, reps: [2] }], { rep: 1 });
  assert.equal(session.joint(untouched, "leftKnee").x, original.x);
  const dropped = previewFrame(session, frame, frame.t, [{ kind: "dropout", joints: ["leftKnee"],
    from: frame.t, to: frame.t + 0.1 }]);
  assert.equal(session.joint(dropped, "leftKnee").kind, "missing");
  assert.equal(dropped.j.length, frame.j.length);
  for (let index = 0; index < frame.j.length; index += 1) {
    if (index !== jointIndex) assert.deepEqual(dropped.j[index], frame.j[index]);
  }
  assert.deepEqual(dropped.lo, (frame.lo ?? []).filter((entry) => entry[0] !== jointIndex));
  assert.deepEqual(dropped.est, (frame.est ?? []).filter((entry) => entry[0] !== jointIndex));
  assert.ok(jointIndex >= 0);
});

test("editor exposes a separate pipeline or coach execution selector", () => {
  const markup = editorMarkup();
  assert.match(markup, /data-editor-execution/);
  assert.match(markup, /<option value="pipeline">Pipeline<\/option>/);
  assert.match(markup, /<option value="coach">Coach<\/option>/);
});

test("playback and coverage scenario views expose the editor action", () => {
  const plan = validPlan();
  const scenario = { ...plan.scenarios[0], sourceRunID: "20261108-120000-ab12" };
  const detail = renderScenarioDetail({ plan, scenario, runID: scenario.sourceRunID });
  assert.match(detail, /data-lab-edit-run="20261108-120000-ab12"/);
  assert.match(detail, /data-lab-edit-scenario="squat-case"/);
  const row = renderCoverageScenarioRow({ ...scenario, status: "passed" });
  assert.match(row, /data-lab-edit-run="20261108-120000-ab12"/);
});

test("editor POST routes enforce Host, replay header, page nonce, size, and traversal guards", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-editor-guards-"));
  try {
    await writeStoredRun(root, SOURCE_RUN_ID, validPlan());
    const server = createServer({ root, maxJSONBytes: 1024 });
    const page = await request(server, { url: "/" });
    const nonce = /name="fmp-replay-nonce" content="([^"]+)"/.exec(page.body)?.[1];
    assert.match(page.body, /src="\/lab\/editor\.mjs"/);
    assert.match((await request(server, { url: "/lab/editor.mjs" })).body, /export async function openEditor/);
    assert.ok(nonce);
    const payload = editBody();
    const missingHeader = await request(server, { method: "POST", url: "/api/lab/scenarios", nonce, body: payload });
    assert.equal(missingHeader.status, 403);
    const missingNonce = await request(server, { method: "POST", url: "/api/lab/scenarios", replayHeader: "1", body: payload });
    assert.equal(missingNonce.status, 403);
    const missingRerunNonce = await request(server, { method: "POST", url: "/api/lab/runs", replayHeader: "1",
      body: JSON.stringify({ editID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }) });
    assert.equal(missingRerunNonce.status, 403);
    const wrongHost = await request(server, { method: "POST", url: "/api/lab/scenarios", host: "evil.example",
      replayHeader: "1", nonce, body: payload });
    assert.equal(wrongHost.status, 403);
    const oversized = await request(server, { method: "POST", url: "/api/lab/scenarios", replayHeader: "1", nonce,
      body: "x".repeat(1100), contentLength: false });
    assert.equal(oversized.status, 413);
    const traversal = await post(server, "/api/lab/scenarios", { sourceRunID: SOURCE_RUN_ID, sourceRevision: 1,
      plan: validPlan(), scenarioID: "../escape",
      mutations: [], mode: "raw", editNote: "Rejected traversal." }, nonce);
    assert.equal(traversal.status, 400);
    const editTraversal = await post(server, "/api/lab/runs", { editID: "../outside" }, nonce);
    assert.equal(editTraversal.status, 400);
    assert.deepEqual(await import("node:fs/promises").then(({ readdir }) => readdir(path.join(root, "diagnostics", "movement-lab", "edits")).catch(() => [])), []);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("scenario POST compares frozen assertions with the stored source revision", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-editor-frozen-source-"));
  try {
    const sourcePlan = validPlan();
    await writeStoredRun(root, SOURCE_RUN_ID, sourcePlan);
    const server = createServer({ root });
    const nonce = await pageNonce(server);
    const forgedPlan = validPlan();
    forgedPlan.scenarios[0].assertions = [{ kind: "repCount", equals: 1 }];
    const saved = await post(server, "/api/lab/scenarios", {
      sourceRunID: SOURCE_RUN_ID, sourceRevision: 1, plan: forgedPlan, scenarioID: "squat-case",
      mutations: [], mode: "raw", editNote: "Try a different depth.",
    }, nonce);
    assert.equal(saved.status, 201);
    const revision = JSON.parse(saved.body).plan.scenarios[0];
    assert.equal(revision.revision, 2);
    assert.equal(revision.parentRevision, 1);
    assert.deepEqual(revision.assertions, sourcePlan.scenarios[0].assertions);
    assert.equal(revision.assertionChangeReason, undefined);

    const unreasonedChange = await post(server, "/api/lab/scenarios", {
      sourceRunID: SOURCE_RUN_ID, sourceRevision: 1, scenarioID: "squat-case", mutations: [], mode: "raw",
      editNote: "Try a different expected count.", assertions: [{ kind: "repCount", equals: 1 }],
    }, nonce);
    assert.equal(unreasonedChange.status, 400);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("scenario save and Swift rerun round trip writes a new revision that appears in run history", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-editor-roundtrip-"));
  let runCount = 0;
  await writeStoredRun(root, SOURCE_RUN_ID, validPlan());
  const server = createServer({ root, executePlan: ({ planPath }) => {
    runCount += 1;
    return fakeRun(root, planPath, `20261108-12000${runCount}-ab1${runCount}`);
  } });
  try {
    const nonce = await pageNonce(server);
    const saved = await post(server, "/api/lab/scenarios", JSON.parse(editBody()), nonce);
    assert.equal(saved.status, 201);
    const edit = JSON.parse(saved.body);
    assert.match(edit.editID, /^[a-f0-9]{32}$/);
    assert.equal(edit.plan.scenarios[0].revision, 2);
    assert.equal(edit.plan.scenarios[0].parentRevision, 1);
    assert.deepEqual(edit.plan.scenarios[0].assertions, validPlan().scenarios[0].assertions);
    const stored = JSON.parse(await readFile(path.join(root, "diagnostics", "movement-lab", "edits", edit.editID, "plan.json"), "utf8"));
    assert.equal(stored.scenarios[0].editNote, "Reduce squat depth for comparison.");
    const rerun = await post(server, "/api/lab/runs", { editID: edit.editID, mode: "pipeline" }, nonce);
    assert.equal(rerun.status, 200);
    const response = JSON.parse(rerun.body);
    assert.equal(response.runID, "20261108-120001-ab11");
    const listed = await request(server, { url: "/api/lab/runs" });
    assert.equal(JSON.parse(listed.body)[0].id, response.runID);
    assert.equal(runCount, 1);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("editor save handler advances through two revisions and explicitly reruns a coach scenario in coach mode", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-editor-two-edits-"));
  let runCount = 0;
  const executionModes = [];
  const sourcePlan = validPlan();
  sourcePlan.scenarios[0].assertions = [{ kind: "spokenCue", textContains: "stand tall", present: true }];
  await writeStoredRun(root, SOURCE_RUN_ID, sourcePlan);
  const server = createServer({ root, executePlan: async ({ planPath, mode }) => {
    executionModes.push(mode);
    runCount += 1;
    return fakeRun(root, planPath, `20261108-12200${runCount}-cd3${runCount}`);
  } });
  try {
    const nonce = await pageNonce(server);
    const fetcher = async (url, options = {}) => {
      const response = await request(server, { url, method: options.method ?? "GET",
        replayHeader: options.headers?.["x-fmp-replay"], nonce: options.headers?.["x-fmp-replay-nonce"],
        body: options.body });
      return { ok: response.status >= 200 && response.status < 300, status: response.status,
        statusText: "synthetic", json: async () => JSON.parse(response.body) };
    };
    const loaded = JSON.parse((await request(server, { url: `/api/lab/runs/${SOURCE_RUN_ID}` })).body);
    const sourceScenario = loaded.plan.scenarios[0];
    const headers = { "content-type": "application/json", "x-fmp-replay": "1", "x-fmp-replay-nonce": nonce };
    const first = await saveAndRerunRevision({ runID: SOURCE_RUN_ID, sourcePlan: loaded.plan, scenario: sourceScenario,
      mutations: [{ kind: "depthScale", scale: 0.7 }], mode: "constrained", executionMode: "coach", time: 1 },
    { editNote: "First edit.", headers, fetcher });
    assert.equal(first.scenario.revision, 2);
    assert.equal(first.scenario.parentRevision, 1);
    assert.equal(first.scenario.sourceRunID, first.runID);
    assert.deepEqual(first.scenario.assertions, sourcePlan.scenarios[0].assertions);
    assert.ok(first.recordingSession.frames.length > 0);

    const second = await saveAndRerunRevision({ ...first,
      mutations: [...first.mutations, { kind: "jointOffset", joints: ["leftKnee"], dx: -0.03, dy: 0,
        peak: 1, rise: 0.2, fall: 0.2, strength: 1 }],
    }, { editNote: "Second edit after reviewing revision two.", headers, fetcher });
    assert.equal(second.scenario.revision, 3);
    assert.equal(second.scenario.parentRevision, 2);
    assert.equal(second.sourcePlan.scenarios[0].revision, 3);
    assert.equal(second.scenario.sourceRunID, second.runID);
    assert.deepEqual(executionModes, ["coach", "coach"]);
    assert.deepEqual(second.scenario.assertions, sourcePlan.scenarios[0].assertions);
    assert.equal(runCount, 2);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("reruns execute serially, settle on runner timeout, and release the queue", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-editor-queue-"));
  let active = 0;
  let maximumActive = 0;
  let runCount = 0;
  await writeStoredRun(root, SOURCE_RUN_ID, validPlan());
  const server = createServer({ root, executePlan: async ({ planPath, mode }) => {
    active += 1;
    maximumActive = Math.max(maximumActive, active);
    await new Promise((resolve) => setTimeout(resolve, 15));
    active -= 1;
    if (mode === "coach") throw new Error("xcodebuild exceeded 1200 seconds");
    runCount += 1;
    return fakeRun(root, planPath, `20261108-12100${runCount}-bc2${runCount}`);
  } });
  try {
    const nonce = await pageNonce(server);
    const first = JSON.parse((await post(server, "/api/lab/scenarios", JSON.parse(editBody()), nonce)).body);
    const second = JSON.parse((await post(server, "/api/lab/scenarios", JSON.parse(editBody()), nonce)).body);
    const [firstResult, secondResult] = await Promise.all([
      post(server, "/api/lab/runs", { editID: first.editID }, nonce),
      post(server, "/api/lab/runs", { editID: second.editID }, nonce),
    ]);
    assert.equal(firstResult.status, 200);
    assert.equal(secondResult.status, 200);
    assert.equal(maximumActive, 1);
    const timedOut = await post(server, "/api/lab/runs", { editID: first.editID, mode: "coach" }, nonce);
    assert.equal(timedOut.status, 500);
    assert.match(JSON.parse(timedOut.body).error, /exceeded 1200 seconds/);
    const recovered = await post(server, "/api/lab/runs", { editID: first.editID }, nonce);
    assert.equal(recovered.status, 200);
    assert.equal(maximumActive, 1);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("editor refuses a symlinked edits directory that resolves outside the repository", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-editor-symlink-root-"));
  const outside = await mkdtemp(path.join(tmpdir(), "fmp-editor-symlink-outside-"));
  try {
    await writeStoredRun(root, SOURCE_RUN_ID, validPlan());
    const diagnostics = path.join(root, "diagnostics");
    const movementLab = path.join(diagnostics, "movement-lab");
    await mkdir(movementLab, { recursive: true });
    await symlink(outside, path.join(movementLab, "edits"));
    const server = createServer({ root });
    const nonce = await pageNonce(server);
    const response = await post(server, "/api/lab/scenarios", JSON.parse(editBody()), nonce);
    assert.equal(response.status, 403);
    assert.deepEqual(await (await import("node:fs/promises")).readdir(outside), []);
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});
