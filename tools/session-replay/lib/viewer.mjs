export function viewerURL(baseURL, args, sessionID = null) {
  const params = new URLSearchParams();
  if (sessionID) params.set("session", sessionID);
  for (const key of ["t", "from", "to"]) if (args?.[key] != null) params.set(key, String(args[key]));
  if (args?.export) params.set("export", "1");
  return `${baseURL}${params.size ? `?${params}` : ""}`;
}

/** Open a replay link in the existing page when possible, and in a browser only when no page is connected. */
export async function openReplayViewer({ args = {}, sessionID = null, baseURL, ensureViewer, getViewerState,
  openURL, sendCommand }) {
  const started = await ensureViewer();
  const state = await getViewerState?.();
  const connected = Number(state?.viewers ?? 0) > 0;
  const url = viewerURL(baseURL, args, sessionID);
  let delivered = 0;
  if (connected) {
    const response = await sendCommand({ command: "open-viewer", sessionId: sessionID,
      t: args.t ?? null, from: args.from ?? null, to: args.to ?? null, export: args.export === true });
    if (response == null) throw new Error("The local viewer server did not accept the open command.");
    delivered = Number(response.delivered ?? 0);
  } else {
    await openURL(url);
  }
  return { started, connected, delivered, url };
}
