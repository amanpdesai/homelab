# Homelab entry points. Most targets run inside WSL2 unless noted.

.DEFAULT_GOAL := help

.PHONY: help bootstrap dotfiles docker tailscale-wsl tui ollama-up ollama-down ollama-logs status

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  %-16s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

bootstrap:  ## Base packages, sshd, ~/srv layout (run inside WSL)
	bash scripts/wsl/00-bootstrap.sh

dotfiles:  ## Symlink dotfiles into $$HOME (run inside WSL)
	bash scripts/wsl/01-link-dotfiles.sh

docker:  ## Install Docker Engine and NVIDIA toolkit (run inside WSL)
	bash scripts/wsl/02-install-docker.sh

tailscale-wsl:  ## Install Tailscale inside WSL (only if needed)
	bash scripts/wsl/03-tailscale.sh

tui:  ## Install hl (terminal manager) + deps + MOTD
	bash scripts/wsl/05-install-tui.sh

ollama-up:  ## Start the Ollama compose stack
	docker compose -f docker/ollama/compose.yaml up -d

ollama-down:  ## Stop the Ollama compose stack
	docker compose -f docker/ollama/compose.yaml down

ollama-logs:  ## Tail Ollama logs
	docker compose -f docker/ollama/compose.yaml logs -f

status:  ## Quick environment snapshot
	@echo "uname:     $$(uname -a)"
	@if [ -f /etc/os-release ]; then . /etc/os-release; echo "distro:    $$PRETTY_NAME"; fi
	@if pidof systemd >/dev/null 2>&1; then echo "systemd:   running"; else echo "systemd:   not running"; fi
	@if command -v docker >/dev/null 2>&1; then echo "docker:    $$(docker --version)"; else echo "docker:    not installed"; fi
	@if command -v tailscale >/dev/null 2>&1; then echo "tailscale: $$(tailscale version | head -1)"; else echo "tailscale: not installed"; fi
	@if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader | sed 's/^/gpu:       /'; else echo "gpu:       no nvidia-smi"; fi
