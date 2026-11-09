export function createSelectionToken() {
  let sequence = 0;
  return {
    next() { sequence += 1; return sequence; },
    isCurrent(token) { return token === sequence; },
  };
}

export function sectionHref(href, section) {
  const url = new URL(href);
  if (section === "recordings") {
    url.searchParams.set("view", "recordings");
  } else {
    url.searchParams.set("view", "runs");
    for (const key of ["session", "t", "from", "to", "export"]) url.searchParams.delete(key);
  }
  return `${url.pathname}${url.search}${url.hash}`;
}

/** Read the deep link emitted by fmp_lab_open, if this URL targets a Movement Lab run. */
export function labOpenRequestFromURL(search) {
  const params = new URLSearchParams(search);
  const runID = params.get("labRun");
  if (!runID) return null;
  const scenarioID = params.get("labScenario");
  const time = params.get("labTime");
  const timestamp = time !== null && time.trim() !== "" ? Number(time) : NaN;
  return {
    runID,
    ...(scenarioID ? { scenarioID } : {}),
    ...(Number.isFinite(timestamp) ? { timestamp } : {}),
  };
}

/** Normalize a live viewer command into the same target shape used by dashboard deep links. */
export function labOpenRequestFromCommand(event) {
  if (event?.type !== "command" || event.command !== "lab-open" || typeof event.runID !== "string") return null;
  const rawTimestamp = event.timestamp;
  const timestamp = typeof rawTimestamp === "number" ? rawTimestamp
    : typeof rawTimestamp === "string" && rawTimestamp.trim() ? Number(rawTimestamp) : NaN;
  return {
    runID: event.runID,
    ...(typeof event.scenarioID === "string" && event.scenarioID ? { scenarioID: event.scenarioID } : {}),
    ...(Number.isFinite(timestamp) ? { timestamp } : {}),
  };
}

/** Connect the viewer's SSE command stream to the shared lab-open request handler. */
export function installLabOpenCommandReceiver(eventSource, handleRequest) {
  eventSource.onmessage = (message) => {
    let event;
    try { event = JSON.parse(message.data); } catch { return; }
    const target = labOpenRequestFromCommand(event);
    if (target) return handleRequest(target);
  };
}

/** Dispatch a normalized URL or viewer command through the dashboard's existing navigation callbacks. */
export function createLabOpenHandler({ navigateToScenario, navigateToRun }) {
  return async (target) => {
    if (!target || typeof target.runID !== "string" || !target.runID) return false;
    if (typeof target.scenarioID === "string" && Number.isFinite(target.timestamp)) {
      return Boolean(await navigateToScenario(target));
    }
    return Boolean(await navigateToRun(target));
  };
}
