function framesOf(records) {
  return Array.isArray(records) ? records.filter((record) => record?.k === "f" && Number.isFinite(record.t)) : [];
}

function headerOf(records) {
  return Array.isArray(records) ? records.find((record) => record?.k === "header") ?? {} : {};
}

function point(frame, jointName, jointOrder) {
  const index = jointOrder.indexOf(jointName);
  const value = index >= 0 ? frame?.j?.[index] : null;
  return Array.isArray(value) && Number.isFinite(value[0]) && Number.isFinite(value[1])
    ? { x: value[0], y: value[1] } : null;
}

function nearestIndex(frames, time) {
  if (!frames.length) return null;
  let best = 0;
  for (let index = 1; index < frames.length; index += 1) {
    if (Math.abs(frames[index].t - time) < Math.abs(frames[best].t - time)) best = index;
  }
  return best;
}

function hipsY(frame, jointOrder) {
  const values = [point(frame, "leftHip", jointOrder), point(frame, "rightHip", jointOrder)]
    .filter(Boolean).map((item) => item.y);
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null;
}

function maximumDepthIndex(frames, jointOrder, candidates = null) {
  let best = null;
  let depth = -Infinity;
  for (const index of candidates ?? frames.map((_, frameIndex) => frameIndex)) {
    const frame = frames[index];
    const value = hipsY(frame, jointOrder);
    if (value != null && value > depth) { depth = value; best = index; }
  }
  return best ?? (frames.length ? 0 : null);
}

function repetitionPeakIndices(frames, jointOrder, repetitionCount) {
  if (frames.length < 3 || !Number.isInteger(repetitionCount) || repetitionCount < 1) return [];
  const values = frames.map((frame) => hipsY(frame, jointOrder));
  const finite = values.filter(Number.isFinite);
  if (finite.length < 3) return [];
  const range = Math.max(...finite) - Math.min(...finite);
  if (range <= 0) return [];
  const threshold = Math.min(...finite) + range * 0.25;
  const timeSpan = Math.max(0, frames.at(-1).t - frames[0].t);
  const minimumSpacing = Math.max(0.2, timeSpan / (repetitionCount * 2));
  const localPeaks = [];
  for (let index = 1; index < frames.length - 1; index += 1) {
    const value = values[index];
    const previous = values[index - 1];
    const next = values[index + 1];
    if (!Number.isFinite(value) || !Number.isFinite(previous) || !Number.isFinite(next) || value < threshold) continue;
    if (value >= previous && value >= next && (value > previous || value > next)) localPeaks.push(index);
  }
  const peaks = [];
  for (const index of localPeaks) {
    const previousIndex = peaks.at(-1);
    if (previousIndex != null && frames[index].t - frames[previousIndex].t < minimumSpacing) {
      if (values[index] > values[previousIndex]) peaks[peaks.length - 1] = index;
    } else {
      peaks.push(index);
    }
  }
  return peaks;
}

function repEventTimes(records) {
  const times = [];
  for (const record of records) {
    if (record?.k !== "e" || record.type !== "rep" || !Number.isFinite(record.t)) continue;
    if (!times.some((value) => Math.abs(value - record.t) < 0.002)) times.push(record.t);
  }
  return times.sort((a, b) => a - b);
}

function repetitionWindow(frames, referencePeakIndices, referenceFrames, repIndex, repetitionCount, eventTimes) {
  const peakIndex = referencePeakIndices[repIndex];
  if (peakIndex != null) {
    const previousPeak = referencePeakIndices[repIndex - 1];
    const nextPeak = referencePeakIndices[repIndex + 1];
    const peakTime = referenceFrames[peakIndex].t;
    const start = previousPeak == null ? frames[0]?.t
      : (referenceFrames[previousPeak].t + peakTime) / 2;
    const end = nextPeak == null ? frames.at(-1)?.t
      : (peakTime + referenceFrames[nextPeak].t) / 2;
    return frames.map((frame, index) => ({ frame, index }))
      .filter(({ frame }) => frame.t >= start && frame.t <= end).map(({ index }) => index);
  }

  const start = repIndex === 0 ? frames[0]?.t : eventTimes[repIndex - 1];
  const end = eventTimes[repIndex] ?? (repIndex === repetitionCount - 1 ? frames.at(-1)?.t : null);
  if (Number.isFinite(start) && Number.isFinite(end) && end >= start) {
    const selected = frames.map((frame, index) => ({ frame, index }))
      .filter(({ frame }) => frame.t >= start && frame.t <= end).map(({ index }) => index);
    if (selected.length) return selected;
  }

  const first = frames[0]?.t;
  const last = frames.at(-1)?.t;
  if (!Number.isFinite(first) || !Number.isFinite(last)) return [];
  const duration = last - first;
  const lower = first + duration * repIndex / repetitionCount;
  const upper = first + duration * (repIndex + 1) / repetitionCount;
  return frames.map((frame, index) => ({ frame, index }))
    .filter(({ frame }) => frame.t >= lower && (repIndex === repetitionCount - 1 ? frame.t <= upper : frame.t < upper))
    .map(({ index }) => index);
}

function depthScaleIndex(frames, jointOrder, scenario, referenceFrames, records) {
  const depthMutations = (Array.isArray(scenario?.mutations) ? scenario.mutations : [])
    .filter((item) => item?.kind === "depthScale");
  const hasUnrestrictedMutation = depthMutations.some((item) => !Array.isArray(item.reps));
  const selectedReps = [...new Set(depthMutations.flatMap((item) => Array.isArray(item.reps) ? item.reps : [])
    .filter((rep) => Number.isInteger(rep) && rep > 0))];
  if (hasUnrestrictedMutation || !selectedReps.length) {
    return { frameIndex: maximumDepthIndex(frames, jointOrder), selectedReps: null };
  }

  const repetitionCount = Number.isInteger(scenario.reps) && scenario.reps > 0
    ? scenario.reps : Math.max(...selectedReps);
  const referencePeaks = repetitionPeakIndices(referenceFrames, jointOrder, repetitionCount);
  const eventTimes = repEventTimes(records);
  const candidates = new Set();
  for (const rep of selectedReps) {
    if (rep > repetitionCount) continue;
    for (const index of repetitionWindow(frames, referencePeaks, referenceFrames, rep - 1, repetitionCount, eventTimes)) {
      candidates.add(index);
    }
  }
  const candidateIndices = [...candidates];
  return {
    frameIndex: maximumDepthIndex(frames, jointOrder, candidateIndices.length ? candidateIndices : null),
    selectedReps,
  };
}

function maximumAsymmetryIndex(frames, jointOrder, referenceFrames, side) {
  let best = maximumDepthIndex(frames, jointOrder);
  let amount = -Infinity;
  frames.forEach((frame, index) => {
    const selectedSide = point(frame, `${side}Hip`, jointOrder);
    const otherSideName = side === "left" ? "rightHip" : "leftHip";
    const otherSide = point(frame, otherSideName, jointOrder);
    if (!selectedSide || !otherSide) return;
    const referenceIndex = referenceFrames.length ? nearestIndex(referenceFrames, frame.t) : null;
    const referenceFrame = referenceIndex == null ? null : referenceFrames[referenceIndex];
    const referenceSelected = referenceFrame ? point(referenceFrame, `${side}Hip`, jointOrder) : null;
    const referenceOther = referenceFrame ? point(referenceFrame, otherSideName, jointOrder) : null;
    const value = referenceSelected && referenceOther
      ? Math.abs((selectedSide.y - referenceSelected.y) - (otherSide.y - referenceOther.y))
      : Math.abs(selectedSide.y - otherSide.y);
    if (value > amount) { amount = value; best = index; }
  });
  return best;
}

function jointLabel(name) {
  return String(name).replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase();
}

function formatTime(value) {
  return `${Math.max(0, value).toFixed(1)} s`;
}

function frameAtOrAfter(frames, time) {
  const index = frames.findIndex((frame) => frame.t >= time);
  return index >= 0 ? index : (frames.length ? frames.length - 1 : null);
}

function repBoundary(records, mutation, frames) {
  const events = records.filter((record) => record?.k === "e" && record.type === "rep" && Number.isFinite(record.t));
  const states = records.filter((record) => record?.k === "state" && Number.isFinite(record.t));
  if (!events.length) return null;
  const target = Array.isArray(mutation.reps) && mutation.reps.length ? mutation.reps[0] : 1;
  const event = events[Math.min(Math.max(target - 1, 0), events.length - 1)];
  const state = states.find((item) => Number(item.reps) >= target && item.t >= event.t);
  return nearestIndex(frames, state?.t ?? event.t);
}

function pauseTime(mutation, mutations) {
  const insertedBefore = mutations.filter((item) => item?.kind === "pause" && item !== mutation && item.at <= mutation.at)
    .reduce((sum, item) => sum + (Number.isFinite(item.duration) ? item.duration : 0), 0);
  return mutation.at + insertedBefore;
}

function selectionFor(scenario, records, frames, referenceFrames) {
  const mutations = Array.isArray(scenario?.mutations) ? scenario.mutations : [];
  const mutation = mutations.find((item) => ["dropout", "confidence", "frameGap", "tempo", "pause"].includes(item?.kind))
    ?? mutations[0] ?? null;
  const kind = mutation?.kind ?? "canonical";
  const header = headerOf(records);
  const jointOrder = Array.isArray(header.jointOrder) ? header.jointOrder : [];
  let frameIndex = null;
  let affectedJoints = [];
  let annotation = "movement";
  let descriptor = "canonical motion";

  switch (kind) {
    case "jointOffset":
      frameIndex = nearestIndex(frames, Number(mutation.peak) || 0);
      affectedJoints = Array.isArray(mutation.joints) ? mutation.joints : [];
      annotation = "joint offset";
      descriptor = `${affectedJoints.map(jointLabel).join(", ") || "joint"} · peak`;
      break;
    case "depthScale":
      {
        const selection = depthScaleIndex(frames, jointOrder, scenario, referenceFrames, records);
        frameIndex = selection.frameIndex;
        descriptor = selection.selectedReps
          ? `maximum hip drop · rep ${selection.selectedReps.join(", ")} peak` : "maximum hip drop · peak";
      }
      affectedJoints = ["leftHip", "rightHip", "leftKnee", "rightKnee"];
      annotation = "depth";
      break;
    case "asymmetry":
      frameIndex = maximumAsymmetryIndex(frames, jointOrder, referenceFrames, mutation.side === "right" ? "right" : "left");
      affectedJoints = [`${mutation.side}Hip`, `${mutation.side}Knee`];
      annotation = "asymmetry";
      descriptor = `${mutation.side} side · peak`;
      break;
    case "tempo":
      frameIndex = repBoundary(records, mutation, frames) ?? maximumDepthIndex(frames, jointOrder);
      annotation = "tempo";
      descriptor = `tempo · rep ${(mutation.reps?.[0] ?? 1)} boundary`;
      break;
    case "pause":
      frameIndex = nearestIndex(frames, pauseTime(mutation, mutations));
      annotation = "pause";
      descriptor = "pause boundary";
      break;
    case "frameGap":
      frameIndex = frameAtOrAfter(frames, mutation.at + mutation.duration);
      annotation = "gap";
      descriptor = "gap · resume boundary";
      break;
    case "dropout":
      frameIndex = frameAtOrAfter(frames, mutation.from);
      if (frameIndex != null && frames[frameIndex].t >= mutation.to) frameIndex = nearestIndex(frames, mutation.from);
      affectedJoints = Array.isArray(mutation.joints) ? mutation.joints : [];
      annotation = "missing landmark";
      descriptor = "missing landmark · window start";
      break;
    case "confidence":
      frameIndex = frameAtOrAfter(frames, mutation.from);
      if (frameIndex != null && frames[frameIndex].t >= mutation.to) frameIndex = nearestIndex(frames, mutation.from);
      affectedJoints = Array.isArray(mutation.joints) ? mutation.joints : [];
      annotation = "confidence";
      descriptor = "confidence · window start";
      break;
    case "framing":
      frameIndex = maximumDepthIndex(frames, jointOrder);
      affectedJoints = [...jointOrder];
      annotation = "framing";
      descriptor = "framing · representative pose";
      break;
    default:
      frameIndex = maximumDepthIndex(frames, jointOrder);
      break;
  }

  const frame = frameIndex == null ? null : frames[frameIndex];
  const timestamp = Number.isFinite(frame?.t) ? frame.t : null;
  const formatted = timestamp == null ? "time unavailable" : formatTime(timestamp);
  const marker = descriptor.endsWith("peak") ? `peak ${formatted}`
    : descriptor.endsWith("window start") ? `window start ${formatted}`
      : descriptor.endsWith("resume boundary") ? `resume ${formatted}`
        : descriptor.endsWith("representative pose") ? `representative ${formatted}` : formatted;
  const base = descriptor.replace(/ · (peak|window start|resume boundary|representative pose)$/, "");
  return {
    frameIndex,
    timestamp,
    affectedJoints: [...new Set(affectedJoints)],
    annotation,
    descriptor: `${base} · ${marker}`,
    kind,
  };
}

/** Choose a stable stored frame that best represents the scenario mutation. */
export function chooseKeyframe(scenario, recording = [], reference = []) {
  const frames = framesOf(recording);
  const referenceFrames = framesOf(reference);
  const selected = selectionFor(scenario, recording, frames, referenceFrames);
  const referenceIndex = selected.timestamp == null ? null : nearestIndex(referenceFrames, selected.timestamp);
  return { ...selected, referenceIndex };
}
