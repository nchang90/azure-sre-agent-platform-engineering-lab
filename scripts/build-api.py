#!/usr/bin/env python3
"""Convert a lab artifact into an SRE Agent data-plane API envelope.

Modes:
    build-api.py agent FILE.yaml         -> prints the extendedAgent envelope to stdout
    build-api.py skill SKILL.md OUT.json  -> writes the skill envelope to OUT, prints name

Agent envelope (PUT {agentEndpoint}/api/v2/extendedAgent/agents/{name}):
    { name, type: "ExtendedAgent", tags: [], properties: <camelCase spec> }

Skill envelope (PUT {agentEndpoint}/api/v2/extendedAgent/skills/{name}):
    { name, type: "Skill", properties: { description, tools, skillContent } }
"""
import json
import os
import re
import sys


def build_agent(path):
    import yaml  # imported lazily so `skill` mode has no YAML dependency

    with open(path, "r", encoding="utf-8") as f:
        doc = yaml.safe_load(f) or {}

    spec = doc.get("spec") or doc
    name = spec.get("name") or doc.get("name")
    if not name:
        sys.exit("missing spec.name")

    # YAML (snake_case) → API (camelCase)
    key_map = {
        "system_prompt": "instructions",
        "handoff_description": "handoffDescription",
        "agent_type": "agentMode",
        "tools": "tools",
        "model": "model",
        "description": "description",
    }
    properties = {}
    for src, dst in key_map.items():
        if src in spec and spec[src] is not None:
            properties[dst] = spec[src]

    # The v2 extendedAgent API requires a handoffs array (empty is allowed).
    properties["handoffs"] = spec.get("handoffs") or []

    json.dump(
        {"name": name, "type": "ExtendedAgent", "tags": [], "properties": properties},
        sys.stdout,
    )


def build_skill(src, out):
    txt = open(src, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", txt, re.S)
    fm = m.group(1) if m else ""

    def field(key):
        mm = re.search(rf"^{key}:\s*(.+)$", fm, re.M)
        return mm.group(1).strip() if mm else ""

    name = field("name") or src.split("/")[-2]
    envelope = {
        "name": name,
        "type": "Skill",
        "properties": {"description": field("description"), "tools": [], "skillContent": txt},
    }
    out_dir = os.path.dirname(out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(envelope, f)
    print(name)


def main(argv):
    mode = argv[1] if len(argv) > 1 else ""
    if mode == "agent" and len(argv) >= 3:
        build_agent(argv[2])
    elif mode == "skill" and len(argv) >= 4:
        build_skill(argv[2], argv[3])
    else:
        sys.exit("Usage: build-api.py agent FILE.yaml | build-api.py skill SKILL.md OUT.json")


if __name__ == "__main__":
    main(sys.argv)
