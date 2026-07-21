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

printf '\n== RAM ==\n'
free -h

printf '\n== Disk (%s) ==\n' "$WORK_DIR"
df -h "$WORK_DIR" 2>/dev/null || df -h "$HOME"

printf '\n== NVIDIA GPU ==\n'
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,compute_cap --format=csv,noheader
else
  printf 'FAIL: nvidia-smi is unavailable.\n'
fi

printf '\n== Existing llama.cpp build ==\n'
if [[ -x "$LLAMA_CLI" ]]; then
  "$LLAMA_CLI" --version 2>&1 || true
else
  printf 'MISSING: %s\n' "$LLAMA_CLI"
fi

printf '\n== Available models ==\n'
if [[ -d "$MODEL_DIR" ]]; then
  ls -lh "$MODEL_DIR"/*.gguf 2>/dev/null || printf '(none found)\n'
else
  printf 'Model directory %s does not exist.\n' "$MODEL_DIR"
fi

printf '\n== Tools ==\n'
for cmd in docker docker-compose node npm python3 git curl wget; do
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%-14s %s\n' "$cmd" "$(command -v "$cmd")"
  else
    printf '%-14s MISSING\n' "$cmd"
  fi
done

printf '\n== Docker ==\n'
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    docker --version
    printf 'Docker daemon: running\n'
  else
    printf 'Docker daemon: NOT RUNNING\n'
  fi
  if docker compose version >/dev/null 2>&1; then
    docker compose version
  else
    printf 'docker compose plugin: MISSING\n'
  fi
fi

printf '\n== Node.js ==\n'
if command -v node >/dev/null 2>&1; then
  node --version
  npm --version
fi

printf '\n== Memory locking ==\n'
printf 'soft limit (KiB): %s\n' "$(ulimit -Sl)"
printf 'hard limit (KiB): %s\n' "$(ulimit -Hl)"

printf '\n== Assessment ==\n'
printf 'Existing llama.cpp build revision: %s\n' "$LLAMA_REV"
printf 'OpenAI-compatible endpoint will be at: http://%s:%s\n' "$LLAMA_HOST" "$LLAMA_PORT"
printf 'Prerequisites for full stack:\n'
printf '  1. A running llama-server instance (script 01)\n'
printf '  2. A model GGUF file in %s\n' "$MODEL_DIR"
printf '  3. Docker for AnythingLLM and n8n containers (script 03)\n'
printf '  4. Node.js/npm for Pi coding agent (script 04)\n'
