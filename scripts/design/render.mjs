import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { anchors } from "./anchors.mjs";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const bundleRoot = path.join(repoRoot, "fix-my-posture-mobile-app-design/project");
const canvasPath = path.join(bundleRoot, "Fix My Posture Redesign.dc.html");
const require = createRequire(import.meta.url);
const { webkit } = require("../../build/tools/node_modules/playwright-core");
const frameJsonPath = path.join(repoRoot, "scripts/design/frames.json");
const metricsPath = path.join(repoRoot, "Design/Metrics/design-metrics.json");
const referenceDir = path.join(repoRoot, "build/design/reference");
const fontCacheDir = path.join(repoRoot, "build/design/font-cache");

if (!fs.existsSync(canvasPath)) {
  console.log("Skipping design references: local design bundle is absent.");
  process.exit(0);
}

execFileSync(process.execPath, [path.join(repoRoot, "scripts/design/extract-frames.mjs")], { cwd: repoRoot, stdio: "inherit" });
fs.mkdirSync(referenceDir, { recursive: true });
fs.mkdirSync(fontCacheDir, { recursive: true });

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
};
const server = http.createServer((request, response) => {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
  } catch {
    response.writeHead(400).end("Bad request");
    return;
  }
  const filePath = path.resolve(bundleRoot, `.${pathname}`);
  if (!filePath.startsWith(`${bundleRoot}${path.sep}`) && filePath !== bundleRoot) {
    response.writeHead(403).end("Forbidden");
    return;
  }
  fs.readFile(filePath, (error, body) => {
    if (error) {
      response.writeHead(404).end("Not found");
      return;
    }
    response.setHeader("Content-Type", contentTypes[path.extname(filePath)] ?? "application/octet-stream");
    response.setHeader("Cache-Control", "no-store");
    response.end(body);
  });
});

function cssEscapeString(value) {
  return value.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
}

function roundHalf(value) {
  return Math.round(value * 2) / 2;
}

async function cacheFont(route) {
  const url = route.request().url();
  const key = crypto.createHash("sha256").update(url).digest("hex");
  const bodyPath = path.join(fontCacheDir, `${key}.bin`);
  const metadataPath = path.join(fontCacheDir, `${key}.json`);
  if (fs.existsSync(bodyPath) && fs.existsSync(metadataPath)) {
    const body = fs.readFileSync(bodyPath);
    const metadata = JSON.parse(fs.readFileSync(metadataPath, "utf8"));
    await route.fulfill({ status: 200, headers: metadata.headers, body });
    return;
  }
  const response = await route.fetch({ timeout: 45000 });
  if (!response.ok()) throw new Error(`Font request failed (${response.status()}): ${url}`);
  const body = await response.body();
  const headers = { ...response.headers() };
  for (const header of ["content-encoding", "content-length", "transfer-encoding", "connection"]) delete headers[header];
  fs.writeFileSync(bodyPath, body);
  fs.writeFileSync(metadataPath, `${JSON.stringify({ headers }, null, 2)}\n`);
  await route.fulfill({ status: response.status(), headers, body });
}

function pageForAnchor(root, definition) {
  if (definition.selector) return root.locator(definition.selector).nth(definition.nth ?? 0);
  const textValue = cssEscapeString(definition.text);
  const matches = root.locator(`text="${textValue}"`);
  return matches.nth(definition.nth ?? 0);
}

async function main() {
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const browser = await webkit.launch({ headless: true });
  try {
    const page = await browser.newPage({
      viewport: { width: 1440, height: 1000 },
      deviceScaleFactor: 3,
      colorScheme: "dark",
      reducedMotion: "reduce",
    });
    page.on("pageerror", (error) => console.error(`Design runtime page error: ${error.message}`));
    await page.route(/^https:\/\/fonts\.(?:googleapis|gstatic)\.com\//, cacheFont);
    await page.goto(`http://127.0.0.1:${server.address().port}/Fix%20My%20Posture%20Redesign.dc.html`, {
      waitUntil: "networkidle",
      timeout: 90000,
    });
    await page.waitForSelector('#t2 .sc-host[data-sc-name="FMP App"]', { timeout: 30000 });
    await page.evaluate(() => document.fonts.ready);

    const materialFont = await page.evaluate(() => ({
      ready: document.fonts.status,
      loaded: [...document.fonts].some((face) => face.family.replaceAll('"', "").trim() === "Material Symbols Rounded" && face.status === "loaded"),
      check: document.fonts.check('24px "Material Symbols Rounded"', "home"),
    }));
    if (materialFont.ready !== "loaded" || !materialFont.loaded || !materialFont.check) {
      throw new Error(`Material Symbols Rounded did not load: ${JSON.stringify(materialFont)}`);
    }

    const frames = JSON.parse(fs.readFileSync(frameJsonPath, "utf8"));
    const imports = page.locator('#t2 .sc-host[data-sc-name="FMP App"]');
    const importCount = await imports.count();
    if (importCount !== frames.length) throw new Error(`Expected ${frames.length} rendered frames, found ${importCount}.`);

    const metricsFrames = {};
    const allIcons = new Set();
    for (let index = 0; index < frames.length; index += 1) {
      const frame = frames[index];
      const frameLocator = imports.nth(index);
      if (frame.attrs.start === "camera") {
        // The canvas hides its right-side controls after three seconds; a center tap reveals them for capture.
        await frameLocator.click({ position: { x: 195, y: 430 }, timeout: 10000 });
      }
      const bounds = await frameLocator.boundingBox();
      if (!bounds || Math.abs(bounds.width - 390) > 0.1 || Math.abs(bounds.height - 844) > 0.1) {
        throw new Error(`${frame.id} frame is not 390×844 CSS px: ${JSON.stringify(bounds)}`);
      }

      const frameAnchors = {};
      for (const [name, definition] of Object.entries(anchors[frame.id] ?? {})) {
        const locator = pageForAnchor(frameLocator, definition);
        const count = await locator.count();
        if (!count || !(await locator.first().isVisible().catch(() => false))) {
          if (definition.optional) continue;
          throw new Error(`Missing visible locator for ${frame.id}.${name}: ${JSON.stringify(definition)}`);
        }
        const box = await locator.first().evaluate((element, closestSelector) => {
          const target = closestSelector ? element.closest(closestSelector) : element;
          if (!target) return null;
          const rect = target.getBoundingClientRect();
          const frame = element.closest('.sc-host').getBoundingClientRect();
          return { x: rect.left - frame.left, y: rect.top - frame.top, width: rect.width, height: rect.height };
        }, definition.closest ?? null);
        if (!box || box.width <= 0 || box.height <= 0) {
          if (definition.optional) continue;
          throw new Error(`Anchor ${frame.id}.${name} has no visible geometry.`);
        }
        frameAnchors[name] = {
          x: roundHalf(box.x),
          y: roundHalf(box.y),
          width: roundHalf(box.width),
          height: roundHalf(box.height),
          kind: definition.kind,
        };
      }

      const extracted = await frameLocator.evaluate((element) => {
        const root = element.firstElementChild;
        const rootStyle = root ? getComputedStyle(root) : getComputedStyle(element);
        const card = [...element.querySelectorAll("[style]")].find((node) => {
          const style = getComputedStyle(node);
          const radius = parseFloat(style.borderTopLeftRadius);
          return Number.isFinite(radius) && radius > 0 && radius < 50 &&
            (style.backgroundImage !== "none" || style.backgroundColor !== "rgba(0, 0, 0, 0)");
        });
        const cardStyle = card ? getComputedStyle(card) : null;
        const primary = element.querySelector("button");
        const primaryStyle = primary ? getComputedStyle(primary) : null;
        const icons = new Set();
        for (const node of element.querySelectorAll("*")) {
          if (!getComputedStyle(node).fontFamily.includes("Material Symbols Rounded")) continue;
          for (const name of node.textContent.trim().split(/\s+/)) {
            if (/^[a-z][a-z0-9_]*$/.test(name)) icons.add(name);
          }
        }
        return {
          icons: [...icons].sort(),
          colors: {
            background: rootStyle.backgroundColor,
            foreground: rootStyle.color,
            card: cardStyle ? (cardStyle.backgroundImage !== "none" ? cardStyle.backgroundImage : cardStyle.backgroundColor) : "",
            primary: primaryStyle ? (primaryStyle.backgroundImage !== "none" ? primaryStyle.backgroundImage : primaryStyle.backgroundColor) : "",
          },
        };
      });
      extracted.icons.forEach((icon) => allIcons.add(icon));
      metricsFrames[frame.id] = {
        label: frame.label,
        attrs: frame.attrs,
        anchors: frameAnchors,
        icons: extracted.icons,
        colors: extracted.colors,
      };

      const referencePath = path.join(referenceDir, `${frame.id}.png`);
      await frameLocator.scrollIntoViewIfNeeded();
      const captureBounds = await frameLocator.boundingBox();
      if (!captureBounds) throw new Error(`Could not position ${frame.id} for capture.`);
      await page.screenshot({
        path: referencePath,
        clip: { x: captureBounds.x, y: captureBounds.y, width: 390, height: 844 },
        animations: "disabled",
        caret: "hide",
      });
      console.log(`${frame.id}: ${Object.keys(frameAnchors).length} anchors → ${path.relative(repoRoot, referencePath)}`);
    }

    const metrics = {
      version: 1,
      renderer: "playwright-webkit-2370",
      viewport: { width: 390, height: 844, scale: 3 },
      frames: metricsFrames,
      allIcons: [...allIcons].sort(),
    };
    fs.mkdirSync(path.dirname(metricsPath), { recursive: true });
    fs.writeFileSync(metricsPath, `${JSON.stringify(metrics, null, 2)}\n`);
    console.log(`Wrote ${frames.length} frame metrics and ${allIcons.size} Material Symbols to ${path.relative(repoRoot, metricsPath)}.`);
  } finally {
    await browser.close();
    await new Promise((resolve) => server.close(resolve));
  }
}

main().catch((error) => {
  console.error(error.stack ?? error);
  process.exitCode = 1;
});
