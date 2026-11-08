"""Behavior tests for the Herdr orchestration command using a fake CLI."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ENTRY_POINT = REPO_ROOT / "scripts" / "orchestrate" / "agent.py"


FAKE_HERDR = r'''#!/usr/bin/env python3
import json
import os
import shlex
import sys
from pathlib import Path

state_path = Path(os.environ["FAKE_HERDR_STATE"])
log_path = Path(os.environ["FAKE_HERDR_LOG"])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
with log_path.open("a") as log:
    log.write(json.dumps(args) + "\n")


def save():
    state_path.write_text(json.dumps(state))


def output(value, plain=False):
    if plain:
        sys.stdout.write(value)
    else:
        print(json.dumps({"id": "fake", "result": value}))


def find_pane(pane_id):
    return next((p for p in state["panes"] if p["pane_id"] == pane_id), None)


def tab_panes(tab_id):
    return sorted((p for p in state["panes"] if p["tab_id"] == tab_id), key=lambda p: p.get("order", 0))


def next_pane_id():
    state["next_pane"] += 1
    return f'w1:p{state["next_pane"]}'


def next_tab_id():
    state["next_tab"] += 1
    return f'w1:t{state["next_tab"]}'


def create_pane(tab_id, cwd=None, label=None):
    pane = {
        "pane_id": next_pane_id(), "tab_id": tab_id, "workspace_id": "w1",
        "cwd": cwd or state["repo_root"], "label": label, "proc": "zsh",
        "agent_status": "unknown", "width": 120, "order": len(tab_panes(tab_id)),
        "visible": os.environ.get("FAKE_HERDR_VISIBLE", "Codex ready"),
    }
    state["panes"].append(pane)
    return pane


def pane_layout(tab_id):
    panes = tab_panes(tab_id)
    total = sum(float(p.get("width", 120 / max(1, len(panes)))) for p in panes) or 120
    scale = 120 / total
    rects = []
    x = 0.0
    for pane in panes:
        width = float(pane.get("width", total / max(1, len(panes)))) * scale
        rects.append({"pane_id": pane["pane_id"], "rect": {"x": x, "y": 0, "width": width, "height": 40}})
        x += width
    splits = []
    for index in range(max(0, len(panes) - 1)):
        parent_x = rects[index]["rect"]["x"]
        parent_width = sum(item["rect"]["width"] for item in rects[index:])
        splits.append({
            "direction": "right", "id": f"split_{index}",
            "rect": {"x": parent_x, "y": 0, "width": parent_width, "height": 40},
            "ratio": rects[index]["rect"]["width"] / parent_width,
        })
    return {
        "area": {"x": 0, "y": 0, "width": 120, "height": 40},
        "panes": rects, "splits": splits, "tab_id": tab_id, "workspace_id": "w1", "zoomed": False,
    }


group = args[0] if args else ""
command = args[1] if len(args) > 1 else ""

if group == "pane" and command == "list":
    output({"panes": state["panes"]})
elif group == "tab" and command == "list":
    tabs = []
    for tab in state["tabs"]:
        tab = dict(tab)
        tab["pane_count"] = len(tab_panes(tab["tab_id"]))
        tabs.append(tab)
    output({"tabs": tabs})
elif group == "agent" and command == "list":
    agents = []
    for pane in state["panes"]:
        if pane.get("name"):
            tab = next(t for t in state["tabs"] if t["tab_id"] == pane["tab_id"])
            agents.append({
                "name": pane["name"], "agent": pane.get("kind", "codex"),
                "agent_status": pane.get("agent_status", "idle"),
                "pane_id": pane["pane_id"], "tab_id": pane["tab_id"], "workspace_id": "w1",
            })
    agents.extend(state.get("extra_agents", []))
    output({"agents": agents})
elif group == "pane" and command == "process-info":
    pane_id = args[args.index("--pane") + 1]
    pane = find_pane(pane_id)
    output({"process_info": {"pane_id": pane_id, "shell_pid": 1, "foreground_process_group_id": 1,
            "foreground_processes": [{"name": pane.get("proc", "zsh"), "argv0": pane.get("proc", "zsh"),
                                     "argv": [], "cmdline": pane.get("command", "")}]}})
elif group == "pane" and command == "layout":
    pane_id = args[args.index("--pane") + 1]
    pane = find_pane(pane_id)
    output({"layout": pane_layout(pane["tab_id"])})
elif group == "pane" and command == "split":
    target_id = args[2]
    target = find_pane(target_id)
    tab_id = target["tab_id"]
    old_width = float(target.get("width", 120))
    ratio = float(args[args.index("--ratio") + 1]) if "--ratio" in args else 0.5
    cwd = args[args.index("--cwd") + 1] if "--cwd" in args else target["cwd"]
    target["width"] = old_width * ratio
    pane = create_pane(tab_id, cwd=cwd)
    pane["width"] = old_width * (1 - ratio)
    pane["order"] = target["order"] + 1
    for other in tab_panes(tab_id):
        if other["order"] > target["order"] and other["pane_id"] != pane["pane_id"]:
            other["order"] += 1
    save()
    output({"pane": pane})
elif group == "pane" and command == "resize":
    pane_id = args[args.index("--pane") + 1]
    pane = find_pane(pane_id)
    panes = tab_panes(pane["tab_id"])
    index = panes.index(pane)
    direction = args[args.index("--direction") + 1]
    amount = float(args[args.index("--amount") + 1])
    layout = pane_layout(pane["tab_id"])
    layout_widths = {item["pane_id"]: item["rect"]["width"] for item in layout["panes"]}
    raw_total = sum(float(item.get("width", 0)) for item in panes)
    if direction == "right" and index + 1 < len(panes):
        parent_width = sum(layout_widths[item["pane_id"]] for item in panes[index:])
        delta = parent_width * amount * raw_total / 120
        pane["width"] += delta
        panes[index + 1]["width"] -= delta
    elif direction == "left" and index > 0:
        parent_width = sum(layout_widths[item["pane_id"]] for item in panes[index - 1:])
        delta = parent_width * amount * raw_total / 120
        pane["width"] += delta
        panes[index - 1]["width"] -= delta
    save()
    output({"pane_id": pane_id})
elif group == "pane" and command == "rename":
    pane = find_pane(args[2])
    pane["label"] = " ".join(args[3:])
    save()
    output({"pane": pane})
elif group == "tab" and command == "create":
    label = args[args.index("--label") + 1]
    cwd = args[args.index("--cwd") + 1]
    tab_id = next_tab_id()
    tab = {"tab_id": tab_id, "workspace_id": "w1", "label": label, "number": len(state["tabs"]) + 1}
    state["tabs"].append(tab)
    pane = create_pane(tab_id, cwd=cwd)
    save()
    output({"tab": tab, "root_pane": pane})
elif group == "pane" and command == "move":
    pane_id = args[2]
    pane = find_pane(pane_id)
    old_tab_id = pane["tab_id"]
    if "--new-tab" in args:
        label = args[args.index("--label") + 1]
        tab_id = next_tab_id()
        tab = {"tab_id": tab_id, "workspace_id": "w1", "label": label, "number": len(state["tabs"]) + 1}
        state["tabs"].append(tab)
        pane["tab_id"] = tab_id
        pane["order"] = 0
        pane["width"] = 120
    else:
        tab_id = args[args.index("--tab") + 1]
        target_id = args[args.index("--target-pane") + 1]
        target = find_pane(target_id)
        ratio = float(args[args.index("--ratio") + 1]) if "--ratio" in args else 0.5
        old_width = float(target.get("width", 120))
        target["width"] = old_width * ratio
        pane["tab_id"] = tab_id
        pane["width"] = old_width * (1 - ratio)
        pane["order"] = target["order"] + 1
        for other in tab_panes(tab_id):
            if other["order"] > target["order"] and other["pane_id"] != pane_id:
                other["order"] += 1
    save()
    output({"move_result": {"pane": {"pane_id": pane_id}, "previous_pane_id": pane_id}})
elif group == "pane" and command == "close":
    pane_id = args[2]
    pane = find_pane(pane_id)
    tab_id = pane["tab_id"]
    state["panes"].remove(pane)
    save()
    output({"pane_id": pane_id})
elif group == "tab" and command == "close":
    tab_id = args[2]
    state["tabs"] = [tab for tab in state["tabs"] if tab["tab_id"] != tab_id]
    save()
    output({"tab_id": tab_id})
elif group == "agent" and command == "start":
    name = args[2]
    kind = args[args.index("--kind") + 1]
    pane_id = args[args.index("--pane") + 1]
    pane = find_pane(pane_id)
    pane.update({"name": name, "kind": kind, "agent_status": "idle", "proc": kind})
    save()
    output({"agent": {"name": name, "pane_id": pane_id, "agent_status": "idle"}})
elif group == "agent" and command == "prompt":
    name = args[2]
    pane = next(p for p in state["panes"] if p.get("name") == name)
    pane["prompt"] = args[3]
    save()
    output({"accepted": True})
elif group == "agent" and command == "wait":
    name = args[2]
    pane = next(p for p in state["panes"] if p.get("name") == name)
    output({"agent": {"name": name, "agent_status": pane.get("agent_status", "idle")}})
elif group == "agent" and command == "read":
    name = args[2]
    pane = next(p for p in state["panes"] if p.get("name") == name)
    source = args[args.index("--source") + 1] if "--source" in args else "recent"
    if os.environ.get("FAKE_HERDR_FAIL") == "agent read":
        metadata_path = Path(os.environ["FAKE_REPO_ROOT"]) / "build" / "orchestrate" / "state.json"
        try:
            managed = json.loads(metadata_path.read_text()).get("agents", {})
        except (OSError, json.JSONDecodeError):
            managed = {}
        state["read_saw_managed"] = name in managed
        save()
        print(json.dumps({"error": {"message": "injected read failure"}}), file=sys.stderr)
        sys.exit(1)
    if source == "visible":
        output(pane.get("visible", "Ready\n"), plain=True)
    else:
        output("", plain=True)
elif group == "agent" and command == "send-keys":
    if os.environ.get("FAKE_HERDR_FAIL") == "agent send-keys":
        print(json.dumps({"error": {"message": "injected send-keys failure"}}), file=sys.stderr)
        sys.exit(1)
    output({"sent": args[3:]})
elif group == "pane" and command == "run":
    pane_id = args[2]
    pane = find_pane(pane_id)
    command_text = " ".join(args[3:])
    pane["command"] = command_text
    if command_text.startswith("cd "):
        parts = shlex.split(command_text)
        pane["cwd"] = parts[1]
        pane["proc"] = "zsh"
    else:
        pane["proc"] = command_text.split()[0]
    save()
    output({"pane_id": pane_id})
else:
    print(json.dumps({"error": {"message": "unsupported fake command: " + " ".join(args)}}), file=sys.stderr)
    sys.exit(1)
'''


FAKE_GIT = r'''#!/usr/bin/env python3
import os
import sys
if sys.argv[1:] == ["rev-parse", "--show-toplevel"]:
    print(os.environ["FAKE_REPO_ROOT"])
    sys.exit(0)
sys.exit(2)
'''


class OrchestrateAgentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.repo = self.base / "repo"
        self.repo.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for filename, source in (("herdr", FAKE_HERDR), ("git", FAKE_GIT)):
            path = self.bin / filename
            path.write_text(source, encoding="utf-8")
            path.chmod(0o755)
        self.state_path = self.base / "herdr-state.json"
        self.log_path = self.base / "herdr-log.jsonl"
        self.state = self.base_state()
        self.write_state()
        self.env = os.environ.copy()
        self.env.update({
            "PATH": str(self.bin) + os.pathsep + self.env.get("PATH", ""),
            "HERDR_ENV": "1",
            "HERDR_WORKSPACE_ID": "w1",
            "FAKE_REPO_ROOT": str(self.repo),
            "FAKE_HERDR_STATE": str(self.state_path),
            "FAKE_HERDR_LOG": str(self.log_path),
        })

    def tearDown(self) -> None:
        self.temp.cleanup()

    def base_state(self) -> dict:
        tab_id = "w1:t1"
        return {
            "repo_root": str(self.repo), "next_pane": 1, "next_tab": 1,
            "focused_pane_id": "w1:p1",
            "tabs": [{"tab_id": tab_id, "workspace_id": "w1", "label": "Main", "number": 1}],
            "panes": [{
                "pane_id": "w1:p1", "tab_id": tab_id, "workspace_id": "w1",
                "label": "Orchestrator", "cwd": str(self.repo), "proc": "claude",
                "name": "orchestrator", "kind": "claude", "agent_status": "working",
                "width": 120, "order": 0, "visible": "Ready",
            }],
        }

    def write_state(self) -> None:
        self.state_path.write_text(json.dumps(self.state), encoding="utf-8")

    def read_state(self) -> dict:
        self.state = json.loads(self.state_path.read_text(encoding="utf-8"))
        return self.state

    def write_metadata(self, *, agents: dict | None = None, scripts: dict | None = None) -> None:
        path = self.repo / "build" / "orchestrate" / "state.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        agent_metadata = agents or {}
        script_metadata = scripts or {}
        for name, meta in agent_metadata.items():
            if isinstance(meta, dict) and not meta.get("pane_id"):
                pane = next((item for item in self.state["panes"] if item.get("name") == name), None)
                if pane:
                    meta["pane_id"] = pane["pane_id"]
        for purpose, meta in script_metadata.items():
            if isinstance(meta, dict) and not meta.get("pane_id"):
                pane = next((item for item in self.state["panes"] if item.get("label") == purpose), None)
                if pane:
                    meta["pane_id"] = pane["pane_id"]
        managed_ids = {
            str(meta["pane_id"])
            for section in (agent_metadata, script_metadata)
            for meta in section.values()
            if isinstance(meta, dict) and meta.get("pane_id")
        }
        managed_tabs = set(self.state.get("managed_tabs", []))
        for tab in self.state["tabs"]:
            if tab.get("label") not in {"Agent", "Agent 2", "Agent 3", "Scripts", "Scripts 2", "Scripts 3"}:
                continue
            pane_ids = {str(pane["pane_id"]) for pane in self.state["panes"] if pane["tab_id"] == tab["tab_id"]}
            if pane_ids and pane_ids <= managed_ids:
                managed_tabs.add(tab["tab_id"])
        self.state["managed_tabs"] = sorted(managed_tabs)
        self.write_state()
        path.write_text(json.dumps({
            "agents": agent_metadata, "scripts": script_metadata,
            "managed_tabs": sorted(managed_tabs),
        }), encoding="utf-8")

    def run_tool(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(ENTRY_POINT), *args],
            cwd=self.repo, env=self.env, text=True, capture_output=True, check=False,
        )

    def calls(self) -> list[list[str]]:
        if not self.log_path.exists():
            return []
        return [json.loads(line) for line in self.log_path.read_text(encoding="utf-8").splitlines()]

    def start(self, name: str, *, kind: str = "codex", model: str = "gpt-6-luna", role: str = "implementer", purpose: str | None = None, extra: tuple[str, ...] = ()) -> subprocess.CompletedProcess[str]:
        return self.run_tool(
            "start", name, "--kind", kind, "--model", model,
            "--purpose", purpose or f"{name} pane", "--role", role, *extra,
        )

    def get_managed_state(self) -> dict:
        return json.loads((self.repo / "build" / "orchestrate" / "state.json").read_text(encoding="utf-8"))

    def pane(self, name: str) -> dict:
        return next(p for p in self.read_state()["panes"] if p.get("name") == name)

    def widths(self, tab_id: str) -> list[float]:
        panes = sorted(
            (pane for pane in self.read_state()["panes"] if pane["tab_id"] == tab_id),
            key=lambda pane: pane.get("order", 0),
        )
        total = sum(float(pane.get("width", 120 / max(1, len(panes)))) for pane in panes) or 120
        return [float(pane.get("width", total / max(1, len(panes)))) * 120 / total for pane in panes]

    def assert_widths(self, tab_id: str, expected: list[float]) -> None:
        actual = self.widths(tab_id)
        self.assertEqual(len(actual), len(expected))
        for width, target in zip(actual, expected):
            self.assertAlmostEqual(width, target, places=3)

    def add_pane(self, *, tab: str = "w1:t1", label: str | None = None, name: str | None = None, kind: str = "codex", status: str = "idle", proc: str | None = None, width: float | None = None, cwd: str | None = None, visible: str = "Ready") -> dict:
        pane_id = f"w1:p{self.state['next_pane'] + 1}"
        self.state["next_pane"] += 1
        count = sum(p["tab_id"] == tab for p in self.state["panes"])
        pane = {
            "pane_id": pane_id, "tab_id": tab, "workspace_id": "w1", "label": label,
            "name": name, "kind": kind, "agent_status": status, "proc": proc or (kind if name else "zsh"),
            "cwd": cwd or str(self.repo), "width": width or 120 / (count + 1), "order": count,
            "visible": visible,
        }
        self.state["panes"].append(pane)
        self.write_state()
        return pane

    def add_tab(self, label: str) -> dict:
        tab_id = f"w1:t{self.state['next_tab'] + 1}"
        self.state["next_tab"] += 1
        tab = {"tab_id": tab_id, "workspace_id": "w1", "label": label, "number": len(self.state["tabs"]) + 1}
        self.state["tabs"].append(tab)
        return tab

    def test_start_uses_explicit_working_directory(self) -> None:
        working_dir = self.repo / "alternate"
        working_dir.mkdir()
        result = self.start("cwdagent", extra=("--cwd", str(working_dir)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.pane("cwdagent")["cwd"], str(working_dir.resolve()))

    def test_start_equalizes_after_split_without_fake_herdr_help(self) -> None:
        first = self.start("first")
        self.assertEqual(first.returncode, 0, first.stderr)
        second = self.start("second")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assert_widths("w1:t1", [40, 40, 40])
        self.assertEqual(self.read_state()["focused_pane_id"], "w1:p1")

    def test_start_and_script_use_overflow_when_main_has_two_unrecorded_agents(self) -> None:
        main_user_agent_one = self.add_pane(name="userclaude", kind="claude", proc="claude", width=40)
        main_user_agent_two = self.add_pane(name="usercodex", kind="codex", proc="codex", width=40)
        self.write_state()
        self.write_metadata()
        unmanaged_ids = {main_user_agent_one["pane_id"], main_user_agent_two["pane_id"]}
        before = json.loads(json.dumps([
            pane for pane in self.state["panes"] if pane["pane_id"] in unmanaged_ids
        ]))

        started = self.start("worker", purpose="Worker")
        self.assertEqual(started.returncode, 0, started.stderr)
        state = self.read_state()
        agent_tab = next(tab for tab in state["tabs"] if tab["label"] == "Agent")
        self.assertEqual(self.pane("worker")["tab_id"], agent_tab["tab_id"])
        self.assertEqual(sum(pane["tab_id"] == "w1:t1" for pane in state["panes"]), 3)

        scripted = self.run_tool("script", "Watcher", "--", "sleep", "10")
        self.assertEqual(scripted.returncode, 0, scripted.stderr)
        state = self.read_state()
        scripts_tab = next(tab for tab in state["tabs"] if tab["label"] == "Scripts")
        watcher = next(pane for pane in state["panes"] if pane.get("label") == "Watcher")
        self.assertEqual(watcher["tab_id"], scripts_tab["tab_id"])
        self.assertEqual(sum(pane["tab_id"] == "w1:t1" for pane in state["panes"]), 3)
        self.assertEqual(
            [pane for pane in state["panes"] if pane["pane_id"] in unmanaged_ids], before
        )
        for call in self.calls():
            if call[:2] == ["pane", "move"]:
                self.assertNotIn(call[2], unmanaged_ids, call)
            if call[:2] in (["pane", "resize"], ["pane", "rename"], ["pane", "close"], ["pane", "split"], ["pane", "run"]):
                target = call[call.index("--pane") + 1] if "--pane" in call else call[2]
                self.assertNotIn(target, unmanaged_ids, call)

    def test_close_does_not_promote_into_full_main_with_unrecorded_agents(self) -> None:
        overflow = self.add_tab("Agent")
        userclaude = self.add_pane(name="userclaude", kind="claude", proc="claude", width=40)
        usercodex = self.add_pane(name="usercodex", kind="codex", proc="codex", width=40)
        closing = self.add_pane(name="closing", tab=overflow["tab_id"])
        waiting = self.add_pane(name="waiting", tab=overflow["tab_id"])
        self.write_state()
        self.write_metadata(agents={
            "closing": {"kind": "codex", "model": "gpt-6-luna", "pane_id": closing["pane_id"]},
            "waiting": {"kind": "codex", "model": "gpt-6-luna", "pane_id": waiting["pane_id"]},
        })

        result = self.run_tool("close", "closing")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        self.assertEqual(sum(pane["tab_id"] == "w1:t1" for pane in state["panes"]), 3)
        self.assertEqual(self.pane("waiting")["tab_id"], overflow["tab_id"])
        self.assertTrue(any(pane["pane_id"] == userclaude["pane_id"] for pane in state["panes"]))
        self.assertTrue(any(pane["pane_id"] == usercodex["pane_id"] for pane in state["panes"]))
        self.assertFalse(any(
            call[:2] == ["pane", "move"] and call[2] == waiting["pane_id"]
            for call in self.calls()
        ))

    def test_third_agent_overflows_and_fourth_fills_agent(self) -> None:
        for name in ("one", "two", "three", "four"):
            result = self.start(name)
            self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        self.assertEqual(self.pane("one")["tab_id"], "w1:t1")
        self.assertEqual(self.pane("two")["tab_id"], "w1:t1")
        agent_tab = next(tab for tab in state["tabs"] if tab["label"] == "Agent")
        self.assertEqual(self.pane("three")["tab_id"], agent_tab["tab_id"])
        self.assertEqual(self.pane("four")["tab_id"], agent_tab["tab_id"])
        self.assertEqual(sum(p["tab_id"] == agent_tab["tab_id"] for p in state["panes"]), 2)
        self.assert_widths("w1:t1", [40, 40, 40])
        self.assert_widths(agent_tab["tab_id"], [60, 60])
        self.assertEqual(state["focused_pane_id"], "w1:p1")

    def test_seventh_pane_creates_agent_2_and_capacity_stays_at_three(self) -> None:
        # Six existing panes (Orchestrator, two Main agents, three Agent agents) precede pane seven.
        agent_tab = self.add_tab("Agent")
        self.add_pane(name="agent1", tab="w1:t1", width=40)
        self.add_pane(name="agent2", tab="w1:t1", width=40)
        for index in range(3, 6):
            self.add_pane(name=f"agent{index}", tab=agent_tab["tab_id"], width=40)
        self.write_state()
        self.write_metadata(agents={
            f"agent{index}": {
                "kind": "codex", "model": "gpt-6-luna", "role": "implementer",
                "started_at": f"2026-01-0{index}T00:00:00Z",
            }
            for index in range(1, 6)
        })
        result = self.start("agent6")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        agent2 = next((tab for tab in state["tabs"] if tab["label"] == "Agent 2"), None)
        self.assertIsNotNone(agent2)
        self.assertEqual(self.pane("agent6")["tab_id"], agent2["tab_id"])
        self.assertLessEqual(max(sum(p["tab_id"] == t["tab_id"] for p in state["panes"]) for t in state["tabs"]), 3)

    def test_main_script_moves_to_scripts_before_new_agent(self) -> None:
        script = self.add_pane(label="Validation", proc="make", width=40)
        main_agent = self.add_pane(name="existing", kind="codex", status="working", width=40)
        main_agent["order"] = 1
        script["order"] = 2
        self.write_state()
        self.write_metadata(
            agents={"existing": {"kind": "codex", "model": "gpt-6-luna", "role": "implementer", "started_at": "2026-01-01T00:00:00Z"}},
            scripts={"Validation": {"started_at": "2026-01-01T00:00:00Z"}},
        )
        result = self.start("next")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        scripts_tab = next(tab for tab in state["tabs"] if tab["label"] == "Scripts")
        self.assertEqual(next(p for p in state["panes"] if p["label"] == "Validation")["tab_id"], scripts_tab["tab_id"])
        self.assertEqual(self.pane("next")["tab_id"], "w1:t1")

    def test_close_promotes_all_waiting_agents_before_backfilling_scripts(self) -> None:
        old = self.add_tab("Agent")
        scripts = self.add_tab("Scripts")
        self.add_pane(name="closing", kind="codex", tab="w1:t1", status="done")
        waiting_late = self.add_pane(name="waitinglate", tab=old["tab_id"], width=60)
        waiting_early = self.add_pane(name="waitingearly", tab=old["tab_id"], width=60)
        script = self.add_pane(label="Validation", tab=scripts["tab_id"], proc="make", width=120)
        script["order"] = 0
        self.write_state()
        self.write_metadata(agents={
            "closing": {"kind": "codex", "model": "x", "role": "implementer", "started_at": "2026-01-01T00:00:00Z", "start_order": 1},
            "waitinglate": {"kind": "codex", "model": "x", "role": "implementer", "started_at": "2026-01-02T00:00:00Z", "start_order": 2},
            "waitingearly": {"kind": "codex", "model": "x", "role": "implementer", "started_at": "2026-01-02T00:00:00Z", "start_order": 3},
        }, scripts={"Validation": {"started_at": "2026-01-01T00:00:00Z"}})
        result = self.run_tool("close", "closing")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        self.assertEqual(self.pane("waitinglate")["tab_id"], "w1:t1")
        self.assertEqual(self.pane("waitingearly")["tab_id"], "w1:t1")
        scripts_tab = next(tab for tab in state["tabs"] if tab["label"] == "Scripts")
        self.assertEqual(next(p for p in state["panes"] if p.get("label") == "Validation")["tab_id"], scripts_tab["tab_id"])
        self.assertIn("promoted=waitinglate,waitingearly", result.stdout)
        self.assertEqual(state["focused_pane_id"], "w1:p1")
        self.assert_widths("w1:t1", [40, 40, 40])

    def test_equal_width_resize_requests_for_two_and_three_columns(self) -> None:
        two = self.add_pane(name="worker", width=50)
        self.state["panes"][0]["width"] = 70
        two["width"] = 50
        self.write_state()
        self.write_metadata(agents={"worker": {"kind": "codex", "pane_id": two["pane_id"]}})
        result = self.run_tool("layout")
        self.assertEqual(result.returncode, 0, result.stderr)
        resize = [call for call in self.calls() if call[:2] == ["pane", "resize"]]
        self.assertEqual(len(resize), 1)
        self.assertEqual(resize[0][resize[0].index("--direction") + 1], "left")
        self.assertEqual(resize[0][resize[0].index("--amount") + 1], "0.083333")
        self.assert_widths("w1:t1", [60, 60])

        self.log_path.write_text("", encoding="utf-8")
        self.state = self.base_state()
        self.state["panes"][0]["width"] = 60
        three_one = self.add_pane(name="workerone", width=30)
        three_two = self.add_pane(name="workertwo", width=30)
        self.write_state()
        self.write_metadata(agents={
            "workerone": {"kind": "codex", "pane_id": three_one["pane_id"]},
            "workertwo": {"kind": "codex", "pane_id": three_two["pane_id"]},
        })
        result = self.run_tool("layout")
        self.assertEqual(result.returncode, 0, result.stderr)
        resize = [call for call in self.calls() if call[:2] == ["pane", "resize"]]
        self.assertEqual(len(resize), 2)
        amounts = [call[call.index("--amount") + 1] for call in resize]
        self.assertEqual(amounts, ["0.166667", "0.125000"])
        self.assert_widths("w1:t1", [40, 40, 40])

    def test_long_purpose_is_rejected(self) -> None:
        result = self.start("purpose", purpose="This purpose is much too long")
        self.assertEqual(result.returncode, 2)
        self.assertIn("20 characters", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_astra_fable_and_terra_models_are_refused(self) -> None:
        for model in ("gpt-6-astra", "gpt-fable", "gpt-6-terra"):
            result = self.start("refused", model=model)
            self.assertEqual(result.returncode, 2)
            self.assertIn("refusing", result.stderr)
        self.assertEqual(self.calls(), [])
        allowed = self.start("terra", model="gpt-6-terra", extra=("--allow-terra",))
        self.assertEqual(allowed.returncode, 0, allowed.stderr)

    def test_prompt_prefix_and_no_double_prefix(self) -> None:
        writer = self.add_pane(name="writer", tab="w1:t1")
        self.write_state()
        self.write_metadata(agents={"writer": {"kind": "codex", "model": "gpt-6-luna", "role": "implementer", "started_at": "2026-01-01T00:00:00Z"}})
        first = self.run_tool("prompt", "writer", "--text", "Check this")
        second = self.run_tool("prompt", "writer", "--text", "Orchestrator: already prefixed")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        prompts = [call[-1] for call in self.calls() if call[:2] == ["agent", "prompt"]]
        self.assertEqual(prompts, ["Orchestrator: Check this", "Orchestrator: already prefixed"])

    def test_brief_wait_prints_one_line_with_report(self) -> None:
        self.add_pane(name="worker", tab="w1:t1")
        self.write_state()
        self.write_metadata(agents={"worker": {"kind": "codex", "model": "gpt-6-luna", "role": "implementer", "started_at": "2026-01-01T00:00:00Z"}})
        report_dir = self.repo / "build" / "briefs"
        report_dir.mkdir(parents=True)
        (report_dir / "worker.report.md").write_text("done", encoding="utf-8")
        result = self.run_tool("prompt", "worker", "--brief", "build/briefs/worker.md", "--wait", "--timeout", "2")
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0], "worker state=idle report=build/briefs/worker.report.md")
        prompt = next(call for call in self.calls() if call[:2] == ["agent", "prompt"])
        self.assertEqual(prompt[-1], "Orchestrator: Read build/briefs/worker.md and do exactly what it says. Reply DONE or BLOCKED.")
        wait = next(call for call in self.calls() if call[:2] == ["agent", "wait"])
        self.assertEqual(wait[wait.index("--timeout") + 1], "2000")

    def test_blocked_wait_prints_last_five_visible_lines(self) -> None:
        self.add_pane(name="blocked", tab="w1:t1")
        self.write_state()
        self.write_metadata(agents={"blocked": {"kind": "codex", "model": "gpt-6-luna", "role": "implementer", "started_at": "2026-01-01T00:00:00Z"}})
        pane = self.pane("blocked")
        pane["agent_status"] = "blocked"
        pane["visible"] = "line one\nline two\nline three\nline four\nline five\nline six\n"
        self.write_state()
        result = self.run_tool("prompt", "blocked", "--text", "continue", "--wait")
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertIn("blocked state=blocked", lines[0])
        self.assertEqual(lines[1:], ["line two", "line three", "line four", "line five", "line six"])

    def test_codex_claude_flags_and_role_tool_lists(self) -> None:
        codex = self.start("codexer", model="gpt-6-luna")
        claude_impl = self.start("claudeimpl", kind="claude", model="claude-sonnet-4-5", purpose="Implement")
        claude_review = self.start("reviewer", kind="claude", model="claude-opus-5-5", role="reviewer", purpose="Review")
        for result in (codex, claude_impl, claude_review):
            self.assertEqual(result.returncode, 0, result.stderr)
        starts = [call for call in self.calls() if call[:2] == ["agent", "start"]]
        codex_call = next(call for call in starts if call[2] == "codexer")
        self.assertEqual(codex_call[codex_call.index("--") + 1:], ["-m", "gpt-6-luna", "-c", "model_reasoning_effort=max", "-s", "workspace-write", "-a", "on-request"])
        impl_call = next(call for call in starts if call[2] == "claudeimpl")
        reviewer_call = next(call for call in starts if call[2] == "reviewer")
        for call in (impl_call, reviewer_call):
            self.assertEqual(call[call.index("--") + 1:call.index("--") + 5], ["--model", call[call.index("--") + 2], "--permission-mode", "acceptEdits"])
        self.assertEqual(impl_call[impl_call.index("--allowedTools") + 1], "Bash(scripts/agent-build.sh:*) Bash(swift test:*) Bash(swift build:*) Bash(xcodebuild:*) Bash(git diff:*) Bash(git status:*) Bash(git log:*) Bash(node --test:*) Bash(python3 -m unittest:*) Read Edit Write Glob Grep")
        self.assertEqual(reviewer_call[reviewer_call.index("--allowedTools") + 1], "Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*) Read Glob Grep Write(build/reviews/**) Edit(build/reviews/**)")

    def test_script_uses_main_when_available_and_scripts_tab_when_busy(self) -> None:
        main = self.run_tool("script", "Watcher", "--", "python3", "-m", "http.server")
        self.assertEqual(main.returncode, 0, main.stderr)
        self.assertIn("tab=Main", main.stdout)
        pane = next(p for p in self.read_state()["panes"] if p.get("label") == "Watcher")
        self.assertEqual(pane.get("command"), "python3 -m http.server")

    def test_script_uses_scripts_tab_when_an_agent_is_waiting(self) -> None:
        overflow = self.add_tab("Agent")
        self.add_pane(name="mainone", tab="w1:t1")
        self.add_pane(name="maintwo", tab="w1:t1")
        self.add_pane(name="busy", tab=overflow["tab_id"])
        self.write_state()
        self.write_metadata(agents={name: {
            "kind": "codex", "model": "gpt-6-luna", "role": "implementer",
            "started_at": f"2026-01-0{index}T00:00:00Z", "start_order": index,
        } for index, name in enumerate(("mainone", "maintwo", "busy"), start=1)})
        result = self.run_tool("script", "Validation", "--", "make", "check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tab=Scripts", result.stdout)
        script_tab = next(tab for tab in self.read_state()["tabs"] if tab["label"] == "Scripts")
        script_pane = next(p for p in self.read_state()["panes"] if p.get("label") == "Validation")
        self.assertEqual(script_pane["tab_id"], script_tab["tab_id"])

    def test_purpose_orchestrator_is_reserved_and_agent_purposes_are_unique(self) -> None:
        reserved = self.start("reserved", purpose="Orchestrator")
        self.assertNotEqual(reserved.returncode, 0)
        self.assertIn("reserved", reserved.stderr)
        self.assertEqual(self.calls(), [])
        script_reserved = self.run_tool("script", "Orchestrator", "--", "sleep", "1")
        self.assertNotEqual(script_reserved.returncode, 0)
        self.assertIn("reserved", script_reserved.stderr)
        self.assertEqual(self.calls(), [])

        first = self.start("first", purpose="Review: engine")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.log_path.write_text("", encoding="utf-8")
        duplicate = self.start("second", purpose="Review: engine")
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertIn("already used", duplicate.stderr)
        self.assertFalse(any(call[:2] in (["pane", "rename"], ["agent", "start"]) for call in self.calls()))

    def test_script_purpose_cannot_collide_with_agent_purpose(self) -> None:
        result = self.start("review", purpose="Review: engine")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.log_path.write_text("", encoding="utf-8")
        script = self.run_tool("script", "Review: engine", "--", "make", "check")
        self.assertNotEqual(script.returncode, 0)
        self.assertIn("already used", script.stderr)
        self.assertFalse(any(call[:2] in (["pane", "run"], ["agent", "start"]) for call in self.calls()))

    def test_script_in_scripts_tab_does_not_lose_its_result_to_new_script(self) -> None:
        overflow = self.add_tab("Agent")
        scripts = self.add_tab("Scripts")
        self.add_pane(name="mainone", tab="w1:t1")
        self.add_pane(name="maintwo", tab="w1:t1")
        self.add_pane(name="waiting", tab=overflow["tab_id"])
        watcher = self.add_pane(tab=scripts["tab_id"], label="Watcher", proc="zsh", width=120)
        self.write_state()
        self.write_metadata(agents={name: {
            "kind": "codex", "model": "gpt-6-luna", "role": "implementer",
            "started_at": f"2026-01-0{index}T00:00:00Z", "start_order": index,
        } for index, name in enumerate(("mainone", "maintwo", "waiting"), start=1)},
            scripts={"Watcher": {"pane_id": watcher["pane_id"], "started_at": "2026-01-01T00:00:00Z"}})
        result = self.run_tool("script", "Next", "--", "sleep", "10")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        self.assertTrue(any(p["pane_id"] == watcher["pane_id"] and p["label"] == "Watcher" for p in state["panes"]))
        next_pane = next(p for p in state["panes"] if p.get("label") == "Next")
        self.assertNotEqual(next_pane["pane_id"], watcher["pane_id"])

    def test_managed_script_shell_is_not_reused_and_closes_by_pane_id(self) -> None:
        for process in ("zsh", "make"):
            with self.subTest(process=process):
                self.state = self.base_state()
                watcher = self.add_pane(label="Watcher", proc=process)
                self.write_state()
                self.write_metadata(scripts={"Watcher": {"pane_id": watcher["pane_id"], "started_at": "2026-01-01T00:00:00Z"}})
                started = self.start("worker", purpose="Worker")
                self.assertEqual(started.returncode, 0, started.stderr)
                self.assertNotEqual(self.pane("worker")["pane_id"], watcher["pane_id"])
                state = self.read_state()
                self.assertTrue(any(p["pane_id"] == watcher["pane_id"] for p in state["panes"]))
                close = self.run_tool("close-script", "Watcher")
                self.assertEqual(close.returncode, 0, close.stderr)
                state = self.read_state()
                self.assertTrue(any(p["pane_id"] == "w1:p1" for p in state["panes"]))
                self.assertFalse(any(p["pane_id"] == watcher["pane_id"] for p in state["panes"]))

    def test_close_script_uses_recorded_pane_id_not_duplicate_label(self) -> None:
        self.state["panes"][0]["label"] = "Watcher"
        scripts = self.add_tab("Scripts")
        watcher = self.add_pane(tab=scripts["tab_id"], label="Watcher", proc="make")
        self.write_state()
        self.write_metadata(scripts={"Watcher": {"pane_id": watcher["pane_id"], "started_at": "2026-01-01T00:00:00Z"}})
        result = self.run_tool("close-script", "Watcher")
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.read_state()
        self.assertTrue(any(p["pane_id"] == "w1:p1" for p in state["panes"]))
        self.assertFalse(any(p["pane_id"] == watcher["pane_id"] for p in state["panes"]))

    def test_close_script_refuses_agent_pane_and_clears_vanished_script(self) -> None:
        worker = self.add_pane(name="worker", tab="w1:t1")
        self.write_state()
        self.write_metadata(
            agents={"worker": {"kind": "codex", "model": "gpt-6-luna", "pane_id": worker["pane_id"]}},
            scripts={"Watcher": {"pane_id": worker["pane_id"]}},
        )
        refused = self.run_tool("close-script", "Watcher")
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("no longer identifies a script pane", refused.stderr)
        self.assertTrue(any(p["pane_id"] == worker["pane_id"] for p in self.read_state()["panes"]))
        self.assertIn("Watcher", self.get_managed_state()["scripts"])

        self.write_metadata(scripts={"Gone": {"pane_id": "w1:p404"}})
        missing = self.run_tool("close-script", "Gone")
        self.assertEqual(missing.returncode, 0, missing.stderr)
        self.assertIn("pane=already-closed", missing.stdout)
        self.assertNotIn("Gone", self.get_managed_state()["scripts"])

    def test_orchestrator_is_discovered_by_reserved_pane_label_without_agent_name(self) -> None:
        self.state["panes"][0].pop("name")
        self.state["extra_agents"] = [{
            "agent": "claude", "agent_status": "working", "pane_id": "w1:p1",
            "tab_id": "w1:t1", "workspace_id": "w1",
        }]
        self.write_state()
        result = self.start("identified", purpose="Identified")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.pane("identified")["tab_id"], "w1:t1")
        layout = self.run_tool("layout")
        self.assertEqual(layout.returncode, 0, layout.stderr)
        script = self.run_tool("script", "Validation", "--", "sleep", "2")
        self.assertEqual(script.returncode, 0, script.stderr)
        self.assertIn("tab=Main", script.stdout)
        self.assertTrue(any(p["pane_id"] == "w1:p1" and p["label"] == "Orchestrator" for p in self.read_state()["panes"]))

    def test_successful_codex_start_stays_managed_when_update_dismissal_fails(self) -> None:
        self.env["FAKE_HERDR_FAIL"] = "agent read"
        result = self.start("codexread", purpose="Codex read")
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = self.get_managed_state()["agents"]["codexread"]
        self.assertEqual(metadata["pane_id"], self.pane("codexread")["pane_id"])
        self.assertEqual(metadata["purpose"], "Codex read")
        self.assertTrue(self.read_state().get("read_saw_managed"))

    def test_update_prompt_send_failure_does_not_unmanage_codex(self) -> None:
        self.env["FAKE_HERDR_FAIL"] = "agent send-keys"
        self.env["FAKE_HERDR_VISIBLE"] = "New version available. Press Enter to update."
        result = self.start("codexesc", purpose="Codex escape")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("codexesc", self.get_managed_state()["agents"])

    def test_update_prompt_is_dismissed_when_present(self) -> None:
        self.env["FAKE_HERDR_VISIBLE"] = "New version available. Press Enter to update."
        result = self.start("codexupdate", purpose="Codex update")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(call[:3] == ["agent", "send-keys", "codexupdate"] and call[3:] == ["esc"] for call in self.calls()))

    def test_close_reconciles_agent_whose_pane_vanished(self) -> None:
        overflow = self.add_tab("Agent")
        self.state["extra_agents"] = [{
            "name": "vanished", "agent": "codex", "agent_status": "done",
            "pane_id": "w1:p404", "tab_id": overflow["tab_id"], "workspace_id": "w1",
        }]
        self.write_state()
        self.write_metadata(agents={"vanished": {"kind": "codex", "model": "gpt-6-luna", "role": "implementer", "pane_id": "w1:p404"}})
        result = self.run_tool("close", "vanished")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("vanished", self.get_managed_state()["agents"])
        self.assertFalse(any(call[:2] == ["pane", "close"] for call in self.calls()))

    def test_wait_timeout_requires_finite_positive_seconds(self) -> None:
        for timeout in ("nan", "inf", "0", "-1", "86401"):
            with self.subTest(timeout=timeout):
                result = self.run_tool("prompt", "worker", "--text", "wait", "--wait", "--timeout", timeout)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--timeout must be finite", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_codex_defaults_to_high_effort_except_luna_and_honors_explicit_effort(self) -> None:
        first = self.start("standard", model="gpt-6.1-sol")
        second = self.start("explicit", model="gpt-6.1-sol", extra=("--effort", "medium"))
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        starts = [call for call in self.calls() if call[:2] == ["agent", "start"]]
        effort = {
            call[2]: call[call.index("-c") + 1]
            for call in starts
        }
        self.assertEqual(effort, {
            "standard": "model_reasoning_effort=high",
            "explicit": "model_reasoning_effort=medium",
        })

    def test_layout_equalizes_stationary_overflow_tabs(self) -> None:
        overflow = self.add_tab("Agent")
        self.add_pane(name="mainone", tab="w1:t1", width=40)
        self.add_pane(name="maintwo", tab="w1:t1", width=40)
        self.add_pane(name="overflowone", tab=overflow["tab_id"], width=90)
        self.add_pane(name="overflowtwo", tab=overflow["tab_id"], width=30)
        for index, name in enumerate(("mainone", "maintwo", "overflowone", "overflowtwo"), start=1):
            if index == 1:
                managed = {}
            managed[name] = {"kind": "codex", "model": "gpt-6-luna", "role": "implementer", "started_at": f"2026-01-0{index}T00:00:00Z", "start_order": index}
        self.write_metadata(agents=managed)
        self.write_state()
        result = self.run_tool("layout")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_widths("w1:t1", [40, 40, 40])
        self.assert_widths(overflow["tab_id"], [60, 60])
        self.assertFalse(any(call[:2] == ["pane", "move"] for call in self.calls()))
        state = self.read_state()
        self.assertEqual(state["focused_pane_id"], "w1:p1")

    def test_status_lists_managed_agent(self) -> None:
        self.add_pane(name="active", tab="w1:t1")
        self.write_state()
        self.write_metadata(agents={"active": {"kind": "codex", "model": "gpt-6-luna", "role": "implementer", "started_at": "2026-01-01T00:00:00Z"}})
        result = self.run_tool("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("active state=idle pane=w1:p2 tab=Main kind=codex model=gpt-6-luna", result.stdout)

    def test_status_reports_no_managed_agents(self) -> None:
        result = self.run_tool("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "no managed agents")

    def test_layout_start_and_close_leave_usage_and_its_agents_alone(self) -> None:
        usage = self.add_tab("Usage")
        claude = self.add_pane(tab=usage["tab_id"], name="userclaude", kind="claude", proc="claude", width=40)
        codex = self.add_pane(tab=usage["tab_id"], name="usercodex", kind="codex", proc="codex", width=40)
        movement = self.add_pane(tab=usage["tab_id"], name="movementlab", kind="codex", proc="codex", label="Movement Lab", width=40)
        self.write_state()
        self.write_metadata(agents={
            "movementlab": {
                "kind": "codex", "model": "gpt-6-luna", "role": "implementer",
                "purpose": "Movement Lab", "pane_id": movement["pane_id"],
            },
        })
        usage_before = json.loads(json.dumps([
            pane for pane in self.state["panes"] if pane["tab_id"] == usage["tab_id"]
        ]))
        user_pane_ids = {claude["pane_id"], codex["pane_id"], movement["pane_id"]}

        layout = self.run_tool("layout")
        self.assertEqual(layout.returncode, 0, layout.stderr)
        started = self.start("worker", purpose="Worker")
        self.assertEqual(started.returncode, 0, started.stderr)
        self.assertEqual(self.pane("worker")["tab_id"], "w1:t1")
        closed = self.run_tool("close", "worker")
        self.assertEqual(closed.returncode, 0, closed.stderr)

        refused = self.run_tool("close", "movementlab")
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("user-owned tab", refused.stderr)
        prompt_refused = self.run_tool("prompt", "movementlab", "--text", "do not touch this user tab")
        self.assertNotEqual(prompt_refused.returncode, 0)
        self.assertIn("user-owned tab", prompt_refused.stderr)
        self.assertIn("movementlab", self.get_managed_state()["agents"])
        usage_after = [
            pane for pane in self.read_state()["panes"] if pane["tab_id"] == usage["tab_id"]
        ]
        self.assertEqual(usage_after, usage_before)

        pane_mutations = {"move", "resize", "rename", "close", "split", "run"}
        for call in self.calls():
            self.assertFalse(call[:2] == ["agent", "prompt"] and call[2] == "movementlab", call)
            if call[:1] == ["pane"] and len(call) > 1 and call[1] in pane_mutations:
                target = call[2] if len(call) > 2 else ""
                if call[1] == "resize" and "--pane" in call:
                    target = call[call.index("--pane") + 1]
                self.assertNotIn(target, user_pane_ids, call)
            if call[:2] in (["pane", "layout"], ["pane", "process-info"]):
                target = call[call.index("--pane") + 1]
                self.assertNotIn(target, user_pane_ids, call)


if __name__ == "__main__":
    unittest.main()
