# ServiceNow Incident Filters

This folder contains the ServiceNow-native incident response plan for the
azmon-lawappinsights scenario.

The filter uses:

- incidentPlatform: ServiceNow
- priorities: "1".."5"

This file is applied directly by the recipe extras script when the active
incident platform is ServiceNow.

Scenario s3 additionally applies:

- `aks-incidents.yaml` for AKS-focused incidents (priorities 1-3)
- `aks-pod-urgent.yaml` for urgent pod incidents (priorities 1-2 with `pod` in the title)
