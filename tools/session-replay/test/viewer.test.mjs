import test from "node:test";
import assert from "node:assert/strict";
import { openReplayViewer, viewerURL } from "../lib/viewer.mjs";

test("viewer links preserve the selected recording, time, range, and export", () => {
  assert.equal(viewerURL("http://127.0.0.1:4317/", { t: 3.5, from: 2, to: 4, export: true }, "recording-id"),
    "http://127.0.0.1:4317/?session=recording-id&t=3.5&from=2&to=4&export=1");
});

test("opening a connected viewer sends an in-place command without opening a browser", async () => {
  const calls = [];
  const result = await openReplayViewer({ args: { t: 3, from: 2, to: 4 }, sessionID: "recording-id",
    baseURL: "http://127.0.0.1:4317/", ensureViewer: async () => false,
    getViewerState: async () => ({ viewers: 1 }),
    openURL: async (url) => calls.push(["open", url]),
    sendCommand: async (command) => { calls.push(["command", command]); return { delivered: 1 }; } });
  assert.equal(result.connected, true);
  assert.equal(result.delivered, 1);
  assert.deepEqual(calls, [["command", { command: "open-viewer", sessionId: "recording-id", t: 3, from: 2, to: 4, export: false }]]);
});

test("opening without a connected page launches only the supplied browser opener", async () => {
  const calls = [];
  const result = await openReplayViewer({ args: {}, baseURL: "http://127.0.0.1:4317/",
    ensureViewer: async () => true, getViewerState: async () => ({ viewers: 0 }),
    openURL: async (url) => calls.push(url),
    sendCommand: async () => assert.fail("no command should be sent without a connected page") });
  assert.equal(result.connected, false);
  assert.equal(result.started, true);
  assert.deepEqual(calls, ["http://127.0.0.1:4317/"]);
});
