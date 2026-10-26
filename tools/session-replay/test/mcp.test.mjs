import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, mkdir, writeFile, readFile, rm } from "node:fs/promises";
import { createServer as createNetServer } from "node:net";
import { createInterface } from "node:readline";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createServer } from "../server.mjs";
import { ID, arrayText } from "./fixtures.mjs";
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
async function start({ maxRows, live = false, root: given } = {}) {
  const root = given ?? await mkdtemp(path.join(tmpdir(), "fmp-mcp-"));
  await mkdir(path.join(root, "diagnostics", "sessions"), { recursive: true });
  await writeFile(path.join(root, "diagnostics", "sessions", `${ID}.json`), arrayText());
  const port = live ? await freePort() : 1;
  const env = { ...process.env, FMP_REPLAY_ROOT: root, FMP_REPLAY_PORT: String(port) };
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

test("initializes and lists the tools", async () => {
  const { request, stop } = await start();
  try {
    const init = await request("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } });
    assert.equal(init.result.protocolVersion, "2025-06-18");
    assert.deepEqual(init.result.capabilities, { tools: {} });
    assert.match(init.result.instructions, /never paste them into commits/);
    const tools = (await request("tools/list")).result.tools.map((tool) => tool.name);
    assert.deepEqual(tools, ["fmp_pull_device", "fmp_list_sessions", "fmp_session_overview", "fmp_query", "fmp_events",
      "fmp_viewer_selection", "fmp_viewer_seek", "fmp_add_note", "fmp_open_viewer"]);
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
    assert.match((await call("fmp_events", { kinds: ["rep", "secrets"] })).message, /kinds may contain only/);
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
