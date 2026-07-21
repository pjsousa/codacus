#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

printf '== OS ==\n'
if command -v lsb_release >/dev/null 2>&1; then
  lsb_release -ds
else
  uname -a
fi

printf '\n== CPU ==\n'
lscpu | grep -E '^(Model name|CPU\(s\)|Core\(s\) per socket|Thread\(s\) per core):'

printf '\n== RAM and disk ==\n'
free -h
df -h "$WORK_DIR" 2>/dev/null || df -h "$HOME"

printf '\n== NVIDIA ==\n'
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,compute_cap --format=csv,noheader
else
  printf 'FAIL: nvidia-smi is unavailable.\n'
fi

printf '\n== Build tools ==\n'
for command_name in git cmake gcc g++ nvcc python3 docker; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '%-8s %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf '%-8s MISSING\n' "$command_name"
  fi
done

printf '\n== Memory locking ==\n'
printf 'soft limit (KiB): %s\n' "$(ulimit -Sl)"
printf 'hard limit (KiB): %s\n' "$(ulimit -Hl)"

printf '\n== Docker GPU passthrough ==\n'
if command -v docker >/dev/null 2>&1; then
  if docker run --rm --gpus all ubuntu:22.04 nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader; then
    printf 'PASS: Docker can access the GPU.\n'
  else
    printf 'FAIL: Docker GPU passthrough is not working.\n'
  fi
else
  printf 'SKIP: Docker is unavailable.\n'
fi

printf '\n== Assessment ==\n'
printf 'Expected model: %s (about 20.9 GB)\n' "$MODEL_FILE"
printf 'Expected source revision: %s\n' "$LLAMA_REV"
printf 'Native build requires CUDA 12.x and CUDA_ARCH=%s; CUDA 13 cannot target Pascal.\n' "$CUDA_ARCH"
printf 'Use --mlock only after raising both soft and hard memlock limits.\n'
