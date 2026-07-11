# Deployment Plan

**Status:** Ready for Validation

## 1. Change

Update `infra/terraform/alerts.tf` so the `orders-api` health, error, and latency alerts use a 1-minute window.

## 2. Validation

- Run `terraform validate`
- Run `terraform plan` for the demo backend
- Confirm the alert rule definitions match the 1-minute window

## 3. Deployment

- Apply the Terraform changes to the demo environment

## 4. Proof

- `terraform -chdir=infra/terraform validate -no-color` — success
- `terraform -chdir=infra/terraform plan -var-file=environment/demo.tfvars -no-color -detailed-exitcode` — success; confirmed 1 alert-window update plus unrelated role assignment replacement
- `terraform -chdir=infra/terraform apply -var-file=environment/demo.tfvars -auto-approve -no-color -target=azurerm_monitor_scheduled_query_rules_alert_v2.orders_api_health -target=azurerm_monitor_scheduled_query_rules_alert_v2.orders_api_errors -target=azurerm_monitor_scheduled_query_rules_alert_v2.orders_api_latency` — success; no changes needed for the alert resources
