# S2 — App Service Autonomous Remediation

**Persona:** Platform Engineering / On-call

**Runtime:** Azure App Service (`sbox`)

**Recipe:** `azmon-lawappinsights`

---

## Quick Start

### Prerequisites & Setup

- Sign in to Azure CLI and GitHub CLI; have GitHub Copilot CLI available.
- Configure the [deployment workflow](../../.github/workflows/deploy.yml) and its Azure credentials.
- Use `infra/terraform/environments/sbox.tfvars`: `scenario = "s2"`,
  `access_level = "High"`, `action_mode = "Autonomous"`, and the Application
  Insights, Log Analytics, and Sev0/Sev1 incident options enabled.
- Deploy the lab once with the `deploy.yml` workflow (`environment=sbox`,
  `runtime=webapp`). This builds the `orders-api` image and
  registers the S2 response plan. Skip it if the latest code is already deployed.

> **Caution:** The chaos toggle intentionally takes the `orders-api` site down.
> Use only `rg-sre-lab-sbox`, never a production app.

The App Service hosts both the **Nordic Integration Summit** website (`/`) and the API
(`/api/info`, `/api/orders`, `/health`). Chaos takes all of them down together:
the website shows a *503 Service Unavailable* page and every API route returns
503.

### Break & Observe

Start `copilot` in the repository and drive the demo with plain-language
prompts. Approve each command Copilot CLI proposes after checking it targets
`rg-sre-lab-sbox` and the `orders-api-*` app; do not choose an option that
allows all tools or run Copilot CLI with `--allow-all-tools`.

To work through the Azure MCP server instead of the Azure CLI, add "use the
Azure MCP server" to any prompt below. Copilot CLI loads it from
`~/.copilot/mcp-config.json`; Copilot Chat in VS Code agent mode loads it from
`.vscode/mcp.json`. The approval rules are the same. If an Azure MCP tool can't
perform a step, Copilot falls back to `az`, so still check each command.

**1. Check it is healthy**

```text
Find the orders-api App Service in rg-sre-lab-sbox, give me its website URL,
and check that /, /api/info and /health return HTTP 200.
```

Open the URL in a browser: the Nordic Integration Summit page loads.

**2. Crash it**

```text
Enable the chaos monkey on that orders-api App Service by setting only the app
setting CHAOS_ENABLED=true. Do not change anything else.
```

Approve only `az webapp config appsettings set` with `CHAOS_ENABLED=true`.
Terraform already sets `CHAOS_MODE=crash` on the app, so no workflow run is
needed. The app restarts, and after about a minute every route returns 503.

**3. Monitor it**

```text
Send 12 requests to / and /health on the orders-api app and show the HTTP
status of each. Then show the Http5xx metric for the last 15 minutes and
whether the "Orders API App Service HTTP 5xx" alert has fired.
```

Refresh the website in your browser: it now shows *503 Service Unavailable*.

**Expected:** every request returns `503`, and the alert fires once more than
five 5xx responses land in five minutes. A `000` means the app is still
restarting; wait a minute and ask again. The alert opens the incident that
Azure SRE Agent picks up and remediates.

---

## Story

A bad app setting takes the `orders-api` App Service down: the worker keeps
running but rejects every request with HTTP 503. Azure Monitor detects the 5xx
responses; Azure SRE Agent correlates the alert with the configuration change
and the worker's `CHAOS` log lines, then reverses the setting on the isolated
lab app. The operator verifies the website and API recover. Application
Insights records every failed request, so request telemetry, the platform metric and app logs all provide outage evidence.

---

## How It Works

1. **Healthy service** → `CHAOS_ENABLED=false`; the website, API and health
   requests pass.
2. **Controlled failure** → a Copilot CLI prompt sets `CHAOS_ENABLED=true` on
   the app, which already has `CHAOS_MODE=crash`; the website and every API
   route return 503.
3. **Alert** → App Service `Http5xx` metrics trigger the S2 Azure Monitor plan
   when the threshold is reached.
4. **Investigation** → `triage-agent` checks app settings, failed requests,
   the `CHAOS` log lines and the change timeline before identifying the cause.
5. **Autonomous recovery** → The approval hooks allow only
   `CHAOS_ENABLED=false` on the confirmed `rg-sre-lab-sbox/orders-api-*` app
   without further approval. Other deployment changes and explicit restarts
   remain gated.
6. **Verification** → Confirm the setting is false, endpoints recover, and
   5xx responses return to baseline.

---

## Architecture

`Browser / client → orders-api (App Service: website + API) → Azure Monitor platform metric → Azure SRE Agent → app-setting reversal`

The S2 response plan handles **Orders API** alerts. Application Insights
records each 503 request and its `CHAOS` trace during the outage. The
architecture image below is conceptual; the deployed S2 workload is
`orders-api`, which serves the Nordic Integration Summit website from the same App
Service.

<img src="../../images/s2-autonomous-remediation.svg" alt="Conceptual S2 incident response flow" width="700" />

---

## Validation Checklist

- [ ] Confirm `/health` and `/` return HTTP 200 before chaos.
- [ ] Confirm `CHAOS_ENABLED=true`, `CHAOS_MODE=crash`, and that `/`, `/health`
  and `/api/orders` return HTTP 503 after Copilot CLI changes the setting.
- [ ] Confirm platform 5xx responses and the **Orders API App Service HTTP
  5xx** alert; a timeout alone does not prove the alert fired.
- [ ] Inspect the Azure SRE Agent incident for the root cause and the exact
  setting reverted. An alert by itself does not prove remediation happened.
- [ ] Confirm `CHAOS_ENABLED=false`, `/health`, `/`, and `/api/orders` recover,
  and the 5xx rate returns to baseline.

To verify after the agent acts, ask Copilot CLI:

```text
Show the CHAOS_ENABLED and CHAOS_MODE app settings on the orders-api App
Service in rg-sre-lab-sbox, then check that /, /health and a POST to
/api/orders return HTTP 200.
```

---

## Cleanup

If the agent does not recover the lab app, ask Copilot CLI to undo the chaos
setting and approve only `CHAOS_ENABLED=false`:

```text
Set only the app setting CHAOS_ENABLED=false on the orders-api App Service in
rg-sre-lab-sbox. Do not change anything else.
```

Terraform always deploys `CHAOS_ENABLED=false`, so any `deploy.yml` run,
including the daily scheduled one, also resets it. Do not substitute `az webapp stop` for the chaos
setting.

---

## Next: What Comes After S2

- [S3 — AKS Root Cause Investigation](../s3-incident-root-cause-investigation/README.md):
  investigate a Kubernetes routing failure with specialist agents.

## Knowledge Base

- [Orders API HTTP 500 playbook](../../knowledge-base/http-500-errors.md)
- [Orders architecture](../../knowledge-base/orders-architecture.md)
