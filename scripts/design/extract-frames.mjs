import fs from "node:fs";

const canvasPath = "fix-my-posture-mobile-app-design/project/Fix My Posture Redesign.dc.html";
const source = fs.readFileSync(canvasPath, "utf8");
const start = source.indexOf('<section class="dv-turn" id="t2">');
const end = source.indexOf("</section>", start);
if (start < 0 || end < 0) throw new Error("Could not locate #t2 in the design canvas.");
const section = source.slice(start, end);
const ids = [
  "train", "routines", "routine", "library", "exercise", "camera-ready", "complete",
  "editor", "editor-picker", "editor-new", "camera-active", "camera-paused", "camera-tip",
  "camera-rest-coach-muted", "camera-lost-mic-off", "camera-tilt", "progress", "history",
  "posture", "assessment", "settings",
];
const attrsPattern = /([\w-]+)\s*=\s*("([^"]*)"|'([^']*)')/g;
const imports = [...section.matchAll(/<dc-import\b([^>]*)>/gs)];
if (imports.length !== ids.length) throw new Error(`Expected ${ids.length} frames in #t2, found ${imports.length}.`);

function decode(value) {
  const trimmed = value.trim();
  if (trimmed === "{{ true }}") return true;
  if (trimmed === "{{ false }}") return false;
  return trimmed;
}

function labelBefore(offset) {
  const before = section.slice(0, offset);
  const pattern = /font:700 13px Nunito,system-ui;color:#555">([^<]+)<\/div>/g;
  let match;
  let last;
  while ((match = pattern.exec(before))) last = match[1];
  if (!last) throw new Error("Could not read a sibling frame label.");
  return last.trim();
}

const frames = imports.map((match, index) => {
  const attrs = {};
  let attr;
  attrsPattern.lastIndex = 0;
  while ((attr = attrsPattern.exec(match[1]))) {
    const key = attr[1];
    if (key === "name" || key === "hint-size") continue;
    attrs[key] = decode(attr[3] ?? attr[4] ?? "");
  }
  return { id: ids[index], label: labelBefore(match.index), attrs };
});

fs.mkdirSync("scripts/design", { recursive: true });
fs.writeFileSync("scripts/design/frames.json", `${JSON.stringify(frames, null, 2)}\n`);
console.log(`Extracted ${frames.length} #t2 frames to scripts/design/frames.json.`);
