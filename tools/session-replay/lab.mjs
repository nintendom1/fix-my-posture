#!/usr/bin/env node
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DEFAULT_SIMULATOR, createFreshRunDirectory, emitPresetManifest, runPlan } from "./lib/lab/runner.mjs";
import { inspectRun, parseWindow } from "./lib/lab/inspect.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

function options(tokens, allowed) {
  const values = {};
  for (let index = 0; index < tokens.length; index += 1) {
    const flag = tokens[index];
    if (!allowed.has(flag)) throw new Error(`Unknown option '${flag}'.`);
    if (flag === "--full") { values.full = true; continue; }
    const value = tokens[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`Option ${flag} requires a value.`);
    if (values[flag] !== undefined) throw new Error(`Option ${flag} was supplied more than once.`);
    values[flag] = value;
    index += 1;
  }
  return values;
}

function usage() {
  return [
    "Usage:",
    "  node tools/session-replay/lab.mjs presets [--exercise air_squat] [--sim ID]",
    "  node tools/session-replay/lab.mjs run <plan.json> [--sim ID] [--mode pipeline|coach]",
    "  node tools/session-replay/lab.mjs run --preset air_squat [--sim ID] [--mode pipeline|coach]",
    "  node tools/session-replay/lab.mjs inspect <run-id> [--scenario ID] [--window START-END] [--full]",
  ].join("\n");
}

async function presets(args) {
  const values = options(args, new Set(["--exercise", "--sim"]));
  const exercise = values["--exercise"] ?? "air_squat";
  if (!/^[a-z0-9_]{1,64}$/.test(exercise)) throw new Error("Exercise id must use lowercase letters, digits, or underscores.");
  const runDir = await createFreshRunDirectory(root);
  const manifest = await emitPresetManifest({ root, runDir, sim: values["--sim"] ?? DEFAULT_SIMULATOR });
  const ids = manifest.presets.filter((entry) => entry.plan?.scenarios?.some((scenario) => scenario.exercise === exercise)).map((entry) => entry.id);
  process.stdout.write(`${ids.join("\n")}\n`);
}

async function run(args) {
  let planPath;
  let presetID;
  if (args[0] === "--preset") {
    presetID = args[1];
    if (!presetID || presetID.startsWith("--")) throw new Error("--preset requires an id.");
    const rest = args.slice(2);
    const values = options(rest, new Set(["--sim", "--mode"]));
    const result = await runPlan({ root, presetID, sim: values["--sim"] ?? DEFAULT_SIMULATOR, mode: values["--mode"] ?? "pipeline" });
    process.stdout.write(`${appendRunID(result.text, result.runID)}\n`);
    return;
  }
  if (args[0]?.startsWith("--")) throw new Error("run expects a plan path or --preset air_squat.");
  planPath = args[0];
  if (!planPath) throw new Error("run requires a plan JSON path or --preset air_squat.");
  const values = options(args.slice(1), new Set(["--sim", "--mode"]));
  const result = await runPlan({ root, planPath: path.resolve(process.cwd(), planPath),
    sim: values["--sim"] ?? DEFAULT_SIMULATOR, mode: values["--mode"] ?? "pipeline" });
  process.stdout.write(`${appendRunID(result.text, result.runID)}\n`);
}

function appendRunID(summary, runID) {
  const lines = summary.split("\n");
  const final = lines.pop() ?? "";
  lines.push(`${final} · run ${runID}`);
  return lines.join("\n");
}

async function inspect(args) {
  const runID = args[0];
  if (!runID) throw new Error("inspect requires a run id.");
  const values = options(args.slice(1), new Set(["--scenario", "--window", "--full"]));
  const window = parseWindow(values["--window"]);
  process.stdout.write(`${await inspectRun({ root, runID, scenarioID: values["--scenario"], window, full: values.full ?? false })}\n`);
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (command === "presets") return presets(args);
  if (command === "run") return run(args);
  if (command === "inspect") return inspect(args);
  throw new Error(usage());
}

main().catch((error) => {
  process.stderr.write(`Movement Lab: ${error.message}\n`);
  process.exitCode = 1;
});
