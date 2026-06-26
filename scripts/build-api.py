#!/usr/bin/env python3
"""Convert a lab artifact into an SRE Agent data-plane API envelope.

Modes:
    build-api.py agent FILE.yaml         -> prints the extendedAgent envelope to stdout
    build-api.py skill SKILL.md OUT.json  -> writes the skill envelope to OUT, prints name
    build-api.py incident-platform FILE.yaml -> prints normalized incident platform spec JSON
    build-api.py incident-filter FILE.yaml -> prints normalized response plan JSON

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


def build_incident_platform(path):
    import yaml  # imported lazily so non-YAML modes stay lightweight

    with open(path, "r", encoding="utf-8") as f:
        doc = yaml.safe_load(f) or {}

    spec = doc.get("spec") or doc

    # Support both platform_type (lab shape) and platformType (template shape).
    platform_type = spec.get("platform_type") or spec.get("platformType") or spec.get("incidentPlatform")
    if not platform_type:
        sys.exit("missing spec.platform_type/platformType")

    result = {
        "name": spec.get("name") or doc.get("name") or "",
        "platformType": platform_type,
        "displayName": spec.get("display_name") or spec.get("displayName") or "",
        "description": spec.get("description") or "",
        "connectionUrl": spec.get("connection_url") or spec.get("connectionUrl") or "",
        "connectionKey": spec.get("connection_key") or spec.get("connectionKey") or "",
    }
    json.dump(result, sys.stdout)


def build_incident_filter(path):
    import yaml  # imported lazily so non-YAML modes stay lightweight

    with open(path, "r", encoding="utf-8") as f:
        doc = yaml.safe_load(f) or {}

    meta = doc.get("metadata") or {}
    spec = doc.get("spec") or doc

    filter_id = meta.get("name") or doc.get("name") or spec.get("id")
    if not filter_id:
        sys.exit("missing metadata.name for incident filter")

    agent_mode = spec.get("agentMode", "autonomous")
    if isinstance(agent_mode, str):
        agent_mode = agent_mode.lower()

    result = {
        "id": filter_id,
        "name": spec.get("name") or filter_id,
        "priorities": spec.get("priorities") or [],
        "titleContains": spec.get("titleContains") or "",
        "handlingAgent": spec.get("handlingAgent") or "default",
        "agentMode": agent_mode,
        "maxAttempts": spec.get("maxAttempts") or spec.get("maxAutomatedInvestigationAttempts") or 3,
    }
    json.dump(result, sys.stdout)


def main(argv):
    mode = argv[1] if len(argv) > 1 else ""
    if mode == "agent" and len(argv) >= 3:
        build_agent(argv[2])
    elif mode == "skill" and len(argv) >= 4:
        build_skill(argv[2], argv[3])
    elif mode == "incident-platform" and len(argv) >= 3:
        build_incident_platform(argv[2])
    elif mode == "incident-filter" and len(argv) >= 3:
        build_incident_filter(argv[2])
    else:
        sys.exit("Usage: build-api.py agent FILE.yaml | build-api.py skill SKILL.md OUT.json | build-api.py incident-platform FILE.yaml | build-api.py incident-filter FILE.yaml")


if __name__ == "__main__":
    main(sys.argv)
