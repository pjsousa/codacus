#!/usr/bin/env bash
set -euo pipefail

LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$LIB_DIR/../.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_DIR/configs/env.local}"

LLAMA_BUILD_DIR="${LLAMA_BUILD_DIR:-$HOME/llama-low-vram-repro/llama-cpp-turboquant/build}"
MODEL_DIR="${MODEL_DIR:-$HOME/llama-low-vram-repro/models}"
LOGS_DIR="${LOGS_DIR:-$PROJECT_DIR/logs}"
RESULTS_DIR="${RESULTS_DIR:-$PROJECT_DIR/results}"
STATE_DIR="${STATE_DIR:-$PROJECT_DIR/.state}"
TOOLS_DIR="${TOOLS_DIR:-$PROJECT_DIR/.tools}"
SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-8088}"
MODEL_PROFILE="${MODEL_PROFILE:-existing-control}"
THREADS="${THREADS:-3}"
THREADS_BATCH="${THREADS_BATCH:-4}"
CACHE_RAM_MIB="${CACHE_RAM_MIB:-4096}"
PI_VERSION="${PI_VERSION:-0.80.10}"
PI_LLAMA_CPP_VERSION="${PI_LLAMA_CPP_VERSION:-0.9.1}"

if [[ -f "$CONFIG_FILE" ]]; then
  # This is executable local configuration and must remain user-owned.
  if [[ -L "$CONFIG_FILE" || -n "$(find "$CONFIG_FILE" -maxdepth 0 -perm /022 -print 2>/dev/null)" ]]; then
    printf 'Refusing unsafe configuration file: %s\n' "$CONFIG_FILE" >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

mkdir -p "$LOGS_DIR" "$RESULTS_DIR" "$STATE_DIR"

timestamp() {
  date -u +%Y%m%dT%H%M%S_%NZ
}

run_id() {
  printf '%s_%s\n' "$(timestamp)" "$$"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    return 1
  }
}

require_file() {
  [[ -f "$1" ]] || {
    printf 'Required file not found: %s\n' "$1" >&2
    return 1
  }
}

find_llama_binary() {
  local name="$1" candidate
  for candidate in \
    "$LLAMA_BUILD_DIR/bin/$name" \
    "$LLAMA_BUILD_DIR/$name" \
    "$LLAMA_BUILD_DIR/tools/server/$name" \
    "$LLAMA_BUILD_DIR/examples/$name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      status_line "FOUND" "$candidate" >&2
      return 0
    fi
  done
  return 1
}

status_line() {
  local status="$1" message="$2"
  printf '%-7s %s\n' "$status" "$message"
}

write_status_json() {
  local output="$1" stage="$2" status="$3" message="$4" evidence="${5:-}"
  python3 - "$output" "$stage" "$status" "$message" "$evidence" <<'PY'
import json, sys
from datetime import datetime, timezone

output, stage, status, message, evidence = sys.argv[1:]
data = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "stage": stage,
    "status": status,
    "message": message,
    "evidence": evidence or None,
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
}

log_command() {
  local output="$1"
  shift
  printf 'Command:' >"$output"
  printf ' %q' "$@" >>"$output"
  printf '\n' >>"$output"
}

confirm_exact() {
  local expected="$1" prompt="$2" answer
  if [[ "${CONFIRM:-}" == "$expected" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    printf 'Confirmation required. Re-run with CONFIRM=%q.\n' "$expected" >&2
    return 1
  fi
  printf '%s\nType %s to continue: ' "$prompt" "$expected" >&2
  read -r answer
  [[ "$answer" == "$expected" ]]
}

load_profiles() {
  local profiles_file="${MODEL_PROFILES_FILE:-$PROJECT_DIR/configs/model-profiles.example.sh}"
  require_file "$profiles_file"
  # shellcheck disable=SC1090
  source "$profiles_file"
}

capture_resources() {
  local output="$1"
  {
    printf 'timestamp=%s\n' "$(date -u +%FT%TZ)"
    free -b
    df -B1 "$PROJECT_DIR"
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu,pstate --format=csv,noheader,nounits
    fi
  } >"$output"
}

managed_server_identity() {
  local pid_file="$STATE_DIR/llama-server.pid"
  local meta_file="$STATE_DIR/llama-server.meta"
  [[ -f "$pid_file" && -f "$meta_file" ]] || return 1
  read -r MANAGED_SERVER_PID <"$pid_file"
  [[ "$MANAGED_SERVER_PID" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$MANAGED_SERVER_PID" 2>/dev/null || return 1

  read -r MANAGED_SERVER_EXE MANAGED_SERVER_START MANAGED_SERVER_PROFILE MANAGED_SERVER_HOST MANAGED_SERVER_PORT MANAGED_SERVER_MODEL_ID < <(
    python3 - "$meta_file" <<'PY'
import pathlib, sys
values = {}
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    key, separator, value = line.partition("=")
    if separator:
        values[key] = value
print(values.get("executable", ""), values.get("start_ticks", ""), values.get("profile", ""), values.get("host", ""), values.get("port", ""), values.get("model_id", ""))
PY
  )
  local actual_exe actual_start cmdline
  actual_exe="$(readlink -f "/proc/$MANAGED_SERVER_PID/exe" 2>/dev/null || true)"
  actual_start="$(python3 - "$MANAGED_SERVER_PID" <<'PY'
import pathlib, sys
try:
    value = pathlib.Path(f"/proc/{sys.argv[1]}/stat").read_text()
    print(value[value.rfind(") ") + 2:].split()[19])
except (OSError, IndexError):
    pass
PY
)"
  cmdline="$(tr '\0' ' ' <"/proc/$MANAGED_SERVER_PID/cmdline" 2>/dev/null || true)"
  [[ -n "$MANAGED_SERVER_EXE" && "$actual_exe" == "$MANAGED_SERVER_EXE" ]] || return 1
  [[ -n "$MANAGED_SERVER_START" && "$actual_start" == "$MANAGED_SERVER_START" ]] || return 1
  [[ "$MANAGED_SERVER_HOST" == "$SERVER_HOST" && "$MANAGED_SERVER_PORT" == "$SERVER_PORT" ]] || return 1
  [[ "$cmdline" == *"--host $SERVER_HOST"* && "$cmdline" == *"--port $SERVER_PORT"* ]] || return 1
}
