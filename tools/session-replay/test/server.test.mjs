import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import http from "node:http";
import { createServer } from "../server.mjs";
import { ID, arrayText, linesText } from "./fixtures.mjs";

async function start({ followPollMs = 1000 } = {}) {
  const root = await mkdtemp(path.join(tmpdir(), "fmp-replay-"));
  await mkdir(path.join(root, "diagnostics", "sessions"), { recursive: true });
  await writeFile(path.join(root, "diagnostics", "sessions", `${ID}.json`), arrayText());
  const server = createServer({ root, followPollMs });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = server.urlFor();
  const post = (route, body, headers = {}) => fetch(base + route.slice(1), { method: "POST",
    headers: { "Content-Type": "application/json", "X-FMP-Replay": "1", ...headers }, body: typeof body === "string" ? body : JSON.stringify(body) });
  const stop = async () => { server.closeClients(); await new Promise((resolve) => server.close(resolve)); await rm(root, { recursive: true, force: true }); };
  return { root, base, post, server, stop };
}

function collectEvents(base) {
  const events = [];
  let buffer = "";
  let response;
  const ready = new Promise((resolve, reject) => {
    const request = http.get(base + "api/events", (stream) => {
      response = stream;
      stream.setEncoding("utf8");
      stream.on("data", (chunk) => {
        buffer += chunk;
        const frames = buffer.split("\n\n");
        buffer = frames.pop() ?? "";
        for (const frame of frames) {
          const line = frame.split("\n").find((value) => value.startsWith("data: "));
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
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.fail(message);
}

test("lists recordings and serves files, building a summary for one without", async () => {
  const { root, base, stop } = await start();
  try {
    const list = await (await fetch(base + "api/sessions")).json();
    assert.equal(list.length, 1);
    assert.equal(list[0].id, ID);
    assert.equal(list[0].title, "Push-Up");
    assert.equal(list[0].frameCount, 201);
    assert.equal(list[0].markerCount, 1);
    assert.equal(list[0].noteCount, 0);
    assert.ok(JSON.parse(await readFile(path.join(root, "diagnostics", "sessions", `${ID}.summary.json`), "utf8")));
    const file = await fetch(base + `api/sessions/${ID}/file`);
    assert.equal(file.status, 200);
    assert.equal(JSON.parse(await file.text()).length > 200, true);
    assert.equal((await fetch(base)).status, 200);
    assert.equal((await fetch(base + "lib/session.mjs")).status, 200);
    assert.equal((await fetch(base + "events.mjs")).status, 200);
    assert.equal((await fetch(base + "player-controls.mjs")).status, 200);
  } finally {
    await stop();
  }
});

test("saves notes beside the recording and needs the viewer's header to write", async () => {
  const { root, base, post, stop } = await start();
  try {
    const refused = await fetch(base + `api/sessions/${ID}/notes`, { method: "POST", body: JSON.stringify({ id: "n1", t: 1 }) });
    assert.equal(refused.status, 403);
    const saved = await (await post(`/api/sessions/${ID}/notes`, { id: "n1", t: 8.4, text: "shoulders vanish" })).json();
    assert.deepEqual(saved.notes.map((n) => n.text), ["shoulders vanish"]);
    const stored = JSON.parse(await readFile(path.join(root, "diagnostics", "sessions", `${ID}.notes.json`), "utf8"));
    assert.equal(stored.schema, "fmp.session-notes/1");
    assert.equal(stored.notes[0].t, 8.4);
    const listed = await (await fetch(base + "api/sessions")).json();
    assert.equal(listed[0].noteCount, 1);
    assert.equal((await post(`/api/sessions/${ID}/notes`, { text: "no id" })).status, 400);
    assert.equal((await post("/api/sessions/00000000-0000-4000-8000-000000000000/notes", { id: "x", t: 1 })).status, 404);
  } finally {
    await stop();
  }
});

test("imports a shared file, converting older JSON Lines, and rejects anything else", async () => {
  const { root, post, stop } = await start();
  try {
    await rm(path.join(root, "diagnostics", "sessions", `${ID}.json`));
    const imported = await (await post("/api/import", linesText())).json();
    assert.deepEqual(imported, { id: ID, title: "Push-Up" });
    const text = await readFile(path.join(root, "diagnostics", "sessions", `${ID}.json`), "utf8");
    assert.ok(Array.isArray(JSON.parse(text)), "stored as a JSON array");
    assert.equal((await post("/api/import", "[\n{\"k\":\"header\",\"schema\":\"other\"}\n]\n")).status, 422);
  } finally {
    await stop();
  }
});

test("Send to Claude writes the outbox, and commands reach open viewers", async () => {
  const { root, base, post, stop } = await start();
  try {
    const events = [];
    const received = new Promise((resolve) => {
      http.get(base + "api/events", (response) => {
        response.setEncoding("utf8");
        response.on("data", (chunk) => {
          for (const line of chunk.split("\n")) if (line.startsWith("data: ")) events.push(JSON.parse(line.slice(6)));
          if (events.some((event) => event.type === "command")) resolve();
        });
      });
    });
    await new Promise((resolve) => setTimeout(resolve, 100));
    const sent = await (await post("/api/viewer/sent", { sessionId: ID, from: 7.5, to: 10, markdown: "# excerpt\n" })).json();
    assert.equal(sent.path, path.join("diagnostics", "outbox", "latest.md"));
    assert.equal(await readFile(path.join(root, "diagnostics", "outbox", "latest.md"), "utf8"), "# excerpt\n");
    assert.equal((await (await fetch(base + "api/viewer/sent")).json()).to, 10);
    await post("/api/viewer/state", { sessionId: ID, t: 8.4 });
    assert.equal((await (await fetch(base + "api/viewer/state")).json()).t, 8.4);
    const delivered = await (await post("/api/viewer/command", { command: "seek", sessionId: ID, t: 8.3 })).json();
    assert.equal(delivered.delivered, 1);
    await received;
    assert.ok(events.some((event) => event.type === "sent"));
    assert.deepEqual(events.find((event) => event.type === "command"), { type: "command", command: "seek", sessionId: ID, t: 8.3 });
  } finally {
    await stop();
  }
});

test("refuses other hosts", async () => {
  const { base, stop } = await start();
  try {
    const status = await new Promise((resolve) => {
      http.get(base + "api/sessions", { headers: { Host: "attacker.example" } }, (response) => resolve(response.statusCode));
    });
    assert.equal(status, 403);
  } finally {
    await stop();
  }
});

test("concurrent note saves all survive", async () => {
  const { root, post, stop } = await start();
  try {
    const responses = await Promise.all(Array.from({ length: 25 }, (_, index) =>
      post(`/api/sessions/${ID}/notes`, { id: `n${index}`, t: index / 2, text: `note ${index}` })));
    assert.ok(responses.every((response) => response.ok));
    const stored = JSON.parse(await readFile(path.join(root, "diagnostics", "sessions", `${ID}.notes.json`), "utf8"));
    assert.equal(stored.notes.length, 25);
    assert.deepEqual(new Set(stored.notes.map((note) => note.id)).size, 25);
  } finally {
    await stop();
  }
});

test("follow events report one new recording and one completed run, after both run files exist", async () => {
  const { root, base, stop } = await start({ followPollMs: 20 });
  const stream = collectEvents(base);
  try {
    await stream.ready;
    const newID = "11111111-1111-4111-8111-111111111111";
    await writeFile(path.join(root, "diagnostics", "sessions", `${newID}.json`), arrayText());
    await waitFor(() => stream.events.filter((event) => event.type === "added" && event.id === newID).length === 1,
      "the new recording should produce one follow event");
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.equal(stream.events.filter((event) => event.type === "added" && event.id === newID).length, 1);

    const runID = "20261117-120000-f00d";
    const runDirectory = path.join(root, "diagnostics", "movement-lab", "runs", runID);
    await mkdir(runDirectory, { recursive: true });
    await writeFile(path.join(runDirectory, "summary.json"), "{}\n");
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.equal(stream.events.some((event) => event.type === "added" && event.id === runID), false,
      "a run with only summary.json is still partial");
    await writeFile(path.join(runDirectory, "results.json"), "[]\n");
    await waitFor(() => stream.events.filter((event) => event.type === "added" && event.id === runID).length === 1,
      "a run with results and summary should produce one follow event");
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.equal(stream.events.filter((event) => event.type === "added" && event.id === runID).length, 1);
    assert.deepEqual(stream.events.find((event) => event.id === newID), { type: "added", kind: "recording", id: newID });
    assert.deepEqual(stream.events.find((event) => event.id === runID), { type: "added", kind: "labRun", id: runID });
  } finally {
    stream.close();
    await stop();
  }
});

test("the follow poller stops when the viewer server closes", async () => {
  const { root, server } = await start({ followPollMs: 20 });
  try {
    assert.equal(server.followWatcherActive, true);
    server.closeClients();
    await new Promise((resolve) => server.close(resolve));
    assert.equal(server.followWatcherActive, false);
    const newID = "22222222-2222-4222-8222-222222222222";
    await writeFile(path.join(root, "diagnostics", "sessions", `${newID}.json`), arrayText());
    await new Promise((resolve) => setTimeout(resolve, 60));
    assert.equal(server.followWatcherActive, false);
  } finally { await rm(root, { recursive: true, force: true }); }
});
