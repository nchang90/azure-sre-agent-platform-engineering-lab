# Custom instructions (superseded)

These `.txt` files are no longer applied. They have been replaced by common
prompts under [`../config/common-prompts/`](../config/common-prompts/), which are
uploaded to `/api/v2/extendedAgent/commonprompts` and attached to each subagent
by reference.

| Was | Now |
|-----|-----|
| `default.txt` | `config/common-prompts/investigation-guidelines.yaml` |
| `s2.txt` | `config/common-prompts/s2-orders-api-runtime.yaml` |
| `s3.txt` | `config/common-prompts/s3-aks-incident.yaml` |
| — | `config/common-prompts/safety-rules.yaml` (new; applies in every scenario) |

The previous mechanism pasted the selected `.txt` into every subagent's
`instructions` at registration time, which duplicated the text per agent, hid it
from the portal, and meant guidance could not be updated without re-registering
every agent. Common prompts are the first-class equivalent.

To add scenario guidance, create `config/common-prompts/<name>.yaml` and add the
name to `ALL_COMMON_PROMPT_NAMES` plus the scenario's `COMMON_PROMPT_NAMES+=()`
block in `scripts/catalog.sh`.

These files are kept only for reference and can be deleted.
