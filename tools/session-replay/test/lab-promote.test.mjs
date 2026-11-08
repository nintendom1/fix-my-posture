import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { mkdtemp, mkdir, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { createServer } from "../server.mjs";
import { createReviewStore, ReviewStoreError, scenarioRevisionContentHash, scenarioReviewKey } from "../lib/lab/review.mjs";
import { renderCoverageScenarioRow } from "../public/lab/coverage.mjs";
import { renderScenarioDetail } from "../public/lab/views.mjs";

const RUN_ID = "20261108-134500-prom1";
const TARGET = { runID: RUN_ID, scenarioID: "canonical", revision: 1 };

function plan() {
  return {
    schemaVersion: 1, id: "air-squat-promotion", title: "Approved Air Squat", purpose: "Exercise promotion.",
    author: "developer", createdAt: "2026-11-08T12:00:00Z",
    scenarios: [{ id: "canonical", exercise: "air_squat", category: "canonical", purpose: "Count the canonical guide motion.",
      canonicalRevision: "guide-fnv1a-test", seed: "133", reps: 5, mode: "constrained", mutations: [],
      assertions: [{ kind: "repCount", equals: 5 }], revision: 1 }],
  };
}

function result() {
  return [{ scenarioID: "canonical", revision: 1, outcome: "passed",
    observed: { reps: 5, rejections: [], signals: [], framingChanges: ["reliable"], cues: [] },
    assertionResults: [{ assertionIndex: 0, passed: true, detail: "expected 5; observed 5" }], invalidReasons: [] }];
}

async function readRecording({ synthetic = true } = {}) {
  const records = JSON.parse(await readFile(new URL("./fixtures/lab-session-recording.json", import.meta.url), "utf8"));
  if (!synthetic) {
    const header = records.find((record) => record.k === "header");
    header.app.configuration = "Release";
    header.device.model = "iPhone";
  }
  return records;
}

async function writeRun(root, { runID = RUN_ID, storedPlan = plan(), storedResults = result(), synthetic = true,
  executionMode = "pipeline" } = {}) {
  const runDirectory = path.join(root, "diagnostics", "movement-lab", "runs", runID);
  const scenariosDirectory = path.join(runDirectory, "scenarios");
  await mkdir(scenariosDirectory, { recursive: true });
  await writeFile(path.join(runDirectory, "plan.json"), JSON.stringify(storedPlan));
  await writeFile(path.join(runDirectory, "results.json"), JSON.stringify(storedResults));
  await writeFile(path.join(runDirectory, "summary.json"), JSON.stringify({ outcomes: { passed: 1 }, executionMode }));
  const recording = await readRecording({ synthetic });
  await writeFile(path.join(scenariosDirectory, "canonical.json"), JSON.stringify(recording));
  return runDirectory;
}

function createTestServer(options) {
  const terminal = [];
  const server = createServer({ ...options, writePromotionCode: (line) => terminal.push(line) });
  return { server, terminal };
}

function latestTerminalCode(terminal) {
  const match = /: (\d{6})\n$/.exec(terminal.at(-1) ?? "");
  assert.ok(match, "the viewer terminal should receive a six-digit code");
  return match[1];
}

function request(server, { method = "GET", url, host = "127.0.0.1", replayHeader = null, nonce = null,
  confirmationToken = null, body: requestBody } = {}) {
  return new Promise((resolve) => {
    const req = new EventEmitter();
    req.method = method;
    req.url = url;
    req.headers = { host };
    req.destroy = () => { req.destroyed = true; };
    if (requestBody !== undefined) req.headers["content-length"] = String(Buffer.byteLength(requestBody));
    if (replayHeader != null) req.headers["x-fmp-replay"] = replayHeader;
    if (nonce != null) req.headers["x-fmp-replay-nonce"] = nonce;
    if (confirmationToken != null) req.headers["x-fmp-lab-confirmation"] = confirmationToken;
    const response = {
      status: null, body: null,
      writeHead(status) { this.status = status; },
      end(data) { this.body = Buffer.isBuffer(data) ? data.toString("utf8") : String(data ?? ""); resolve(this); },
    };
    server.emit("request", req, response);
    if (requestBody !== undefined) queueMicrotask(() => {
      req.emit("data", Buffer.from(requestBody));
      req.emit("end");
    });
  });
}

async function pageNonce(server) {
  const response = await request(server, { url: "/" });
  assert.equal(response.status, 200);
  return /name="fmp-replay-nonce" content="([^"]+)"/.exec(response.body)?.[1];
}

function post(server, url, data, nonce, options = {}) {
  return request(server, { method: "POST", url, replayHeader: "1", nonce,
    confirmationToken: options.confirmationToken, body: JSON.stringify(data), ...options });
}

async function approve(server, nonce, target = TARGET) {
  const response = await post(server, "/api/lab/review", { ...target, status: "approved", note: "Verified the recorded rep count." }, nonce);
  assert.equal(response.status, 201, response.body);
  return JSON.parse(response.body).review;
}

async function confirmation(server, nonce, terminal, target = TARGET) {
  const response = await post(server, "/api/lab/promote/confirm-token", target, nonce);
  assert.equal(response.status, 201, response.body);
  const grant = JSON.parse(response.body);
  assert.deepEqual(Object.keys(grant).sort(), ["expiresAt", "token"]);
  const code = latestTerminalCode(terminal);
  return { token: grant.token, code };
}

async function promote(server, nonce, token, code, target = TARGET) {
  const data = { ...target, confirmationCode: code };
  return post(server, "/api/lab/promote", data, nonce, { confirmationToken: token });
}

test("scenario review key is deterministic and fingerprints the stored definition", () => {
  const storedScenario = plan().scenarios[0];
  const key = scenarioReviewKey({ runID: RUN_ID, planID: plan().id, scenario: storedScenario });
  const reorderedScenario = Object.fromEntries(Object.entries(storedScenario).reverse());
  const reorderedKey = scenarioReviewKey({ runID: RUN_ID, planID: plan().id, scenario: reorderedScenario });
  assert.deepEqual(reorderedKey, key);
  assert.equal(key.scenarioID, storedScenario.id);
  assert.equal(key.revision, storedScenario.revision);
  assert.equal(key.contentHash, scenarioRevisionContentHash(storedScenario));

  const nextRunKey = scenarioReviewKey({ runID: "20261108-134501-prom2", planID: plan().id, scenario: storedScenario });
  assert.notEqual(nextRunKey.runID, key.runID);
  assert.equal(nextRunKey.contentHash, key.contentHash);
  const changedScenario = { ...storedScenario, purpose: "Changed stored definition." };
  const changedKey = scenarioReviewKey({ runID: RUN_ID, planID: plan().id, scenario: changedScenario });
  assert.notEqual(changedKey.contentHash, key.contentHash);
});

test("review state is atomic, persistent, and isolated by scenario revision", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-review-store-"));
  try {
    let time = new Date("2026-11-08T12:00:00Z");
    const store = createReviewStore(root, { now: () => time });
    const contentHash = scenarioRevisionContentHash(plan().scenarios[0]);
    const key = { runID: RUN_ID, planID: "air-squat-promotion", scenarioID: "canonical", revision: 1, contentHash };
    assert.equal(await store.read(key), null);
    const approved = await store.save({ ...key, status: "approved", note: "Reviewed assertions.", runID: RUN_ID });
    assert.equal(approved.updatedAt, time.toISOString());
    assert.deepEqual(await store.read(key), approved);
    time = new Date("2026-11-08T12:01:00Z");
    const revisedReview = await store.save({ ...key, status: "needs-edit", note: "Check the shallow case.", runID: RUN_ID });
    assert.equal(revisedReview.status, "needs-edit");
    assert.equal(revisedReview.note, "Check the shallow case.");
    assert.equal(revisedReview.updatedAt, time.toISOString());
    assert.equal(await store.read({ ...key, revision: 2 }), null);
    assert.equal(await store.read({ ...key, runID: "20261108-134501-prom2" }), null);
    assert.equal(await store.read({ ...key, contentHash: "0".repeat(64) }), null);
    const files = await readdir(path.join(root, "diagnostics", "movement-lab", "reviews", key.runID));
    assert.deepEqual(files, [`${key.planID}.${key.scenarioID}.r1.${contentHash}.json`]);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("review store rejects a run-directory symlink that escapes diagnostics", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-review-symlink-"));
  const outside = await mkdtemp(path.join(tmpdir(), "fmp-review-outside-"));
  try {
    const reviews = path.join(root, "diagnostics", "movement-lab", "reviews");
    await mkdir(reviews, { recursive: true });
    await symlink(outside, path.join(reviews, RUN_ID));
    const store = createReviewStore(root);
    await assert.rejects(store.save({ runID: RUN_ID, planID: "air-squat-promotion", scenarioID: "canonical", revision: 1,
      contentHash: scenarioRevisionContentHash(plan().scenarios[0]), status: "approved", note: "Should remain contained." }),
    (error) => error instanceof ReviewStoreError && error.status === 403);
    assert.deepEqual(await readdir(outside), []);
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});

test("review API guards writes and exposes approved state in run and coverage views", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-review-api-"));
  try {
    await writeRun(root);
    const server = createServer({ root });
    const nonce = await pageNonce(server);
    const missingHeader = await request(server, { method: "POST", url: "/api/lab/review", nonce,
      body: JSON.stringify({ ...TARGET, status: "approved", note: "verified" }) });
    assert.equal(missingHeader.status, 403);
    const missingNonce = await request(server, { method: "POST", url: "/api/lab/review", replayHeader: "1",
      body: JSON.stringify({ ...TARGET, status: "approved", note: "verified" }) });
    assert.equal(missingNonce.status, 403);

    const approved = await approve(server, nonce);
    assert.equal(approved.status, "approved");
    assert.equal(typeof approved.updatedAt, "string");
    const run = JSON.parse((await request(server, { url: `/api/lab/runs/${RUN_ID}` })).body);
    assert.equal(run.plan.scenarios[0].review.note, "Verified the recorded rep count.");
    const coverage = JSON.parse((await request(server, { url: "/api/lab/coverage" })).body);
    assert.equal(coverage.scenarios[0].reviewStatus, "approved");
    assert.equal(coverage.scenarios[0].promoted, false);

    const scenario = { ...run.plan.scenarios[0], promoted: false };
    const panel = renderScenarioDetail({ plan: run.plan, scenario, result: run.results[0], runID: RUN_ID });
    assert.match(panel, /data-lab-review-action="approved"/);
    assert.match(panel, /data-lab-review-action="rejected"/);
    assert.match(panel, /data-lab-review-action="exploratory"/);
    assert.match(panel, /data-lab-review-action="needs-edit"/);
    assert.match(panel, /data-lab-promote/);
    const notApproved = renderScenarioDetail({ plan: run.plan,
      scenario: { ...scenario, review: { status: "exploratory", note: "still exploring" } }, result: run.results[0], runID: RUN_ID });
    assert.doesNotMatch(notApproved, /data-lab-promote/);
    assert.match(renderCoverageScenarioRow({ ...coverage.scenarios[0], promoted: true }), /Promoted to CI/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("promotion needs a one-time confirmation and writes an immutable fixture without frames", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-promote-api-"));
  try {
    await writeRun(root);
    const { server, terminal } = createTestServer({ root });
    const nonce = await pageNonce(server);
    await approve(server, nonce);
    const missingHeader = await request(server, { method: "POST", url: "/api/lab/promote/confirm-token", nonce,
      body: JSON.stringify(TARGET) });
    assert.equal(missingHeader.status, 403);
    const missingNonce = await request(server, { method: "POST", url: "/api/lab/promote/confirm-token", replayHeader: "1",
      body: JSON.stringify(TARGET) });
    assert.equal(missingNonce.status, 403);
    assert.equal((await promote(server, nonce, null, null)).status, 403);

    const grant = await confirmation(server, nonce, terminal);
    const promoted = await promote(server, nonce, grant.token, grant.code);
    assert.equal(promoted.status, 201, promoted.body);
    const response = JSON.parse(promoted.body);
    assert.equal(response.fixturePath,
      "PostureAnalysisApp/Tests/Fixtures/MovementScenarios/approved/air_squat/canonical.r1.json");
    const fixturePath = path.join(root, response.fixturePath);
    const before = await readFile(fixturePath, "utf8");
    const fixture = JSON.parse(before);
    assert.equal(fixture.provenance.kind, "developer-approved");
    assert.equal(fixture.executionMode, "pipeline");
    assert.equal(fixture.plan.scenarios[0].assertions[0].equals, 5);
    assert.equal(fixture.result.observed.reps, 5);
    assert.equal("recording" in fixture, false);
    assert.equal("frames" in fixture, false);
    const coverage = JSON.parse((await request(server, { url: "/api/lab/coverage" })).body);
    assert.equal(coverage.scenarios[0].reviewStatus, "approved");
    assert.equal(coverage.scenarios[0].promoted, true);
    assert.match(renderCoverageScenarioRow(coverage.scenarios[0]), /approved/);
    assert.match(renderCoverageScenarioRow(coverage.scenarios[0]), /Promoted to CI/);
    assert.equal((await promote(server, nonce, grant.token, grant.code)).status, 403, "a used token must not promote a second time");

    const secondGrant = await confirmation(server, nonce, terminal);
    const immutable = await promote(server, nonce, secondGrant.token, secondGrant.code);
    assert.equal(immutable.status, 409);
    assert.equal(await readFile(fixturePath, "utf8"), before, "a second promotion cannot replace the fixture");
    const fixturesRoot = path.join(root, "PostureAnalysisApp", "Tests", "Fixtures", "MovementScenarios");
    assert.deepEqual(await readdir(fixturesRoot), ["approved"], "promotion writes no artifacts outside the approved fixture folder");
    const approvedExercises = await readdir(path.join(fixturesRoot, "approved"));
    assert.deepEqual(approvedExercises, ["air_squat"]);
    assert.deepEqual(await readdir(path.join(fixturesRoot, "approved", "air_squat")), ["canonical.r1.json"]);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("promotion needs the code printed to the viewer terminal; headless POST without it is refused", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-promote-human-code-"));
  try {
    await writeRun(root);
    const { server, terminal } = createTestServer({ root });
    const nonce = await pageNonce(server);
    await approve(server, nonce);
    const grant = await confirmation(server, nonce, terminal);
    assert.equal(terminal.length, 1);
    assert.match(terminal[0], new RegExp(`\\b${grant.code}\\b`));

    const withoutCode = await post(server, "/api/lab/promote", TARGET, nonce,
      { confirmationToken: grant.token });
    assert.equal(withoutCode.status, 403);
    assert.match(JSON.parse(withoutCode.body).error, /Incorrect promotion code/);
    assert.equal(await readdir(path.join(root, "PostureAnalysisApp", "Tests", "Fixtures")).catch(() => null), null);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("five incorrect promotion codes invalidate the grant and a fresh code works", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-promote-rate-limit-"));
  try {
    await writeRun(root);
    const { server, terminal } = createTestServer({ root });
    const nonce = await pageNonce(server);
    await approve(server, nonce);
    const grant = await confirmation(server, nonce, terminal);
    const wrongCode = grant.code === "000000" ? "111111" : "000000";
    for (let attempt = 1; attempt <= 5; attempt += 1) {
      const response = await promote(server, nonce, grant.token, wrongCode);
      assert.equal(response.status, attempt === 5 ? 429 : 403);
    }
    assert.equal((await promote(server, nonce, grant.token, grant.code)).status, 403,
      "the invalidated grant must reject its original code");
    const freshGrant = await confirmation(server, nonce, terminal);
    assert.equal(terminal.length, 2);
    const promoted = await promote(server, nonce, freshGrant.token, freshGrant.code);
    assert.equal(promoted.status, 201, promoted.body);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("approval is scoped to its source run and scenario content hash", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-review-run-scope-"));
  const siblingRunID = "20261108-134501-prom2";
  const changedDefinitionRunID = "20261108-134502-prom3";
  try {
    await writeRun(root);
    const changedObservation = result();
    changedObservation[0].observed.cues = ["different observed coach cue"];
    await writeRun(root, { runID: siblingRunID, storedResults: changedObservation });
    const changedPlan = plan();
    changedPlan.scenarios[0].purpose = "Sibling definition with an otherwise identical identity.";
    await writeRun(root, { runID: changedDefinitionRunID, storedPlan: changedPlan });

    const { server, terminal } = createTestServer({ root });
    const nonce = await pageNonce(server);
    await approve(server, nonce, TARGET);

    for (const runID of [siblingRunID, changedDefinitionRunID]) {
      const run = JSON.parse((await request(server, { url: `/api/lab/runs/${runID}` })).body);
      assert.equal(run.plan.scenarios[0].review, null, `run ${runID} must not inherit another run's approval`);
      const target = { ...TARGET, runID };
      const tokenRequest = await post(server, "/api/lab/promote/confirm-token", target, nonce);
      assert.equal(tokenRequest.status, 409, `run ${runID} needs its own approval`);
    }

    const sourceGrant = await confirmation(server, nonce, terminal, TARGET);
    const crossRun = await promote(server, nonce, sourceGrant.token, sourceGrant.code,
      { ...TARGET, runID: siblingRunID });
    assert.equal(crossRun.status, 403, "a source run's grant cannot promote a sibling run");

    const coverage = JSON.parse((await request(server, { url: "/api/lab/coverage" })).body);
    assert.equal(coverage.scenarios[0].sourceRunID, changedDefinitionRunID);
    assert.equal(coverage.scenarios[0].reviewStatus, "not reviewed");
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("editing stored scenario content under the same run invalidates review display and token binding", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-review-content-binding-"));
  try {
    await writeRun(root);
    const { server, terminal } = createTestServer({ root });
    const nonce = await pageNonce(server);
    await approve(server, nonce);
    const grant = await confirmation(server, nonce, terminal);

    const changedPlan = plan();
    changedPlan.scenarios[0].purpose = "Stored scenario content changed after approval.";
    const planPath = path.join(root, "diagnostics", "movement-lab", "runs", RUN_ID, "plan.json");
    await writeFile(planPath, JSON.stringify(changedPlan));

    const run = JSON.parse((await request(server, { url: `/api/lab/runs/${RUN_ID}` })).body);
    assert.equal(run.plan.scenarios[0].review, null);
    const tokenRequest = await post(server, "/api/lab/promote/confirm-token", TARGET, nonce);
    assert.equal(tokenRequest.status, 409, "changed scenario content has no matching approval");
    const staleGrant = await promote(server, nonce, grant.token, grant.code);
    assert.equal(staleGrant.status, 403, "the old content hash must not authorize promotion");
    assert.equal(await readdir(path.join(root, "PostureAnalysisApp", "Tests", "Fixtures")).catch(() => null), null);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("coach-mode spoken-cue approval stores coach mode in the fixture", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-promote-coach-mode-"));
  try {
    const coachPlan = plan();
    coachPlan.scenarios[0].assertions = [{ kind: "spokenCue", textContains: "Set 1 of 2", present: true }];
    const coachResult = result();
    coachResult[0].observed.cues = ["Set 1 of 2 — stand tall"];
    coachResult[0].assertionResults = [{ assertionIndex: 0, passed: true, detail: "expected spoken cue" }];
    await writeRun(root, { storedPlan: coachPlan, storedResults: coachResult, executionMode: "coach" });

    const { server, terminal } = createTestServer({ root });
    const nonce = await pageNonce(server);
    await approve(server, nonce);
    const grant = await confirmation(server, nonce, terminal);
    const promoted = await promote(server, nonce, grant.token, grant.code);
    assert.equal(promoted.status, 201, promoted.body);
    const fixture = JSON.parse(await readFile(path.join(root, JSON.parse(promoted.body).fixturePath), "utf8"));
    assert.equal(fixture.executionMode, "coach");
    assert.equal(fixture.plan.scenarios[0].assertions[0].kind, "spokenCue");
    assert.deepEqual(fixture.result.observed.cues, ["Set 1 of 2 — stand tall"]);

    const regressionSource = await readFile(new URL("../../../PostureAnalysisApp/Tests/MovementLabRegressionTests.swift", import.meta.url), "utf8");
    assert.match(regressionSource, /mode:\s*fixture\.executionMode/);
    const batchWriterSource = await readFile(new URL("../../../PostureAnalysisApp/Tests/MovementLabTests.swift", import.meta.url), "utf8");
    assert.match(batchWriterSource, /executionMode:\s*mode\.rawValue/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("promotion confirmation expires after sixty seconds", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-promote-expiry-"));
  try {
    await writeRun(root);
    let now = Date.UTC(2026, 10, 8, 12);
    const { server, terminal } = createTestServer({ root, now: () => now });
    const nonce = await pageNonce(server);
    await approve(server, nonce);
    const grant = await confirmation(server, nonce, terminal);
    now += 60_001;
    const expired = await promote(server, nonce, grant.token, grant.code);
    assert.equal(expired.status, 403);
    assert.match(JSON.parse(expired.body).error, /expired/);
    assert.equal(await readdir(path.join(root, "PostureAnalysisApp", "Tests", "Fixtures")).catch(() => null), null);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("promotion refuses recordings not produced by the synthetic Movement Lab", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-promote-real-recording-"));
  try {
    await writeRun(root, { synthetic: false });
    const { server, terminal } = createTestServer({ root });
    const nonce = await pageNonce(server);
    await approve(server, nonce);
    const grant = await confirmation(server, nonce, terminal);
    const refused = await promote(server, nonce, grant.token, grant.code);
    assert.equal(refused.status, 422);
    assert.match(JSON.parse(refused.body).error, /synthetic Movement Lab/);
    assert.equal(await readdir(path.join(root, "PostureAnalysisApp", "Tests", "Fixtures")).catch(() => null), null);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("CLI and MCP entry points do not expose the promotion endpoint", async () => {
  const entryPoints = [new URL("../lab.mjs", import.meta.url), new URL("../mcp.mjs", import.meta.url)];
  for (const entryPoint of entryPoints) {
    const source = await readFile(entryPoint, "utf8");
    assert.doesNotMatch(source, /\/api\/lab\/promote/, `${path.basename(entryPoint.pathname)} must not expose promotion`);
  }
  const dashboard = await readFile(new URL("../public/lab/dashboard.mjs", import.meta.url), "utf8");
  assert.match(dashboard, /window\.confirm/);
  assert.match(dashboard, /\/api\/lab\/promote\/confirm-token/);
  assert.match(dashboard, /window\.prompt\([\s\S]*terminal running this viewer/);
  assert.match(dashboard, /confirmationCode:\s*code\.trim\(\)/);
});
