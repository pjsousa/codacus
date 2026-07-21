#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
failure_count=0

printf '== OS and kernel ==\n'
if command -v lsb_release >/dev/null 2>&1; then
  lsb_release -ds
fi
uname -a

printf '\n== CPU ==\n'
lscpu

printf '\n== RAM, swap, disk ==\n'
free -b
swapon --show --bytes || true
df -B1 "$PROJECT_DIR"

printf '\n== GPU ==\n'
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,uuid,driver_version,memory.total,memory.used,memory.free,compute_cap --format=csv,noheader
else
  printf 'FAIL: nvidia-smi is unavailable.\n'
  failure_count=$((failure_count + 1))
fi

printf '\n== Tools (inspection only; nothing is installed) ==\n'
for command_name in bash git sha256sum nvidia-smi hf jq curl shellcheck; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '%-12s %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf '%-12s MISSING\n' "$command_name"
  fi
done

printf '\n== Toolchain and container runtime versions ==\n'
for version_command in "git --version" "cmake --version" "gcc --version" "g++ --version" "python3 --version" "docker --version" "podman --version"; do
  read -r command_name _ <<<"$version_command"
  if command -v "$command_name" >/dev/null 2>&1; then
    bash -c "$version_command" | sed -n '1p'
  else
    printf '%s MISSING\n' "$command_name"
  fi
done
if [[ -x /usr/local/cuda-12.2/bin/nvcc ]]; then
  /usr/local/cuda-12.2/bin/nvcc --version
else
  printf 'nvcc MISSING at /usr/local/cuda-12.2/bin/nvcc\n'
fi

printf '\n== Process limits ==\n'
ulimit -a

printf '\n== Required read-only runtime ==\n'
printf 'source=%s\nbuild=%s\nrevision=%s\n' "$SOURCE_DIR" "$BUILD_DIR" "$LLAMA_REV"
printf 'binary_artifact=%s\nternary_artifact=%s\nqwen_control=%s\n' \
  "$BINARY_MODEL_PATH" "$TERNARY_MODEL_PATH" "$QWEN_MODEL_PATH"

printf '\nAssessment: this script made no host changes and did not probe Docker.\n'
if (( failure_count > 0 )); then
  exit 1
fi
