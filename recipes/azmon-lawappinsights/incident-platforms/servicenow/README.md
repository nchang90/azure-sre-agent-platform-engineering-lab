# ServiceNow Incident Platform

This folder mirrors the upstream SRE-agent recipe shape for ServiceNow incident handling.

The incident platform itself is configured at provisioning time by `scripts/post-provision.sh` (from the `INCIDENT_PLATFORM` setting and `SERVICENOW_*` env vars); this folder holds the platform-specific incident filters.

Use the SRE Agent connector setup capability to bind the ServiceNow instance and credentials before importing this recipe.
