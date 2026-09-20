#!/usr/bin/env python3
"""Resolve which documents a merged code change has left behind.

The agent does not decide where a code change belongs; OWNERS below does, so
the same diff routes to the same document no matter which model reads it. A
reviewer checks the routing by reading one table.

This also extracts the identifiers the change added and removed, because the
agent asking "is this documented anywhere?" one grep at a time is what exhausts
an agentic run's turn budget. Answer it here, once, mechanically.

Compares two git refs -- by default the merge commit against its first parent,
which is exactly the merged pull request. Prints JSON to stdout and always
exits 0: the agent decides what to write, not whether there is work.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BASE = os.environ.get("DOCS_BASE_REF") or "HEAD~1"
HEAD = os.environ.get("DOCS_HEAD_REF") or "HEAD"

# Which document owns which code path. Every rule that matches contributes, so
# one path may oblige several documents. A path matching no rule is not
# docs-worthy -- that is the rule the agent is forbidden to second-guess.
OWNERS = [
    ("src/orders-api/**", [
        "src/orders-api/README.md",
        "knowledge-base/orders-architecture.md",
        "knowledge-base/runbooks/containers/orders-architecture.md",
    ]),
    ("src/change-lookup/**", ["src/change-lookup/README.md"]),
    ("infra/terraform/**", ["scenarios/README.md"]),
    ("infra/bicep/**", ["scenarios/s1-detect-triage/README.md"]),
    ("infra/k8s/**", ["scenarios/s3-incident-root-cause-investigation/README.md"]),
    ("scripts/*.sh", ["scripts/README.md", "scenarios/README.md"]),
    ("scripts/*.py", ["scripts/README.md"]),
    ("recipes/azmon-lawappinsights/**", ["recipes/azmon-lawappinsights/README.md"]),
    ("recipes/alert-response-incident-operations/**",
     ["recipes/alert-response-incident-operations/README.md"]),
    ("scenarios/s1-detect-triage/**", ["scenarios/s1-detect-triage/README.md"]),
    ("scenarios/s2-autonomous-remediation/**", ["scenarios/s2-autonomous-remediation/README.md"]),
    ("scenarios/s3-incident-root-cause-investigation/**",
     ["scenarios/s3-incident-root-cause-investigation/README.md"]),
    ("scenarios/s4-alert-response-incident-operations/**",
     ["scenarios/s4-alert-response-incident-operations/README.md"]),
    ("scenarios/s5-pim-elevation-audit/**", ["scenarios/s5-pim-elevation-audit/README.md"]),
    ("scenarios/s6-frontdoor-incident-response/**",
     ["scenarios/s6-frontdoor-incident-response/README.md"]),
]


def git(*args):
    """Run git, returning stdout, or "" if the command failed."""
    done = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True)
    return done.stdout if done.returncode == 0 else ""


def resolved(ref):
    return bool(git("rev-parse", "--verify", "--quiet", ref + "^{commit}").strip())


def show(ref, path):
    return git("show", "%s:%s" % (ref, path))


def ls(ref, prefix, suffix):
    names = git("ls-tree", "-r", "--name-only", ref, prefix).splitlines()
    return sorted(n for n in names if n.endswith(suffix))


def matches(pattern, path):
    """Glob where ** crosses directories and * does not."""
    rx = re.escape(pattern).replace(r"\*\*", "\x00").replace(r"\*", "[^/]*")
    return re.fullmatch(rx.replace("\x00", ".*"), path) is not None


# A shallow clone cannot see the parent commit. Say so rather than reporting an
# empty diff, which is indistinguishable from a change that owed no documents.
if not (resolved(BASE) and resolved(HEAD)):
    json.dump({
        "base": BASE,
        "head": HEAD,
        "base_resolved": False,
        "target_count": 0,
        "problem": "cannot resolve %s or %s -- deepen the checkout" % (BASE, HEAD),
    }, sys.stdout, indent=2)
    sys.stdout.write("\n")
    sys.exit(0)

# --- what changed, and which documents own it ----------------------------

changed = []
for line in git("diff", "--name-status", "%s...%s" % (BASE, HEAD)).splitlines():
    parts = line.split("\t")
    if len(parts) >= 2 and not parts[-1].endswith(".md"):
        changed.append((parts[0][0], parts[-1]))

owed = {}
for status, path in changed:
    for pattern, docs in OWNERS:
        if matches(pattern, path):
            for doc in docs:
                owed.setdefault(doc, []).append("%s %s" % (status, path))

targets = [
    {
        "doc": doc,
        "exists": os.path.exists(os.path.join(ROOT, doc)),
        "triggered_by": sorted(set(paths)),
    }
    for doc, paths in sorted(owed.items())
]

# --- which identifiers the change added or removed -----------------------

def terraform_variables(ref):
    found = {}
    for path in ls(ref, "infra/terraform", ".tf"):
        for name in re.findall(r'variable\s+"([a-z]\w*)"', show(ref, path)):
            found[name] = path
    return found


def tfvars_keys(ref):
    found = {}
    for path in ls(ref, "scripts", ".sh"):
        for name in re.findall(r"tfvar(?:_bool)?\s+([a-z]\w*)", show(ref, path)):
            found[name] = path
    return found


def prose(ref):
    text = {}
    for path in ls(ref, "", ".md"):
        text[path] = show(ref, path)
    return text


head_prose = prose(HEAD)
all_prose = "\n".join(head_prose.values())

added, removed = [], []
for kind, at_base, at_head in (
    ("terraform variable", terraform_variables(BASE), terraform_variables(HEAD)),
    ("tfvars key", tfvars_keys(BASE), tfvars_keys(HEAD)),
):
    for name in sorted(set(at_head) - set(at_base)):
        added.append({
            "kind": kind,
            "name": name,
            "defined_in": at_head[name],
            "documented": name in all_prose,
        })
    for name in sorted(set(at_base) - set(at_head)):
        stale = sorted(p for p, t in head_prose.items() if name in t)
        removed.append({"kind": kind, "name": name, "still_documented_in": stale})

report = {
    "base": BASE,
    "head": HEAD,
    "base_resolved": True,
    "changed_code_files": len(changed),
    "target_count": len(targets),
    "targets": targets,
    "added_identifiers": added,
    "removed_identifiers": removed,
}
json.dump(report, sys.stdout, indent=2)
sys.stdout.write("\n")
