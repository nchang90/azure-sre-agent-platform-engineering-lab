# ServiceNow Incident Filters

This folder contains ServiceNow-native incident response plans for the
azmon-lawappinsights scenario.

Each filter uses:

- incidentPlatform: ServiceNow
- priorities: "1".."5"

These files are applied directly by scripts/post-provision.sh when the active
incident platform is ServiceNow.
