#!/usr/bin/env python3
"""Find documentation this repo's code has made wrong.

The agent does not decide what drifted; this does, so the same commit yields
the same findings no matter which model reads them. Every check below is a
mechanical comparison between two files.

Set CHANGED_FILES (newline-separated) to mark findings in those files as
gating; everything else is advisory backlog. Unset means a whole-repo sweep.
Prints JSON to stdout.
"""
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
found = []


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def walk(subdir, suffix):
    for base, _, names in os.walk(os.path.join(ROOT, subdir)):
        for name in sorted(names):
            if name.endswith(suffix) and ".git" not in base:
                yield os.path.relpath(os.path.join(base, name), ROOT)


def report(path, problem):
    found.append({"file": path, "problem": problem})


plans = [p for p in walk("recipes", ".yaml") if "incident-filters" in p]
docs = {p: read(p) for p in walk("", ".md")}

# build_incident_filter emits a fixed dict and the API rejects anything else,
# so a key it does not list is silently dropped at registration.
builder = read("scripts/build-api.py").split("def build_incident_filter(")[1]
sent = set(re.findall(r'"([A-Za-z_]+)":', builder.split("json.dump")[0]))

for path in plans:
    spec = read(path).split("spec:")[1]
    for key in re.findall(r"^  ([A-Za-z]\w*):", spec, re.M):
        if key not in sent | {"maxAttempts", "incident_platform"}:
            report(path, "spec.%s is never sent; build-api.py drops it" % key)

    # Plans register by metadata.name but are cleaned up by file name.
    name = re.search(r"^metadata:\s*\n\s*name:\s*(\S+)", read(path), re.M)
    stem = os.path.splitext(os.path.basename(path))[0]
    if name and name.group(1) != stem:
        report(path, "metadata.name is %s but the file is %s" % (name.group(1), stem))

# A scenario selecting a missing plan makes apply-extras.sh exit. Only the
# scoped lists matter: ALL_RESPONSE_PLAN_NAMES outlives its files on purpose,
# so that stale remote plans still get deleted.
stems = {os.path.splitext(os.path.basename(p))[0] for p in plans}
for block in re.finditer(r"(?<!ALL_)RESPONSE_PLAN_NAMES=\((.*?)\)", read("scripts/catalog.sh"), re.S):
    for plan in set(block.group(1).split()) - stems:
        report("scripts/catalog.sh", "selects response plan %s but no YAML has that name" % plan)

for path, text in docs.items():
    for link in re.findall(r"\[[^\]]+\]\((?!https?:|#|mailto:)([^)#]+)", text):
        if not os.path.exists(os.path.join(ROOT, os.path.dirname(path), link.strip())):
            report(path, "link to %s does not exist" % link.strip())

# A tfvars key the scripts require but nothing explains how to set.
prose = "\n".join(docs.values())
for path in walk("scripts", ".sh"):
    for key in set(re.findall(r"tfvar(?:_bool)?\s+([a-z]\w*)", read(path))):
        if key not in prose:
            report(path, "reads tfvars key %s but no doc mentions it" % key)

touched = set(os.environ.get("CHANGED_FILES", "").split())
findings = []
for path, problem in sorted({(f["file"], f["problem"]) for f in found}):
    findings.append({"file": path, "problem": problem,
                     "gating": not touched or path in touched})
gating = [f for f in findings if f["gating"]]

json.dump({
    "recommendation": "docs_required" if gating else "docs_optional",
    "gating_count": len(gating),
    "advisory_count": len(findings) - len(gating),
    "findings": findings,
}, sys.stdout, indent=2)
sys.stdout.write("\n")
