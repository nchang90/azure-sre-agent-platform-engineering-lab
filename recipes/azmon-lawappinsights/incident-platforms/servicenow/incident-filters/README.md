# ServiceNow Incident Filters

ServiceNow-native response plans. `scripts/apply-extras.sh` registers the plans
named in `RESPONSE_PLAN_NAMES` (see `scripts/catalog.sh`) with
`PUT /api/v2/extendedAgent/incidentFilters/{metadata.name}`.

`metadata.name` must match the file name. It is both the registered plan id and
the catalog entry. After registration, `scripts/apply-extras.sh` lists the
agent's response plans and deletes every plan except the one selected for the
active scenario. This also removes legacy and portal-created plans.

## Plans

| File | Scope |
|---|---|
| `all-incidents.yaml` | Shared default: every priority, orchestrator, autonomous. |
| `aks-incidents.yaml` | S3: priority 1-3, title contains `checkout-api`, autonomous. |
| `s2-orders-api-runtime.yaml` | S2: priority 1-3, title contains `Orders API`. |

## Supported fields

Always sent: `incidentPlatform`, `isEnabled`, `priorities`, `titleContains`,
`handlingAgent`, `agentMode`, `maxAutomatedInvestigationAttempts`.

Sent only when the YAML declares them: `deepInvestigationEnabled`,
`mergeEnabled`, `mergeWindowHours`. A plan that omits one produces the exact
payload it did before.

`build_incident_filter` in `scripts/build-api.py` is the whole contract — it
emits these keys and drops everything else, so adding a key here without adding
it there does nothing.

The optional three are part of the upstream payload: `sreagent-templates/bicep/apply-extras.sh`
in [microsoft/sre-agent](https://github.com/microsoft/sre-agent) PUTs them to
this same route in this same envelope, and its `snow-p1p2.yaml` ships
`mergeEnabled` and `mergeWindowHours`. #74 dropped `deepInvestigationEnabled`
alongside the real fix in that commit — a wrong request envelope and a duplicate
`maxAttempts` key — so it was never established that the API rejects it.
If an agent build does turn out to reject them, `register_response_plan_file`
strips all three and retries once rather than failing the apply; watch the apply
output for "agent rejected the optional plan fields".

## Advanced filters are a portal feature

Azure SRE Agent added advanced ServiceNow filters in September 2026: assignment
group, configuration item, category and subcategory, caller, location, state,
impact, urgency, severity, "title does not contain", and up to 20 custom
incident fields whose names start with `u_`.

These are **not** configured from this folder. They are a preview gated behind a
portal toggle, and the data-plane property names are not published, so a plan
using them is built in the portal rather than checked in here. See
[Configure ServiceNow response plans](https://sre.azure.com/docs/tutorials/incident-platforms/configure-servicenow-response-plans).

### Setting one up

1. Open the agent, go to **Incidents -> Triggers & response plans**, and turn on
   **Advanced filters**.
2. Create a response plan, or open an existing one.
3. Set the **assignment group**. Selections are stored by `sys_id`, so renaming
   the group in ServiceNow does not change the plan's scope. Left empty, the
   plan inherits the group configured for **Generate insights** when ServiceNow
   was connected; if none was set there, the remaining filters define the match.
4. Add the built-in filters you need, then expand **Advanced filters ->
   Add custom field** for `u_*` fields. Custom fields match on exact equality
   against the stored value; reference fields normally take the record's
   `sys_id`.
5. Pick the response agent and autonomy level. **Review** lets the agent
   investigate and propose; **Autonomous** lets it act within its permissions.
6. Run **Incidents preview** before saving or enabling. Confirm the result is
   neither broader nor narrower than intended, adjusting the filters or the time
   range until it is.

All populated filters are ANDed. Within a multi-select field such as priority or
assignment group, an incident matches any selected value.

Turning the preview toggle off leaves advanced plans stored but shows them as
**Off**, and turning it back on does not re-enable them — preview and enable
each one again.

### ServiceNow account access

The integration account needs read access to every incident field a plan uses.
For the portal's field suggestions it also needs `sys_user_group` (assignment
groups) and `sys_dictionary` (custom-field discovery). Without those two the
plan still works; only the suggestions go away, and `u_*` names are typed
manually.
