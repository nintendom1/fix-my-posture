// A small synthetic push-up recording, built in code so no real recording is ever committed.
export const ID = "599FCD69-CD80-4E21-978B-CDEA95DD23FC";
export const JOINTS = ["nose", "neck", "leftEye", "rightEye", "leftEar", "rightEar", "leftShoulder", "rightShoulder",
  "leftElbow", "rightElbow", "leftWrist", "rightWrist", "root", "leftHip", "rightHip", "leftKnee", "rightKnee",
  "leftAnkle", "rightAnkle"];

/** Records for a 20 s set: tracking is reliable from 2 s, lost from 8.25 s to 9.4 s (no joints 8.3–9.1 s). */
export function records() {
  const out = [
    { k: "header", schema: "fmp.workout-session/1", kind: "workout", id: ID, startedAt: "2027-01-15T08:00:00.000-08:00",
      device: { model: "iPhone16,1", os: "18.1" }, camera: { analysisHz: 10 }, jointOrder: JOINTS, confidenceFloor: 0.3,
      framing: { minimumConfidence: 0.4, reliableAfter: 0.6, unreliableAfter: 0.3 },
      exercises: { push_up: { name: "Push-Up", cameraView: "floor", required: ["leftShoulder", "rightShoulder"], anyOfRequired: [],
        focus: ["leftShoulder", "rightShoulder", "leftWrist"], configuration: { downMaxRatio: 0.5, upMinRatio: 0.8, maximumSampleGap: 0.28 } } } },
    { k: "pipe", t: 0.3, control: "exercise", exercise: "push_up", cameraView: "floor", epoch: 1 },
    { k: "state", t: 0.3, phase: "framing", ex: "push_up", set: 1, reps: 0 },
    { k: "e", t: 1, type: "command", command: "start", source: "voice", phrase: "let's go" },
    { k: "state", t: 1, phase: "exercising", ex: "push_up", set: 1, reps: 0 },
    { k: "e", t: 2, type: "framing", framing: { ok: true, g: null } },
    { k: "e", t: 8.25, type: "framing", framing: { ok: false, g: "stepBackFloor" } },
    { k: "e", t: 8.6, type: "speak", text: "I can't see you.", muted: false },
    { k: "e", t: 9.4, type: "framing", framing: { ok: true, g: null } },
    { k: "e", t: 15, type: "rep", epoch: 1, ts: 1015, sides: ["left", "right"] },
    { k: "state", t: 15, phase: "exercising", ex: "push_up", set: 1, reps: 1 },
    { k: "marker", t: 16.5, heardAt: 16, id: "M1", source: "voice", text: "that one counted" },
  ];
  for (let step = 0; step <= 200; step += 1) {
    const t = step / 10;
    const ok = t >= 2 && !(t >= 8.25 && t < 9.4);
    const frame = { k: "f", t, ts: 1000 + t, seq: step + 1, p: true, cnt: ok, j: JOINTS.map(() => null), fr: { ok, g: null },
      rd: { left: { signal: 0.9 - (step % 40) / 100, elbow: 170 - (step % 40), zone: "middle" } } };
    if (step === 0) frame.wh = [1080, 1920];
    if (!(t >= 8.3 && t <= 9.1)) {
      frame.j[6] = [740.5, 713.25, 0.65];
      frame.j[7] = [402, 695, t > 8 && t < 8.3 ? 0.35 : 0.63];
      frame.j[10] = [813, 1231, 0.74];
    }
    if (t === 8.1) {
      frame.j[7] = null;
      frame.lo = [[7, 401, 700, 0.22]];
    }
    if (t === 12) frame.est = [[10, 820, 1300]];
    if (t === 15) frame.out = [{ rep: { epoch: 1, ts: 1015, sides: ["left", "right"] } }];
    frame.th = { left: { start: [700, 804, 900, 804], top: [700, 966, 900, 966], locked: true, confirmed: "start" } };
    out.push(frame);
  }
  out.push({ k: "end", t: 20.5, endedAt: "2027-01-15T08:00:20.500-08:00", reason: "workoutEnded", frames: 201, seqGaps: 0 });
  out.sort((a, b) => (a.k === "header" ? -1 : b.k === "header" ? 1 : (a.t ?? 0) - (b.t ?? 0)));
  return out;
}

export const arrayText = (items = records()) => "[\n" + items.map((r) => JSON.stringify(r)).join(",\n") + "\n]\n";
export const linesText = (items = records()) => items.map((r) => JSON.stringify(r)).join("\n") + "\n";
