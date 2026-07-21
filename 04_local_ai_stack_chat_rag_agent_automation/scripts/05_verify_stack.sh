#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

require_command curl

LLAMA_BASE_URL="${LLAMA_BASE_URL:-http://${LLAMA_HOST:-127.0.0.1}:${LLAMA_PORT:-8080}}"
ANYTHING_LLM_PORT="${ANYTHING_LLM_PORT:-3001}"
N8N_PORT="${N8N_PORT:-5678}"

overall_pass=0

check() {
  local name="$1"
  local url="$2"
  local desc="$3"
  printf '[..] %s' "$desc"
  if curl --silent --fail --max-time 5 "$url" >/dev/null 2>&1; then
    printf '\r[OK] %s (%s)\n' "$desc" "$url"
  else
    printf '\r[--] %s (%s)\n' "$desc" "$url"
    overall_pass=1
  fi
}

printf '=== Local AI Stack — End-to-End Verification ===\n\n'

printf '--- Inference Engine ---\n'
check "llama-server" "$LLAMA_BASE_URL/health" "llama-server health endpoint"
check "llama-models" "$LLAMA_BASE_URL/v1/models" "OpenAI-compatible /v1/models"

printf '\n--- Chat UI (AnythingLLM) ---\n'
check "anythingllm" "http://127.0.0.1:$ANYTHING_LLM_PORT" "AnythingLLM web UI"

printf '\n--- Automation (n8n) ---\n'
check "n8n" "http://127.0.0.1:$N8N_PORT/healthz" "n8n health endpoint"

printf '\n--- Coding Agent (Pi) ---\n'
if command -v pi >/dev/null 2>&1; then
  printf '[OK] Pi binary found at %s\n' "$(command -v pi)"
  config_file="${HOME}/.pi/config.json"
  if [[ -f "$config_file" ]]; then
    if grep -q "$LLAMA_BASE_URL" "$config_file" 2>/dev/null; then
      printf '[OK] Pi config points to local endpoint\n'
    else
      printf '[--] Pi config exists but endpoint mismatch. Expected: %s\n' "$LLAMA_BASE_URL"
    fi
  else
    printf '[--] Pi config file not found\n'
  fi
else
  printf '[--] Pi is not installed\n'
fi

printf '\n--- Summary ---\n'
if (( overall_pass == 0 )); then
  printf 'All reachable services verified.\n'
else
  printf 'Some services are unreachable. Start missing services with the appropriate script.\n'
fi
printf '\nStack endpoints:\n'
printf '  Inference:    %s/v1\n' "$LLAMA_BASE_URL"
printf '  Chat UI:      http://localhost:%s\n' "$ANYTHING_LLM_PORT"
printf '  Automation:   http://localhost:%s\n' "$N8N_PORT"
printf '  Coding agent: pi (CLI)\n'

exit "$overall_pass"
