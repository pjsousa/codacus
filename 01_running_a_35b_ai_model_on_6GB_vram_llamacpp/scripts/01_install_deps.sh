#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
else
  require_command sudo
  SUDO=(sudo)
fi

"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y \
  build-essential cmake git git-lfs curl wget ca-certificates \
  python3 python3-venv python3-pip jq time

TOOLS_VENV="${TOOLS_VENV:-$WORK_DIR/tools-venv}"
mkdir -p "$WORK_DIR"
python3 -m venv "$TOOLS_VENV"
"$TOOLS_VENV/bin/python" -m pip install --upgrade pip huggingface_hub

if [[ "${INSTALL_CUDA:-0}" == "1" ]]; then
  keyring_deb="/tmp/cuda-keyring_1.1-1_all.deb"
  wget -O "$keyring_deb" \
    https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
  "${SUDO[@]}" dpkg -i "$keyring_deb"
  "${SUDO[@]}" apt-get update
  "${SUDO[@]}" apt-get -s install cuda-toolkit-12-2
  "${SUDO[@]}" apt-get install -y cuda-toolkit-12-2
fi

printf '\nDependencies installed.\n'
printf 'Hugging Face CLI: %s/bin/hf\n' "$TOOLS_VENV"
if [[ "${INSTALL_CUDA:-0}" != "1" ]]; then
  printf 'CUDA was not changed. Re-run with INSTALL_CUDA=1 to install toolkit-only cuda-toolkit-12-2.\n'
fi
