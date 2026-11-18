export const viewerEvents = new EventSource("/api/events");

/** This page's id. The server counts acknowledgements per page, and runs this page starts carry it as `startedBy`. */
export const pageID = crypto.randomUUID();

/** Tells the server this page acted on a command, so MCP tools report what happened rather than who was listening. */
export function acknowledgeCommand(event) {
  if (typeof event?.commandID !== "string") return;
  void fetch("/api/viewer/ack", { method: "POST", headers: { "Content-Type": "application/json", "X-FMP-Replay": "1" },
    body: JSON.stringify({ commandID: event.commandID, pageID }) }).catch(() => {});
}
