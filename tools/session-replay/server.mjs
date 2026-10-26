#!/usr/bin/env node
// Local server for the FMP session replay viewer. Serves the viewer and the recordings pulled into
// diagnostics/sessions/, saves viewer notes beside them, and keeps what the viewer sent to Claude in
// diagnostics/outbox/. It binds to 127.0.0.1 only and never sends anything off this Mac.
//
//   node tools/session-replay/server.mjs [--port 4317] [--open]
//
// Node 20 or later, no dependencies.

import { createServer as createHTTPServer } from "node:http";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Session, applyNote, emptyNotes, normalizeFileText, NOTES_SCHEMA } from "./lib/session.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
export const DEFAULT_PORT = 4317;
const MAX_IMPORT_BYTES = 300 * 1024 * 1024;
const MAX_JSON_BYTES = 8 * 1024 * 1024;
const ID = /^[0-9A-Fa-f-]{36}$/;
const STATIC = {
  "/": ["public/index.html", "text/html; charset=utf-8"],
  "/app.js": ["public/app.js", "text/javascript; charset=utf-8"],
  "/views.mjs": ["public/views.mjs", "text/javascript; charset=utf-8"],
  "/style.css": ["public/style.css", "text/css; charset=utf-8"],
  "/lib/session.mjs": ["lib/session.mjs", "text/javascript; charset=utf-8"],
};

/** The viewer's server. `root` is the repository; recordings live in `root/diagnostics/sessions`. */
export function createServer({ root = path.resolve(here, "../.."), port = DEFAULT_PORT } = {}) {
  const sessionsDir = path.join(root, "diagnostics", "sessions");
  const outboxDir = path.join(root, "diagnostics", "outbox");
  const clients = new Set();
  let viewerState = null;
  let lastSent = null;

  function broadcast(event) {
    const data = `data: ${JSON.stringify(event)}\n\n`;
    for (const client of clients) client.write(data);
  }

  async function readJSON(file, fallback) {
    try {
      return JSON.parse(await fs.readFile(file, "utf8"));
    } catch {
      return fallback;
    }
  }

  let temporaryCount = 0;
  async function writeAtomic(file, text) {
    await fs.mkdir(path.dirname(file), { recursive: true });
    temporaryCount += 1;
    const temporary = `${file}.${process.pid}.${temporaryCount}.tmp`;
    await fs.writeFile(temporary, text);
    await fs.rename(temporary, file);
  }

  // Read-modify-write work on one key (a recording's notes, or the outbox) runs one at a time, so two saves can't
  // both read the old document and lose each other's change.
  const queues = new Map();
  function serialized(key, work) {
    const run = (queues.get(key) ?? Promise.resolve()).then(work, work);
    const settled = run.catch(() => {});
    queues.set(key, settled);
    settled.then(() => { if (queues.get(key) === settled) queues.delete(key); });
    return run;
  }

  const recordingFile = (id) => path.join(sessionsDir, `${id}.json`);
  const notesFile = (id) => path.join(sessionsDir, `${id}.notes.json`);
  const summaryFile = (id) => path.join(sessionsDir, `${id}.summary.json`);

  async function notesFor(id) {
    const document = await readJSON(notesFile(id), null);
    return document?.schema === NOTES_SCHEMA ? document : emptyNotes(id);
  }

  /** A summary for the list, from the phone's sidecar or, for imported files, from the recording itself. */
  async function summaryFor(id) {
    const stored = await readJSON(summaryFile(id), null);
    if (stored) return stored;
    const session = Session.fromText(await fs.readFile(recordingFile(id), "utf8"));
    const summary = {
      id, startedAt: session.header.startedAt ?? null, endedAt: session.end?.endedAt ?? null, title: session.title,
      exerciseIDs: session.exerciseSpans.map((span) => span.label), frameCount: session.frames.length,
      markerCount: session.markers.length, isComplete: session.isComplete,
    };
    await serialized(`recording:${id}`, () => writeAtomic(summaryFile(id), JSON.stringify(summary)));
    return summary;
  }

  async function listSessions() {
    let names = [];
    try {
      names = await fs.readdir(sessionsDir);
    } catch {
      return [];
    }
    const ids = names.filter((name) => name.endsWith(".json") && !name.endsWith(".summary.json") && !name.endsWith(".notes.json"))
      .map((name) => name.slice(0, -5)).filter((id) => ID.test(id));
    const sessions = [];
    for (const id of ids) {
      try {
        const summary = await summaryFor(id);
        const stat = await fs.stat(recordingFile(id));
        const notes = await notesFor(id);
        sessions.push({ ...summary, id, bytes: stat.size, noteCount: notes.notes.length });
      } catch {
        // An unreadable file is left out of the list.
      }
    }
    return sessions.sort((a, b) => String(b.startedAt ?? "").localeCompare(String(a.startedAt ?? "")));
  }

  async function importRecording(text) {
    const normalized = normalizeFileText(text);
    const session = Session.fromText(normalized);
    if (session.header.schema !== "fmp.workout-session/1" || !ID.test(session.id)) {
      throw new HTTPError(422, "Not an FMP workout recording (schema fmp.workout-session/1).");
    }
    await serialized(`recording:${session.id}`, async () => {
      await writeAtomic(recordingFile(session.id), normalized);
      await fs.rm(summaryFile(session.id), { force: true });
    });
    return { id: session.id, title: session.title };
  }

  async function handle(request, response) {
    const url = new URL(request.url, `http://${request.headers.host}`);
    const host = request.headers.host ?? "";
    // Only this Mac may call; a page elsewhere can't reach the server through DNS rebinding.
    if (!/^(127\.0\.0\.1|localhost)(:\d+)?$/.test(host)) throw new HTTPError(403, "Forbidden host.");
    if (request.method === "POST" && request.headers["x-fmp-replay"] !== "1") {
      throw new HTTPError(403, "Missing X-FMP-Replay header.");
    }

    if (request.method === "GET" && STATIC[url.pathname]) {
      const [file, type] = STATIC[url.pathname];
      return send(response, 200, await fs.readFile(path.join(here, file)), type);
    }
    if (request.method === "GET" && url.pathname === "/api/sessions") return sendJSON(response, await listSessions());
    if (request.method === "GET" && url.pathname === "/api/events") {
      response.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
      response.write(": connected\n\n");
      clients.add(response);
      request.on("close", () => clients.delete(response));
      return;
    }
    if (url.pathname === "/api/import" && request.method === "POST") {
      return sendJSON(response, await importRecording(await body(request, MAX_IMPORT_BYTES)));
    }
    if (url.pathname === "/api/viewer/state") {
      if (request.method === "GET") return sendJSON(response, viewerState);
      if (request.method === "POST") {
        viewerState = { ...JSON.parse(await body(request, MAX_JSON_BYTES)), updatedAt: new Date().toISOString() };
        return sendJSON(response, viewerState);
      }
    }
    if (url.pathname === "/api/viewer/sent") {
      if (request.method === "GET") return sendJSON(response, lastSent);
      if (request.method === "POST") {
        const sent = JSON.parse(await body(request, MAX_JSON_BYTES));
        if (typeof sent.markdown !== "string") throw new HTTPError(400, "markdown is required.");
        const file = path.join(outboxDir, "latest.md");
        await serialized("outbox", async () => {
          lastSent = { ...sent, sentAt: new Date().toISOString() };
          await writeAtomic(file, sent.markdown);
          await writeAtomic(path.join(outboxDir, "latest.json"), JSON.stringify(lastSent, null, 2));
        });
        broadcast({ type: "sent", sessionId: sent.sessionId ?? null });
        return sendJSON(response, { path: path.relative(root, file), tokens: Math.ceil(sent.markdown.length / 3.6) });
      }
    }
    if (url.pathname === "/api/viewer/command" && request.method === "POST") {
      const command = JSON.parse(await body(request, MAX_JSON_BYTES));
      broadcast({ type: "command", ...command });
      return sendJSON(response, { delivered: clients.size });
    }
    const match = url.pathname.match(/^\/api\/sessions\/([0-9A-Fa-f-]{36})\/(file|notes)$/);
    if (match) {
      const [, id, part] = match;
      if (part === "file" && request.method === "GET") {
        return send(response, 200, await fs.readFile(recordingFile(id)), "application/json; charset=utf-8");
      }
      if (part === "notes" && request.method === "GET") return sendJSON(response, await notesFor(id));
      if (part === "notes" && request.method === "POST") {
        await fs.access(recordingFile(id));
        const note = JSON.parse(await body(request, MAX_JSON_BYTES));
        if (typeof note.id !== "string" || !Number.isFinite(Number(note.t))) throw new HTTPError(400, "A note needs id and t.");
        const document = await serialized(`notes:${id}`, async () => {
          const updated = applyNote(await notesFor(id), note);
          await writeAtomic(notesFile(id), JSON.stringify(updated, null, 2) + "\n");
          return updated;
        });
        broadcast({ type: "notes", sessionId: id });
        return sendJSON(response, document);
      }
    }
    throw new HTTPError(404, "Not found.");
  }

  const server = createHTTPServer((request, response) => {
    handle(request, response).catch((error) => {
      const status = error instanceof HTTPError ? error.status : error?.code === "ENOENT" ? 404 : 500;
      sendJSON(response, { error: error?.message ?? String(error) }, status);
    });
  });
  server.urlFor = (actualPort = server.address()?.port ?? port) => `http://127.0.0.1:${actualPort}/`;
  server.closeClients = () => { for (const client of clients) client.end(); clients.clear(); };
  return server;
}

class HTTPError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function send(response, status, data, type) {
  response.writeHead(status, { "Content-Type": type, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" });
  response.end(data);
}

function sendJSON(response, value, status = 200) {
  send(response, status, JSON.stringify(value ?? null), "application/json; charset=utf-8");
}

function body(request, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new HTTPError(413, "Too large."));
        request.destroy();
      } else {
        chunks.push(chunk);
      }
    });
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

async function main() {
  const args = process.argv.slice(2);
  const portIndex = args.indexOf("--port");
  const port = portIndex >= 0 ? Number(args[portIndex + 1]) : Number(process.env.FMP_REPLAY_PORT ?? DEFAULT_PORT);
  const shouldOpen = args.includes("--open");
  const server = createServer({ port });
  const url = `http://127.0.0.1:${port}/`;
  server.on("error", (error) => {
    if (error.code === "EADDRINUSE") {
      console.log(`The replay viewer is already running at ${url}`);
      if (shouldOpen) spawn("open", [url], { stdio: "ignore", detached: true }).unref();
      process.exit(0);
    }
    throw error;
  });
  server.listen(port, "127.0.0.1", () => {
    console.log(`FMP session replay: ${url}  (recordings: diagnostics/sessions/, Ctrl-C to stop)`);
    if (shouldOpen) spawn("open", [url], { stdio: "ignore", detached: true }).unref();
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
