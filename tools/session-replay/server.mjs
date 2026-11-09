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
import { randomBytes, randomUUID } from "node:crypto";
import { promises as fs, constants as fsConstants } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createStore, StoreError } from "./lib/store.mjs";
import { createLabStore, LabStoreError } from "./lib/lab/store.mjs";
import { buildCoverageModel } from "./lib/lab/coverage.mjs";
import { buildScenarioRevision, RevisionError } from "./lib/lab/revisions.mjs";
import { validatePlanText } from "./lib/lab/plan.mjs";
import { DEFAULT_SIMULATOR, isSafeRunID, MAX_PLAN_BYTES, runPlan as runMovementPlan } from "./lib/lab/runner.mjs";

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
  "/lib/lab/keyframe.mjs": ["lib/lab/keyframe.mjs", "text/javascript; charset=utf-8"],
  "/lab/dashboard.mjs": ["public/lab/dashboard.mjs", "text/javascript; charset=utf-8"],
  "/lab/selection.mjs": ["public/lab/selection.mjs", "text/javascript; charset=utf-8"],
  "/lab/views.mjs": ["public/lab/views.mjs", "text/javascript; charset=utf-8"],
  "/lab/coverage.mjs": ["public/lab/coverage.mjs", "text/javascript; charset=utf-8"],
  "/lab/editor.mjs": ["public/lab/editor.mjs", "text/javascript; charset=utf-8"],
};

const EDIT_ID = /^[a-f0-9]{32}$/;
const EDIT_DIRECTORY = ["diagnostics", "movement-lab", "edits"];
const PAGE_NONCE_LIFETIME_MS = 60 * 60 * 1000;

function within(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

async function safeEditsDirectory(root) {
  await fs.mkdir(root, { recursive: true });
  const canonicalRoot = await fs.realpath(root);
  let current = canonicalRoot;
  for (const component of EDIT_DIRECTORY) {
    current = path.join(current, component);
    try { await fs.mkdir(current); }
    catch (error) { if (error?.code !== "EEXIST") throw error; }
    const stat = await fs.lstat(current);
    const resolved = await fs.realpath(current);
    if (!stat.isDirectory() || stat.isSymbolicLink() || resolved !== current || !within(canonicalRoot, resolved)) {
      throw new LabStoreError(403, "Movement Lab edit path must stay inside the repository.");
    }
  }
  return { canonicalRoot, directory: current };
}

async function writeEditPlan(root, plan) {
  const { canonicalRoot, directory } = await safeEditsDirectory(root);
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const editID = randomUUID().replaceAll("-", "").toLowerCase();
    const editDirectory = path.join(directory, editID);
    try { await fs.mkdir(editDirectory); }
    catch (error) { if (error?.code === "EEXIST") continue; throw error; }
    const resolved = await fs.realpath(editDirectory);
    if (!within(canonicalRoot, resolved) || resolved !== editDirectory) {
      throw new LabStoreError(403, "Movement Lab edit path must stay inside the repository.");
    }
    const temporary = path.join(editDirectory, `.plan-${randomUUID()}.tmp`);
    const target = path.join(editDirectory, "plan.json");
    try {
      await fs.writeFile(temporary, `${JSON.stringify(plan, null, 2)}\n`, { flag: "wx", mode: 0o600 });
      await fs.link(temporary, target);
      await fs.unlink(temporary);
      return editID;
    } catch (error) {
      await fs.unlink(temporary).catch(() => {});
      await fs.rm(editDirectory, { recursive: true, force: true }).catch(() => {});
      throw error;
    }
  }
  throw new Error("Could not allocate a unique Movement Lab edit id.");
}

async function readEditPlan(root, editID, maxBytes) {
  if (typeof editID !== "string" || !EDIT_ID.test(editID)) throw new LabStoreError(400, "Invalid Movement Lab edit id.");
  const { canonicalRoot, directory } = await safeEditsDirectory(root);
  const editDirectory = path.join(directory, editID);
  let directoryStat;
  try { directoryStat = await fs.lstat(editDirectory); }
  catch (error) { if (error?.code === "ENOENT") throw new LabStoreError(404, "Saved Movement Lab edit was not found."); throw error; }
  const resolvedDirectory = await fs.realpath(editDirectory);
  if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink() || resolvedDirectory !== editDirectory
    || !within(canonicalRoot, resolvedDirectory)) {
    throw new LabStoreError(403, "Movement Lab edit path must stay inside the repository.");
  }
  const planPath = path.join(editDirectory, "plan.json");
  const stat = await fs.lstat(planPath).catch((error) => {
    if (error?.code === "ENOENT") throw new LabStoreError(404, "Saved Movement Lab edit was not found.");
    throw error;
  });
  if (!stat.isFile() || stat.isSymbolicLink()) throw new LabStoreError(403, "Saved Movement Lab plan must be a regular file.");
  if (stat.size > maxBytes) throw new LabStoreError(413, "Saved Movement Lab plan is too large.");
  const handle = await fs.open(planPath, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0));
  let text;
  try {
    const openedStat = await handle.stat();
    if (!openedStat.isFile() || openedStat.size > maxBytes) throw new LabStoreError(413, "Saved Movement Lab plan is too large.");
    const bytes = await handle.readFile();
    if (bytes.byteLength > maxBytes) throw new LabStoreError(413, "Saved Movement Lab plan is too large.");
    text = bytes.toString("utf8");
  } finally { await handle.close(); }
  const checked = validatePlanText(text);
  if (checked.errors.length) throw new LabStoreError(422, `Saved Movement Lab plan is invalid:\n${checked.errors.join("\n")}`);
  return { planPath, plan: checked.plan };
}

function serialQueue() {
  let tail = Promise.resolve();
  return (operation) => {
    const result = tail.then(operation);
    tail = result.catch(() => undefined);
    return result;
  };
}

/** The viewer's server. `root` is the repository; recordings live in `root/diagnostics/sessions`. */
export function createServer({ root = REPOSITORY_ROOT, port = DEFAULT_PORT, executePlan = runMovementPlan,
  maxJSONBytes = MAX_JSON_BYTES } = {}) {
  const store = createStore(root);
  const labStore = createLabStore(root);
  const clients = new Set();
  const pageNonces = new Map();
  const enqueueRerun = serialQueue();
  let viewerState = null;
  let lastSent = null;

  function issuePageNonce() {
    const now = Date.now();
    for (const [nonce, expiry] of pageNonces) if (expiry <= now) pageNonces.delete(nonce);
    while (pageNonces.size >= 128) pageNonces.delete(pageNonces.keys().next().value);
    const nonce = randomBytes(24).toString("base64url");
    pageNonces.set(nonce, now + PAGE_NONCE_LIFETIME_MS);
    return nonce;
  }

  function requirePageNonce(request) {
    const nonce = request.headers["x-fmp-replay-nonce"];
    const expiry = pageNonces.get(nonce);
    if (typeof nonce !== "string" || expiry === undefined || expiry <= Date.now()) {
      throw new StoreError(403, "Missing or expired page nonce.");
    }
  }

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

    if (request.method === "GET" && url.pathname === "/") {
      const nonce = issuePageNonce();
      const page = (await fs.readFile(path.join(here, STATIC["/"][0]), "utf8"))
        .replace("</head>", `<meta name="fmp-replay-nonce" content="${nonce}">\n</head>`)
        .replace("</body>", '<script type="module" src="/lab/editor.mjs"></script>\n</body>');
      return send(response, 200, page, "text/html; charset=utf-8");
    }
    if (request.method === "GET" && STATIC[url.pathname]) {
      const [file, type] = STATIC[url.pathname];
      return send(response, 200, await fs.readFile(path.join(here, file)), type);
    }
    if (request.method === "GET" && url.pathname === "/api/sessions") return sendJSON(response, await store.listSessions());
    if (url.pathname === "/api/lab/scenarios") {
      if (request.method !== "POST") throw new LabStoreError(405, "Movement Lab scenario edits require POST.");
      requirePageNonce(request);
      const input = JSON.parse(await body(request, maxJSONBytes));
      if (!input || typeof input !== "object" || Array.isArray(input)) throw new RevisionError("Request must be a JSON object.");
      const sourceRun = await labStore.readRun(input.sourceRunID);
      if (!Number.isSafeInteger(input.sourceRevision) || input.sourceRevision < 1) {
        throw new RevisionError("sourceRevision must be the stored scenario revision.");
      }
      const sourceScenario = sourceRun.plan.scenarios.find((scenario) => scenario.id === input.scenarioID);
      if (!sourceScenario) throw new RevisionError(`Scenario '${input.scenarioID}' was not found in the stored source run.`);
      if (sourceScenario.revision !== input.sourceRevision) {
        throw new LabStoreError(409, "The stored source revision changed. Reload the scenario before editing.");
      }
      // The caller supplies edits only. Frozen expectations and all other base fields come from the stored run.
      const plan = buildScenarioRevision({ ...input, plan: sourceRun.plan });
      if (Buffer.byteLength(JSON.stringify(plan), "utf8") > MAX_PLAN_BYTES) {
        throw new LabStoreError(413, `Revised plan exceeds ${MAX_PLAN_BYTES} bytes.`);
      }
      const editID = await writeEditPlan(root, plan);
      return sendJSON(response, { editID, plan }, 201);
    }
    if (url.pathname === "/api/lab/runs") {
      if (request.method === "POST") {
        // Preserve the old read-only response for a bodyless POST; editor requests carry a JSON body.
        if (request.headers["content-length"] === undefined && request.headers["transfer-encoding"] === undefined) {
          throw new LabStoreError(405, "Movement Lab POST requires a JSON body.");
        }
        requirePageNonce(request);
        const input = JSON.parse(await body(request, maxJSONBytes));
        if (!input || typeof input !== "object" || Array.isArray(input)) throw new LabStoreError(400, "Request must be a JSON object.");
        const mode = input.mode ?? "pipeline";
        if (mode !== "pipeline" && mode !== "coach") throw new LabStoreError(400, "mode must be pipeline or coach.");
        const { planPath } = await readEditPlan(root, input.editID, MAX_PLAN_BYTES);
        const run = await enqueueRerun(() => executePlan({ root, planPath, sim: DEFAULT_SIMULATOR, mode }));
        if (!isSafeRunID(run?.runID)) throw new LabStoreError(500, "Movement Lab runner returned an invalid run id.");
        return sendJSON(response, { editID: input.editID, runID: run.runID, summary: run.summary ?? null });
      }
      if (request.method !== "GET") throw new LabStoreError(405, "Movement Lab runs support GET or POST.");
      return sendJSON(response, await labStore.listRuns());
    }
    if (url.pathname === "/api/lab/coverage") {
      if (request.method !== "GET") throw new LabStoreError(405, "Movement Lab routes are read-only.");
      const runs = await labStore.listRuns();
      const storedRuns = await Promise.all(runs.map((run) => labStore.readRun(run.id)));
      return sendJSON(response, buildCoverageModel(storedRuns));
    }
    const labArtifact = url.pathname.match(/^\/api\/lab\/runs\/([^/]+)\/scenarios\/([^/]+)\/([^/]+)$/);
    if (labArtifact) {
      if (request.method !== "GET") throw new LabStoreError(405, "Movement Lab routes are read-only.");
      const [, runID, scenarioID, artifact] = labArtifact;
      return sendJSON(response, await labStore.readScenarioArtifact(runID, scenarioID, artifact));
    }
    const labRun = url.pathname.match(/^\/api\/lab\/runs\/([^/]+)$/);
    if (labRun) {
      if (request.method !== "GET") throw new LabStoreError(405, "Movement Lab routes are read-only.");
      const run = await labStore.readRun(labRun[1]);
      run.runID = labRun[1];
      for (const scenario of run.plan.scenarios) scenario.sourceRunID = labRun[1];
      return sendJSON(response, run);
    }
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
      const status = error instanceof StoreError || error instanceof LabStoreError || error instanceof RevisionError ? error.status
        : error instanceof SyntaxError ? 400 : error?.code === "ENOENT" ? 404 : 500;
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
    const declaredLength = Number(request.headers["content-length"]);
    if (Number.isFinite(declaredLength) && declaredLength > limit) {
      request.resume?.();
      reject(new StoreError(413, "Too large."));
      return;
    }
    const chunks = [];
    let size = 0;
    let exceeded = false;
    request.on("data", (chunk) => {
      if (exceeded) return;
      size += chunk.length;
      if (size > limit) {
        exceeded = true;
        reject(new StoreError(413, "Too large."));
        request.resume?.();
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
