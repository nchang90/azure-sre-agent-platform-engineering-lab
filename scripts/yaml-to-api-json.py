#!/usr/bin/env python3
"""Map a YAML subagent spec into the SRE Agent v2 extendedAgent envelope.

Output shape matches Microsoft's apply-extras.sh contract:
    PUT {agentEndpoint}/api/v2/extendedAgent/agents/{name}
    body = { name, type: "ExtendedAgent", tags: [], properties: <spec> }

Where <spec> uses camelCase keys:
    { instructions, handoffDescription, tools, agentMode, ... }
"""
import json
import sys

import yaml

if len(sys.argv) != 2:
    sys.stderr.write("Usage: yaml-to-api-json.py FILE\n")
    sys.exit(2)

with open(sys.argv[1], "r", encoding="utf-8") as f:
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

envelope = {
    "name": name,
    "type": "ExtendedAgent",
    "tags": [],
    "properties": properties,
}
json.dump(envelope, sys.stdout)
