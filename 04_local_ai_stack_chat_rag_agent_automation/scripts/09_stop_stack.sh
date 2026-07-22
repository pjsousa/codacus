#!/usr/bin/env bash
# Stop every stack layer started by this package. Containers are stopped but
# their named volumes (AnythingLLM storage, n8n data) are preserved. Set
# PURGE_VOLUMES=1 to also delete those volumes (data loss, opt-in).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

stop_pid_file() {
  # stop_pid_file <label> <pid_file> <expected_binary_substring>
  local label="$1" pid_file="$2" expected="$3"
  if [[ ! -f "$pid_file" ]]; then
    printf 'SKIP: %s not running (no PID file).\n' "$label"
    return
  fi
  local pid
  pid="$(cat "$pid_file")"
  if ! kill -0 "$pid" 2>/dev/null; then
    printf 'SKIP: %s PID %s already exited.\n' "$label" "$pid"
    rm -f "$pid_file"
    return
  fi
  if ! tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q -- "$expected"; then
    printf 'WARN: PID %s does not look like %s; refusing to kill it. Remove %s manually if stale.\n' \
      "$pid" "$expected" "$pid_file" >&2
    return
  fi
  kill "$pid" 2>/dev/null || true
  for _ in $(seq 1 30); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$pid" 2>/dev/null; then
    printf 'WARN: %s PID %s did not exit on SIGTERM; sending SIGKILL.\n' "$label" "$pid" >&2
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
  printf 'Stopped %s (PID %s).\n' "$label" "$pid"
}

stop_pid_file "llama-swap" "$LLAMA_SWAP_PID_FILE" "llama-swap"
stop_pid_file "engine (llama-server router)" "$ENGINE_PID_FILE" "llama-server"

if command -v docker >/dev/null 2>&1; then
  for stack in anythingllm n8n; do
    compose_file="$STACK_DIR/$stack/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
      if [[ "${PURGE_VOLUMES:-0}" == "1" ]]; then
        docker compose -f "$compose_file" down -v
        printf 'Stopped %s and DELETED its named volume.\n' "$stack"
      else
        docker compose -f "$compose_file" down
        printf 'Stopped %s (volume preserved).\n' "$stack"
      fi
    else
      printf 'SKIP: no compose file for %s.\n' "$stack"
    fi
  done
else
  printf 'WARN: docker unavailable; containers (if any) left running.\n' >&2
fi

printf 'Stack stopped. Logs and reports remain under %s.\n' "$RESULTS_DIR"
