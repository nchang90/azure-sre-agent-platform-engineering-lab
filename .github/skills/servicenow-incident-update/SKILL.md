---
name: servicenow-incident-update
description: Write the completed investigation result back to the originating ServiceNow incident as a work note, and attach the supporting RCA or evidence report. Use as the final step of an AKS incident investigation, once triage, root cause and evidence are settled. The single owner of all ServiceNow write operations.
---

# ServiceNow Incident Update — Orders Platform

You post the finished investigation result to the ServiceNow incident that
started this investigation. You are the **only** owner of ServiceNow write
operations; no other skill or agent writes to ServiceNow.

This skill closes the loop of the S3 flow:

```text
incident -> HTTP trigger -> agent triage -> root cause -> ServiceNow update
```

## Authoritative external references

Use these as primary references before relying on other external sources:

1. Azure SRE Agent docs: https://sre.azure.com/docs
2. Official Azure SRE Agent repo/resources: https://github.com/microsoft/sre-agent

## When to use

- An investigation has produced a root cause and evidence, and the originating
  incident record needs the result.
- An operator explicitly asks to post an update or attach a report to an
  incident.

Do not use to open an incident, change its state, reassign it, or resolve or
close it. The incident already exists — the operator created it before the HTTP
trigger fired — and S3 keeps remediation and closure manual.

## Before writing anything

1. **Identify the target incident.** The incident number arrives with the
   incident context. Never guess a number and never invent one; if no number is
   available, report that and stop.
2. **Read the record first** with `LookupServiceNowIncident`, passing the
   incident number. It returns the `sys_id`, the `link`, the descriptive fields,
   and the most recent work notes. If `found` is `false`, report that and stop —
   do not fall back to posting somewhere else.
3. **Confirm the investigation is complete.** The update must carry a root
   cause, not a progress note. If triage is still open, say so in the work note
   explicitly rather than implying a conclusion.
4. **Check what is already there.** Read the `work_notes` returned in step 2. If
   an Azure SRE Agent update naming the same root cause is already on the
   record, do not post a second one — report that it is already there. If
   `work_notes_warning` is present the history could not be read: say so in your
   report rather than assuming the record is empty.

## Steps

1. **Post the work note** with `UpdateServiceNowIncident`:
   - `sys_id`: the value returned by `LookupServiceNowIncident`, which skips a
     second number lookup. Fall back to `incident_number` only if the lookup was
     unavailable.
   - `work_note`: the update, in the format below.
   - Leave `additional_comments` empty unless the operator explicitly asked for
     a customer-visible comment — work notes are internal, comments are not.
   - Surface the incident as a markdown hyperlink `[<number>](<link>)` using the
     `link` returned by either tool — never the bare number, which is not
     clickable. Do not try to build the URL yourself; the tools return it.
2. **Attach the full report** with `UploadServiceNowAttachment`:
   - `table_sys_id`: the same `sys_id`.
   - `table_name`: `incident`.
   - `file_name`: e.g. `rca-checkout-api-no-endpoints.md`.
   - `content`: the full RCA and before/after evidence.
   - The work note is the summary; the attachment is the detail. Do not paste a
     multi-page report into a work note.
3. **Report back** the incident number, the link, and what was written.

## Work note format

Keep it operator-readable and short enough to scan in the incident view.

```text
Azure SRE Agent — investigation update

What customers saw: <symptom and impact>
What stayed healthy: <what the evidence rules out>
What broke: <the confirmed technical fault>
Affected resources: <resource, namespace, cluster>
Change implicated: <change and its timestamp, or "none correlated">
Confidence: <low|medium|high>

Recommended next step (requires operator approval):
<the safest reversible action>

Evidence attached: <file name>
No remediation has been performed by the agent.
```

## Safety rules

- **Notes only.** `LookupServiceNowIncident` is read-only.
  `UpdateServiceNowIncident` writes `work_notes` and, when explicitly asked,
  `comments`. Neither touches state, assignment or close fields. Do not attempt
  to work around that.
- **Never claim remediation.** S3 keeps remediation manual. The work note must
  state that no remediation was performed, and must never describe a
  recommendation as if it had been applied.
- **Label confidence.** Carry the confirmed/likely/suspected distinction from
  `rca-analysis` into the note. Do not upgrade a hypothesis on the way out.
- **Redact before writing.** The incident record is operator-visible and often
  broadly readable. Mask any secret, token, connection string, key or personal
  data as `[REDACTED]` before it reaches a work note or an attachment.
- **Degrade gracefully.** If credentials are not configured, all three tools
  return `success: false`. Report that the update could not be posted, return the
  update text so an operator can paste it manually, and do not retry in a loop.
- **One update per conclusion.** Post once when the investigation concludes, not
  on every intermediate finding.

## Verification

The record was read before it was written, no duplicate update was posted, and
the work note names a specific root cause with its confidence, states what
stayed healthy, names the correlated change or says none was found, recommends a
next step marked as requiring approval, states that no remediation was
performed, and links the attached evidence. The incident is surfaced as
`[<number>](<link>)`.
