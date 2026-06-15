#!/usr/bin/env python3
"""Convert a SKILL.md (with YAML frontmatter) into the SRE Agent skills envelope.

Usage: skill-to-api-json.py SKILL.md OUTPUT.json
Writes the JSON body and prints the skill name on stdout.
"""
import json
import re
import sys

if len(sys.argv) < 3:
    sys.exit("Usage: skill-to-api-json.py SKILL.md OUTPUT.json")

src, out = sys.argv[1], sys.argv[2]
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
    "properties": {
        "description": field("description"),
        "tools": [],
        "skillContent": txt,
    },
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(envelope, f)
print(name)
