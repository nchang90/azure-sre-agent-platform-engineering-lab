# servicenow-aks-incident

AKS cluster incident management with ServiceNow as the incident platform.

## Overview

This recipe integrates Azure Kubernetes Service (AKS) cluster health monitoring with ServiceNow incident lifecycle management. The SRE agent detects pod and node failures, triages severity, creates incidents in ServiceNow, and executes remediation actions (scale, drain, restart) with approval gates.

## Prerequisites

- Azure subscription with SRE Agent RP access
- AKS cluster with Container insights (Azure Monitor for containers) enabled
- Log Analytics workspace configured for AKS diagnostics
- ServiceNow instance with REST API enabled
- Microsoft Entra ID service principal with permissions for both AKS and ServiceNow

## Deployment

This recipe uses the shared `/infra/terraform/` configuration. Deploy via:

```bash
# 1. Copy the recipe tfvars example
cp recipes/servicenow-aks-incident/terraform/terraform.tfvars.example \
   infra/terraform/terraform.tfvars

# 2. Edit tfvars with your values
vim infra/terraform/terraform.tfvars

# 3. Deploy infrastructure
cd infra/terraform
terraform init
terraform apply -var-file=terraform.tfvars

# 4. Register recipe connectors and automations
cd ../../
./scripts/apply-extras.sh --scenario s3 --recipe servicenow-aks-incident
```

## Parameters

| Param | Required | Example | Notes |
|---|---|---|---|
| agentName | ✅ | `aks-sre-agent` | Lowercase, hyphens only |
| resourceGroup | ✅ | `prod-aks-rg` | RG containing AKS cluster |
| location | ✅ | `eastus2` | Azure region |
| aksClusterName | ✅ | `prod-aks` | AKS cluster name for monitoring |
| lawId | | `/subscriptions/.../workspaces/prod-law` | Log Analytics workspace resource ID. If blank, metrics-only mode. |
| serviceNowInstanceUrl | ✅ | `https://prod-instance.service-now.com` | ServiceNow instance URL |
| serviceNowUsername | ✅ | `sre-integration-user` | Integration user with incident CRUD permissions |
| modelProvider | | `Anthropic` | Options: `Anthropic`, `MicrosoftFoundry` |

## What You Get

| Category | Items |
|---|---|
| **Platform** | Azure Monitor (pod/node health alerts) |
| **Connectors** | Log Analytics, Azure Monitor, ServiceNow REST API |
| **Skills** | investigate-aks-alerts, triage-pod-node-health, remediate-aks-resources |
| **Subagents** | aks-triage-agent, aks-remediator |
| **Response Plans** | aks-pod-failures, aks-node-pressure, aks-cluster-upgrade |
| **Incident Filters** | Pod CrashLoopBackOff, Node NotReady, Upgrade Failures |
| **Scheduled Tasks** | aks-cluster-health-check (daily) |
| **Hooks** | prevent-cascade-scale-down, require-approval-for-drains |

## Architecture

```
AKS Cluster Health
  ├─ Pod status (CrashLoopBackOff, Pending, ImagePullBackOff)
  ├─ Node status (NotReady, MemoryPressure, DiskPressure)
  └─ Control plane (API latency, etcd availability)
         ↓
    Azure Monitor Alert Rules
         ↓
    SRE Agent (orchestrator)
         ↓
    ServiceNow Incident
         ├─ aks-triage-agent (Log Analytics KQL → root cause)
         ├─ aks-remediator (Execute: scale, drain, restart, redeploy)
         └─ Approval Workflow
```

## Expected Outcomes

### Pod CrashLoopBackOff
1. Pod enters CrashLoopBackOff (container restart count > 5)
2. Azure Monitor alert fires
3. SRE agent creates P2 incident in ServiceNow
4. Triage agent queries pod logs, finds app error
5. Remediation suggested: redeploy latest revision
6. Human approves → pod redeployed → incident closed

### Node NotReady
1. Node becomes NotReady (kubelet timeout or disk pressure)
2. Azure Monitor alert fires
3. SRE agent creates P2 incident in ServiceNow
4. Triage agent confirms node is unhealthy (0 capacity)
5. Remediation suggested: drain node & scale up
6. Human approves → node drained → replicas rescheduled → incident closed

### Cluster Upgrade Failure
1. Control plane upgrade fails or gets stuck
2. Azure Monitor alert fires (API server latency spike)
3. SRE agent creates P1 incident in ServiceNow
4. Triage agent confirms control plane issue via metrics
5. Remediation suggested: rollback upgrade or restart components
6. Human approves → rollback executed → cluster health restored

## Runbook References

Uses runbooks from `knowledge-base/runbooks/aks/`:
- `pod-crashloop.md`
- `node-not-ready.md`
- `cluster-upgrade-failure.md`

## Links

- [Azure SRE Agent](https://github.com/microsoft/sre-agent)
- [S3 Scenario](../../scenarios/s3-incident-root-cause-investigation/README.md)
- [AKS Troubleshooting](https://docs.microsoft.com/en-us/azure/aks/troubleshooting)
