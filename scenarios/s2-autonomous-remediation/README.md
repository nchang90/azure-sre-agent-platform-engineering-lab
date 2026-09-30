# Lab: Recover an App Service outage with Azure SRE Agent (S2)

In this guided lab, you're the on-call platform engineer for `orders-api`. You'll
deploy a healthy app to the **isolated S2 sandbox**, use GitHub Copilot CLI to
enable a deliberate Chaos Monkey crash, and observe Azure Monitor and Azure
SRE Agent investigate and recover the service.

> [!IMPORTANT]
> This exercise intentionally crashes an App Service worker. Run it only in
> `rg-sre-lab-sbox`, not on a production website. The deployed `orders-api`
> root returns service metadata; this repository does not deploy a dashboard.

## Learning objectives

After completing this lab, you can:

- Verify a healthy App Service and establish a request baseline.
- Trigger and observe a controlled process failure using a Terraform toggle.
- Correlate an Azure Monitor alert with App Service startup logs and app settings.
- Verify autonomous recovery and reconcile the Terraform configuration.

## Prerequisites

- An Azure subscription and access to deploy the S2 sandbox. Sign in with
  `az login`, authenticate `gh`, and have GitHub Copilot CLI available.
- The repository's Azure deployment secrets and Terraform backend configured
  as described in the [repository setup](../../README.md#deploy).
- `infra/terraform/environments/sbox.tfvars` configured for `scenario = "s2"`,
  `access_level = "High"`, `action_mode = "Autonomous"`,
  `enable_app_insights_connector = true`,
  `enable_log_analytics_connector = true`, and
  `enable_sev01_incident_filter = true`.
- A separate terminal for observing the workflow and checking the endpoint.

The [deploy workflow](../../.github/workflows/deploy.yml) defaults to
`runtime=webapp` and `chaos=false`. It provisions the S2 App Service and
registers the S2 response plan, agent guidance, and approval hooks. The
`chaos=true` input is restricted to the `sbox` App Service deployment.

## Exercise 1: Deploy the healthy service

1. Start the sandbox deployment. When `apply=true`, this workflow plans and
   applies automatically; the plan is visible in its run logs.

   ```bash
   gh workflow run deploy.yml \
     -f environment=sbox -f runtime=webapp \
     -f chaos=false -f plan=true -f apply=true
   gh run watch
   ```

1. Resolve the app name and URL. Keep these variables in the same shell for
   the following exercises.

   ```bash
   RESOURCE_GROUP="rg-sre-lab-sbox"
   BACKEND_WEBAPP_NAME="$(az webapp list \
     --resource-group "$RESOURCE_GROUP" \
     --query "[?starts_with(name, 'orders-api-')].name | [0]" \
     --output tsv)"
   APP_FQDN="$(az webapp show \
     --resource-group "$RESOURCE_GROUP" --name "$BACKEND_WEBAPP_NAME" \
     --query defaultHostName --output tsv)"
   APP_URL="https://$APP_FQDN"
   ```

1. Confirm that the root, health endpoint, and an order request all succeed.

   ```bash
   curl --fail --silent --show-error "$APP_URL/"
   curl --fail --silent --show-error "$APP_URL/health"
   curl --fail --silent --show-error \
     -X POST "$APP_URL/api/orders" \
     -H "Content-Type: application/json" \
     --data '{"customerId":"baseline-user","sku":"BASELINE","quantity":1}'
   ```

   **Expected result:** All three requests return HTTP 200. The root returns
   JSON service metadata; `/health` reports `healthy`. The app setting
   `CHAOS_ENABLED` is `false`, and `CHAOS_MODE` is `crash`.

## Exercise 2: Observe the outage

Use GitHub Copilot CLI to trigger the sandbox `deploy.yml` workflow with
`environment=sbox`, `runtime=webapp`, and `chaos=true`. Inspect and approve
the proposed command yourself; do not use unrestricted tool access or
target another environment. The `enable_s2_chaos` Terraform toggle sets
`CHAOS_ENABLED=true`, causing the worker to crash on startup.

1. After the workflow applies, confirm the setting and service impact.

   ```bash
   az webapp config appsettings list \
     --resource-group "$RESOURCE_GROUP" --name "$BACKEND_WEBAPP_NAME" \
     --query "[?name=='CHAOS_ENABLED' || name=='CHAOS_MODE'].{name:name,value:value}" \
     --output table
   curl --silent --output /dev/null --max-time 10 \
     --write-out "health HTTP %{http_code}\n" "$APP_URL/health"
   ```

   **Expected result:** `CHAOS_ENABLED=true`, `CHAOS_MODE=crash`, and `/health`
   no longer returns HTTP 200. The worker cannot emit new Application Insights
   request traces while down.

1. Generate requests to exercise the App Service **platform** `Http5xx` metric.

   ```bash
   for request in {1..12}; do
     curl --silent --output /dev/null --max-time 10 \
       --write-out "request $request: HTTP %{http_code}\n" "$APP_URL/"
   done
   ```

   **Expected result:** More than five platform 5xx responses in five minutes
   can fire `Orders API App Service HTTP 5xx`. A `000` indicates no HTTP
   response and doesn't count; check the metric before continuing.

## Exercise 3: Investigate the alert and verify recovery

1. In Azure Monitor, find the **Orders API App Service HTTP 5xx** alert.
   Confirm its affected resource is the sandbox `orders-api` App Service and
   record the alert time and the platform 5xx count.

1. In Azure SRE Agent, inspect the S2 incident handled by `triage-agent`.
   Compare the alert time with the deploy workflow and the App Service
   `CHAOS_ENABLED` and `CHAOS_MODE` settings. Check startup/crash logs; the
   worker can't send new application traces while it is down. If no incident
   appears, check the alert state and the S2 response plan before assuming the
   agent investigated.

1. Check the agent's proposed root cause and action. For this lab, evidence
   should link `CHAOS_ENABLED=true` and `CHAOS_MODE=crash` to the startup
   failure. The approval hooks allow one autonomous exception: set **only**
   `CHAOS_ENABLED=false` on `rg-sre-lab-sbox/orders-api-*`. Explicit restarts
   and other deployment changes still require approval.

1. Once the agent reports recovery, verify the live setting and endpoints.

   ```bash
   az webapp config appsettings list \
     --resource-group "$RESOURCE_GROUP" --name "$BACKEND_WEBAPP_NAME" \
     --query "[?name=='CHAOS_ENABLED' || name=='CHAOS_MODE'].{name:name,value:value}" \
     --output table
   curl --fail --silent --show-error "$APP_URL/health"
   curl --fail --silent --show-error "$APP_URL/"
   curl --fail --silent --show-error \
     -X POST "$APP_URL/api/orders" \
     -H "Content-Type: application/json" \
     --data '{"customerId":"verify-user","sku":"VERIFY","quantity":1}'
   ```

   **Expected result:** `CHAOS_ENABLED=false`, all three endpoints return
   HTTP 200, and the platform 5xx rate returns to baseline. Record the
   incident evidence and action before declaring the lab complete.

## Exercise 4: Reconcile the configuration

The agent's direct App Service fix restores traffic but doesn't change the
Terraform state left by the `chaos=true` deployment. Reconcile it so another
apply can't reintroduce the crash.

1. Run a plan-only workflow with the default-off toggle. Review the Terraform
   plan in the run logs before launching the apply workflow.

   ```bash
   gh workflow run deploy.yml \
     -f environment=sbox -f runtime=webapp \
     -f chaos=false -f plan=true -f apply=false
   gh run watch
   ```

1. Apply the safe toggle. The workflow generates a new plan for this run, so
   check that no unexpected changes occurred between runs.

   ```bash
   gh workflow run deploy.yml \
     -f environment=sbox -f runtime=webapp \
     -f chaos=false -f plan=true -f apply=true
   gh run watch
   ```

1. Repeat the health and order checks from Exercise 3. The scheduled
   deployment also uses `chaos=false`, but don't wait for it to clean up an
   active lab outage.

## Troubleshooting and safe cleanup

| Observation | Check or action |
|---|---|
| The site still returns 200 | Confirm that the `chaos=true` workflow applied, the sandbox app has both chaos settings, and the worker recycled. |
| Requests return `000` but no alert fires | Inspect the App Service `Http5xx` metric. The metric alert needs more than five platform 5xx responses in five minutes; connection failures alone don't meet that condition. |
| Alert fires but no agent incident appears | Confirm the S2 response plan is enabled, the alert title includes `Orders API`, and the agent has access to the sandbox resource group. |
| The agent doesn't restore service | After recording evidence, manually set only `CHAOS_ENABLED=false` on the sandbox app, then complete Exercise 4. |

For manual recovery when automation does not act:

```bash
az webapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" --name "$BACKEND_WEBAPP_NAME" \
  --settings CHAOS_ENABLED=false --output none
```

Do not use `az webapp stop` as a substitute for the Chaos Monkey toggle.
Stopping the app doesn't provide the configuration root cause this lab is
designed to investigate. For a backend-only 500 variant, see the
[orders architecture runbook](../../knowledge-base/runbooks/containers/orders-architecture.md);
that variant uses the separate Application Insights request alert.

## Next step

Continue to [S3: AKS incident root-cause investigation](../s3-incident-root-cause-investigation/README.md).
