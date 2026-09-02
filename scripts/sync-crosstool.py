#!/usr/bin/env python3
"""Generate the Codex-side files from the Claude Code sources.

Claude Code, GitHub Copilot CLI and Codex CLI all read
.claude-plugin/marketplace.json and each plugin's .claude-plugin/plugin.json,
so the plugins install as-is in all three. Two things do not carry over:

- Codex does not accept the {"source": "github", ...} object form and prefers
  its own manifest at .agents/plugins/marketplace.json, where display names,
  categories and install policy can be set. Generated here from the Claude
  manifest so the two never drift.
- Codex plugins cannot bundle subagents (openai/codex#18988) and Codex agents
  are TOML, not markdown. Each plugins/*/agents/*.md becomes
  codex/agents/<plugin>--<agent>.toml for users to copy into ~/.codex/agents/.

Usage: scripts/sync-crosstool.py [--check]
  --check  exit 1 if the generated files are out of date (for CI / pre-commit)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLAUDE_MARKETPLACE = ROOT / ".claude-plugin" / "marketplace.json"
CODEX_MARKETPLACE = ROOT / ".agents" / "plugins" / "marketplace.json"
CODEX_AGENTS = ROOT / "codex" / "agents"
CATEGORY = "Developer Tools"


def codex_marketplace(claude: dict) -> str:
    plugins = []
    for entry in claude["plugins"]:
        source = entry["source"]
        if not isinstance(source, str) or not source.startswith("./"):
            raise SystemExit(f"{entry['name']}: Codex needs a './' path source")
        plugins.append({
            "name": entry["name"],
            "source": source,
            "description": entry.get("description", ""),
            "version": entry.get("version", "0.0.0"),
            "category": CATEGORY,
            "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
        })
    doc = {
        "name": claude["name"],
        "interface": {"displayName": "michaelp AI tools"},
        "plugins": plugins,
    }
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def parse_agent(path: Path):
    text = path.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        raise SystemExit(f"{path}: no frontmatter")
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    return meta, m.group(2).strip()


def toml_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def codex_agent(plugin: str, path: Path) -> str:
    meta, body = parse_agent(path)
    name = meta.get("name", path.stem)
    if "'''" in body:
        raise SystemExit(f"{path}: body contains ''' which TOML literal strings cannot hold")
    header = (
        f"# Generated from plugins/{plugin}/agents/{path.name} by scripts/sync-crosstool.py.\n"
        f"# Copy to ~/.codex/agents/ (or <repo>/.codex/agents/). Edit the source, not this file.\n"
    )
    return (
        header
        + f"name = {toml_str(name)}\n"
        + f"description = {toml_str(meta.get('description', ''))}\n"
        + "developer_instructions = '''\n"
        + body
        + "\n'''\n"
    )


def main() -> int:
    check = "--check" in sys.argv
    claude = json.loads(CLAUDE_MARKETPLACE.read_text(encoding="utf-8"))
    expected = {CODEX_MARKETPLACE: codex_marketplace(claude)}
    for entry in claude["plugins"]:
        plugin_dir = ROOT / entry["source"]
        for agent in sorted((plugin_dir / "agents").glob("*.md")):
            expected[CODEX_AGENTS / f"{entry['name']}--{agent.stem}.toml"] = codex_agent(entry["name"], agent)

    stale = []
    for path, content in expected.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current != content:
            stale.append(path)
            if not check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
    extra = [p for p in CODEX_AGENTS.glob("*.toml") if p not in expected] if CODEX_AGENTS.exists() else []
    if not check:
        for p in extra:
            p.unlink()

    rel = lambda p: p.relative_to(ROOT)
    if check:
        for p in stale:
            print(f"out of date: {rel(p)}")
        for p in extra:
            print(f"orphan: {rel(p)}")
        if stale or extra:
            print("run scripts/sync-crosstool.py")
            return 1
        print("cross-tool files are in sync")
        return 0
    for p in stale:
        print(f"wrote {rel(p)}")
    for p in extra:
        print(f"removed {rel(p)}")
    if not stale and not extra:
        print("nothing to do")
    return 0


if __name__ == "__main__":
    sys.exit(main())
