// Recordings on this Mac: diagnostics/sessions/<id>.json with its .summary.json and .notes.json sidecars, and the
// outbox the viewer's "Send to Claude" writes. Shared by the viewer's server and the MCP tools. Node only.
import { promises as fs } from "node:fs";
import path from "node:path";
import { Session, applyNote, emptyNotes, normalizeFileText, NOTES_SCHEMA, SCHEMA } from "./session.mjs";

export const ID = /^[0-9A-Fa-f-]{36}$/;

export class StoreError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function createStore(root) {
  const sessionsDir = path.join(root, "diagnostics", "sessions");
  const outboxDir = path.join(root, "diagnostics", "outbox");
  let temporaryCount = 0;
  const queues = new Map();

  const recordingFile = (id) => path.join(sessionsDir, `${checked(id)}.json`);
  const notesFile = (id) => path.join(sessionsDir, `${checked(id)}.notes.json`);
  const summaryFile = (id) => path.join(sessionsDir, `${checked(id)}.summary.json`);

  function checked(id) {
    if (!ID.test(String(id))) throw new StoreError(400, `Not a recording id: ${id}`);
    return id;
  }

  async function readJSON(file, fallback) {
    try {
      return JSON.parse(await fs.readFile(file, "utf8"));
    } catch {
      return fallback;
    }
  }

  async function writeAtomic(file, text) {
    await fs.mkdir(path.dirname(file), { recursive: true });
    temporaryCount += 1;
    const temporary = `${file}.${process.pid}.${temporaryCount}.tmp`;
    await fs.writeFile(temporary, text);
    await fs.rename(temporary, file);
  }

  /**
   * Holds a lock file beside `file` while `work` runs, so two processes (the viewer's server and Claude's MCP server,
   * or two Claude sessions) can't both read the old document and lose each other's change. A lock older than
   * `staleAfter` was left by a crash and is taken over.
   */
  async function withFileLock(file, work, { timeout = 5000, staleAfter = 10_000 } = {}) {
    const lock = `${file}.lock`;
    await fs.mkdir(path.dirname(file), { recursive: true });
    const deadline = Date.now() + timeout;
    for (;;) {
      try {
        const handle = await fs.open(lock, "wx");
        await handle.writeFile(String(process.pid));
        await handle.close();
        break;
      } catch (error) {
        if (error.code !== "EEXIST") throw error;
        const age = await fs.stat(lock).then((stat) => Date.now() - stat.mtimeMs, () => 0);
        if (age > staleAfter) { await fs.rm(lock, { force: true }); continue; }
        if (Date.now() > deadline) throw new StoreError(503, `Another process is still saving ${path.basename(file)}.`);
        await new Promise((resolve) => setTimeout(resolve, 15 + Math.random() * 25));
      }
    }
    try {
      return await work();
    } finally {
      await fs.rm(lock, { force: true });
    }
  }

  /** Read-modify-write work on one key runs one at a time, so two saves can't both read the old document. */
  function serialized(key, work) {
    const run = (queues.get(key) ?? Promise.resolve()).then(work, work);
    const settled = run.catch(() => {});
    queues.set(key, settled);
    settled.then(() => { if (queues.get(key) === settled) queues.delete(key); });
    return run;
  }

  async function notesFor(id) {
    const document = await readJSON(notesFile(id), null);
    return document?.schema === NOTES_SCHEMA ? document : emptyNotes(id);
  }

  /** A summary for lists, from the phone's sidecar or, for imported files, from the recording itself. */
  async function summaryFor(id) {
    const stored = await readJSON(summaryFile(id), null);
    if (stored) return stored;
    const session = await readSession(id);
    const summary = {
      id, startedAt: session.header.startedAt ?? null, endedAt: session.end?.endedAt ?? null, title: session.title,
      exerciseIDs: session.exerciseSpans.map((span) => span.label), frameCount: session.frames.length,
      markerCount: session.markers.length, isComplete: session.isComplete,
    };
    await serialized(`recording:${id}`, () => writeAtomic(summaryFile(id), JSON.stringify(summary)));
    return summary;
  }

  /** Newest first. */
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

  async function readRecordingText(id) {
    try {
      return await fs.readFile(recordingFile(id), "utf8");
    } catch (error) {
      if (error.code === "ENOENT") throw new StoreError(404, `No recording ${id} in diagnostics/sessions/.`);
      throw error;
    }
  }

  async function readSession(id) {
    return Session.fromText(await readRecordingText(id));
  }

  async function saveNote(id, note) {
    await readRecordingText(id);
    if (typeof note?.id !== "string" || !Number.isFinite(Number(note.t))) throw new StoreError(400, "A note needs id and t.");
    return serialized(`notes:${id}`, () => withFileLock(notesFile(id), async () => {
      const updated = applyNote(await notesFor(id), note);
      await writeAtomic(notesFile(id), JSON.stringify(updated, null, 2) + "\n");
      return updated;
    }));
  }

  async function importRecording(text) {
    const normalized = normalizeFileText(text);
    const session = Session.fromText(normalized);
    if (session.header.schema !== SCHEMA || !ID.test(session.id)) {
      throw new StoreError(422, `Not an FMP workout recording (schema ${SCHEMA}).`);
    }
    await serialized(`recording:${session.id}`, async () => {
      await writeAtomic(recordingFile(session.id), normalized);
      await fs.rm(summaryFile(session.id), { force: true });
    });
    return { id: session.id, title: session.title };
  }

  /** What the viewer last sent to Claude: `{markdown, sessionId, from, to, ...}` or null. */
  async function readOutbox() {
    const meta = await readJSON(path.join(outboxDir, "latest.json"), null);
    if (!meta) return null;
    try {
      meta.markdown = await fs.readFile(path.join(outboxDir, "latest.md"), "utf8");
    } catch {
      // The metadata alone still says what was sent.
    }
    return meta;
  }

  async function writeOutbox(sent) {
    const file = path.join(outboxDir, "latest.md");
    const record = { ...sent, sentAt: new Date().toISOString() };
    await serialized("outbox", async () => {
      await writeAtomic(file, sent.markdown);
      await writeAtomic(path.join(outboxDir, "latest.json"), JSON.stringify(record, null, 2));
    });
    return { record, path: path.relative(root, file) };
  }

  return { root, sessionsDir, outboxDir, listSessions, readRecordingText, readSession, notesFor, saveNote, importRecording, readOutbox, writeOutbox };
}
