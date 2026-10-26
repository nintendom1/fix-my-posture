import test from "node:test";
import assert from "node:assert/strict";
import { Session } from "../lib/session.mjs";
import * as views from "../public/views.mjs";
import { records, JOINTS } from "./fixtures.mjs";

const EVIL = "\"><img src=x onerror=alert(1)><script>alert(2)</script>";

/** A recording that tries to inject markup through every string it carries. */
function hostileSession() {
  const items = records().map((record) => structuredClone(record));
  const header = items[0];
  header.plan = { name: EVIL };
  header.exercises.push_up.name = EVIL;
  header.jointOrder = [...JOINTS.slice(0, -1), EVIL];
  for (const record of items) {
    if (record.k === "f") {
      record.rd.left.zone = EVIL;
      record.fr.g = EVIL;
      record.sig = [EVIL];
      record.fv = { [EVIL]: EVIL };
      record.th.left.confirmed = EVIL;
      record.th.left.start = [EVIL, 1, 2, 3];
      if (record.j[6]) record.j[6] = [EVIL, "1e3", 0.5];
    }
    if (record.k === "e" && record.type === "framing") record.framing.g = EVIL;
    if (record.k === "e" && record.type === "speak") record.text = EVIL;
    if (record.k === "e" && record.type === "command") { record.command = EVIL; record.phrase = EVIL; }
    if (record.k === "state") { record.phase = EVIL; record.set = EVIL; }
    if (record.k === "marker") { record.text = EVIL; record.source = EVIL; record.t = EVIL; }
  }
  return new Session(items);
}

/** Escaped text such as `&lt;img onerror=…` is inert; a real tag or an attribute breakout is not. */
function assertInert(html, where) {
  assert.doesNotMatch(html, /<img|<script/i, `${where} lets a tag through`);
  assert.ok(!html.includes(EVIL), `${where} includes the hostile text unescaped`);
}

test("every view escapes strings from a hostile recording and note", () => {
  const session = hostileSession();
  const notes = [{ id: EVIL, t: 5, end: null, text: EVIL, author: EVIL }];
  const toggles = { mirror: true, thresholds: true, labels: true, angles: true };
  for (const index of [20, 50, 82, 85, 120]) {
    const frame = session.frames[index];
    assertInert(views.stageSVG(session, frame, { width: 1080, height: 1920, toggles, glow: "#fff", trail: [[frame, 0.2]] }), "stage");
    assertInert(views.stats(session, frame.t, frame, session.stateAt(frame.t)), "stats");
    assertInert(views.checks(session, index), "checks");
    assertInert(views.readings(frame), "readings");
    assertInert(views.confidence(session, frame, frame.t), "confidence");
  }
  assertInert(views.sessionOptions([{ id: EVIL, title: EVIL, startedAt: EVIL, markerCount: EVIL, isComplete: false }]), "session picker");
  assertInert(views.phaseLane(session), "phase lane");
  assertInert(views.framingLane(session), "tracking lane");
  assertInert(views.repLane(session), "rep lane");
  assertInert(views.issueLane(session), "issue lane");
  assertInert(views.noteLane(session, notes), "note lane");
  assertInert(views.notesList(session, notes), "notes list");
  assertInert(views.logRows(session.timeline.concat([{ t: EVIL, kind: EVIL, title: EVIL, detail: EVIL }])), "event log");
  assertInert(views.filters([EVIL], EVIL), "filters");
  const charts = views.charts(session, session.frames, [-1, 1]);
  for (const [name, svg] of Object.entries(charts)) assertInert(svg, `${name} chart`);
});

test("SVG coordinates are always numbers", () => {
  const session = hostileSession();
  const svg = views.stageSVG(session, session.frames[50], { width: 1080, height: 1920, toggles: { mirror: false, thresholds: true }, glow: "#fff" });
  for (const [, value] of svg.matchAll(/ (?:x|y|x1|x2|y1|y2|cx|cy|r)="([^"]*)"/g)) {
    assert.ok(Number.isFinite(Number(value)), `non-numeric coordinate ${value}`);
  }
});

test("the frame gap check uses camera timestamps, not when the coach handled the frame", () => {
  const items = records().map((record) => structuredClone(record));
  const frames = items.filter((record) => record.k === "f");
  // The coach handled frame 50 late (t jumps 0.5 s) but the camera captured it on time (ts +0.1 s).
  frames[50].t = frames[49].t + 0.5;
  frames[60].ts = frames[59].ts + 0.4;
  const session = new Session(items);
  const index = (frame) => session.frames.indexOf(frame);
  assert.match(views.checks(session, index(frames[50])), /pass">✓<\/span><span>Camera frame gap<\/span><span class="v pass">0\.10 s/);
  assert.match(views.checks(session, index(frames[60])), /fail">✗<\/span><span>Camera frame gap<\/span><span class="v fail">0\.40 s/);
});

test("the rep lane numbers counted reps and marks the ones the coach didn't count", () => {
  const items = records();
  items.push({ k: "e", t: 17, type: "rep", epoch: 0, ts: 1017, sides: ["left", "right"] });
  items.sort((a, b) => (a.k === "header" ? -1 : b.k === "header" ? 1 : (a.t ?? 0) - (b.t ?? 0)));
  const lane = views.repLane(new Session(items));
  assert.match(lane, /class="mark"[^>]*color:#3ddc97[^>]*>1<\/span>/);
  assert.match(lane, /class="mark"[^>]*title="0:17\.0 · sides left\+right · not counted"[^>]*>×<\/span>/);
  assert.equal((lane.match(/>×</g) ?? []).length, 1);
});
