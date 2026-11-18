import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, mkdir, writeFile, readFile, rm } from "node:fs/promises";
import { createServer as createNetServer } from "node:net";
import { createInterface } from "node:readline";
import http from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "../server.mjs";
import { ID, arrayText, records } from "./fixtures.mjs";
import { createStore } from "../lib/store.mjs";

const mcpPath = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "mcp.mjs");

async function freePort() {
  const server = createNetServer();
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  await new Promise((resolve) => server.close(resolve));
  return port;
}

/** An MCP server over stdio against a temporary repository with one synthetic recording. Without `live`, it points
 * at a closed port, so no test needs to open a socket unless it runs a viewer server. */
async function start({ maxRows, live = false, root: given, port: requestedPort, extraEnv = {}, recordingText = arrayText() } = {}) {
  const root = given ?? await mkdtemp(path.join(tmpdir(), "fmp-mcp-"));
  await mkdir(path.join(root, "diagnostics", "sessions"), { recursive: true });
  await writeFile(path.join(root, "diagnostics", "sessions", `${ID}.json`), recordingText);
  const port = requestedPort ?? (live ? await freePort() : 1);
  const env = { ...process.env, FMP_REPLAY_ROOT: root, FMP_REPLAY_PORT: String(port), ...extraEnv };
  if (maxRows) env.FMP_REPLAY_MAX_ROWS = String(maxRows);
  const child = spawn(process.execPath, [mcpPath], { env });
  const pending = new Map();
  createInterface({ input: child.stdout }).on("line", (line) => {
    const message = JSON.parse(line);
    pending.get(message.id)?.(message);
    pending.delete(message.id);
  });
  let nextID = 1;
  const request = (method, params) => new Promise((resolve) => {
    const id = nextID++;
    pending.set(id, resolve);
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
  });
  const call = async (name, args = {}) => {
    const response = await request("tools/call", { name, arguments: args });
    return { text: response.result.content[0].text, isError: response.result.isError === true };
  };
  const stop = async () => { child.kill(); await rm(root, { recursive: true, force: true }); };
  return { root, port, request, call, stop };
}

function connectEvents(port) {
  const events = [];
  let buffer = "";
  let response;
  const ready = new Promise((resolve, reject) => {
    const request = http.get(`http://127.0.0.1:${port}/api/events`, (stream) => {
      response = stream;
      stream.setEncoding("utf8");
      stream.on("data", (chunk) => {
        buffer += chunk;
        const frames = buffer.split("\n\n");
        buffer = frames.pop() ?? "";
        for (const frame of frames) {
          const line = frame.split("\n").find((item) => item.startsWith("data: "));
          if (line) events.push(JSON.parse(line.slice(6)));
        }
      });
      resolve();
    });
    request.on("error", reject);
  });
  return { events, ready, close: () => response?.destroy() };
}

async function waitFor(predicate, message) {
  const deadline = Date.now() + 3000;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.fail(message);
}

test("initializes and lists the tools", async () => {
  const { request, stop } = await start();
  try {
    const init = await request("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } });
    assert.equal(init.result.protocolVersion, "2025-06-18");
    assert.deepEqual(init.result.capabilities, { tools: {} });
    assert.match(init.result.instructions, /never paste them into commits/);
    const tools = (await request("tools/list")).result.tools.map((tool) => tool.name);
    assert.deepEqual(tools, ["fmp_pull_device", "fmp_list_sessions", "fmp_session_overview", "fmp_query", "fmp_events",
      "fmp_viewer_selection", "fmp_viewer_seek", "fmp_viewer_control", "fmp_add_note", "fmp_open_viewer", "fmp_lab_manifest", "fmp_lab_run",
      "fmp_lab_inspect", "fmp_lab_open"]);
    assert.equal((await request("nope")).error.code, -32601);
    assert.deepEqual((await request("ping")).result, {});
  } finally {
    await stop();
  }
});

test("overview, query, and events read the recording", async () => {
  const { call, stop } = await start();
  try {
    const list = await call("fmp_list_sessions");
    assert.match(list.text, new RegExp(`^${ID}  .*Push-Up  201 frames  1 markers  0 notes$`));
    const overview = await call("fmp_session_overview", { session: ID.slice(0, 8) });
    assert.match(overview.text, /Tracking losses \(1\)\n- 0:08\.3–0:09\.4 \(1\.2 s\): stepBackFloor/);
    assert.match(overview.text, /Reps: 1 analyzer rep events; 1 counted \(#1 at 0:15\.0\)/);
    assert.match(overview.text, /- 0:16\.0 marker on phone \(voice\): that one counted/);
    assert.match(overview.text, /fmp_query session=599FCD69 from=7\.3 to=10\.4 preset=tracking/);
    const excerpt = await call("fmp_query", { from: "0:07.5", to: 10, preset: "rep" });
    assert.equal(excerpt.isError, false);
    assert.match(excerpt.text, /## State at the window start\nphase exercising/);
    assert.match(excerpt.text, /^8\.5,LOST,0,,-,-,-,/m);
    const events = await call("fmp_events", { from: 8, to: 10, kinds: ["warn", "voice"] });
    assert.match(events.text, /^2 events/);
    assert.match(events.text, /0:08\.3 \[warn\] Tracking lost — stepBackFloor/);
  } finally {
    await stop();
  }
});

test("overview lists bridged gaps separately and events classifies them as info", async () => {
  const items = records().map((record) => structuredClone(record));
  items[0].exercises.push_up.framing = { ...items[0].framing, unreliableAfter: 0.8 };
  const frame = items.find((record) => record.k === "f" && record.t === 9);
  assert.ok(frame, "the synthetic recording has a frame at the bridge time");
  frame.info = [{ level: "info", type: "bottomDropoutBridged", ts: frame.ts, seconds: 0.5, maximum: 0.8 }];
  const { call, stop } = await start({ recordingText: arrayText(items) });
  try {
    const overview = await call("fmp_session_overview", { session: ID.slice(0, 8) });
    assert.match(overview.text, /Framing needs .* unreliable after 0\.8 s missing/);
    assert.match(overview.text, /^- push_up \(floor\).*framing drops after 0\.8 s missing$/m);
    assert.match(overview.text, /Bridged gaps \(1\)\n- 0:09\.0 Bottom dropout bridged: 0\.50 s \(limit 0\.80 s\)/);
    assert.match(overview.text, /Other issues \(0\)\nnone/);

    const events = await call("fmp_events", { from: 9, to: 9, kinds: ["info"] });
    assert.match(events.text, /^1 events/);
    assert.match(events.text, /0:09\.0 \[info\] Bottom dropout bridged: 0\.50 s \(limit 0\.80 s\)/);
  } finally {
    await stop();
  }
});

test("overview and events list side-view exercise entries and stance", async () => {
  const items = records().map((record) => structuredClone(record));
  items[0].exercises.hammer_curl = { name: "Hammer Curl", cameraView: "front", required: ["leftElbow"], focus: ["leftElbow"] };
  items[0].exercises["hammer_curl.side"] = {
    name: "Hammer Curl", cameraView: "side", required: ["leftElbow", "leftWrist"], focus: ["leftElbow", "leftWrist"],
  };
  items.push(
    { k: "pipe", t: 17.5, control: "exercise", exercise: "hammer_curl", cameraView: "front", epoch: 2 },
    { k: "pipe", t: 18.5, control: "exercise", exercise: "hammer_curl", cameraView: "side", epoch: 3 },
    { k: "e", t: 18.75, type: "stance", settled: "side", turning: false },
  );
  items.sort((a, b) => (a.k === "header" ? -1 : b.k === "header" ? 1 : (a.t ?? 0) - (b.t ?? 0)));
  const { call, stop } = await start({ recordingText: arrayText(items) });
  try {
    const overview = await call("fmp_session_overview", { session: ID.slice(0, 8) });
    assert.match(overview.text, /^- hammer_curl \(side\) 0:18\.5–0:20\.5: required LE LW/m);
    const events = await call("fmp_events", { from: 18.75, to: 18.75, kinds: ["info"] });
    assert.match(events.text, /^1 events/);
    assert.match(events.text, /0:18\.8 \[info\] Stance — settled=side · turning=false/);
  } finally {
    await stop();
  }
});

test("queries are kept to a useful size", async () => {
  const { call, request, stop } = await start({ maxRows: 100 });
  try {
    const large = await call("fmp_query", { from: 0, to: 20, preset: "rep", rate: 10 });
    assert.equal(large.isError, true);
    assert.match(large.text, /201 frame rows at 10 Hz/);
    assert.equal((await call("fmp_query", { from: 0, to: 20, rate: 2 })).isError, false, "a lower rate fits");
    assert.equal((await call("fmp_query", { from: 0, to: 20, rate: 10, allowLarge: true })).isError, false);
    assert.match((await call("fmp_query", { from: 9, to: 9 })).text, /is empty/);
    assert.match((await call("fmp_query", { from: "soon", to: 9 })).text, /seconds or m:ss/);
    assert.match((await call("fmp_query", { session: "ffff", from: 1, to: 2 })).text, /No recording matches/);
    assert.equal((await request("tools/call", { name: "fmp_typo", arguments: {} })).error.code, -32602);
  } finally {
    await stop();
  }
});

test("notes are saved directly without the viewer, and through it when it runs", async () => {
  const { root, port, call, stop } = await start({ live: true });
  const server = createServer({ root, port });
  try {
    const direct = await call("fmp_add_note", { t: 8.4, text: "Shoulders drop below 0.4 here." });
    assert.match(direct.text, /it has 1 note/);
    const notesPath = path.join(root, "diagnostics", "sessions", `${ID}.notes.json`);
    assert.equal(JSON.parse(await readFile(notesPath, "utf8")).notes[0].author, "claude");

    const offline = await call("fmp_viewer_seek", { t: 8.3 });
    assert.equal(offline.isError, true);
    assert.match(offline.text, /isn't open/);

    await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
    const viaServer = await call("fmp_add_note", { t: 9, end: 9.4, text: "Back." });
    assert.match(viaServer.text, /it has 2 note/);
    assert.match((await call("fmp_viewer_seek", { t: 8.3 })).text, /no viewer is open/);
    const selection = await call("fmp_viewer_selection");
    assert.match(selection.text, /Nothing has been sent/);
    await fetch(`http://127.0.0.1:${port}/api/viewer/sent`, { method: "POST", headers: { "Content-Type": "application/json", "X-FMP-Replay": "1" },
      body: JSON.stringify({ sessionId: ID, title: "Push-Up", from: 7.5, to: 10, markdown: "# excerpt\n" }) });
    assert.match((await call("fmp_viewer_selection")).text, /Last sent from the viewer .*0:07\.5–0:10\.0\):\n\n# excerpt/s);
  } finally {
    server.closeClients();
    await new Promise((resolve) => server.close(resolve));
    await stop();
  }
});

test("arguments are validated against each tool's schema, and only real tools run", async () => {
  const { request, stop } = await start();
  try {
    const call = async (name, args) => (await request("tools/call", { name, arguments: args })).error;
    assert.match((await call("fmp_add_note", { text: "check this" })).message, /t is required/);
    assert.match((await call("fmp_add_note", { t: 1, text: "x".repeat(2001) })).message, /longer than 2000/);
    assert.match((await call("fmp_query", { from: 1, to: 2, preset: "everything" })).message, /preset must be one of/);
    assert.match((await call("fmp_query", { from: 1, to: 2, include: { video: true } })).message, /include: unknown argument video/);
    assert.match((await call("fmp_list_sessions", { limit: 0 })).message, /at least 1/);
    assert.match((await call("fmp_events", { kinds: ["rep", "secrets"] })).message, /kinds(\[\d+\])? may contain only/);
    for (const name of ["constructor", "toString", "__proto__", "hasOwnProperty"]) {
      assert.equal((await call(name, {})).code, -32602, name);
    }
  } finally {
    await stop();
  }
});

test("the protocol version is one the server knows", async () => {
  const { request, stop } = await start();
  try {
    assert.equal((await request("initialize", { protocolVersion: "2025-03-26" })).result.protocolVersion, "2025-03-26");
    assert.equal((await request("initialize", { protocolVersion: "1999-01-01" })).result.protocolVersion, "2025-11-25");
  } finally {
    await stop();
  }
});

test("a viewer serving another checkout is never written to", async () => {
  const other = await mkdtemp(path.join(tmpdir(), "fmp-other-"));
  const { port, call, stop } = await start({ live: true });
  const server = createServer({ root: other, port });
  try {
    await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
    const note = await call("fmp_add_note", { t: 1, text: "for this checkout" });
    assert.equal(note.isError, true);
    assert.match(note.text, /another checkout/);
    assert.match((await call("fmp_viewer_seek", { t: 1 })).text, /another checkout/);
    assert.match((await call("fmp_open_viewer", {})).text, /another checkout/);
  } finally {
    server.closeClients();
    await new Promise((resolve) => server.close(resolve));
    await rm(other, { recursive: true, force: true });
    await stop();
  }
});

test("viewer MCP commands control playback and open work in place, falling back to a browser only with no viewer", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-viewer-control-"));
  const bin = path.join(root, "fake-bin");
  const openLog = path.join(root, "open.log");
  await mkdir(bin, { recursive: true });
  await writeFile(path.join(bin, "open"), '#!/bin/sh\nprintf "%s\\n" "$1" >> "$FMP_TEST_OPEN_LOG"\n', { mode: 0o755 });
  await writeFile(openLog, "");
  const mcp = await start({ live: true, root, extraEnv: { PATH: `${bin}:${process.env.PATH ?? ""}`, FMP_TEST_OPEN_LOG: openLog } });
  const server = createServer({ root, port: mcp.port });
  let stream;
  try {
    await new Promise((resolve) => server.listen(mcp.port, "127.0.0.1", resolve));
    stream = connectEvents(mcp.port);
    await stream.ready;

    const listed = (await mcp.request("tools/list")).result.tools;
    const controlSchema = listed.find((tool) => tool.name === "fmp_viewer_control").inputSchema;
    assert.deepEqual(controlSchema.properties.action.enum,
      ["play", "pause", "toggle", "loop", "autoplay", "follow", "speed", "reload", "latest"]);
    assert.equal(controlSchema.additionalProperties, false);
    assert.equal((await mcp.call("fmp_viewer_control", { action: "latest" })).isError, true);

    const opened = await mcp.call("fmp_open_viewer", { session: ID, t: "0:03", from: 2, to: 4 });
    assert.match(opened.text, /Navigated 1 connected viewer\(s\).*in place/);
    await waitFor(() => stream.events.some((event) => event.command === "open-viewer"), "open-viewer command was not posted");
    assert.deepEqual(stream.events.find((event) => event.command === "open-viewer"), {
      type: "command", command: "open-viewer", sessionId: ID, t: 3, from: 2, to: 4, export: false,
    });
    assert.equal((await readFile(openLog, "utf8")).trim(), "", "a connected page should not spawn a new tab");

    const seek = await mcp.call("fmp_viewer_seek", { session: ID, t: 3, from: 2, to: 4, play: true });
    assert.match(seek.text, /selecting 0:02\.0–0:04\.0/);
    const commandActions = [
      { action: "play" }, { action: "pause" }, { action: "toggle" }, { action: "loop", value: "off" },
      { action: "autoplay", value: "off" }, { action: "follow", value: "on" }, { action: "speed", speed: 2 },
      { action: "reload" },
    ];
    for (const args of commandActions) assert.equal((await mcp.call("fmp_viewer_control", args)).isError, false);
    await waitFor(() => stream.events.filter((event) => event.type === "command").length >= commandActions.length + 2,
      "viewer controls were not all posted");
    assert.deepEqual(stream.events.find((event) => event.command === "seek"), {
      type: "command", command: "seek", sessionId: ID, t: 3, from: 2, to: 4, note: null, play: true,
    });
    assert.deepEqual(stream.events.filter((event) => event.command === "control").map((event) => event.action),
      commandActions.map((args) => args.action));

    const latestRecording = await mcp.call("fmp_viewer_control", { action: "latest", kind: "recording" });
    assert.match(latestRecording.text, /Navigated 1 connected viewer\(s\).*in place/);
    await waitFor(() => stream.events.filter((event) => event.command === "open-viewer").length === 2,
      "latest recording was not opened in place");

    const newRunID = "20261117-120001-ab12";
    const runDirectory = path.join(root, "diagnostics", "movement-lab", "runs", newRunID);
    await mkdir(runDirectory, { recursive: true });
    await writeFile(path.join(runDirectory, "plan.json"), JSON.stringify({ title: "Newest run", scenarios: [] }));
    await writeFile(path.join(runDirectory, "summary.json"), "{}");
    await writeFile(path.join(runDirectory, "results.json"), "[]");
    const latestRun = await mcp.call("fmp_viewer_control", { action: "latest", kind: "labRun" });
    assert.match(latestRun.text, /Navigated 1 connected viewer\(s\).*Movement Lab dashboard.*in place/);
    await waitFor(() => stream.events.some((event) => event.command === "lab-open" && event.runID === newRunID),
      "latest Lab run was not opened in place");

    await (await fetch(`http://127.0.0.1:${mcp.port}/api/viewer/state`, { method: "POST",
      headers: { "Content-Type": "application/json", "X-FMP-Replay": "1" },
      body: JSON.stringify({ sessionId: ID, t: 3, playing: true, loop: false, autoplay: false, follow: true, speed: 2 }) })).json();
    const selection = await mcp.call("fmp_viewer_selection");
    assert.match(selection.text, /playing; loop off; autoplay off; follow on; speed 2×/);

    stream.close();
    await new Promise((resolve) => setTimeout(resolve, 75));
    const noPage = await mcp.call("fmp_open_viewer", { session: ID });
    assert.match(noPage.text, /Opened/);
    await waitFor(async () => (await readFile(openLog, "utf8")).trim().length > 0,
      "open should launch a browser when no page is connected");
  } finally {
    stream?.close();
    server.closeClients();
    await new Promise((resolve) => server.close(resolve));
    await mcp.stop();
  }
});

test("pulls requested together share one run", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-pull-"));
  await mkdir(path.join(root, "scripts", "diagnostics"), { recursive: true });
  const counter = path.join(root, "runs");
  await writeFile(path.join(root, "scripts", "diagnostics", "pull.sh"), `echo run >> "${counter}"; sleep 0.3; echo "Pulled 1 recording."\n`);
  const { call, stop } = await start({ root });
  try {
    const results = await Promise.all([call("fmp_pull_device"), call("fmp_pull_device"), call("fmp_pull_device")]);
    assert.deepEqual(results.map((result) => result.text), Array(3).fill("Pulled 1 recording."));
    assert.equal((await readFile(counter, "utf8")).trim().split("\n").length, 1);
  } finally {
    await stop();
  }
});

test("note saves from separate processes all survive", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-lock-"));
  await mkdir(path.join(root, "diagnostics", "sessions"), { recursive: true });
  await writeFile(path.join(root, "diagnostics", "sessions", `${ID}.json`), arrayText());
  const storePath = new URL("../lib/store.mjs", import.meta.url).href;
  const writer = (prefix) => new Promise((resolve, reject) => {
    const script = `import { createStore } from ${JSON.stringify(storePath)};
      const store = createStore(${JSON.stringify(root)});
      await Promise.all(Array.from({ length: 15 }, (_, i) => store.saveNote(${JSON.stringify(ID)}, { id: "${prefix}" + i, t: i, text: "${prefix}" })));`;
    const child = spawn(process.execPath, ["--input-type=module", "-e", script], { stdio: ["ignore", "ignore", "pipe"] });
    let errors = "";
    child.stderr.on("data", (chunk) => { errors += chunk; });
    child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(errors))));
  });
  try {
    await Promise.all([writer("a"), writer("b")]);
    const notes = (await createStore(root).notesFor(ID)).notes;
    assert.equal(notes.length, 30);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
