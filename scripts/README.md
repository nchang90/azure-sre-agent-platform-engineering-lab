# Scripts

Automation and deployment utilities.

| Script | Purpose |
|--------|---------|
| `apply-extras.sh` | Register agents, skills, automations, and scheduled tasks with SRE Agent data plane |
| `build-api.py` | Convert lab artifacts (agents, skills) into SRE Agent data-plane envelopes |
| `catalog.sh` | Define the scenario-specific agents, skills, and configurations used by `apply-extras.sh` |
| `deploy.sh` | Apply Terraform, register recipe extras, deploy AKS workloads, and update application images |

The deployment script is driven by [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)
and reads resource details from `terraform output`.

## Usage

```bash
# Register all agents and skills
./scripts/apply-extras.sh

# Build a custom agent envelope
./scripts/build-api.py agent my-agent.yaml

# Run a previously planned deployment
bash scripts/deploy.sh sbox tfplan

```
