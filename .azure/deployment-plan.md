# Deployment Plan

**Status:** Validated

## 1. Change

Enable richer `orders-api` runtime logging for the S1/S2 Container Apps scenarios:

- Emit explicit Information-level console logs from `src/orders-api/Program.cs` for requests, health checks, order operations, forced failures, and simulation state changes.
- Add Terraform Container App environment variables so deployed `orders-api` keeps default/simple console logging at `Information`.
- Keep runbook and skill KQL resilient by querying `ContainerAppConsoleLogs_CL` when present and `AppTraces` as fallback.
- Add AKS/S3-specific table guidance so AKS scenarios use Kubernetes log tables instead of Container Apps tables.

## 2. Validation

- Build `orders-api`.
- Validate Terraform.
- Plan Terraform against the `sbox` environment and confirm the intended `orders-api` update.
- Avoid applying unrelated SRE Agent/RBAC drift shown by the full plan.

## 3. Deployment

- Apply only the targeted `azurerm_container_app.orders_api[0]` Terraform change for `sbox`.
- Build the updated `orders-api:latest` image in ACR.
- Update the live `orders-api` Container App to the rebuilt image.
- Generate health/failure traffic and query logs to confirm runtime telemetry.

## 4. Validation Proof

- `dotnet build src/orders-api/OrdersApi.csproj --nologo` — success; 0 warnings, 0 errors.
- `terraform -chdir=infra/terraform validate -no-color` — success.
- `terraform -chdir=infra/terraform plan -var-file=environments/sbox.tfvars -no-color -detailed-exitcode` — exit code 2; expected changes detected. Intended change: in-place update to `azurerm_container_app.orders_api[0]` adding `Logging__LogLevel__Default=Information`, `Logging__LogLevel__Microsoft.AspNetCore=Information`, and `Logging__Console__FormatterName=simple`. Unrelated drift also appeared on `azapi_resource.sre_agent[0]` and `azurerm_role_assignment.deployer_admin[0]`; deployment will target only `orders-api`.
- Azure subscription confirmed by user: `MCT Subscirption` (`1c885bf5-48ba-47ee-9957-bd1c94bcbf61`).
