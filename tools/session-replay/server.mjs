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
import { createStore, StoreError } from "./lib/store.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
export const DEFAULT_PORT = 4317;
export const REPOSITORY_ROOT = path.resolve(here, "../..");
const MAX_IMPORT_BYTES = 300 * 1024 * 1024;
const MAX_JSON_BYTES = 8 * 1024 * 1024;
const STATIC = {
  "/": ["public/index.html", "text/html; charset=utf-8"],
  "/app.js": ["public/app.js", "text/javascript; charset=utf-8"],
  "/views.mjs": ["public/views.mjs", "text/javascript; charset=utf-8"],
  "/style.css": ["public/style.css", "text/css; charset=utf-8"],
  "/lib/session.mjs": ["lib/session.mjs", "text/javascript; charset=utf-8"],
};

/** The viewer's server. `root` is the repository; recordings live in `root/diagnostics/sessions`. */
export function createServer({ root = REPOSITORY_ROOT, port = DEFAULT_PORT } = {}) {
  const store = createStore(root);
  const clients = new Set();
  let viewerState = null;
  let lastSent = null;

  function broadcast(event) {
    const data = `data: ${JSON.stringify(event)}\n\n`;
    for (const client of clients) client.write(data);
  }

  async function handle(request, response) {
    const url = new URL(request.url, `http://${request.headers.host}`);
    const host = request.headers.host ?? "";
    // Only this Mac may call; a page elsewhere can't reach the server through DNS rebinding.
    if (!/^(127\.0\.0\.1|localhost)(:\d+)?$/.test(host)) throw new StoreError(403, "Forbidden host.");
    if (request.method === "POST" && request.headers["x-fmp-replay"] !== "1") {
      throw new StoreError(403, "Missing X-FMP-Replay header.");
    }

    if (request.method === "GET" && STATIC[url.pathname]) {
      const [file, type] = STATIC[url.pathname];
      return send(response, 200, await fs.readFile(path.join(here, file)), type);
    }
    if (request.method === "GET" && url.pathname === "/api/sessions") return sendJSON(response, await store.listSessions());
    if (request.method === "GET" && url.pathname === "/api/identity") {
      return sendJSON(response, { app: "fmp-replay", root: await fs.realpath(root).catch(() => root) });
    }
    if (request.method === "GET" && url.pathname === "/api/events") {
      response.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
      response.write(": connected\n\n");
      clients.add(response);
      request.on("close", () => clients.delete(response));
      return;
    }
    if (url.pathname === "/api/import" && request.method === "POST") {
      return sendJSON(response, await store.importRecording(await body(request, MAX_IMPORT_BYTES)));
    }
    if (url.pathname === "/api/viewer/state") {
      if (request.method === "GET") return sendJSON(response, { ...viewerState, viewers: clients.size });
      if (request.method === "POST") {
        viewerState = { ...JSON.parse(await body(request, MAX_JSON_BYTES)), updatedAt: new Date().toISOString() };
        return sendJSON(response, viewerState);
      }
    }
    if (url.pathname === "/api/viewer/sent") {
      if (request.method === "GET") return sendJSON(response, lastSent ?? await store.readOutbox());
      if (request.method === "POST") {
        const sent = JSON.parse(await body(request, MAX_JSON_BYTES));
        if (typeof sent.markdown !== "string") throw new StoreError(400, "markdown is required.");
        const { record, path: file } = await store.writeOutbox(sent);
        lastSent = record;
        broadcast({ type: "sent", sessionId: sent.sessionId ?? null });
        return sendJSON(response, { path: file, tokens: Math.ceil(sent.markdown.length / 3.6) });
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
        return send(response, 200, await store.readRecordingText(id), "application/json; charset=utf-8");
      }
      if (part === "notes" && request.method === "GET") return sendJSON(response, await store.notesFor(id));
      if (part === "notes" && request.method === "POST") {
        const document = await store.saveNote(id, JSON.parse(await body(request, MAX_JSON_BYTES)));
        broadcast({ type: "notes", sessionId: id });
        return sendJSON(response, document);
      }
    }
    throw new StoreError(404, "Not found.");
  }

  const server = createHTTPServer((request, response) => {
    handle(request, response).catch((error) => {
      const status = error instanceof StoreError ? error.status : error instanceof SyntaxError ? 400 : error?.code === "ENOENT" ? 404 : 500;
      sendJSON(response, { error: error?.message ?? String(error) }, status);
    });
  });
  server.urlFor = (actualPort = server.address()?.port ?? port) => `http://127.0.0.1:${actualPort}/`;
  server.closeClients = () => { for (const client of clients) client.end(); clients.clear(); };
  return server;
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
        reject(new StoreError(413, "Too large."));
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
  const server = createServer({ root: process.env.FMP_REPLAY_ROOT ?? REPOSITORY_ROOT, port });
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
