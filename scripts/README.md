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

If Azure returns `AgentDeletionRequested`, `deploy.sh` re-plans once with a
replacement of the already-deleting SRE Agent. Terraform retries DELETE and
waits for deletion before recreating the agent and its dependent resources.
The replacement plan preserves the original saved plan's inputs in a private
temporary file that is removed on exit. Other apply failures are not recovered,
except for the existing workspace lookup retry. If Azure still cannot delete
the agent, deployment stops; investigate the Azure deletion error before retrying.

## Usage

```bash
# Register all agents and skills
./scripts/apply-extras.sh

# Build a custom agent envelope
./scripts/build-api.py agent my-agent.yaml

# Run a previously planned deployment
bash scripts/deploy.sh sbox tfplan

```
