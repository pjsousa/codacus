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
df -h "$PROJECT_DIR"

printf '\n== NVIDIA ==\n'
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,compute_cap --format=csv,noheader
else
  printf 'WARN: nvidia-smi is unavailable; the engine will run CPU-only.\n'
fi

printf '\n== Stack tools ==\n'
for command_name in git curl jq docker node npm npx ss; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '%-8s %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf '%-8s MISSING\n' "$command_name"
  fi
done

printf '\n== Docker ==\n'
if command -v docker >/dev/null 2>&1; then
  if docker info --format 'server={{.ServerVersion}}' 2>/dev/null; then
    docker compose version 2>/dev/null || printf 'WARN: docker compose plugin unavailable.\n'
    printf 'running containers: %s\n' "$(docker ps -q | wc -l)"
  else
    printf 'WARN: Docker daemon is not reachable by this user.\n'
  fi
fi

printf '\n== Existing project-01 engine build ==\n'
if [[ -x "$LLAMA_SERVER" ]]; then
  "$LLAMA_SERVER" --version
  if [[ -d "$SOURCE_DIR/.git" ]]; then
    printf 'checkout revision: %s\n' "$(git -C "$SOURCE_DIR" rev-parse HEAD)"
  fi
else
  printf 'FAIL: %s not found. This project consumes the project-01 build; see GUIDE.md.\n' "$LLAMA_SERVER"
fi

printf '\n== Model artifacts ==\n'
found_model=0
for gguf in "$MODEL_DIR"/*.gguf; do
  [[ -e "$gguf" ]] || continue
  found_model=1
  du -h "$gguf"
done
if [[ "$found_model" == "0" ]]; then
  printf 'WARN: no GGUF files under %s\n' "$MODEL_DIR"
fi

printf '\n== Port availability ==\n'
for port in "$ROUTER_PORT" "$ANYTHINGLLM_PORT" "$N8N_PORT" "$LLAMA_SWAP_PORT" 8080; do
  listener="$(port_listener "$port")"
  if [[ -n "$listener" ]]; then
    printf 'port %-5s IN USE: %s\n' "$port" "$listener"
  else
    printf 'port %-5s free\n' "$port"
  fi
done

printf '\n== Memory locking ==\n'
printf 'soft limit (KiB): %s\n' "$(ulimit -Sl)"
printf 'hard limit (KiB): %s\n' "$(ulimit -Hl)"

printf '\n== Assessment ==\n'
printf 'Engine model: %s\n' "$MODEL_FILE"
printf 'Router endpoint will be %s (video used port 8080; see GUIDE.md section 3).\n' "$ENGINE_BASE_URL"
printf 'Stack scripts never modify the project-01 build; containers need no GPU.\n'
printf 'Set ENGINE_MLOCK=1 only after raising both memlock limits (see GUIDE.md).\n'
