#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

action="${1:-status}"
profile="${2:-$MODEL_PROFILE}"
pid_file="$STATE_DIR/llama-server.pid"
meta_file="$STATE_DIR/llama-server.meta"
require_command flock
exec 9>"$STATE_DIR/llama-server.lock"
flock -n 9 || { status_line FAIL "Another server lifecycle operation is active"; exit 1; }

meta_value() {
  local key="$1"
  [[ -f "$meta_file" ]] || return 1
  python3 - "$meta_file" "$key" <<'PY'
import sys
path, key = sys.argv[1:]
for line in open(path, encoding="utf-8"):
    name, separator, value = line.rstrip("\n").partition("=")
    if separator and name == key:
        print(value)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

is_owned() {
  [[ -f "$pid_file" ]] || return 1
  local pid
  read -r pid <"$pid_file"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  local expected_exe expected_start actual_exe actual_start
  expected_exe="$(meta_value executable 2>/dev/null || true)"
  expected_start="$(meta_value start_ticks 2>/dev/null || true)"
  actual_exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  actual_start="$(python3 - "$pid" <<'PY'
import pathlib, sys
try:
    value = pathlib.Path(f"/proc/{sys.argv[1]}/stat").read_text()
    fields = value[value.rfind(") ") + 2:].split()
    print(fields[19])
except (OSError, IndexError):
    pass
PY
)"
  [[ -n "$expected_exe" && -n "$expected_start" && "$actual_exe" == "$expected_exe" && "$actual_start" == "$expected_start" ]] || return 2
}

signal_owned() {
  local signal_name="$1" pid expected_exe expected_start
  read -r pid <"$pid_file"
  expected_exe="$(meta_value executable)"
  expected_start="$(meta_value start_ticks)"
  python3 - "$pid" "$signal_name" "$expected_exe" "$expected_start" <<'PY'
import os, pathlib, signal, sys
pid, signal_name, expected_exe, expected_start = sys.argv[1:]
pid = int(pid)
pidfd = os.pidfd_open(pid)
try:
    actual_exe = str(pathlib.Path(f"/proc/{pid}/exe").resolve())
    value = pathlib.Path(f"/proc/{pid}/stat").read_text()
    actual_start = value[value.rfind(") ") + 2:].split()[19]
    if actual_exe != expected_exe or actual_start != expected_start:
        raise SystemExit(1)
    signal.pidfd_send_signal(pidfd, getattr(signal, f"SIG{signal_name}"))
finally:
    os.close(pidfd)
PY
}

stop_owned() {
  local pid
  read -r pid <"$pid_file"
  signal_owned TERM
  for _ in $(seq 1 30); do
    set +e
    is_owned
    ownership=$?
    set -e
    (( ownership == 0 )) && { sleep 1; continue; }
    (( ownership == 1 )) && break
    status_line FAIL "PID identity changed while waiting for shutdown; refusing further signals"
    return 1
  done
  set +e
  is_owned
  ownership=$?
  set -e
  if (( ownership == 0 )); then
    status_line WARN "Server did not stop within 30 seconds; sending KILL to verified PID $pid"
    signal_owned KILL
    for _ in $(seq 1 5); do
      set +e
      is_owned
      ownership=$?
      set -e
      (( ownership == 1 )) && break
      (( ownership == 2 )) && { status_line FAIL "PID identity changed after KILL; retaining metadata"; return 1; }
      sleep 1
    done
  fi
  set +e
  is_owned
  ownership=$?
  set -e
  if (( ownership != 1 )); then
    status_line FAIL "Verified PID $pid remains alive; retaining ownership metadata"
    return 1
  fi
  rm -f "$pid_file" "$meta_file"
}

case "$action" in
  status)
    set +e
    is_owned
    ownership=$?
    set -e
    if (( ownership == 0 )); then
      read -r pid <"$pid_file"
      if response="$(curl --connect-timeout 2 --max-time 10 --silent --show-error --fail "http://$SERVER_HOST:$SERVER_PORT/health" 2>/dev/null)" \
        && python3 -c 'import json,sys; assert json.loads(sys.argv[1]).get("status") == "ok"' "$response"; then
        status_line PASS "llama-server PID $pid is healthy on $SERVER_HOST:$SERVER_PORT"
      else
        status_line WARN "Owned llama-server PID $pid is running but not ready"
      fi
    elif (( ownership == 2 )); then
      status_line FAIL "PID metadata does not match the live process; state was retained for inspection"
      exit 1
    else
      status_line "NOT RUN" "No owned llama-server process is running"
    fi
    exit 0
    ;;
  stop)
    set +e
    is_owned
    ownership=$?
    set -e
    if (( ownership == 2 )); then
      status_line FAIL "Refusing to signal a process whose executable/start time do not match recorded ownership"
      exit 1
    fi
    if (( ownership != 0 )); then
      status_line "NOT RUN" "No owned llama-server process is running"
      rm -f "$pid_file" "$meta_file"
      exit 0
    fi
    read -r pid <"$pid_file"
    stop_owned
    status_line PASS "Stopped owned llama-server PID $pid"
    exit 0
    ;;
  start|foreground) ;;
  *)
    printf 'Usage: %s status | stop | start PROFILE | foreground PROFILE\n' "$0" >&2
    exit 2
    ;;
esac

[[ "$SERVER_HOST" == "127.0.0.1" || "${ALLOW_REMOTE_BIND:-NO}" == "YES" ]] || {
  status_line FAIL "Non-loopback bind requires ALLOW_REMOTE_BIND=YES"
  exit 1
}
set +e
is_owned
ownership=$?
set -e
if (( ownership == 0 )); then
  status_line FAIL "An owned llama-server process is already running"
  exit 1
elif (( ownership == 2 )); then
  status_line FAIL "Live process conflicts with retained server ownership metadata"
  exit 1
fi
if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$SERVER_PORT" | grep -q LISTEN; then
  status_line FAIL "Port $SERVER_PORT is already occupied; no process was stopped"
  exit 1
fi

load_profiles
load_model_profile "$profile"
N_CPU_MOE="${N_CPU_MOE_OVERRIDE:-$N_CPU_MOE}"
CONTEXT_SIZE="${CONTEXT_SIZE_OVERRIDE:-$CONTEXT_SIZE}"
BATCH_SIZE="${BATCH_SIZE_OVERRIDE:-$BATCH_SIZE}"
UBATCH_SIZE="${UBATCH_SIZE_OVERRIDE:-$UBATCH_SIZE}"
CACHE_TYPE_K="${CACHE_TYPE_K_OVERRIDE:-$CACHE_TYPE_K}"
CACHE_TYPE_V="${CACHE_TYPE_V_OVERRIDE:-$CACHE_TYPE_V}"
CACHE_REUSE="${CACHE_REUSE_OVERRIDE:-$CACHE_REUSE}"
server="$(find_llama_binary llama-server)"
require_file "$MODEL_PATH"
model_sha256="$(sha256sum "$MODEL_PATH" | cut -d ' ' -f 1)"
write_server_result() {
  local output="$1" status="$2" message="$3" evidence="$4"
  write_status_json "$output" start-server "$status" "$message" "$evidence"
  python3 - "$output" "$profile" "$MODEL_PATH" "$model_sha256" "$N_CPU_MOE" "$CONTEXT_SIZE" "$UBATCH_SIZE" "$CACHE_TYPE_K" "$CACHE_TYPE_V" <<'PY'
import json, pathlib, sys
path, profile, model_path, model_sha256, n_cpu_moe, context_size, ubatch_size, cache_k, cache_v = sys.argv[1:]
data = json.loads(pathlib.Path(path).read_text())
data["profile"] = profile
data["configuration"] = {
    "model_path": model_path, "model_sha256": model_sha256, "n_cpu_moe": int(n_cpu_moe),
    "context_size": int(context_size), "ubatch_size": int(ubatch_size),
    "cache_type_k": cache_k, "cache_type_v": cache_v,
}
pathlib.Path(path).write_text(json.dumps(data, indent=2) + "\n")
PY
}
confirm_exact "RUN_SERVER_$profile" \
  "This loads a large model and may consume substantial RAM/VRAM. Binding remains $SERVER_HOST."

cmd=(
  "$server"
  --model "$MODEL_PATH"
  --alias "$MODEL_ID"
  --host "$SERVER_HOST"
  --port "$SERVER_PORT"
  --n-gpu-layers "$N_GPU_LAYERS"
  --n-cpu-moe "$N_CPU_MOE"
  --ctx-size "$CONTEXT_SIZE"
  --parallel "$PARALLEL"
  --threads "$THREADS"
  --threads-batch "$THREADS_BATCH"
  --batch-size "$BATCH_SIZE"
  --ubatch-size "$UBATCH_SIZE"
  --cache-type-k "$CACHE_TYPE_K"
  --cache-type-v "$CACHE_TYPE_V"
  --flash-attn "$FLASH_ATTN"
  --cache-reuse "$CACHE_REUSE"
  --cache-ram "$CACHE_RAM_MIB"
  --fit off
  --jinja
  --metrics
  --offline
  --no-ui
)
if [[ "$MMAP_MODE" == "off" ]]; then
  cmd+=(--no-mmap)
else
  cmd+=(--mmap)
fi

id="$(run_id)"
log="$LOGS_DIR/server_${profile}_${id}.log"
command_log="$LOGS_DIR/server_${profile}_${id}.command"
readiness_log="$LOGS_DIR/server_${profile}_${id}.readiness.json"
resources_before="$LOGS_DIR/server_${profile}_${id}.resources-before.txt"
resources_after="$LOGS_DIR/server_${profile}_${id}.resources-after.txt"
log_command "$command_log" "${cmd[@]}"
printf 'Profile note: %s\n' "$MODEL_CANDIDATE_NOTE" >>"$command_log"
capture_resources "$resources_before"

if [[ "$action" == "foreground" ]]; then
  status_line WARN "Starting foreground server; readiness must be checked from another terminal"
  exec "${cmd[@]}" 2>&1 | tee "$log"
fi

setsid "${cmd[@]}" >"$log" 2>&1 &
pid=$!
printf '%s\n' "$pid" >"$pid_file"
for _ in $(seq 1 20); do
  if [[ -r "/proc/$pid/stat" && -e "/proc/$pid/exe" ]] \
    && [[ "$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)" == "$(readlink -f "$server")" ]]; then
    break
  fi
  sleep 0.1
done
executable="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
if [[ "$executable" != "$(readlink -f "$server")" ]]; then
  status_line FAIL "Server process exited or did not establish executable identity"
  rm -f "$pid_file" "$meta_file"
  exit 1
fi
start_ticks="$(python3 - "$pid" <<'PY'
import pathlib, sys
value = pathlib.Path(f"/proc/{sys.argv[1]}/stat").read_text()
fields = value[value.rfind(") ") + 2:].split()
print(fields[19])
PY
)"
printf 'profile=%s\nlog=%s\ncommand=%s\nstarted=%s\nexecutable=%s\nstart_ticks=%s\nhost=%s\nport=%s\nmodel_id=%s\n' \
  "$profile" "$log" "$command_log" "$(date -u +%FT%TZ)" "$executable" "$start_ticks" "$SERVER_HOST" "$SERVER_PORT" "$MODEL_ID" >"$meta_file"

ready=0
readiness_deadline=$((SECONDS + 720))
for _ in $(seq 1 720); do
  remaining=$((readiness_deadline - SECONDS))
  (( remaining > 0 )) || break
  if ! kill -0 "$pid" 2>/dev/null; then
    break
  fi
  if response="$(curl --connect-timeout 2 --max-time 10 --silent --show-error --fail "http://$SERVER_HOST:$SERVER_PORT/health" 2>/dev/null)" \
    && python3 -c 'import json,sys; assert json.loads(sys.argv[1]).get("status") == "ok"' "$response"; then
    models_response="$(curl --connect-timeout 2 --max-time 10 --silent --show-error --fail "http://$SERVER_HOST:$SERVER_PORT/v1/models" 2>/dev/null || true)"
    if python3 -c 'import json,sys; data=json.loads(sys.argv[1]); expected=sys.argv[2]; assert any(item.get("id") == expected for item in data.get("data", []))' "$models_response" "$MODEL_ID" 2>/dev/null; then
      request_file="$LOGS_DIR/server_${profile}_${id}.request.json"
      python3 - "$request_file" "$MODEL_ID" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump({"model": sys.argv[2], "messages": [{"role": "user", "content": "Reply with OK."}], "max_tokens": 1, "temperature": 0, "stream": False}, handle)
PY
      inference_max=$((remaining < 300 ? remaining : 300))
      inference_response="$(curl --connect-timeout 2 --max-time "$inference_max" --silent --show-error --fail \
        -H 'Content-Type: application/json' --data-binary "@$request_file" \
        "http://$SERVER_HOST:$SERVER_PORT/v1/chat/completions" 2>/dev/null || true)"
      if python3 -c 'import json,sys; data=json.loads(sys.argv[1]); assert data.get("choices")' "$inference_response" 2>/dev/null; then
        python3 - "$readiness_log" "$response" "$models_response" "$inference_response" <<'PY'
import json, sys
output, health, models, inference = sys.argv[1:]
with open(output, "w", encoding="utf-8") as handle:
    json.dump({"health": json.loads(health), "models": json.loads(models), "inference": json.loads(inference)}, handle, indent=2)
    handle.write("\n")
PY
        ready=1
        break
      fi
    fi
  fi
  sleep 1
done

result="$RESULTS_DIR/server-${profile}-${id}.json"
if (( ready == 1 )); then
  capture_resources "$resources_after"
  vram_free="$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | sed -n '1p' | tr -d ' ' || true)"
  mem_available_kib="$(grep '^MemAvailable:' /proc/meminfo | tr -s ' ' | cut -d ' ' -f 2)"
  swap_before_bytes="$(grep '^Swap:' "$resources_before" | tr -s ' ' | cut -d ' ' -f 3)"
  swap_after_bytes="$(grep '^Swap:' "$resources_after" | tr -s ' ' | cut -d ' ' -f 3)"
  if [[ ! "$vram_free" =~ ^[0-9]+$ ]]; then
    write_server_result "$result" FAIL "Inference passed but VRAM telemetry was unavailable" "$resources_after"
    status_line FAIL "VRAM telemetry is required; stopping server"
    stop_owned || true
    exit 1
  fi
  if (( vram_free < 256 )); then
    write_server_result "$result" FAIL "Inference passed but less than 256 MiB VRAM remained" "$resources_after"
    status_line FAIL "Unsafe VRAM margin after load; stopping server"
    stop_owned || true
    exit 1
  fi
  if (( mem_available_kib < 8 * 1024 * 1024 || swap_after_bytes > swap_before_bytes + 64 * 1024 * 1024 )); then
    write_server_result "$result" FAIL "Inference passed but host RAM/swap safety criterion failed" "$resources_after"
    status_line FAIL "Unsafe host RAM or swap use after load; stopping server"
    stop_owned || true
    exit 1
  fi
  write_server_result "$result" PASS "Server health, model identity, and bounded inference passed for profile $profile" "$readiness_log"
  status_line PASS "Server ready at http://$SERVER_HOST:$SERVER_PORT (PID $pid)"
  printf 'Stop safely with: %s stop\n' "$0"
else
  capture_resources "$resources_after"
  write_server_result "$result" FAIL "Server exited or did not become ready within 12 minutes" "$log"
  status_line FAIL "Server failed readiness; inspect $log"
  set +e
  is_owned
  ownership=$?
  set -e
  if (( ownership == 0 )); then
    stop_owned || true
  fi
  exit 1
fi
