# Scripts

Automation and deployment utilities.

| Script | Purpose |
|--------|---------|
| `apply-extras.sh` | Register agents, skills, automations, and scheduled tasks with SRE Agent data plane |
| `build-api.py` | Convert lab artifacts (agents, skills) into SRE Agent data-plane envelopes |
| `catalog.sh` | List all registered agents, skills, and configurations |
| `create-servicenow-incident.sh` | Create ServiceNow incidents for testing incident response flows |

## Usage

```bash
# Register all agents and skills
./scripts/apply-extras.sh

# List registered agents
./scripts/catalog.sh

# Build a custom agent envelope
./scripts/build-api.py agent my-agent.yaml

# Create a test incident
./scripts/create-servicenow-incident.sh
```
