# GPU and LLM

## VRAM budget

The RTX 4060 Ti has 8188 MiB usable VRAM. At idle on the Windows
desktop, expect roughly 1.5 to 2 GB already in use by the desktop
compositor, browser hardware acceleration, and Discord/Spotify if
running. Realistic free VRAM headroom for an LLM while the desktop is
"doing nothing" is around 6 GB.

| Workload | VRAM | Notes |
| --- | --- | --- |
| Idle Windows desktop | 1.5 - 2.0 GB | DWM, browser, Discord |
| Add a Chromium browser with hw accel | + 0.3 - 0.6 GB | HW video decode pushes this up further |
| Llama 3.1 8B Q4_K_M | ~ 5.0 GB | comfortable with desktop |
| Llama 3.1 8B Q5_K_M | ~ 5.7 GB | tight, close hw-accel browsers |
| Qwen2.5 7B Q4 | ~ 4.5 GB | fast, comfortable headroom |
| 13B class Q4 | ~ 7.5 - 8 GB | borderline; OOM risk under load |
| 30B class Q4 | does not fit | use a remote API or rent a box |
| AAA game launching | + 4 - 7 GB suddenly | this is why we do not run both |

## Coexistence with gaming

Hard rule: stop GPU-heavy server workloads before launching a game.

```bash
hl game-on                  # stop every GPU-tagged stack
# or, gentler -- let Ollama's keep-alive expire:
#   OLLAMA_KEEP_ALIVE=5m means the model unloads 5 min after last use
```

Soft rule: leave Ollama up but expect the model to be evicted from
VRAM when a game allocates. The game runs fine; the next Ollama call
just has to reload the weights, costing a few seconds.

If we ever start running training jobs (not just inference), they
should always be a deliberate, foreground action with the game closed.

## Ollama specifics

The compose file at `docker/ollama/compose.yaml`:
- binds to `127.0.0.1:11434` only (tailnet-only access via Windows host).
- mounts a named volume `ollama-data` so models survive restarts.
- requests `gpu: all` via the NVIDIA Container Toolkit reservation.
- sets `OLLAMA_KEEP_ALIVE=5m` so models unload after 5 minutes idle,
  freeing VRAM automatically.

### Recommended starter models

```bash
docker compose -f docker/ollama/compose.yaml exec ollama ollama pull llama3.1:8b-instruct-q4_K_M
docker compose -f docker/ollama/compose.yaml exec ollama ollama pull qwen2.5-coder:7b-instruct-q4_K_M
docker compose -f docker/ollama/compose.yaml exec ollama ollama pull nomic-embed-text   # for RAG
```

### Verify GPU passthrough into the container

```bash
docker compose -f docker/ollama/compose.yaml exec ollama nvidia-smi
```

Expect to see the 4060 Ti listed. If `nvidia-smi` is missing inside the
container, the NVIDIA Container Toolkit was not configured -- run
`sudo nvidia-ctk runtime configure --runtime=docker` and
`sudo systemctl restart docker` (covered by `02-install-docker.sh`).

## CUDA-on-WSL gotchas

- The NVIDIA driver lives on the *Windows* side. Do not install
  `nvidia-driver-*` packages inside Ubuntu; they conflict with the
  Microsoft GPU paravirtualization shim.
- `nvidia-smi` inside WSL goes through the shim. Reported CUDA version
  may differ from the latest Linux release; that is normal.
- After a Windows driver update, run `wsl --shutdown` so the new
  driver shim is picked up on next boot.

## When to outgrow the 4060 Ti

Concrete signals that 8 GB is too small:
- We want 13B+ models at higher than Q4 quality.
- We want long context windows (32k+) on 7B models -- KV cache eats VRAM fast.
- We start fine-tuning, even LoRA on 7B models.

Cheapest "bigger box" moves, in order:
1. Rent an H100 / A100 by the hour (Lambda, RunPod) when actually needed.
2. Add a second GPU to this box (the 4060 Ti has only x8 PCIe lanes;
   a second slot is fine for inference).
3. Buy a used 3090 24 GB. Pulls more power; consider PSU headroom.
