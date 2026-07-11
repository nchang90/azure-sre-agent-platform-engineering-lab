# S1 — Base Azure Infrastructure (Bicep + azd)

S1 is the **foundation layer**: pure Azure infrastructure, deployed with Bicep via
`azd`. Zero application logic, zero AKS, zero Terraform. It stands up the resources
everything else builds on and emits outputs the Terraform layer
([`../terraform/`](../terraform/)) consumes.

## What S1 deploys

| Resource | Bicep type | Module | Notes |
|---|---|---|---|
| Resource group | `Microsoft.Resources/resourceGroups` | `main.bicep` | `rg-<env>`, created at subscription scope |
| Managed identity | `Microsoft.ManagedIdentity/userAssignedIdentities` | `identity.bicep` | The agent's user-assigned identity |
| Log Analytics workspace | `Microsoft.OperationalInsights/workspaces` | `loganalytics.bicep` | PerGB2018, 30-day retention |
| Application Insights | `Microsoft.Insights/components` | `loganalytics.bicep` | Workspace-based; the agent's log config points here |
| Container Apps environment | `Microsoft.App/managedEnvironments` | `containerapps.bicep` | Wired to the Log Analytics workspace |
| Base SRE Agent | `Microsoft.App/agents@2025-05-01-preview` | `sre-agent.bicep` | Mirrors Microsoft's official `agent-core.bicep` |
| RBAC | `Microsoft.Authorization/roleAssignments` | `sre-agent.bicep` | Monitoring Reader + Log Analytics Reader on the RG, SRE Agent Administrator |

## Layout

```
infra/bicep/
├── main.bicep             # subscription scope: RG + module orchestration + outputs
├── main.parameters.json   # azd env-var → param mapping
└── modules/               # one small, single-purpose module per concern (RG scope)
    ├── identity.bicep        # user-assigned managed identity
    ├── loganalytics.bicep    # Log Analytics workspace + Application Insights
    ├── containerapps.bicep   # Container Apps managed environment
    └── sre-agent.bicep       # base SRE Agent + its RBAC
```

`main.bicep` creates the resource group and wires the modules together by passing
each module's outputs (identity principal ID, workspace name, App Insights IDs)
into the next. The SRE Agent / identity / LAW / App Insights / RBAC blocks follow
Microsoft's official template ([microsoft/sre-agent → `sreagent-templates/bicep`](https://github.com/microsoft/sre-agent/tree/main/sreagent-templates/bicep)).

## Deploy

```bash
# 1. Create an azd environment
azd env new s1-demo

# 2. Pick a region supported by the SRE Agent RP
azd env set AZURE_LOCATION eastus2          # or swedencentral | uksouth | australiaeast

# 3. (optional) override defaults
azd env set AGENT_NAME sre-demo             # default: sre-agent
azd env set AGENT_ACCESS_LEVEL Low          # Low | High
azd env set AGENT_ACTION_MODE Review        # Review | Automatic

# 4. Provision (infra only — no services to deploy)
azd provision
```

`azd down` deletes the resource group.

### Direct Bicep (without azd)

```bash
az deployment sub create \
  --location eastus2 \
  --template-file main.bicep \
  --parameters environmentName=s1-demo location=eastus2 agentName=sre-demo
```

## Outputs (for the Terraform layer)

After `azd provision`, read them with `azd env get-values` (they are also written to
`.azure/<env>/.env`):

| Output | Description |
|---|---|
| `AZURE_RESOURCE_GROUP` | Foundation resource group name |
| `AZURE_SUBSCRIPTION_ID` / `AZURE_TENANT_ID` | Deployment subscription / tenant |
| `SRE_MANAGED_IDENTITY_ID` / `_PRINCIPAL_ID` / `_CLIENT_ID` | Agent identity |
| `SRE_LOG_ANALYTICS_WORKSPACE_ID` / `_CUSTOMER_ID` | Log Analytics workspace |
| `SRE_APP_INSIGHTS_CONNECTION_STRING` / `_APP_ID` | Application Insights |
| `SRE_CONTAINER_APPS_ENVIRONMENT_ID` / `_NAME` | Container Apps environment |
| `SRE_AGENT_ID` / `SRE_AGENT_NAME` | Base SRE Agent |

Feed these into Terraform via `TF_VAR_*` environment variables or a generated
`*.auto.tfvars` file so the logic/app layer attaches to the S1 foundation instead
of recreating it.
