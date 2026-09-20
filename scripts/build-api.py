#!/usr/bin/env python3
"""Convert a lab artifact into an SRE Agent data-plane API envelope.

Modes:
    build-api.py agent FILE.yaml         -> prints the extendedAgent envelope to stdout
    build-api.py skill SKILL.md OUT.json  -> writes the skill envelope to OUT, prints name
    build-api.py tool FILE.yaml OUT.json  -> writes the tool envelope to OUT, prints name
    build-api.py hook FILE.yaml OUT.json  -> writes the hook envelope to OUT, prints name
    build-api.py common-prompt FILE.yaml OUT.json -> writes the prompt envelope, prints name
    build-api.py repo FILE.yaml OUT.json  -> writes the repo envelope to OUT, prints name
    build-api.py incident-platform FILE.yaml -> prints normalized incident platform spec JSON
    build-api.py incident-filter FILE.yaml -> prints normalized response plan JSON

Agent envelope (PUT {agentEndpoint}/api/v2/extendedAgent/agents/{name}):
    { name, type: "ExtendedAgent", tags: [], properties: <camelCase spec> }

Skill envelope (PUT {agentEndpoint}/api/v2/extendedAgent/skills/{name}):
    { name, type: "Skill", properties: { description, tools, skillContent } }

Tool envelope (PUT {agentEndpoint}/api/v2/extendedAgent/tools/{name}):
    { name, type: "Tool", tags: [], properties: <spec verbatim> }

Hook envelope (PUT {agentEndpoint}/api/v2/extendedAgent/hooks/{name}):
    { name, type: "GlobalHook", tags: [], properties: <spec verbatim> }

Common prompt envelope (PUT {agentEndpoint}/api/v2/extendedAgent/commonprompts/{name}):
    { name, type: "CommonPrompt", tags: [], properties: <spec verbatim> }

Repo envelope (PUT {agentEndpoint}/api/v2/repos/{name}) -- note: NOT under
extendedAgent, and its properties are normalized rather than passed verbatim:
    { name, type: "CodeRepo", properties: { url, type: "GitHub"|"AzureDevOps", ... } }
"""
import json
import os
import re
import sys

# Shared grants. Several skills differ only by an extra tool, so name the common
# set once rather than repeating it per skill.
READ_ONLY_DIAGNOSTICS = [
    "SearchMemory",
    "RunAzCliReadCommands",
    "GetAzCliHelp",
    "QueryLogAnalyticsByWorkspaceId",
    "QueryAppInsightsByResourceId",
    "ExecutePythonCode",
]

SKILL_TOOLS = {
    "aks-change-triage-rollback": [
        "SearchMemory",
        "RunAzCliReadCommands",
        "RunAzCliWriteCommands",
        "QueryLogAnalyticsByWorkspaceId",
        "QueryAppInsightsByResourceId",
    ],
    "azure-cost": [
        "SearchMemory",
        "RunAzCliReadCommands",
        "GetAzCliHelp",
    ],
    "azure-kubernetes": [
        "SearchMemory",
        "RunAzCliReadCommands",
        "RunAzCliWriteCommands",
        "GetAzCliHelp",
    ],
    "containerapps-500-diagnostics": [
        "SearchMemory",
        "RunAzCliReadCommands",
        "RunAzCliWriteCommands",
        "GetAzCliHelp",
        "QueryLogAnalyticsByWorkspaceId",
        "QueryAppInsightsByResourceId",
        "ExecutePythonCode",
    ],
    "containerapps-latency-diagnostics": [
        "SearchMemory",
        "RunAzCliReadCommands",
        "RunAzCliWriteCommands",
        "GetAzCliHelp",
        "QueryLogAnalyticsByWorkspaceId",
        "QueryAppInsightsByResourceId",
        "ExecutePythonCode",
    ],
    "evidence-before-after": READ_ONLY_DIAGNOSTICS,
    "incident-orchestrator-coordination": [
        "SearchMemory",
    ],
    "investigate-azure-alerts": [
        "SearchMemory",
        "RunAzCliReadCommands",
        "QueryAppInsightsUsingAppId",
        "QueryLogAnalyticsByWorkspaceId",
    ],
    "servicenow-incident-update": [
        "SearchMemory",
        "UpdateServiceNowIncident",
        "UploadServiceNowAttachment",
    ],
    "triage-app-errors": [
        "SearchMemory",
        "QueryAppInsightsByResourceId",
        "QueryAppInsightsUsingAppId",
        "QueryLogAnalyticsByWorkspaceId",
    ],
}


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
        "handoffs": "handoffs",
        "tools": "tools",
        "model": "model",
        "description": "description",
    }
    properties = {}
    for src, dst in key_map.items():
        if src in spec and spec[src] is not None:
            properties[dst] = spec[src]

    properties.setdefault("handoffs", [])

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
        "properties": {
            "description": field("description"),
            "tools": SKILL_TOOLS.get(name, []),
            "skillContent": txt,
        },
    }
    _write_envelope(envelope, out)


PLACEHOLDER_RE = re.compile(r"@@([A-Z0-9_]+)@@")


def substitute_credentials(raw):
    """Fill @@TOKEN@@ placeholders from the environment.

    The PythonTool sandbox cannot read environment variables, so credentials have
    to be literal in functionCode; committed sources keep the placeholders and are
    never secrets. Tokens are discovered from the file rather than listed here, so
    a tool needing a different credential needs no change to this script -- and a
    placeholder that is never resolved is an error instead of shipping verbatim.
    """
    missing = []
    for key in sorted(set(PLACEHOLDER_RE.findall(raw))):
        value = os.environ.get(key, "")
        if value:
            raw = raw.replace("@@%s@@" % key, value)
        else:
            missing.append(key)
    if missing:
        sys.exit("missing credentials: %s" % ", ".join(missing))
    return raw


def _load_yaml(path, transform=None):
    import yaml  # imported lazily so `skill` mode has no YAML dependency

    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    if transform:
        raw = transform(raw)
    return yaml.safe_load(raw) or {}


def _write_envelope(envelope, out, mode=None):
    out_dir = os.path.dirname(out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(envelope, f)
    if mode is not None:
        os.chmod(out, mode)
    print(envelope["name"])


def build_spec_envelope(src, out, type_name, transform=None, mode=None):
    """Tools, hooks and common prompts share one shape: spec passed through verbatim."""
    doc = _load_yaml(src, transform)
    meta = doc.get("metadata") or {}
    spec = doc.get("spec") or {}

    name = meta.get("name") or doc.get("name")
    if not name:
        sys.exit("missing metadata.name in %s" % src)
    if not spec:
        sys.exit("missing spec in %s" % src)

    _write_envelope(
        {"name": name, "type": type_name, "tags": [], "properties": spec}, out, mode
    )


# Each spec-shaped kind is one row: API type, an optional source transform, and an
# optional output file mode. A new kind costs a row, not another function.
SPEC_KINDS = {
    "tool": ("Tool", substitute_credentials, 0o600),
    "hook": ("GlobalHook", None, None),
    "common-prompt": ("CommonPrompt", None, None),
}


# spec.type in the YAML is a short lab-side name; the API expects the View enum.
REPO_TYPES = {
    "ado": "AzureDevOps",
    "azuredevops": "AzureDevOps",
    "azure-devops": "AzureDevOps",
}


def build_repo(src, out):
    doc = _load_yaml(src)
    meta = doc.get("metadata") or {}
    spec = doc.get("spec") or {}

    name = meta.get("name") or doc.get("name")
    if not name:
        sys.exit("missing name in %s" % src)

    url = (spec.get("url") or "").strip()
    if not url or url.startswith("{{"):
        sys.exit("repo url not substituted in %s (got %r)" % (src, url))
    # Short "owner/repo" is not a valid URL to the API; normalize it.
    if not url.startswith("http") and "/" in url:
        url = "https://github.com/" + url

    properties = {
        "url": url,
        "type": REPO_TYPES.get((spec.get("type") or "github").lower(), "GitHub"),
    }
    for key in ("description", "branch"):
        value = spec.get(key)
        if value:
            properties[key] = value

    _write_envelope({"name": name, "type": "CodeRepo", "properties": properties}, out)


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
        "incidentPlatform": spec.get("incidentPlatform") or spec.get("incident_platform") or "",
        "isEnabled": spec.get("isEnabled", True),
        "priorities": spec.get("priorities") or [],
        "titleContains": spec.get("titleContains") or "",
        "handlingAgent": spec.get("handlingAgent") or "default",
        "agentMode": agent_mode,
        "maxAutomatedInvestigationAttempts": spec.get("maxAutomatedInvestigationAttempts") or spec.get("maxAttempts") or 3,
    }
    json.dump(result, sys.stdout)


def main(argv):
    mode = argv[1] if len(argv) > 1 else ""
    if mode == "agent" and len(argv) >= 3:
        build_agent(argv[2])
    elif mode == "skill" and len(argv) >= 4:
        build_skill(argv[2], argv[3])
    elif mode in SPEC_KINDS and len(argv) >= 4:
        build_spec_envelope(argv[2], argv[3], *SPEC_KINDS[mode])
    elif mode == "repo" and len(argv) >= 4:
        build_repo(argv[2], argv[3])
    elif mode == "incident-platform" and len(argv) >= 3:
        build_incident_platform(argv[2])
    elif mode == "incident-filter" and len(argv) >= 3:
        build_incident_filter(argv[2])
    else:
        sys.exit(
            "Usage: build-api.py agent FILE.yaml"
            " | build-api.py skill SKILL.md OUT.json"
            " | build-api.py tool FILE.yaml OUT.json"
            " | build-api.py hook FILE.yaml OUT.json"
            " | build-api.py common-prompt FILE.yaml OUT.json"
            " | build-api.py repo FILE.yaml OUT.json"
            " | build-api.py incident-platform FILE.yaml"
            " | build-api.py incident-filter FILE.yaml"
        )


if __name__ == "__main__":
    main(sys.argv)
