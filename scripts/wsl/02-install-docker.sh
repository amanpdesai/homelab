#!/usr/bin/env bash
# 02-install-docker.sh -- native Docker Engine inside WSL2 plus the NVIDIA
# Container Toolkit for GPU passthrough. Use this instead of Docker Desktop.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

require_wsl
require_not_root
sudo -v || die "sudo failed"

if command -v docker >/dev/null 2>&1 && docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
	ok "Docker already installed: $(docker --version)"
else
	log "Adding Docker apt repository"
	sudo install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
		| sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	sudo chmod a+r /etc/apt/keyrings/docker.gpg

	. /etc/os-release
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
		| sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

	log "Installing Docker Engine"
	sudo apt-get update -y
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
		docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

	log "Adding $USER to the docker group"
	sudo usermod -aG docker "$USER"

	if pidof systemd >/dev/null 2>&1; then
		sudo systemctl enable --now docker
		ok "docker enabled via systemd"
	else
		warn "systemd not running -- start docker manually until /etc/wsl.conf takes effect."
	fi
fi

# NVIDIA Container Toolkit for GPU passthrough (CUDA-on-WSL).
if dpkg -s nvidia-container-toolkit >/dev/null 2>&1; then
	ok "NVIDIA Container Toolkit already installed"
else
	log "Installing NVIDIA Container Toolkit"
	curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
		| sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
	curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
		| sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
		| sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
	sudo apt-get update -y
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit
	sudo nvidia-ctk runtime configure --runtime=docker
	if pidof systemd >/dev/null 2>&1; then
		sudo systemctl restart docker
	fi
	ok "NVIDIA Container Toolkit installed"
fi

ok "Docker install complete."
echo
echo "Log out and back in (or run 'newgrp docker') so group membership applies."
echo "Test GPU access:"
echo "  docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi"
