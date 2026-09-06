# ServiceNow Incident Filters

This folder contains the ServiceNow-native incident response plan for the
azmon-lawappinsights scenario.

The filter uses:

- incidentPlatform: ServiceNow
- priorities: "1".."5"

This file is applied directly by the recipe extras script when the active
incident platform is ServiceNow.

Scenario s3 additionally applies:

- `aks-pod-urgent.yaml` for urgent AKS pod incidents (priorities 1-2 with `AKS` in the title)
