# Azure Front Door Broken Routing Rule Runbook

**Severity:** High  
**Component:** Azure Front Door  
**Symptom:** 503 Service Unavailable, 400 Bad Request, or user traffic not reaching origin  

---

## 1. Quick Detection Signals

| Signal | Query |
|--------|-------|
| **Failed Health Probes** | `AzureDiagnostics \| where ResourceProvider == "MICROSOFT.CDN" and Category == "FrontdoorHealthProbeLog" \| where httpStatus !in ("200", "301", "302")` |
| **High 503 Rate** | `AzureDiagnostics \| where Category == "FrontdoorAccessLog" \| where httpStatus_s == "503" \| summarize count() by bin(TimeGenerated, 5m)` |
| **Origin Unreachable** | Check if Container Apps environment is running or if Network policies block Front Door |
| **Routing Rule Disabled** | Verify routing rule `rr-default` is in `Enabled` state in Azure Portal |

---

## 2. Root Cause Analysis Tree

### A. Origin is Down or Unhealthy
```
1. Check Container Apps environment status
   az containerapp environment show -g <rg> -n <env-name>
   
2. Check if all Container Apps in the environment are running
   az containerapp list -g <rg> -o table
   
3. Manually test health probe endpoint
   curl -I https://<container-apps-env>.eastus2.azurecontainerapps.io/health
   
4. If origin returns non-200 status code, the health probe will mark it as unhealthy
```

### B. Frontend Endpoint Not Configured
```
1. Verify frontend endpoint exists
   az cdn endpoint show -g <rg> -n <profile-name> -o json
   
2. Check that frontendEndpointName is linked to the routing rule
   Portal: Front Door > Routing Rules > rr-default > Frontend Hosts
```

### C. Routing Rule Mismatch
```
1. Verify routing rule pattern matches traffic
   Expected: /* (matches all paths)
   
2. Check protocol settings
   - forwardingProtocol: HttpsOnly (HTTPS to origin)
   - httpsRedirect: Enabled (redirect HTTP → HTTPS)
   
3. If origin is HTTP-only, change forwardingProtocol to Http
```

### D. Network/Firewall Blocking
```
1. Verify Container Apps network policy allows inbound from Front Door
   az containerapp environment network-policy show -g <rg> -n <env-name>
   
2. Check if NSGs or Private Endpoints are blocking Front Door IPs
   Front Door service tag: AzureFrontDoor (use in NSG rules)
```

### E. DNS/Endpoint Not Resolving
```
1. Test Front Door endpoint hostname resolution
   nslookup <fd-xxxx>.azurefd.net
   
2. Verify CNAME records if using custom domain
   nslookup <your-custom-domain.com>
   → Should point to <fd-xxxx>.azurefd.net
```

---

## 3. Remediation Steps

### **Level 1: Immediate Mitigation (Operator)**
```bash
# Step 1: Enable/Disable routing rule
az cdn route update \
  -g <resource-group> \
  --profile-name <profile-name> \
  --endpoint-name <endpoint-name> \
  --name rr-default \
  --enable-caching true \
  --enable-compression true

# Step 2: Check origin group health
az cdn origin show \
  -g <resource-group> \
  --profile-name <profile-name> \
  --origin-group-name og-<token> \
  --name origin-<token>

# Step 3: Restart origin service if applicable
az containerapp restart -g <resource-group> -n <app-name>
```

### **Level 2: Configuration Fix (SRE)**
If health probe path is wrong:
```bicep
healthProbeSettings: {
  probePath: '/health'        // Update if endpoint is different
  probeProtocol: 'Https'      // Use Https if origin requires it
  probeIntervalInSeconds: 100 // Default 100s
}
```

If origin hostname is unreachable:
```bicep
origin 'Microsoft.Cdn/profiles/origins@2024-02-01' = {
  properties: {
    hostName: containerAppsEnvFqdn  // Verify this FQDN is correct
    httpPort: 80
    httpsPort: 443
    enabledState: 'Enabled'
  }
}
```

### **Level 3: Full Redeployment (Platform)**
```bash
# Redeploy Front Door module
az deployment group create \
  -g <resource-group> \
  -f infra/bicep/main.bicep \
  -p environmentName=<env> \
  --no-wait

# Verify with azd
azd deploy
```

---

## 4. Diagnostic Queries (KQL)

### Check Health Probe Status Over Time
```kusto
AzureDiagnostics
| where Category == 'FrontdoorHealthProbeLog'
| where TimeGenerated > ago(1h)
| summarize 
    Success = sumif(1, httpStatus_s == '200'),
    Failures = sumif(1, httpStatus_s != '200'),
    LatencyMs = avg(timeTaken_d)
  by tostring(httpStatus_s), bin(TimeGenerated, 5m)
| render columnchart
```

### Track Routing Rule Traffic
```kusto
AzureDiagnostics
| where Category == 'FrontdoorAccessLog'
| where TimeGenerated > ago(1h)
| summarize 
    Requests = count(),
    Errors = countif(httpStatus_s >= 400),
    P99Latency = percentile(timeTaken_d, 99)
  by httpStatus_s, routingRuleName_s
| order by Errors desc
```

### Correlate with Application Insights
```kusto
AppTraces
| where timestamp > ago(30m)
| where severityLevel >= 2
| project timestamp, message, customDimensions
| union (
  exceptions
  | where timestamp > ago(30m)
  | project timestamp, outerMessage, type = strcat('Exception-', outerType)
)
```

---

## 5. SRE Agent Auto-Response

### Trigger Conditions
```yaml
when:
  - metric: frontdoor_health_probe_failure_rate
    threshold: > 10%
    window: 5m
  - metric: frontend_endpoint_error_rate
    threshold: > 5%
    window: 5m
```

### Agent Actions
1. **Diagnose:** Query health probe logs and origin status
2. **Assess:** Check if origin service is actually down or misconfigured
3. **Propose:**
   - Restart origin container apps
   - Update routing rule if probe path is wrong
   - Failover to secondary origin if available
4. **Prompt:** Alert SRE with diagnosis and wait for approval
5. **Execute:** Apply fix if approved

### Escalation Path
- **Low Impact:** Auto-remediate (restart container, re-enable endpoint)
- **High Impact:** Page SRE on-call, wait for approval before remediation
- **Critical:** Immediately notify platform team, suggest traffic diversion

---

## 6. Prevention & Monitoring

### Proactive Monitors
- [ ] Health probe failure rate > 5% → Alert
- [ ] P99 latency > 2000ms → Warn
- [ ] 503 error rate spike > 2x baseline → Page
- [ ] Origin response timeout > 30s → Investigate

### Runbook Tests (Weekly)
```bash
# Simulate health probe failure
az containerapp update -g <rg> -n <app> --min-replicas 0

# Monitor auto-recovery
az containerapp update -g <rg> -n <app> --min-replicas 1

# Verify Front Door detects and routes around failure
curl -I https://<fd-xxxx>.azurefd.net/health
```

### Incident Review Template
```
Incident: Front Door Broken Routing
Duration: <start> → <resolution>
Root Cause: [Health probe timeout / Origin down / Config mismatch]
Detection: [Alert / Manual]
Fix: [Auto-remediated / Manual intervention]
Prevention: [Monitor added / Config reviewed / Runbook updated]
```

---

**Last Updated:** 2026-08-29  
**Owner:** SRE Team  
**Escalation:** On-Call SRE → Platform Engineering
