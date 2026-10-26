import test from "node:test";
import assert from "node:assert/strict";
import { Session, parseRecords, normalizeFileText, renderExcerpt, sampleFrames, PRESETS, applyNote, emptyNotes,
  shortJoint, clock, estimateTokens } from "../lib/session.mjs";
import { ID, records, arrayText, linesText } from "./fixtures.mjs";

test("reads a closed JSON array, an unclosed one, and older JSON Lines alike", () => {
  const closed = parseRecords(arrayText());
  assert.equal(closed.records.length, records().length);
  assert.equal(closed.skipped, 0);
  assert.deepEqual(parseRecords(linesText()).records, closed.records);
  const crashed = arrayText().replace(/\n\]\n$/, "") + ",\n{\"k\":\"f\",\"t\":21,\"j\":[";
  const unclosed = parseRecords(crashed);
  assert.equal(unclosed.records.length, records().length, "every whole record survives a crash");
  assert.equal(unclosed.skipped, 1, "the record cut short is skipped");
});

test("normalizing gives a valid JSON array with one record per line", () => {
  const text = normalizeFileText(linesText());
  const parsed = JSON.parse(text);
  assert.equal(parsed.length, records().length);
  assert.ok(text.startsWith("[\n{\"k\":\"header\""));
  assert.equal(text.split("\n").length, records().length + 3);
  assert.equal(normalizeFileText(""), "[\n]\n");
});

test("the session model finds frames, state, exercise, and tracking losses", () => {
  const session = Session.fromText(arrayText());
  assert.equal(session.id, ID);
  assert.equal(session.title, "Push-Up");
  assert.equal(session.frames.length, 201);
  assert.deepEqual(session.imageSize, [1080, 1920]);
  assert.deepEqual(session.frames.at(-1).size, [1080, 1920], "the image size carries forward");
  assert.equal(session.duration, 20.5);
  assert.equal(session.isComplete, true);
  assert.equal(session.stateAt(14.9).reps, 0);
  assert.equal(session.stateAt(15).reps, 1);
  assert.equal(session.exerciseIDAt(5), "push_up");
  assert.deepEqual(session.focusJoints(5), ["leftShoulder", "rightShoulder", "leftWrist"]);
  assert.deepEqual(session.losses.map((loss) => [loss.start, loss.end]), [[8.25, 9.4]]);
  assert.equal(session.framingSpans[0].ok, false);
  assert.equal(session.framingSpans[0].wasReliable, false, "not tracking yet is not a loss");
  const titles = session.timeline.map((item) => `${item.t} ${item.title}`);
  assert.ok(titles.includes("8.25 Tracking lost"));
  assert.ok(titles.includes("1 Command: start"));
  assert.ok(titles.includes("15 Rep 1"), "the analyzer's event, counted by the coach");
  assert.deepEqual(session.reps.map((rep) => [rep.t, rep.outcome, rep.count]), [[15, "counted", 1]]);
  assert.ok(titles.includes("16 Marker (voice)"));
});

test("joints are seen, below the floor, estimated, or missing", () => {
  const session = Session.fromText(arrayText());
  const at = (t) => session.frameAt(t);
  assert.deepEqual(session.joint(at(5), "leftShoulder"), { name: "leftShoulder", x: 740.5, y: 713.25, c: 0.65, kind: "seen" });
  assert.equal(session.joint(at(8.2), "rightShoulder").kind, "seen");
  assert.deepEqual(session.joint(at(8.1), "rightShoulder"), { name: "rightShoulder", x: 401, y: 700, c: 0.22, kind: "low" });
  assert.equal(session.joint(at(8.5), "rightShoulder").kind, "missing");
  assert.equal(session.joint(at(12), "leftWrist").kind, "est");
  assert.equal(session.minConfidence(at(8.25), ["leftShoulder", "rightShoulder"]), 0.35);
  assert.equal(session.minConfidence(at(8.15), ["leftShoulder", "rightShoulder"]), 0.22);
  assert.equal(session.minConfidence(at(8.5), ["leftShoulder", "rightShoulder"]), 0);
});

test("sampled frames keep about the rate and every framing change", () => {
  const session = Session.fromText(arrayText());
  const frames = sampleFrames(session, 7, 10, 5);
  const times = frames.map((frame) => frame.t);
  assert.equal(times[0], 7);
  assert.ok(times.includes(8.3), "the frame where framing is lost is kept");
  assert.ok(times.includes(9.4), "and the frame where it comes back");
  for (const [a, b] of times.slice(1).map((t, i) => [times[i], t])) assert.ok(b - a <= 0.21, `${a} → ${b}`);
  assert.equal(sampleFrames(session, 0, 20, 0).length, 0, "rate 0 is events only");
  assert.ok(sampleFrames(session, 14, 16, 1).some((frame) => frame.t === 15), "a counted rep's frame is always kept");
});

test("an excerpt has the window, notes, tuning, events, and a frame table", () => {
  const session = Session.fromText(arrayText());
  const notes = [{ t: 8.4, text: "shoulders vanish", author: "you" }, { t: 30, text: "outside", author: "you" }];
  const text = renderExcerpt(session, { from: 7.5, to: 10, options: PRESETS.rep, notes });
  assert.match(text, /^# FMP replay excerpt · Push-Up · 2027-01-15 08:00/);
  assert.match(text, /window 0:07\.5–0:10\.0 \(2\.5 s\) · 5 Hz · Rep counting/);
  assert.match(text, /- 0:08\.4 \(you\): shoulders vanish/);
  assert.doesNotMatch(text, /outside/);
  assert.match(text, /tuning: downMaxRatio=0\.5 maximumSampleGap=0\.28 upMinRatio=0\.8/);
  assert.match(text, /0:08\.3 Tracking lost — stepBackFloor/);
  assert.match(text, /^t,frm,cnt,g,LS,RS,LW,L\.sig,L\.elb,L\.zone,R\.sig,R\.elb,R\.zone,L\.startY,L\.topY,L\.lock,R\.startY,R\.topY,R\.lock,rep$/m);
  assert.match(text, /^8\.1,ok,1,,\.65 741 713,lo\.22 401 700,\.74 813 1231,/m, "a joint below the floor shows its confidence");
  assert.match(text, /^8\.5,LOST,0,,-,-,-,/m);
  const flow = renderExcerpt(session, { from: 0, to: 20.5, options: PRESETS.flow });
  assert.doesNotMatch(flow, /## Frames/);
  assert.match(flow, /## Events/);
  assert.ok(estimateTokens(text) > 100 && estimateTokens(text) < 2000);
});

test("notes are added, edited, and deleted by id, in time order", () => {
  let document = emptyNotes(ID);
  document = applyNote(document, { id: "b", t: 9, text: "later" }, "2027-01-01T00:00:00Z");
  document = applyNote(document, { id: "a", t: 2, end: 3, text: "range", author: "claude" }, "2027-01-01T00:00:01Z");
  document = applyNote(document, { id: "b", t: 9, text: "edited" }, "2027-01-01T00:00:02Z");
  assert.deepEqual(document.notes.map((n) => [n.id, n.text, n.author, n.end]), [["a", "range", "claude", 3], ["b", "edited", "you", null]]);
  assert.equal(document.notes[1].createdAt, "2027-01-01T00:00:00Z");
  assert.equal(document.notes[1].updatedAt, "2027-01-01T00:00:02Z");
  document = applyNote(document, { id: "a", t: 2, deleted: true });
  assert.deepEqual(document.notes.map((n) => n.id), ["b"]);
});

test("names and clocks match the app's report", () => {
  assert.equal(shortJoint("leftShoulder"), "LS");
  assert.equal(shortJoint("rightAnkle"), "RA");
  assert.equal(shortJoint("nose"), "Nose");
  assert.equal(clock(116.44), "1:56.4");
  assert.equal(clock(58, false), "0:58");
});

test("alternative joint sets use whichever alternative is visible, as framing does", () => {
  const items = records().map((record) => structuredClone(record));
  const exercise = items[0].exercises.push_up;
  exercise.required = [];
  exercise.anyOfRequired = [["leftShoulder", "leftElbow"], ["rightShoulder", "rightWrist"]];
  for (const frame of items.filter((record) => record.k === "f")) {
    frame.j = frame.j.map(() => null);
    frame.j[7] = [400, 700, 0.8];
    frame.j[11] = [300, 1240, 0.7];
  }
  const session = new Session(items);
  const frame = session.frameAt(5);
  assert.deepEqual(session.requiredJoints(frame), ["rightShoulder", "rightWrist"]);
  assert.deepEqual(session.weakestRequired(frame), { name: "rightWrist", value: 0.7, kind: "seen" });
});

test("guidance changes while tracking stays lost are kept", () => {
  const items = records().map((record) => structuredClone(record));
  items.push({ k: "e", t: 8.85, type: "framing", framing: { ok: false, g: "stepIntoViewFloor" } });
  items.push({ k: "e", t: 0.5, type: "framing", framing: { ok: false, g: "stepIntoViewFloor" } });
  for (const frame of items.filter((record) => record.k === "f")) {
    if (frame.t >= 8.85 && frame.t < 9.4) frame.fr.g = "stepIntoViewFloor";
  }
  items.sort((a, b) => (a.k === "header" ? -1 : b.k === "header" ? 1 : (a.t ?? 0) - (b.t ?? 0)));
  const session = new Session(items);
  assert.deepEqual(session.losses.map((loss) => [loss.start, loss.end, loss.guidances]), [[8.25, 9.4, ["stepBackFloor", "stepIntoViewFloor"]]]);
  const titles = session.timeline.map((item) => `${item.t} ${item.title} ${item.detail}`);
  assert.ok(titles.includes("0.5 Not tracking stepIntoViewFloor"), "the first guidance is kept");
  assert.ok(titles.includes("8.85 Guidance stepIntoViewFloor"));
  assert.ok(sampleFrames(session, 8, 10, 2).some((frame) => frame.t === 8.9), "a sampled excerpt keeps the guidance change");
});

test("an excerpt says what state was in force when its window starts", () => {
  const session = Session.fromText(arrayText());
  const quiet = renderExcerpt(session, { from: 3, to: 5, options: PRESETS.flow });
  assert.match(quiet, /## State at the window start\nphase exercising · exercise push_up · set 1 · reps 0 · counting off · framing reliable/);
  assert.match(quiet, /## Events \(0\)/);
  const later = renderExcerpt(session, { from: 16, to: 18, options: PRESETS.flow });
  assert.match(later, /reps 1/);
});

test("pipeline controls in the window are listed with the events", () => {
  const items = records().map((record) => structuredClone(record));
  items.push({ k: "pipe", t: 9.5, control: "counting", counting: true });
  items.sort((a, b) => (a.k === "header" ? -1 : b.k === "header" ? 1 : (a.t ?? 0) - (b.t ?? 0)));
  const text = renderExcerpt(new Session(items), { from: 9, to: 10, options: PRESETS.rep });
  assert.match(text, /0:09\.5 Pipeline: counting — on/);
});

test("an excerpt across two exercises keeps both exercises' joints and labels each row", () => {
  const items = records().map((record) => structuredClone(record));
  items[0].exercises.air_squat = { name: "Air Squat", cameraView: "front", required: ["leftKnee"], anyOfRequired: [], focus: ["leftKnee", "leftAnkle"] };
  items.push({ k: "pipe", t: 10, control: "exercise", exercise: "air_squat", cameraView: "front", epoch: 2 });
  items.sort((a, b) => (a.k === "header" ? -1 : b.k === "header" ? 1 : (a.t ?? 0) - (b.t ?? 0)));
  const text = renderExcerpt(new Session(items), { from: 9.5, to: 10.5, options: PRESETS.rep });
  assert.match(text, /^t,ex,frm,cnt,g,LS,RS,LW,LK,LA,/m);
  assert.match(text, /^9\.5,push_up,/m);
  assert.match(text, /^10\.5,air_squat,/m);
});

test("each analyzer rep is classified by what the coach did with it", () => {
  const header = records()[0];
  const state = (t, fields) => ({ k: "state", t, phase: "exercising", ex: "push_up", set: 1, reps: 0, counting: true, epoch: 1,
    sideReps: { left: 0, right: 0 }, ...fields });
  const rep = (t, sides, epoch = 1) => ({ k: "e", t, type: "rep", epoch, ts: 1000 + t, sides });
  const session = new Session([
    header,
    state(1, {}),
    // Arms counted one at a time: the left arm alone leaves the count at 0, then the right arm makes it 1.
    rep(2, ["left"]), state(2, { sideReps: { left: 1, right: 0 } }),
    rep(3, ["right"]), state(3.001, { reps: 1, sideReps: { left: 1, right: 1 } }),
    // The set completes on this rep, which resets the count before the next state is recorded.
    rep(4, ["left", "right"]), state(4, { phase: "resting", set: 2, reps: 0, counting: false }),
    // During rest, and from an older analyzer: neither counts.
    rep(5, ["left", "right"]),
    state(6, { phase: "exercising", set: 2, epoch: 2 }),
    rep(7, ["left", "right"], 1),
    state(8, { counting: false, set: 2, epoch: 2 }),
    rep(9, ["left", "right"], 2),
  ]);
  assert.deepEqual(session.reps.map((r) => [r.t, r.outcome, r.count, r.reason]), [
    [2, "oneSide", null, null],
    [3, "counted", 1, null],
    [4, "completedSet", 2, null],
    [5, "notCounted", null, "phase resting"],
    [7, "notCounted", null, "stale analyzer (epoch 1, coach at 2)"],
    [9, "notCounted", null, "counting off"],
  ]);
  const titles = session.timeline.filter((item) => ["rep", "analyzer", "warn"].includes(item.kind)).map((item) => `${item.t} ${item.title}`);
  assert.deepEqual(titles, ["2 Rep on one side, count unchanged", "3 Rep 1", "4 Rep 2, set complete", "5 Analyzer rep not counted",
    "7 Analyzer rep not counted", "9 Analyzer rep not counted"]);
});
