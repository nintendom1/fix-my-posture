import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { createServer } from "../server.mjs";
import { createLabStore, LabStoreError } from "../lib/lab/store.mjs";
import { recordsToFileText, Session } from "../lib/session.mjs";
import * as replayViews from "../public/views.mjs";
import { renderRunCards, renderRunHeader, renderScenarioDetail, renderScenarioList } from "../public/lab/views.mjs";
import { createSelectionToken, sectionHref } from "../public/lab/selection.mjs";

const RUN_ID = "20261108-100000-a1b2";
const OLD_RUN_ID = "20261108-090000-c3d4";
const SESSION_ID = "E0286BB2-5258-5A31-2092-7A963B90AE7C";

function scenario(id, purpose = `Purpose for ${id}`) {
  return {
    id, name: `Scenario ${id}`, exercise: "air_squat", category: "alignment", purpose,
    canonicalRevision: "guide-fnv1a-test", seed: "9007199254740993", reps: 5, mode: "raw",
    mutations: [{ kind: "jointOffset", joints: ["leftKnee"], dx: -0.05, dy: 0, peak: 3.7, rise: 0.3, fall: 0.3, strength: 1 }],
    assertions: [{ kind: "repCount", equals: 5 }], revision: 1,
  };
}

function runPlan(id = RUN_ID) {
  return {
    schemaVersion: 1, id: `plan-${id}`, title: `Movement run ${id}`, purpose: "Exercise run summary.",
    author: "developer", createdAt: "2026-11-01T08:30:00Z",
    scenarios: [
      { ...scenario("canonical"), category: "canonical", mutations: [], assertions: [{ kind: "repCount", equals: 5 }] },
      { ...scenario("failed"), assertions: [{ kind: "rejection", reasonContains: "partialEnd", countMin: 1 }] },
      { ...scenario("spoken"), assertions: [{ kind: "spokenCue", textContains: "stand tall", present: true }] },
      { ...scenario("invalid"), mutations: [{ kind: "depthScale", scale: 50 }], assertions: [] },
      { ...scenario("not-tested"), assertions: [] },
      { ...scenario("planned"), assertions: [] },
    ],
  };
}

function results() {
  return [
    { scenarioID: "canonical", revision: 1, outcome: "passed", observed: { reps: 5, rejections: [], signals: [], framingChanges: ["reliable"], cues: [] }, assertionResults: [{ assertionIndex: 0, passed: true, detail: "expected 5; observed 5" }], invalidReasons: [] },
    { scenarioID: "failed", revision: 1, outcome: "failed", observed: { reps: 4, rejections: ["partialEnd at 4.933"], signals: ["squat.knees_in"], framingChanges: ["stepBackFullBody"], cues: [] }, assertionResults: [{ assertionIndex: 0, passed: false, detail: "expected one partialEnd; observed zero" }], invalidReasons: [] },
    { scenarioID: "spoken", revision: 1, outcome: "inconclusive", observed: { reps: 5, rejections: [], signals: [], framingChanges: ["reliable"], cues: [] }, assertionResults: [{ assertionIndex: 0, passed: false, detail: "Inconclusive: spokenCue requires coach mode." }], invalidReasons: [] },
    { scenarioID: "invalid", revision: 1, outcome: "invalid", observed: { reps: null, rejections: [], signals: [], framingChanges: [], cues: [] }, assertionResults: [], invalidReasons: ["Composite depth scale must be finite.", "<img src=x onerror=alert(1)>"] },
    { scenarioID: "not-tested", revision: 1, outcome: "notRun", observed: { reps: null, rejections: [], signals: [], framingChanges: [], cues: [] }, assertionResults: [], invalidReasons: [] },
  ];
}

async function recordingFixture() {
  const records = JSON.parse(await readFile(new URL("./fixtures/lab-session-recording.json", import.meta.url), "utf8"));
  const frame = records.find((record) => record.k === "f");
  frame.rej = [{ ts: frame.ts, reason: "partialEnd", reached: [] }];
  frame.sig = ["squat.knees_in"];
  return records;
}

async function timelineFixture() {
  const records = await recordingFixture();
  const firstState = records.find((record) => record.k === "state");
  const firstRep = records.find((record) => record.k === "e" && record.type === "rep");
  const firstFrame = records.find((record) => record.k === "f");
  const pipeIndex = records.findIndex((record) => record.k === "pipe");
  const endIndex = records.findIndex((record) => record.k === "end");
  if (!firstState || !firstRep || !firstFrame || pipeIndex < 0 || endIndex < 0) throw new Error("Synthetic timeline fixture is incomplete.");
  records.splice(pipeIndex + 1, 0, { ...firstState, t: 0, phase: "ready", reps: 0, sideReps: { left: 0, right: 0 } });
  records.splice(endIndex + 1, 0,
    { ...firstState, t: 7.833, phase: "exercising", reps: 5, sideReps: { left: 5, right: 5 } },
    { ...firstFrame, t: 7.933, ts: 7.933333333333334,
      out: [{ rep: { epoch: 1, ts: 7.933333333333334, sides: ["left", "right"] } }], rej: [] },
    { ...firstState, t: 7.933, phase: "exercising", reps: 6, sideReps: { left: 6, right: 6 } },
    { ...firstState, t: 8, phase: "rest", reps: 6, sideReps: { left: 6, right: 6 } });
  const nonEvents = records.filter((record) => record.k !== "e");
  const events = [
    { k: "e", t: 2, type: "framing", framing: { ok: false, g: "stepBackFullBody" } },
    { k: "e", t: 4.833, type: "framing", framing: { ok: true, g: null } },
    { ...firstRep },
    { k: "e", t: 6, type: "framing", framing: { ok: false, g: "stepBackFullBody" } },
    { k: "e", t: 7.8, type: "framing", framing: { ok: true, g: null } },
    { k: "e", t: 7.933, type: "rep", epoch: 1, ts: 7.933333333333334, sides: ["left", "right"] },
  ];
  records.splice(0, records.length, ...nonEvents, ...events);
  const end = records.find((record) => record.k === "end");
  if (end) end.t = 8;
  return records;
}

async function writeRun(root, runID, options = {}) {
  const plan = options.plan ?? runPlan(runID);
  const scenarioResults = options.scenarioResults ?? results();
  const recording = options.recording ?? await recordingFixture();
  const runDirectory = path.join(root, "diagnostics", "movement-lab", "runs", runID);
  const scenarios = path.join(runDirectory, "scenarios");
  await mkdir(scenarios, { recursive: true });
  await writeFile(path.join(runDirectory, "plan.json"), JSON.stringify(plan));
  await writeFile(path.join(runDirectory, "results.json"), JSON.stringify(scenarioResults));
  await writeFile(path.join(runDirectory, "summary.json"), JSON.stringify({ schemaVersion: 1,
    outcomes: { passed: 1, failed: 1, inconclusive: 1, invalid: 1, notRun: 1 }, elapsedSeconds: 3.2,
    guideRevisions: { air_squat: "guide-fnv1a-test" } }));
  await writeFile(path.join(scenarios, "failed.json"), JSON.stringify(recording));
  await writeFile(path.join(scenarios, "failed.reference.json"), JSON.stringify(recording));
  return runDirectory;
}

function request(server, { method = "GET", url, host = "127.0.0.1", replayHeader = null }) {
  return new Promise((resolve) => {
    const req = new EventEmitter();
    req.method = method;
    req.url = url;
    req.headers = { host };
    if (replayHeader != null) req.headers["x-fmp-replay"] = replayHeader;
    const res = {
      status: null,
      headers: null,
      body: null,
      writeHead(status, headers) { this.status = status; this.headers = headers; },
      end(body) { this.body = Buffer.isBuffer(body) ? body.toString("utf8") : String(body ?? ""); resolve(this); },
    };
    server.emit("request", req, res);
  });
}

test("Movement Lab store validates ids, caps reads, and rejects symlink escapes", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-lab-store-safe-"));
  const outside = await mkdtemp(path.join(tmpdir(), "fmp-lab-store-outside-"));
  const store = createLabStore(root, { maxFileBytes: 512 });
  try {
    await writeRun(root, RUN_ID);
    await assert.rejects(store.readRun("../outside"), (error) => error instanceof LabStoreError && error.status === 400);
    await assert.rejects(store.readRun("/tmp/outside"), (error) => error instanceof LabStoreError && error.status === 400);
    await assert.rejects(store.readScenarioArtifact(RUN_ID, "../outside", "recording"),
      (error) => error instanceof LabStoreError && error.status === 400);
    await assert.rejects(store.readScenarioArtifact(RUN_ID, "failed", "../../plan.json"),
      (error) => error instanceof LabStoreError && error.status === 404);
    await assert.rejects(store.readScenarioArtifact(RUN_ID, "failed", "recording"),
      (error) => error instanceof LabStoreError && error.status === 413);

    const symlinkRun = "20261108-110000-e5f6";
    const runs = path.join(root, "diagnostics", "movement-lab", "runs");
    await symlink(outside, path.join(runs, symlinkRun));
    await assert.rejects(store.readRun(symlinkRun), (error) => error instanceof LabStoreError && error.status === 403);

    const secondRoot = await mkdtemp(path.join(tmpdir(), "fmp-lab-store-file-link-"));
    try {
      const linkedRun = await writeRun(secondRoot, RUN_ID);
      const scenarioDir = path.join(linkedRun, "scenarios");
      await rm(path.join(scenarioDir, "failed.json"));
      await symlink(path.join(outside, "outside.json"), path.join(scenarioDir, "failed.json"));
      await writeFile(path.join(outside, "outside.json"), "[]");
      await assert.rejects(createLabStore(secondRoot).readScenarioArtifact(RUN_ID, "failed", "recording"),
        (error) => error instanceof LabStoreError && error.status === 403 && /outside the repository root/.test(error.message));
    } finally { await rm(secondRoot, { recursive: true, force: true }); }
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});

test("Movement Lab store rejects scenario artifacts symlinked outside the repository root", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-lab-artifact-root-"));
  const outside = await mkdtemp(path.join(tmpdir(), "fmp-lab-artifact-outside-"));
  try {
    const runDirectory = await writeRun(root, RUN_ID);
    const artifact = path.join(runDirectory, "scenarios", "failed.reference.json");
    const outsideArtifact = path.join(outside, "reference.json");
    await rm(artifact);
    await writeFile(outsideArtifact, "[]");
    await symlink(outsideArtifact, artifact);
    await assert.rejects(createLabStore(root).readScenarioArtifact(RUN_ID, "failed", "reference"),
      (error) => error instanceof LabStoreError && error.status === 403 && /outside the repository root/.test(error.message));
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});

test("run summaries expose the dashboard contract and sort newest first", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-lab-store-list-"));
  try {
    await writeRun(root, OLD_RUN_ID);
    await writeRun(root, RUN_ID);
    const store = createLabStore(root);
    const runs = await store.listRuns();
    assert.deepEqual(runs.map((run) => run.id), [RUN_ID, OLD_RUN_ID]);
    const summary = await store.readRun(RUN_ID).then((run) => run.summary);
    assert.equal(summary.title, `Movement run ${RUN_ID}`);
    assert.equal(summary.createdAt, "2026-11-08T10:00:00.000Z");
    assert.equal(summary.planCreatedAt, "2026-11-01T08:30:00Z");
    assert.deepEqual(summary.exerciseIDs, ["air_squat"]);
    assert.equal(summary.scenarioCount, 6);
    assert.equal(summary.evaluatedCount, 4);
    assert.equal(summary.plannedCount, 1);
    assert.deepEqual(summary.outcomes, { passed: 1, failed: 1, inconclusive: 1, invalid: 1, notRun: 1 });
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("newer run and scenario selections ignore older responses that resolve afterward", async () => {
  const tokens = createSelectionToken();
  let rendered = "";
  let resolveA;
  let resolveB;
  const responseA = new Promise((resolve) => { resolveA = resolve; });
  const responseB = new Promise((resolve) => { resolveB = resolve; });
  const load = async (response) => {
    const token = tokens.next();
    const value = await response;
    if (tokens.isCurrent(token)) rendered = value;
  };

  const runA = load(responseA);
  const runB = load(responseB);
  resolveB("run B");
  await runB;
  resolveA("run A");
  await runA;
  assert.equal(rendered, "run B");

  let resolveScenarioA;
  let resolveScenarioB;
  const scenarioA = new Promise((resolve) => { resolveScenarioA = resolve; });
  const scenarioB = new Promise((resolve) => { resolveScenarioB = resolve; });
  const oldSelection = load(scenarioA);
  const newSelection = load(scenarioB);
  resolveScenarioB("scenario B frames and assertions");
  await newSelection;
  resolveScenarioA("scenario A frames and assertions");
  await oldSelection;
  assert.equal(rendered, "scenario B frames and assertions");
});

test("section URLs retain recording deep links and clear them when returning to runs", () => {
  const deepLink = "http://127.0.0.1:4317/?session=synthetic-id&t=4.9&from=4&to=6&export=1";
  assert.equal(sectionHref(deepLink, "recordings"), "/?session=synthetic-id&t=4.9&from=4&to=6&export=1&view=recordings");
  assert.equal(sectionHref(deepLink, "runs"), "/?view=runs");
});

test("read-only lab API routes retain Host and POST guards and tolerate a missing root", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-lab-api-"));
  const outside = await mkdtemp(path.join(tmpdir(), "fmp-lab-api-outside-"));
  const missingRoot = path.join(root, "missing-root");
  try {
    await writeRun(root, RUN_ID);
    const server = createServer({ root });
    const list = await request(server, { url: "/api/lab/runs" });
    assert.equal(list.status, 200);
    assert.equal(JSON.parse(list.body)[0].id, RUN_ID);
    const run = await request(server, { url: `/api/lab/runs/${RUN_ID}` });
    assert.equal(run.status, 200);
    assert.equal(JSON.parse(run.body).plan.title, `Movement run ${RUN_ID}`);
    const artifact = await request(server, { url: `/api/lab/runs/${RUN_ID}/scenarios/failed/reference` });
    assert.equal(artifact.status, 200);
    assert.ok(Array.isArray(JSON.parse(artifact.body)));
    const referencePath = path.join(root, "diagnostics", "movement-lab", "runs", RUN_ID, "scenarios", "failed.reference.json");
    const outsideReference = path.join(outside, "reference.json");
    await rm(referencePath);
    await writeFile(outsideReference, "[]");
    await symlink(outsideReference, referencePath);
    const escapedArtifact = await request(server, { url: `/api/lab/runs/${RUN_ID}/scenarios/failed/reference` });
    assert.equal(escapedArtifact.status, 403);
    assert.match(JSON.parse(escapedArtifact.body).error, /outside the repository root/);
    assert.equal((await request(server, { url: "/api/lab/runs", host: "attacker.example" })).status, 403);
    assert.equal((await request(server, { method: "POST", url: "/api/lab/runs", replayHeader: "1" })).status, 405);
    assert.equal((await request(server, { method: "POST", url: "/api/lab/runs" })).status, 403);

    const missingServer = createServer({ root: missingRoot });
    const missingRuns = await request(missingServer, { url: "/api/lab/runs" });
    assert.equal(missingRuns.status, 200);
    assert.deepEqual(JSON.parse(missingRuns.body), []);
    const missingHome = await request(missingServer, { url: "/" });
    assert.equal(missingHome.status, 200);
    assert.match(missingHome.body, /labDashboard/);
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});

test("dashboard views show every status, expected-versus-observed details, failure seeks, and escape artifact text", async () => {
  const plan = runPlan();
  plan.author = `<img src=x onerror=alert(1)>`;
  plan.scenarios[1].purpose = `<script>alert("lab")</script>`;
  plan.scenarios[1].mutations[0].joints = [`leftKnee"><img src=x>`];
  const resultList = results();
  const rows = renderScenarioList(plan, resultList);
  for (const label of ["planned", "executed", "passed", "failed", "inconclusive", "invalid", "not tested"]) {
    assert.ok(rows.includes(`>${label}<`), `Missing status label ${label}`);
  }
  assert.match(rows, /&lt;script&gt;alert\(&quot;lab&quot;\)&lt;\/script&gt;/);
  assert.doesNotMatch(rows, /<script>|<img src=x/);
  assert.match(rows, /data-lab-scenario="failed"/);
  assert.match(renderRunCards([{ id: RUN_ID, title: plan.title, createdAt: plan.createdAt, exerciseIDs: ["air_squat"], scenarioCount: 6, evaluatedCount: 4, outcomes: { passed: 1 } }]), /4\/6 scenarios evaluated/);

  const recording = await timelineFixture();
  const detail = renderScenarioDetail({ plan, scenario: plan.scenarios[1], result: resultList[1], recording, reference: recording });
  assert.match(detail, /data-lab-stage="reference"/);
  assert.match(detail, /data-lab-stage="modified"/);
  assert.match(detail, /Expected vs\. observed/);
  assert.match(detail, /partialEnd/);
  assert.match(detail, /squat\.knees_in/);
  assert.match(detail, /data-lab-seek="4\.933"/);
  assert.match(detail, /Canonical reference/);
  assert.match(detail, /class="lab-lane lane"/);
  assert.match(detail, /class="lab-lane lane marks"/);
  assert.ok((detail.match(/class="seg"/g) ?? []).length >= 8, "phase and framing transitions should render separate segments");
  assert.match(detail, /class="mark" data-t="4\.933"/);
  assert.match(detail, /class="mark" data-t="7\.933"/);
  assert.doesNotMatch(detail, /<script>|<img src=x/);

  const invalidDetail = renderScenarioDetail({ plan, scenario: plan.scenarios[3], result: resultList[3] });
  assert.match(invalidDetail, /Composite depth scale must be finite\./);
  assert.match(invalidDetail, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.doesNotMatch(invalidDetail, /<img src=x/);

  const runHeader = renderRunHeader({ plan, summary: { id: RUN_ID, title: plan.title, createdAt: plan.createdAt,
    exerciseIDs: ["air_squat"], scenarioCount: 6, evaluatedCount: 4, plannedCount: 1,
    planCreatedAt: plan.createdAt, outcomes: { passed: 1, failed: 1, inconclusive: 1, invalid: 1 }, guideRevisions: { air_squat: "guide-test" } } });
  assert.match(runHeader, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.match(runHeader, /Plan created/);
  assert.match(runHeader, /6/);
});

test("existing replay routes and SVG views still read the recording fixture", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-replay-regression-"));
  try {
    const recordings = path.join(root, "diagnostics", "sessions");
    await mkdir(recordings, { recursive: true });
    const records = await recordingFixture();
    await writeFile(path.join(recordings, `${SESSION_ID}.json`), recordsToFileText(records.map((record) => JSON.stringify(record))));
    const server = createServer({ root });
    const listResponse = await request(server, { url: "/api/sessions" });
    assert.equal(listResponse.status, 200);
    assert.equal(JSON.parse(listResponse.body)[0].id, SESSION_ID);
    const fileResponse = await request(server, { url: `/api/sessions/${SESSION_ID}/file` });
    assert.equal(fileResponse.status, 200);
    const session = Session.fromText(fileResponse.body);
    assert.equal(session.reps.length, 1);
    const frame = session.frames[0];
    const svg = replayViews.stageSVG(session, frame, { width: 1080, height: 1920,
      toggles: { mirror: true, angles: true, thresholds: true, labels: true }, glow: "#9b7bff" });
    assert.match(svg, /<line/);
    assert.doesNotMatch(svg, /<script/);
    const page = await request(server, { url: "/" });
    assert.equal(page.status, 200);
    assert.match(page.body, /data-lab-view="recordings"/);
    assert.doesNotMatch(page.body, /https?:\/\//);
    const replayApp = (await request(server, { url: "/app.js" })).body;
    assert.match(replayApp, /Session Replay viewer/);
    assert.match(replayApp, /FMPReplayViewer/);
    assert.match(replayApp, /if \(\$\("app"\)\.hidden\) return;/);
    assert.match((await request(server, { url: "/lab/selection.mjs" })).body, /createSelectionToken/);
    assert.match((await request(server, { url: "/views.mjs" })).body, /export function stageSVG/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

