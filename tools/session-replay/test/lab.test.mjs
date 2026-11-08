import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile, readFile, rm, symlink, chmod, lstat } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { Session, recordsToFileText } from "../lib/session.mjs";
import { landmarkNamesFromSwiftSource, SWIFT_LANDMARK_NAMES, validatePlan, validatePlanText } from "../lib/lab/plan.mjs";
import { buildXcodebuildArgs, createFreshRunDirectory, createRunID, emitPresetManifest, formatSummary,
  invokeXcodebuild, isSafeRunID, runPlan } from "../lib/lab/runner.mjs";
import { filterRecords, inspectRun, parseWindow, renderInspection } from "../lib/lab/inspect.mjs";

function plan() {
  return {
    schemaVersion: 1, id: "boundary-plan", title: "Boundary", purpose: "Exercise validation edges",
    author: "developer", createdAt: "2026-11-07T12:00:00Z",
    scenarios: [{
      id: "boundary", exercise: "air_squat", category: "timing", purpose: "Boundary values",
      canonicalRevision: "guide-fnv1a-test", seed: "18446744073709551615", reps: 120, mode: "raw",
      mutations: [{ kind: "tempo", scale: 0.3, reps: [1, 120] }],
      assertions: [{ kind: "repCount", min: 0, max: 120 }], revision: 1,
    }],
  };
}

test("plan validation accepts decimal UInt64 and inclusive numeric boundaries", () => {
  assert.deepEqual(validatePlan(plan()), []);
  const above = plan();
  above.scenarios[0].seed = "18446744073709551616";
  assert.ok(validatePlan(above).includes("scenarios[0].seed: must be a base-10 UInt64 string"));
  const below = plan();
  below.scenarios[0].mutations[0].scale = 0.299999;
  assert.ok(validatePlan(below).includes("scenarios[0].mutations[0].scale: must be between 0.3 and 2"));
  const overReps = plan();
  overReps.scenarios[0].reps = 121;
  assert.ok(validatePlan(overReps).includes("scenarios[0].reps: must be an integer from 1 through 120"));
});

test("plan shape errors report exact paths before execution", () => {
  const malformed = plan();
  malformed.scenarios[0].mutations[0].scale = "fast";
  malformed.scenarios[0].assertions[0] = { kind: "repCount", equals: -1 };
  malformed.scenarios[0].seed = 4;
  const errors = validatePlan(malformed);
  assert.ok(errors.includes("scenarios[0].mutations[0].scale: must be a finite number"));
  assert.ok(errors.includes("scenarios[0].assertions[0].equals: must be a nonnegative integer"));
  assert.ok(errors.includes("scenarios[0].seed: must be a base-10 UInt64 string"));
  assert.match(validatePlanText("{").errors[0], /^\$: invalid JSON/);
});

test("joint validation stays in parity with every Swift LandmarkType case", async () => {
  const source = await readFile(new URL("../../../PostureAnalysisApp/Models/LandmarkType.swift", import.meta.url), "utf8");
  const names = landmarkNamesFromSwiftSource(source);
  assert.deepEqual(SWIFT_LANDMARK_NAMES, names);
  const candidate = plan();
  candidate.scenarios[0].mutations = [{ kind: "jointOffset", joints: names, dx: 0, dy: 0,
    peak: 0.5, rise: 0, fall: 0, strength: 1 }];
  assert.deepEqual(validatePlan(candidate), []);
  for (const unknown of ["leftToe", "rightToe", "notALandmark"]) {
    candidate.scenarios[0].mutations[0].joints = [unknown];
    assert.ok(validatePlan(candidate).includes("scenarios[0].mutations[0].joints[0]: is not a LandmarkType name"));
  }
});

test("composite depth is rejected before large or tiny geometry reaches generation", () => {
  const tooLarge = plan();
  tooLarge.scenarios[0].mutations = Array.from({ length: 5 }, () => ({ kind: "depthScale", scale: 2 }));
  assert.ok(validatePlan(tooLarge).some((error) => error.includes("composite depth scale for repetition 1")));
  const tooSmall = plan();
  tooSmall.scenarios[0].mutations = Array.from({ length: 4 }, () => ({ kind: "depthScale", scale: 0.3 }));
  assert.ok(validatePlan(tooSmall).some((error) => error.includes("composite depth scale for repetition 1")));
});

test("run ids are timestamped and reject absolute paths and traversal", () => {
  assert.equal(createRunID(new Date("2026-11-07T12:34:56Z"), "a1b2c3"), "20261107-123456-a1b2c3");
  assert.equal(isSafeRunID("20261107-123456-a1b2c3"), true);
  for (const unsafe of ["../latest", "/tmp/run", "20261107-123456-../x", "latest"]) assert.equal(isSafeRunID(unsafe), false);
});

test("xcodebuild gets a fixed argument vector and fake runner receives batch environment", async () => {
  const args = buildXcodebuildArgs({ sim: "343F77B5-4F5B-41D7-99DB-9372183E6046" });
  assert.ok(Array.isArray(args));
  assert.ok(args.includes("-parallel-testing-enabled"));
  assert.ok(args.includes("-only-testing:PostureAnalysisAppTests/MovementLabTests/testEnvironmentPlanWritesBatchArtifacts"));
  assert.equal(args.some((value) => value.includes(";")), false);

  const root = await mkdtemp(path.join(tmpdir(), "fmp-lab-run-"));
  const inputPath = path.join(root, "input.json");
  await writeFile(inputPath, JSON.stringify(plan()));
  const calls = [];
  const runner = async (argv, config) => {
    calls.push({ argv, config });
    const output = config.env.FMP_LAB_OUT;
    await mkdir(output, { recursive: true });
    await writeFile(path.join(output, "results.json"), JSON.stringify([{ scenarioID: "boundary", outcome: "passed", observed: { reps: 2 }, assertionResults: [] }]));
    await writeFile(path.join(output, "summary.json"), JSON.stringify({ outcomes: { passed: 1, failed: 0, inconclusive: 0, invalid: 0, notRun: 0 }, elapsedSeconds: 0.1 }));
    return { code: 0 };
  };
  try {
    const result = await runPlan({ root, planPath: inputPath, sim: "343F77B5-4F5B-41D7-99DB-9372183E6046",
      now: new Date("2026-11-07T12:34:56Z"), suffix: "a1b2c3", runner });
    assert.equal(calls.length, 1);
    assert.deepEqual(calls[0].argv, args);
    assert.equal(calls[0].config.env.TEST_RUNNER_FMP_LAB_PLAN, inputPath);
    assert.equal(calls[0].config.env.FMP_LAB_MODE, "pipeline");
    assert.match(calls[0].config.env.FMP_LAB_EXECUTION_REVISION, /unknown|dirty-/);
    assert.equal(result.runID, "20261107-123456-a1b2c3");
    assert.match(result.text, /total 1 · passed 1/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("invalid plans, existing runs, and symlinked roots are rejected before execution", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-lab-safe-root-"));
  const outside = await mkdtemp(path.join(tmpdir(), "fmp-lab-outside-"));
  const inputPath = path.join(root, "input.json");
  await writeFile(inputPath, JSON.stringify(plan()));
  let calls = 0;
  const runner = async () => { calls += 1; };
  try {
    const malformed = plan();
    malformed.scenarios[0].mutations[0].reps = [];
    await writeFile(inputPath, JSON.stringify(malformed));
    await assert.rejects(runPlan({ root, planPath: inputPath, now: new Date("2026-11-07T12:34:56Z"), suffix: "bad123", runner }), /Invalid Movement Lab plan/);
    assert.equal(calls, 0);
    await assert.rejects(lstat(path.join(root, "diagnostics")), { code: "ENOENT" });

    await writeFile(inputPath, JSON.stringify(plan()));
    const safeID = "20261107-123456-a1b2c3";
    const runs = path.join(root, "diagnostics", "movement-lab", "runs");
    await mkdir(runs, { recursive: true });
    await mkdir(path.join(runs, safeID));
    await assert.rejects(runPlan({ root, planPath: inputPath, now: new Date("2026-11-07T12:34:56Z"), suffix: "a1b2c3", runner }), /refuses to reuse existing/);
    assert.equal(calls, 0);

    const linkedRoot = await mkdtemp(path.join(tmpdir(), "fmp-lab-linked-root-"));
    try {
      await symlink(outside, path.join(linkedRoot, "diagnostics"));
      await assert.rejects(createFreshRunDirectory(linkedRoot, safeID), /Unsafe Movement Lab directory component/);
    } finally { await rm(linkedRoot, { recursive: true, force: true }); }
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});

test("preset manifest emission uses an existing safe run directory and refuses replacement", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-lab-presets-"));
  try {
    const runDir = await createFreshRunDirectory(root, "20261107-123456-a1b2c3");
    const runner = async (argv, config) => {
      assert.ok(argv.includes("-only-testing:PostureAnalysisAppTests/MovementLabTests/testEmitBuiltInPresetsManifest"));
      await writeFile(config.env.FMP_LAB_PRESETS_OUT, JSON.stringify({ presets: [{ id: "air_squat", plan: plan() }] }), { flag: "wx" });
    };
    const manifest = await emitPresetManifest({ root, runDir, runner });
    assert.equal(manifest.presets[0].id, "air_squat");
    await assert.rejects(emitPresetManifest({ root, runDir, runner }), /refuses to overwrite/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("timeout sends TERM then KILL to the process group and settles with inherited pipes", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-lab-timeout-"));
  const bin = path.join(root, "bin");
  await mkdir(bin);
  const fake = path.join(bin, "xcodebuild");
  await writeFile(fake, "#!/bin/sh\ntrap '' TERM\n(sleep 30) &\nwait\n", { mode: 0o755 });
  await chmod(fake, 0o755);
  const started = Date.now();
  try {
    await assert.rejects(invokeXcodebuild([], { cwd: root,
      env: { ...process.env, PATH: `${bin}${path.delimiter}${process.env.PATH}` },
      timeoutMs: 100, termGraceMs: 80, killWaitMs: 100 }), /exceeded 0 seconds/);
    assert.ok(Date.now() - started < 2_000, `timeout took ${Date.now() - started}ms`);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("summary output lists only nonpassing scenarios and one totals line", () => {
  const fixture = [
    { scenarioID: "ok", outcome: "passed", observed: { reps: 5 } },
    { scenarioID: "missed", outcome: "failed", observed: { reps: 4 }, assertionResults: [{ passed: false, detail: "expected 5; observed 4" }] },
    { scenarioID: "unknown", outcome: "inconclusive", observed: { reps: null } },
  ];
  const text = formatSummary(fixture, { outcomes: { passed: 1, failed: 1, inconclusive: 1, invalid: 0, notRun: 0 }, elapsedSeconds: 1.25 });
  assert.equal(text.split("\n").length, 3);
  assert.doesNotMatch(text, /^ok:/m);
  assert.match(text, /^missed: failed · reps 4 · expected 5; observed 4$/m);
  assert.match(text, /^unknown: inconclusive · reps unknown$/m);
  assert.match(text, /^total 3 · passed 1 · failed 1 · inconclusive 1 · invalid 0 · notRun 0 · 1\.25s$/m);
});

test("inspect uses actual frame rep payloads, top-level viewer records, and inclusive windows", async () => {
  const fixtureURL = new URL("./fixtures/lab-session-recording.json", import.meta.url);
  const records = JSON.parse(await readFile(fixtureURL, "utf8"));
  const frame = records.find((record) => record.k === "f");
  assert.ok(frame.out.some((item) => item.rep?.sides?.length === 2));
  assert.deepEqual(parseWindow("4.8-5"), { from: 4.8, to: 5 });
  assert.throws(() => parseWindow("5-4"), /must not exceed/);
  assert.equal(filterRecords(records, { from: 4.8, to: 5 }).length, 6);

  const scenario = { id: "boundary", assertions: [{ kind: "repCount", equals: 5 }] };
  const result = { scenarioID: "boundary", outcome: "passed", revision: 1,
    observed: { reps: 5, rejections: [], signals: [], framingChanges: [], cues: [] },
    assertionResults: [{ assertionIndex: 0, passed: true, detail: "expected 5; observed 5" }] };
  const output = renderInspection({ scenario, result, records, window: { from: 4.8, to: 5 } });
  assert.match(output, /PASS · expected 5; observed 5/);
  assert.match(output, /rep completed · left\+right/);
  assert.match(output, /state exercising reps=5/);
  assert.match(output, /framing reliable/);

  const session = Session.fromText(recordsToFileText(records.map((record) => JSON.stringify(record))));
  assert.equal(session.reps.length, 1);
  assert.equal(session.events.filter((event) => event.type === "rep").length, 1);
  assert.ok(session.states.length > 0);
  assert.ok(session.framingSpans.some((span) => span.ok));

  const root = await mkdtemp(path.join(tmpdir(), "fmp-lab-inspect-"));
  const runID = "20261107-123456-a1b2c3";
  const runDir = path.join(root, "diagnostics", "movement-lab", "runs", runID);
  await mkdir(path.join(runDir, "scenarios"), { recursive: true });
  await writeFile(path.join(runDir, "plan.json"), JSON.stringify({ scenarios: [scenario] }));
  await writeFile(path.join(runDir, "results.json"), JSON.stringify([result]));
  await writeFile(path.join(runDir, "summary.json"), JSON.stringify({ outcomes: { passed: 1 } }));
  await writeFile(path.join(runDir, "scenarios", "boundary.json"), JSON.stringify(records));
  try {
    const inspected = await inspectRun({ root, runID, scenarioID: "boundary", window: { from: 4.8, to: 5 } });
    assert.match(inspected, /rep completed/);
    await assert.rejects(inspectRun({ root, runID: "../outside" }), /traversal/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("ordinary inspect bounds assertions, observed values, reasons, and events under one budget", () => {
  const scenario = { id: "huge", assertions: Array.from({ length: 100 }, (_, index) => ({ kind: "spokenCue", textContains: `cue-${index}`, present: true })) };
  const result = {
    scenarioID: "huge", outcome: "invalid", revision: 2,
    invalidReasons: ["finite-coordinate rejection".repeat(100)],
    observed: { reps: 0, rejections: Array.from({ length: 100 }, () => "reason".repeat(100)),
      signals: Array.from({ length: 100 }, () => "signal"), framingChanges: Array.from({ length: 100 }, () => "stepBackFullBody"),
      cues: Array.from({ length: 100 }, () => "spoken cue".repeat(100)) },
    assertionResults: [],
  };
  const records = Array.from({ length: 100 }, (_, index) => ({ k: "e", t: index, type: `event-${index}` }));
  const output = renderInspection({ scenario, result, records });
  assert.ok(output.split("\n").length <= 58);
  assert.ok(output.length <= 11_800);
  assert.match(output, /Invalid reasons \(1\)/);
  assert.match(output, /finite-coordinate rejection/);
  assert.match(output, /more lines omitted; pass --full/);
  const expanded = renderInspection({ scenario, result, records, full: true });
  assert.ok(expanded.split("\n").length > output.split("\n").length);
});

test("inspect escapes multiline details before enforcing the rendered line budget", () => {
  const scenario = { id: "multiline", assertions: [{ kind: "repCount", equals: 1 }] };
  const result = {
    scenarioID: "multiline", outcome: "failed", revision: 1,
    observed: { reps: 0, rejections: [], signals: [], framingChanges: [], cues: ["cue\n".repeat(100)] },
    assertionResults: [{ assertionIndex: 0, passed: false, detail: "detail\n".repeat(100) }],
  };
  const output = renderInspection({ scenario, result, records: [] });
  assert.ok(output.split("\n").length <= 58);
  assert.ok(output.includes("detail\\n"));
  assert.ok(output.includes("cue\\n"));
  assert.ok(output.length <= 11_800);
});

