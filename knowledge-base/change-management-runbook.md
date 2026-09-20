# Change Management Runbook

Use this runbook when an incident may be tied to a recent deployment or an
active Change Request (CR).

## 1. Confirm change context

1. Read the active CR from the service signal (`/health`, deployment metadata,
   or incident payload).
2. Query `change-lookup`:
   - `GET /changes/{cr}` when you already have a CR number
   - `GET /changes/active/now` when you need the currently active window
3. Capture the CR risk, blast radius, linked commit or PR, and rollback plan.

## 2. Correlate the incident

Keep facts separate from hypotheses:

- Did the incident start inside the CR implementation window?
- Does the blast radius match the affected service?
- Does the linked commit or PR match the component that is failing?
- Did the error rate change immediately after the rollout?

## 3. Choose the safest response

| Situation | Preferred action |
|---|---|
| Clear deployment regression with known rollback | Roll back to the last known healthy revision or build |
| Suspected regression but evidence is incomplete | Hold further rollout, keep investigating |
| No matching active or recent CR | Treat as a non-change incident until evidence says otherwise |

## 4. Record the decision

Document:

- CR number
- Why the CR is or is not the likely trigger
- Mitigation chosen (rollback, hold, observe)
- Verification signal used to confirm recovery
