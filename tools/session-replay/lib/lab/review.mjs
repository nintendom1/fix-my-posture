import { createHash, randomUUID } from "node:crypto";
import { promises as fs, constants as fsConstants } from "node:fs";
import path from "node:path";

const REVIEW_COMPONENTS = ["diagnostics", "movement-lab", "reviews"];
const REVIEW_ID = /^[a-z0-9_-]{1,64}$/;
const RUN_ID = /^\d{8}-\d{6}-[A-Za-z0-9]{4,12}$/;
const CONTENT_HASH = /^[a-f0-9]{64}$/;
const REVIEW_STATUSES = new Set(["approved", "rejected", "exploratory", "needs-edit"]);
const MAX_REVIEW_BYTES = 64 * 1024;

export class ReviewStoreError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function isWithin(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

function stableJSON(value) {
  if (Array.isArray(value)) return `[${value.map(stableJSON).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJSON(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

/** Fingerprint the stored scenario definition independent of JSON object key order. */
export function scenarioRevisionContentHash(scenario) {
  if (!scenario || typeof scenario !== "object" || Array.isArray(scenario)) {
    throw new ReviewStoreError(400, "Scenario content must be an object.");
  }
  return createHash("sha256").update(stableJSON(scenario), "utf8").digest("hex");
}

/** Build the approval key from the stored plan scenario before any view fields are attached. */
export function scenarioReviewKey({ runID, planID, scenario } = {}) {
  if (!scenario || typeof scenario.id !== "string" || !Number.isSafeInteger(scenario.revision)) {
    throw new ReviewStoreError(400, "Stored scenario identity must include an id and positive revision.");
  }
  return validateKey({ runID, planID, scenarioID: scenario.id, revision: scenario.revision,
    contentHash: scenarioRevisionContentHash(scenario) });
}

function validateKey({ runID, planID, scenarioID, revision, contentHash } = {}) {
  if (typeof runID !== "string" || !RUN_ID.test(runID)
    || typeof planID !== "string" || !REVIEW_ID.test(planID)
    || typeof scenarioID !== "string" || !REVIEW_ID.test(scenarioID)
    || !Number.isSafeInteger(revision) || revision < 1
    || typeof contentHash !== "string" || !CONTENT_HASH.test(contentHash)) {
    throw new ReviewStoreError(400, "Review identity must include a run, safe plan/scenario ids, a positive revision, and a scenario content hash.");
  }
  return { runID, planID, scenarioID, revision, contentHash };
}

function filename({ planID, scenarioID, revision, contentHash }) {
  return `${planID}.${scenarioID}.r${revision}.${contentHash}.json`;
}

export function createReviewStore(root, { now = () => new Date() } = {}) {
  async function directory({ create }) {
    const canonicalRoot = await fs.realpath(root);
    let current = canonicalRoot;
    for (const component of REVIEW_COMPONENTS) {
      current = path.join(current, component);
      try {
        if (create) await fs.mkdir(current);
      } catch (error) {
        if (error?.code !== "EEXIST") throw error;
      }
      let stat;
      try { stat = await fs.lstat(current); }
      catch (error) { if (!create && error?.code === "ENOENT") return null; throw error; }
      const resolved = await fs.realpath(current);
      if (!stat.isDirectory() || stat.isSymbolicLink() || resolved !== current || !isWithin(canonicalRoot, resolved)) {
        throw new ReviewStoreError(403, "Movement Lab review path must stay inside diagnostics/movement-lab/reviews.");
      }
    }
    return { canonicalRoot, path: current };
  }

  async function runDirectory(base, runID, { create }) {
    const target = path.join(base.path, runID);
    try {
      if (create) await fs.mkdir(target);
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
    }
    let stat;
    try { stat = await fs.lstat(target); }
    catch (error) { if (!create && error?.code === "ENOENT") return null; throw error; }
    const resolved = await fs.realpath(target);
    if (!stat.isDirectory() || stat.isSymbolicLink() || resolved !== target || !isWithin(base.path, resolved)) {
      throw new ReviewStoreError(403, "Movement Lab review path must stay inside diagnostics/movement-lab/reviews.");
    }
    return target;
  }

  async function read(key) {
    const valid = validateKey(key);
    const base = await directory({ create: false });
    if (!base) return null;
    const scopedDirectory = await runDirectory(base, valid.runID, { create: false });
    if (!scopedDirectory) return null;
    const target = path.join(scopedDirectory, filename(valid));
    let stat;
    try { stat = await fs.lstat(target); }
    catch (error) { if (error?.code === "ENOENT") return null; throw error; }
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > MAX_REVIEW_BYTES) {
      throw new ReviewStoreError(403, "Movement Lab review state must be a small regular file.");
    }
    const resolved = await fs.realpath(target);
    if (resolved !== target || !isWithin(base.path, resolved)) {
      throw new ReviewStoreError(403, "Movement Lab review path must stay inside diagnostics/movement-lab/reviews.");
    }
    const handle = await fs.open(target, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0));
    let text;
    try { text = (await handle.readFile()).toString("utf8"); }
    finally { await handle.close(); }
    let value;
    try { value = JSON.parse(text); }
    catch { throw new ReviewStoreError(422, "Movement Lab review state is invalid JSON."); }
    if (value?.schemaVersion !== 1 || value.runID !== valid.runID || value.planID !== valid.planID
      || value.scenarioID !== valid.scenarioID || value.revision !== valid.revision
      || value.contentHash !== valid.contentHash || !REVIEW_STATUSES.has(value.status)
      || typeof value.note !== "string" || typeof value.updatedAt !== "string") {
      throw new ReviewStoreError(422, "Movement Lab review state does not match its scenario revision.");
    }
    return value;
  }

  async function save({ runID, planID, scenarioID, revision, contentHash, status, note } = {}) {
    const key = validateKey({ runID, planID, scenarioID, revision, contentHash });
    if (!REVIEW_STATUSES.has(status)) throw new ReviewStoreError(400, "Unknown Movement Lab review status.");
    if (typeof note !== "string" || !note.trim() || note.trim().length > 500) {
      throw new ReviewStoreError(400, "A review note of 1–500 characters is required.");
    }
    const previous = await read(key);
    const base = await directory({ create: true });
    const scopedDirectory = await runDirectory(base, key.runID, { create: true });
    const target = path.join(scopedDirectory, filename(key));
    const record = {
      schemaVersion: 1,
      ...key,
      status,
      note: note.trim(),
      updatedAt: now().toISOString(),
      ...(previous?.promotedAt ? { promotedAt: previous.promotedAt, fixturePath: previous.fixturePath } : {}),
    };
    const temporary = path.join(scopedDirectory, `.${filename(key)}.${randomUUID()}.tmp`);
    let handle;
    try {
      handle = await fs.open(temporary, "wx", 0o600);
      await handle.writeFile(`${JSON.stringify(record, null, 2)}\n`, "utf8");
      await handle.sync();
      await handle.close();
      handle = null;
      await fs.rename(temporary, target);
    } catch (error) {
      await handle?.close().catch(() => {});
      await fs.unlink(temporary).catch(() => {});
      throw error;
    }
    return record;
  }

  return { read, save };
}

export { REVIEW_STATUSES };
