import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { buildCoverageModel } from "../lib/lab/coverage.mjs";
import { chooseKeyframe } from "../lib/lab/keyframe.mjs";
import { createServer } from "../server.mjs";
import { createCoveragePlaybackNavigator, installCoverageViewElements,
  renderCoverageMatrix, renderCoverageScenarioRow, renderCoverageThumbnail, bindCoverageSeekHandler } from "../public/lab/coverage.mjs";

const RUN_OLD = "20261108-090000-c3d4";
const RUN_MIDDLE = "20261108-100000-a1b2";
const RUN_NEW = "20261108-110000-e5f6";
const JOINTS = ["leftHip", "rightHip", "leftKnee", "rightKnee", "leftAnkle", "rightAnkle"];

function navigationTab(section) {
  const tab = {
    dataset: { labView: section }, attributes: {}, activeClasses: new Set(),
    textContent: section === "runs" ? "Runs" : section === "recordings" ? "Session recordings" : "Scenario coverage",
    setAttribute(name, value) { this.attributes[name] = value; },
  };
  tab.classList = { toggle(name, active) { if (active) tab.activeClasses.add(name); else tab.activeClasses.delete(name); } };
  return tab;
}

test("coverage tab is injected once into the persistent shared section navigation", async () => {
  const html = await readFile(new URL("../public/index.html", import.meta.url), "utf8");
  const navStart = html.indexOf('<nav class="lab-view-tabs"');
  const navEnd = html.indexOf("</nav>", navStart);
  const staticNav = html.slice(navStart, navEnd);
  assert.equal((staticNav.match(/data-lab-view=/g) ?? []).length, 2);
  assert.equal((staticNav.match(/data-lab-view="runs"/g) ?? []).length, 1);
  assert.equal((staticNav.match(/data-lab-view="recordings"/g) ?? []).length, 1);

  const runs = navigationTab("runs");
  const recordings = navigationTab("recordings");
  const navigation = {
    hidden: false,
    tabs: [runs, recordings],
    querySelector(selector) {
      return selector === '[data-lab-view="recordings"]' ? recordings : null;
    },
    insertBefore(button, before) {
      this.tabs.splice(this.tabs.indexOf(before), 0, button);
    },
  };
  const dashboard = {
    coverageView: null,
    querySelector(selector) {
      if (selector === ".lab-layout") return layout;
      if (selector === "#labCoverageView") return this.coverageView;
      return null;
    },
  };
  const layout = {
    insertAdjacentElement(position, element) {
      assert.equal(position, "afterend");
      dashboard.coverageView = element;
    },
  };
  const doc = {
    getElementById(id) { return id === "labDashboard" ? dashboard : null; },
    querySelector(selector) { return selector === ".lab-view-tabs" ? navigation : null; },
    createElement(tagName) {
      return { tagName, dataset: {}, attributes: {}, setAttribute(name, value) { this.attributes[name] = value; } };
    },
  };

  const installed = installCoverageViewElements(doc);
  assert.ok(installed);
  assert.equal(installed.button.dataset.labView, "coverage");
  assert.equal(installed.button.textContent, "Scenario coverage");
  assert.deepEqual(navigation.tabs.map((tab) => tab.dataset.labView), ["runs", "coverage", "recordings"]);
  assert.equal(navigation.tabs.filter((tab) => tab.dataset.labView === "coverage").length, 1);
  assert.equal(installCoverageViewElements(doc), null, "installing again does not duplicate the tab");
});

function scenario(id, revision = 1, overrides = {}) {
  return {
    id, exercise: "air_squat", category: "alignment", purpose: `Purpose for ${id}`,
    canonicalRevision: "guide-test", mutations: [{ kind: "jointOffset", joints: ["leftKnee"], dx: -0.05, dy: 0,
      peak: 1, rise: 0.2, fall: 0.2, strength: 1 }], assertions: [], revision, ...overrides,
  };
}

function storedRun(id, createdAt, scenarios, outcomes = {}) {
  return {
    id, summary: { id, createdAt },
    plan: { scenarios },
    results: scenarios.filter((item) => outcomes[item.revision]).map((item) => ({
      scenarioID: item.id, revision: item.revision, outcome: outcomes[item.revision], observed: {}, assertionResults: [],
    })),
  };
}

function coverageRecords({ kneeX = 120, bottomY = 250, asymmetry = 0 } = {}) {
  const frames = [
    { t: 0, hip: 100, leftHip: 100, rightHip: 100, kneeX },
    { t: 1, hip: 180, leftHip: 180 + asymmetry, rightHip: 180, kneeX: kneeX + 15 },
    { t: 2, hip: bottomY, leftHip: bottomY, rightHip: bottomY, kneeX: kneeX + 30 },
    { t: 3, hip: 160, leftHip: 160, rightHip: 160, kneeX: kneeX + 10 },
  ];
  return [
    { k: "header", schema: "fmp.workout-session/1", jointOrder: JOINTS, exercises: {}, framing: { minimumConfidence: 0.3 } },
    ...frames.map((frame) => ({
      k: "f", t: frame.t, ts: frame.t, wh: [300, 600],
      j: [
        [100, frame.leftHip, 0.9], [200, frame.rightHip, 0.9], [100, 220 + frame.t * 8, 0.9],
        [200, 220 + frame.t * 8, 0.9], [100, 300, 0.9], [200, 300, 0.9],
      ].map((joint, index) => index === 2 ? [frame.kneeX, joint[1], joint[2]] : joint),
    })),
    { k: "e", t: 1, type: "rep", epoch: 1, sides: ["left", "right"] },
    { k: "e", t: 2, type: "rep", epoch: 1, sides: ["left", "right"] },
    { k: "state", t: 1.1, reps: 1 },
    { k: "state", t: 2.1, reps: 2 },
    { k: "end", t: 3 },
  ];
}

test("coverage aggregates the newest result per scenario id and revision and marks empty cells not tested", () => {
  const rev1 = scenario("knee-edit", 1);
  const rev2 = scenario("knee-edit", 2, { purpose: "Revised knee edit", category: "alignment" });
  const model = buildCoverageModel([
    storedRun(RUN_OLD, "2026-11-08T09:00:00Z", [rev1], { 1: "failed" }),
    storedRun(RUN_MIDDLE, "2026-11-08T10:00:00Z", [rev1], { 1: "passed" }),
    storedRun(RUN_NEW, "2026-11-08T11:00:00Z", [rev2], { 2: "notRun" }),
  ]);
  const cell = model.cells.find((item) => item.exercise === "air_squat" && item.category === "alignment");
  assert.equal(model.label, "Scenario coverage");
  assert.equal(cell.scenarios.length, 2);
  assert.equal(cell.status, "mixed");
  assert.equal(cell.counts.passed, 1);
  assert.equal(cell.counts["not tested"], 1);
  assert.equal(cell.scenarios.find((item) => item.revision === 1).status, "passed");
  assert.equal(cell.scenarios.find((item) => item.revision === 2).status, "not tested");
  assert.equal(model.cells.find((item) => item.exercise === "air_squat" && item.category === "tracking").status, "not tested");
  assert.equal(model.cells.find((item) => item.exercise === "air_squat" && item.category === "tracking").scenarios.length, 0);
  const matrix = renderCoverageMatrix(model);
  assert.match(matrix, /Tracking/);
  assert.match(matrix, /not tested/);
  const expanded = renderCoverageMatrix(model, { expanded: new Set(["air_squat|alignment"]) });
  assert.match(expanded, /coverage-drilldown/);
  assert.match(expanded, /knee-edit/);
  const passedOnly = renderCoverageMatrix(model, { status: "passed" });
  assert.doesNotMatch(passedOnly, /class="coverage-cell not-tested"/);
});

test("keyframes follow each mutation peak, event, or window boundary and label event types", () => {
  const records = coverageRecords({ bottomY: 250, asymmetry: 35 });
  const cases = [
    [{ kind: "jointOffset", joints: ["leftKnee"], peak: 1 }, 1, "joint offset", "leftKnee"],
    [{ kind: "depthScale", scale: 0.5 }, 2, "depth", "leftHip"],
    [{ kind: "asymmetry", side: "left", amount: 0.1 }, 1, "asymmetry", "leftHip"],
    [{ kind: "tempo", scale: 1.5, reps: [2] }, 2, "tempo", null],
    [{ kind: "pause", at: 1 }, 1, "pause", null],
    [{ kind: "frameGap", at: 1.5, duration: 0.5 }, 2, "gap", null],
    [{ kind: "dropout", joints: ["leftKnee"], from: 0.9, to: 1.1 }, 1, "missing landmark", "leftKnee"],
    [{ kind: "confidence", joints: ["rightKnee"], from: 0.9, to: 1.1, value: 0.2 }, 1, "confidence", "rightKnee"],
    [{ kind: "framing", scale: 1.2, offsetX: 0, offsetY: 0 }, 2, "framing", "leftHip"],
  ];
  for (const [mutation, expectedIndex, expectedType, affected] of cases) {
    const selected = chooseKeyframe({ id: "case", revision: 1, mutations: [mutation] }, records);
    assert.equal(selected.frameIndex, expectedIndex, mutation.kind);
    assert.equal(selected.annotation, expectedType, mutation.kind);
    if (affected) assert.ok(selected.affectedJoints.includes(affected), mutation.kind);
  }
  assert.match(chooseKeyframe({ mutations: [{ kind: "dropout", joints: ["leftKnee"], from: 1, to: 2 }] }, records).descriptor, /window start/);
  assert.match(chooseKeyframe({ mutations: [{ kind: "frameGap", at: 1.5, duration: 0.5 }] }, records).descriptor, /resume/);
  assert.match(chooseKeyframe({ mutations: [{ kind: "tempo", scale: 1.5 }] }, records).descriptor, /rep 1 boundary/);
});

function repeatedDepthRecords(hipHeights) {
  return [
    { k: "header", schema: "fmp.workout-session/1", jointOrder: JOINTS, exercises: {} },
    ...hipHeights.map((hipY, index) => ({
      k: "f", t: index, ts: index, wh: [300, 600],
      j: [[100, hipY, 0.9], [200, hipY, 0.9], [100, hipY + 70, 0.9], [200, hipY + 70, 0.9], [100, 400, 0.9], [200, 400, 0.9]],
    })),
  ];
}

test("depth keyframe stays within the selected repetition when another repetition is deeper", () => {
  const recording = repeatedDepthRecords([100, 340, 100, 210, 100]);
  const reference = repeatedDepthRecords([100, 340, 100, 340, 100]);
  const selected = chooseKeyframe({ id: "shallow-second-rep", revision: 1, reps: 2,
    mutations: [{ kind: "depthScale", scale: 0.5, reps: [2] }] }, recording, reference);
  assert.equal(selected.frameIndex, 3);
  assert.equal(selected.timestamp, 3);
  assert.match(selected.descriptor, /rep 2 peak/);
});

test("coverage rows keep the rep count so selective-depth thumbnails land on the mutated repetition", () => {
  const scenario = { id: "shallow-second-of-three", revision: 1, exercise: "air_squat", category: "depth_rom", reps: 3,
    mutations: [{ kind: "depthScale", scale: 0.5, reps: [2] }], assertions: [] };
  const model = buildCoverageModel([{ id: "run-1", plan: { scenarios: [scenario] }, results: [] }]);
  const row = model.scenarios.find((item) => item.id === scenario.id);
  assert.equal(row?.reps, 3);
  const recording = repeatedDepthRecords([100, 340, 100, 210, 100, 340, 100]);
  const reference = repeatedDepthRecords([100, 340, 100, 340, 100, 340, 100]);
  const selected = chooseKeyframe(row, recording, reference);
  assert.equal(selected.frameIndex, 3);
});

test("same-exercise scenarios with different mutations render distinctive stored-frame SVGs", () => {
  const reference = coverageRecords();
  const offsetRecording = coverageRecords({ kneeX: 90 });
  const deepRecording = coverageRecords({ bottomY: 310 });
  const offset = renderCoverageThumbnail(scenario("offset", 1, {
    mutations: [{ kind: "jointOffset", joints: ["leftKnee"], peak: 1 }],
  }), offsetRecording, reference);
  const depth = renderCoverageThumbnail(scenario("depth", 1, {
    mutations: [{ kind: "depthScale", scale: 0.5 }],
  }), deepRecording, reference);
  const offsetSVG = offset.html.match(/<svg[\s\S]*?<\/svg>/g) ?? [];
  const depthSVG = depth.html.match(/<svg[\s\S]*?<\/svg>/g) ?? [];
  assert.notEqual(offsetSVG.at(-1), depthSVG.at(-1));
  assert.match(offset.html, /Reference/);
  assert.match(offset.html, /Mutated/);
  assert.match(offset.html, /left knee · peak 1\.0 s/);
  assert.match(depth.html, /maximum hip drop · peak 2\.0 s/);
  assert.match(offset.html, /coverage-joint-highlight/);
});

test("coverage row escapes scenario text and thumbnail click wiring carries the exact seek target", () => {
  const hostile = scenario('<img src=x onerror="bad">', 1, { purpose: "<script>unsafe</script>" });
  const html = renderCoverageScenarioRow(hostile, { thumbnailHTML: "<button>thumbnail</button>" });
  assert.doesNotMatch(html, /<img src=x/);
  assert.doesNotMatch(html, /<script>/);
  const thumbnail = renderCoverageThumbnail(scenario("seek-case", 1, { sourceRunID: RUN_NEW,
    mutations: [{ kind: "jointOffset", joints: ["leftKnee"], peak: 1 }] }), coverageRecords());
  assert.match(thumbnail.html, /data-lab-seek-run="20261108-110000-e5f6"/);
  assert.match(thumbnail.html, /data-lab-seek-time="1"/);

  let listener;
  let target;
  let prevented = false;
  bindCoverageSeekHandler({ addEventListener(type, callback) { assert.equal(type, "click"); listener = callback; } }, (value) => { target = value; });
  const button = { dataset: { labSeekRun: RUN_NEW, labSeekScenario: "knee-edit", labSeekTime: "2.125" } };
  listener({ target: { closest: (selector) => selector === "[data-lab-seek-run]" ? button : null }, preventDefault() { prevented = true; } });
  assert.deepEqual(target, { runID: RUN_NEW, scenarioID: "knee-edit", timestamp: 2.125 });
  assert.equal(prevented, true);
});

test("clicking a nonfirst thumbnail in the selected run waits for that run before selecting and seeking", async () => {
  const displayedRunID = RUN_NEW;
  let resolveRun;
  let selectedScenario = "first";
  let sought = null;
  let navigation;
  const steps = [];
  const navigate = createCoveragePlaybackNavigator({
    activateRuns() { steps.push("activate runs"); },
    loadRun(runID) {
      steps.push("load requested run");
      assert.equal(runID, displayedRunID);
      return new Promise((resolve) => { resolveRun = resolve; });
    },
    async selectScenario(runID, scenarioID) {
      assert.equal(runID, displayedRunID);
      steps.push(`select ${scenarioID}`);
      selectedScenario = scenarioID;
      return true;
    },
    async seek(selection) { steps.push("seek"); sought = selection; return true; },
  });
  let click;
  bindCoverageSeekHandler({ addEventListener(type, listener) { assert.equal(type, "click"); click = listener; } },
    (selection) => { navigation = navigate(selection); });
  const thumbnail = { dataset: { labSeekRun: displayedRunID, labSeekScenario: "second", labSeekTime: "2.125" } };
  click({ target: { closest: () => thumbnail }, preventDefault() {} });
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(steps, ["activate runs", "load requested run"]);
  assert.equal(selectedScenario, "first");
  assert.equal(sought, null);

  resolveRun({ summary: { id: displayedRunID }, plan: { scenarios: [{ id: "first" }, { id: "second" }] } });
  assert.equal(await navigation, true);
  assert.equal(selectedScenario, "second");
  assert.deepEqual(sought, { runID: displayedRunID, scenarioID: "second", timestamp: 2.125 });
  assert.deepEqual(steps, ["activate runs", "load requested run", "select second", "seek"]);
});

function apiScenario() { return scenario("api-case", 1, { mutations: [] }); }

async function writeAPIArtifact(root) {
  const runID = RUN_NEW;
  const directory = path.join(root, "diagnostics", "movement-lab", "runs", runID);
  const scenariosDirectory = path.join(directory, "scenarios");
  await mkdir(scenariosDirectory, { recursive: true });
  const plan = { schemaVersion: 1, id: "api", title: "API", purpose: "Synthetic API test", scenarios: [apiScenario()] };
  await writeFile(path.join(directory, "plan.json"), JSON.stringify(plan));
  await writeFile(path.join(directory, "summary.json"), JSON.stringify({ outcomes: { passed: 1 } }));
  await writeFile(path.join(directory, "results.json"), JSON.stringify([{ scenarioID: "api-case", revision: 1, outcome: "passed" }]));
  const records = coverageRecords();
  await writeFile(path.join(scenariosDirectory, "api-case.json"), JSON.stringify(records));
  await writeFile(path.join(scenariosDirectory, "api-case.reference.json"), JSON.stringify(records));
}

function apiRequest(server, { method = "GET", url, host = "127.0.0.1", replayHeader = null }) {
  return new Promise((resolve) => {
    const request = new EventEmitter();
    request.method = method;
    request.url = url;
    request.headers = { host };
    if (replayHeader != null) request.headers["x-fmp-replay"] = replayHeader;
    const response = {
      status: null, body: "",
      writeHead(status) { this.status = status; },
      end(body) { this.body = Buffer.isBuffer(body) ? body.toString("utf8") : String(body ?? ""); resolve(this); },
    };
    server.emit("request", request, response);
  });
}

test("coverage API is read-only, returns stored scenarios, and retains the local Host guard", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "fmp-lab-coverage-api-"));
  try {
    await writeAPIArtifact(root);
    const server = createServer({ root });
    const response = await apiRequest(server, { url: "/api/lab/coverage" });
    assert.equal(response.status, 200);
    const model = JSON.parse(response.body);
    assert.equal(model.label, "Scenario coverage");
    assert.equal(model.scenarios[0].id, "api-case");

    const forbidden = await apiRequest(server, { url: "/api/lab/coverage", host: "untrusted.example" });
    assert.equal(forbidden.status, 403);
    const mutation = await apiRequest(server, { method: "POST", url: "/api/lab/coverage", replayHeader: "1" });
    assert.equal(mutation.status, 405);
    const moduleFile = await apiRequest(server, { url: "/lab/coverage.mjs" });
    assert.equal(moduleFile.status, 200);
    const keyframeModule = await apiRequest(server, { url: "/lib/lab/keyframe.mjs" });
    assert.equal(keyframeModule.status, 200);
  } finally { await rm(root, { recursive: true, force: true }); }
});
