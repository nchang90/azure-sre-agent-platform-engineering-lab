#!/usr/bin/env python3
"""Find documentation this repo's code has made wrong.

The agent does not decide what is stale; this does, so the same commit yields
the same findings no matter which model reads them. Every check below is a
mechanical comparison between two files. Prints JSON to stdout and always
exits 0 — the agent decides what to do about the findings.
"""
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
stale = set()


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def walk(subdir, suffix):
    for base, _, names in os.walk(os.path.join(ROOT, subdir)):
        for name in sorted(names):
            if name.endswith(suffix) and ".git" not in base:
                yield os.path.relpath(os.path.join(base, name), ROOT)


docs = {p: read(p) for p in walk("", ".md")}

# A relative link whose target is gone.
for path, text in docs.items():
    for link in re.findall(r"\[[^\]]+\]\((?!https?:|#|mailto:)([^)#]+)", text):
        if not os.path.exists(os.path.join(ROOT, os.path.dirname(path), link.strip())):
            stale.add((path, "link to %s does not exist" % link.strip()))

# A tfvars key the scripts require but nothing explains how to set.
prose = "\n".join(docs.values())
for path in walk("scripts", ".sh"):
    for key in set(re.findall(r"tfvar(?:_bool)?\s+([a-z]\w*)", read(path))):
        if key not in prose:
            stale.add((path, "reads tfvars key %s but no doc mentions it" % key))

findings = [{"file": f, "problem": p} for f, p in sorted(stale)]

json.dump({"stale_count": len(findings), "findings": findings}, sys.stdout, indent=2)
sys.stdout.write("\n")
