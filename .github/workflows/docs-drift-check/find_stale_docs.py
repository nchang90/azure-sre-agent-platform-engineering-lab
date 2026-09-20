#!/usr/bin/env python3
"""Check that this repo's documentation still matches its code.

Every check below is a mechanical comparison between two files, so the same
commit always gives the same answer. Prints one line per stale document and
exits 1 if there are any, so it can gate a workflow. Run it locally the same
way CI does:

    python3 .github/workflows/docs-drift-check/find_stale_docs.py
"""
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

for path, problem in sorted(stale):
    print("%s: %s" % (path, problem))

if stale:
    print("\n%d stale finding(s)." % len(stale))
    sys.exit(1)

print("Documentation is up to date.")
