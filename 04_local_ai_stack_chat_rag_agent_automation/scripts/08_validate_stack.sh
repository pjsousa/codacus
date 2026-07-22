#!/usr/bin/env bash
# End-to-end stack validation (video chapter 13:54). Hard-fails on the engine
# layer; UI layers fail only when their container exists but is unhealthy.
# Optional soak: SOAK_SECONDS=28800 SOAK_INTERVAL=300 repeats the engine chat
# check and records telemetry.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_command curl
require_command jq
require_command docker
prepare_results
curl_auth_args

SOAK_SECONDS="${SOAK_SECONDS:-0}"
SOAK_INTERVAL="${SOAK_INTERVAL:-300}"

run_id="stack_validation_$(timestamp)"
report="$RESULTS_DIR/${run_id}.md"
telemetry_file="$RESULTS_DIR/${run_id}_telemetry.csv"
failures=0
warnings=0

hard_fail() { printf 'FAIL: %s\n' "$1" | tee -a "$report"; failures=$((failures + 1)); }
soft_warn() { printf 'WARN: %s\n' "$1" | tee -a "$report"; warnings=$((warnings + 1)); }
pass() { printf 'PASS: %s\n' "$1" | tee -a "$report"; }
skip() { printf 'SKIP: %s\n' "$1" | tee -a "$report"; }

{
  printf '# Stack validation %s\n\n' "$(date -u +%FT%TZ)"
  printf '- engine base URL: %s\n' "$ENGINE_BASE_URL"
  printf '- model alias: %s\n' "$MODEL_ALIAS"
  printf '- engine build revision: %s\n\n' "$LLAMA_REV"
} >"$report"

chat_once() {
  # chat_once <output_json> — echoes seconds_total, returns nonzero on failure.
  curl --silent --max-time 300 "${CURL_AUTH_ARGS[@]}" \
    -H 'Content-Type: application/json' \
    -o "$1" -w '%{time_total}' \
    -d "$(jq -nc --arg model "$MODEL_ALIAS" --arg prompt "$SMOKE_PROMPT" \
      '{model:$model,messages:[{role:"user",content:$prompt}],max_tokens:'"$SMOKE_MAX_TOKENS"',temperature:0,seed:42}')" \
    "$ENGINE_BASE_URL/v1/chat/completions"
}

printf '== Engine ==\n'
models_json="$RESULTS_DIR/${run_id}_models.json"
if curl --silent --fail --max-time 15 "${CURL_AUTH_ARGS[@]}" \
  "$ENGINE_BASE_URL/v1/models" -o "$models_json" 2>/dev/null; then
  if jq -e --arg id "$MODEL_ALIAS" '.data[]? | select(.id == $id)' "$models_json" >/dev/null; then
    pass "engine lists preset \"$MODEL_ALIAS\""
  else
    hard_fail "engine is up but preset \"$MODEL_ALIAS\" is not listed (see $models_json)"
  fi
else
  hard_fail "engine not reachable at $ENGINE_BASE_URL (run scripts/02_start_engine.sh)"
fi

smoke_json="$RESULTS_DIR/${run_id}_smoke.json"
if seconds="$(chat_once "$smoke_json")" && jq -e '.choices[0].message.content | length > 0' \
  "$smoke_json" >/dev/null 2>&1; then
  pass "routed chat completion in ${seconds}s: $(jq -r '.choices[0].message.content' "$smoke_json")"
else
  hard_fail "routed chat completion failed (see $smoke_json)"
fi

printf '\n== UI layers ==\n'
check_container() {
  # check_container <name> <health_url>
  local name="$1" health_url="$2"
  if ! docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    skip "$name container not created yet"
    return
  fi
  if ! docker ps --format '{{.Names}}' | grep -qx "$name"; then
    hard_fail "$name container exists but is not running (docker start $name)"
    return
  fi
  local code
  code="$(curl --silent --max-time 10 -o /dev/null -w '%{http_code}' "$health_url" || true)"
  if [[ "$code" =~ ^(200|302)$ ]]; then
    pass "$name answers HTTP $code"
  else
    hard_fail "$name unhealthy (HTTP $code at $health_url; docker logs $name)"
  fi
  local policy
  policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name")"
  if [[ "$policy" == "unless-stopped" || "$policy" == "always" ]]; then
    pass "$name restart policy is $policy"
  else
    soft_warn "$name restart policy is $policy (expected unless-stopped)"
  fi
}
check_container anythingllm "http://127.0.0.1:$ANYTHINGLLM_PORT"
check_container n8n "http://127.0.0.1:$N8N_PORT/healthz"

printf '\n== Engine process ==\n'
if [[ -f "$ENGINE_PID_FILE" ]] && kill -0 "$(cat "$ENGINE_PID_FILE")" 2>/dev/null; then
  engine_pid="$(cat "$ENGINE_PID_FILE")"
  pass "engine process $engine_pid alive"
  grep -E '^(VmRSS|VmLck|VmSwap):' "/proc/$engine_pid/status" | tee -a "$report"
else
  soft_warn "engine PID file $ENGINE_PID_FILE missing or stale (started another way?)"
fi
capture_snapshot "$RESULTS_DIR/${run_id}_after.txt"

if (( SOAK_SECONDS > 0 )); then
  printf '\n== Soak (%ss every %ss) ==\n' "$SOAK_SECONDS" "$SOAK_INTERVAL"
  printf 'timestamp,http_time_s,vmrss_kib,vmswap_kib,gpu_memory_mib\n' >"$telemetry_file"
  end_time=$((SECONDS + SOAK_SECONDS))
  soak_failures=0
  while (( SECONDS < end_time )); do
    sleep "$SOAK_INTERVAL"
    soak_json="$RESULTS_DIR/${run_id}_soak.json"
    if ! seconds="$(chat_once "$soak_json")"; then
      soak_failures=$((soak_failures + 1))
      seconds="-1"
    fi
    vmrss_kib="-"; vmswap_kib="-"
    if [[ -n "${engine_pid:-}" ]] && kill -0 "$engine_pid" 2>/dev/null; then
      read -r _ vmrss_kib _ < <(grep '^VmRSS:' "/proc/$engine_pid/status")
      read -r _ vmswap_kib _ < <(grep '^VmSwap:' "/proc/$engine_pid/status")
    fi
    gpu_mib="-"
    if command -v nvidia-smi >/dev/null 2>&1; then
      gpu_mib="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)"
    fi
    printf '%s,%s,%s,%s,%s\n' "$(date -u +%FT%TZ)" "$seconds" "$vmrss_kib" "$vmswap_kib" "$gpu_mib" \
      | tee -a "$telemetry_file"
  done
  if (( soak_failures > 0 )); then
    hard_fail "$soak_failures soak request(s) failed (telemetry: $telemetry_file)"
  else
    pass "soak completed without failed requests ($telemetry_file)"
  fi
fi

printf '\n== Result ==\n'
printf 'Report: %s\n' "$report"
if (( failures > 0 )); then
  printf '%s check(s) failed, %s warning(s).\n' "$failures" "$warnings" >&2
  exit 1
fi
printf 'All checks passed (%s warning(s)).\n' "$warnings"
