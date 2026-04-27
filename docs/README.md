# homelab docs

Long-form documentation that does not belong in the top-level README.
The top-level README is the quickstart and conventions reference; this
directory is for context, decisions, and operational knowledge that
would otherwise be lost if I (or a future me) walks back into this
project after six months.

| Doc | Purpose |
| --- | --- |
| [architecture.md](architecture.md) | What each layer is and why it exists. Boot flow and traffic flow. |
| [decisions.md](decisions.md) | Architecture decision records. Why we chose A over B. |
| [networking.md](networking.md) | Mirrored WSL networking, Tailscale wiring, port flow, debug recipes. |
| [gpu-and-llm.md](gpu-and-llm.md) | VRAM budget on the 4060 Ti, Ollama notes, gaming coexistence. |
| [operations.md](operations.md) | Runbook for common ops: SSH, updates, restarts, adding services. |
| [troubleshooting.md](troubleshooting.md) | Symptom -> diagnosis -> fix for the failure modes I have hit. |
| [inventory.md](inventory.md) | Living snapshot of hardware, software, and pre-existing state. |

When in doubt, prefer adding a section to one of these over inventing a
new file.
