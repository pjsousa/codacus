#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

id="$(run_id)"
report="$LOGS_DIR/preflight_${id}.log"
summary="$RESULTS_DIR/preflight_${id}.json"
pass=0
warn=0
fail=0

record() {
  local status="$1" message="$2"
  status_line "$status" "$message" | tee -a "$report"
  case "$status" in
    PASS) pass=$((pass + 1)) ;;
    WARN) warn=$((warn + 1)) ;;
    FAIL) fail=$((fail + 1)) ;;
  esac
}

: >"$report"
{
  printf 'Preflight UTC: %s\n' "$(date -u +%FT%TZ)"
  printf 'Project: %s\nBuild: %s\nModels: %s\n\n' "$PROJECT_DIR" "$LLAMA_BUILD_DIR" "$MODEL_DIR"
  printf '== OS and shell ==\n'
  if [[ -r /etc/os-release ]]; then
    source /etc/os-release
    printf 'OS: %s\n' "${PRETTY_NAME:-unknown}"
  fi
  uname -a
  printf 'Shell: %s\n\n' "${SHELL:-unknown}"
  printf '== CPU ==\n'
  lscpu
  printf '\n== RAM ==\n'
  free -h
  printf '\n== Disk ==\n'
  df -h "$PROJECT_DIR" "$MODEL_DIR" 2>/dev/null || df -h "$PROJECT_DIR"
  printf '\n== NVIDIA ==\n'
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,memory.free,compute_cap --format=csv,noheader
  else
    printf 'nvidia-smi unavailable\n'
  fi
  printf '\n== Memory lock ==\nsoft=%s\nhard=%s\n' "$(ulimit -Sl)" "$(ulimit -Hl)"
  printf '\n== Port %s ==\n' "$SERVER_PORT"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "sport = :$SERVER_PORT" || true
  fi
  printf '\n== Utilities ==\n'
  for utility in curl wget git python3 node npm nvidia-smi jq flock; do
    printf '%-12s %s\n' "$utility" "$(command -v "$utility" 2>/dev/null || printf MISSING)"
  done
  printf '\n== Existing llama.cpp version ==\n'
  if binary="$(find_llama_binary llama-server 2>/dev/null)"; then
    "$binary" --version || true
  fi
} >>"$report" 2>&1

if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader | sed -n '1p')"
  if [[ "$gpu_name" == *"GTX 1070"* ]]; then
    record PASS "Target GTX 1070 detected: $gpu_name"
  else
    record WARN "Hardware differs from the GTX 1070 target: $gpu_name"
  fi
else
  record FAIL "NVIDIA runtime is not visible"
fi

if [[ -d "$LLAMA_BUILD_DIR" ]]; then
  record PASS "Existing llama.cpp build directory exists"
else
  record FAIL "Build directory is missing: $LLAMA_BUILD_DIR"
fi

for binary in llama-server llama-cli; do
  if path="$(find_llama_binary "$binary" 2>/dev/null)"; then
    record PASS "$binary found at $path"
  else
    record FAIL "$binary was not found under the existing build"
  fi
done

for utility in curl wget git python3 node npm nvidia-smi; do
  if command -v "$utility" >/dev/null 2>&1; then
    record PASS "$utility is available"
  else
    record WARN "$utility is unavailable; no package was installed"
  fi
done

if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
  node_minor="$(node -p 'process.versions.node.split(".")[1]')"
  if (( node_major > 22 || (node_major == 22 && node_minor >= 19) )); then
    record PASS "Node $(node --version) satisfies Pi's >=22.19.0 requirement"
  else
    record WARN "Node $(node --version) is present but current Pi requires >=22.19.0"
  fi
fi

if [[ -r "$LLAMA_BUILD_DIR/CMakeCache.txt" ]] && grep -q '^GGML_CUDA:BOOL=ON' "$LLAMA_BUILD_DIR/CMakeCache.txt"; then
  record PASS "CMake cache records GGML_CUDA=ON"
else
  record WARN "CUDA build status was not proven from CMakeCache.txt"
fi

if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$SERVER_PORT" | grep -q LISTEN; then
  record WARN "Port $SERVER_PORT is already in use; choose another port before launch"
else
  record PASS "Port $SERVER_PORT appears available"
fi

overall="PASS"
if (( fail > 0 )); then
  overall="FAIL"
elif (( warn > 0 )); then
  overall="WARN"
fi

python3 - "$summary" "$overall" "$pass" "$warn" "$fail" "$report" <<'PY'
import json, sys
from datetime import datetime, timezone

output, overall, passed, warned, failed, report = sys.argv[1:]
data = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "stage": "preflight",
    "status": overall,
    "counts": {"pass": int(passed), "warn": int(warned), "fail": int(failed)},
    "evidence": report,
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY

printf '\nSummary: %s (PASS=%d WARN=%d FAIL=%d)\nReport: %s\nResult: %s\n' \
  "$overall" "$pass" "$warn" "$fail" "$report" "$summary"
(( fail == 0 ))
