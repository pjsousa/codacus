#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

mode="${1:-smoke}"
[[ "$mode" == "smoke" || "$mode" == "hot-swap" ]] || {
  printf 'Usage: %s [smoke|hot-swap]\n' "$0" >&2
  exit 2
}

require_command curl
require_command python3
require_command sha256sum
require_command timeout

pi_bin="$TOOLS_DIR/pi-$PI_VERSION/node_modules/.bin/pi"
if [[ ! -x "$pi_bin" ]]; then
  result="$RESULTS_DIR/pi-smoke-$(run_id).json"
  write_status_json "$result" pi-agent "NOT RUN" "Pi is not installed; run scripts/02_install_pi.sh after confirmation" ""
  status_line "NOT RUN" "Pi is not installed at $pi_bin"
  exit 0
fi

base_url="http://$SERVER_HOST:$SERVER_PORT"
if [[ "$mode" == "smoke" ]] && ! managed_server_identity; then
  result="$RESULTS_DIR/pi-smoke-$(run_id).json"
  write_status_json "$result" pi-agent "NOT RUN" "A verified managed llama.cpp server is required" ""
  status_line "NOT RUN" "Start the server with scripts/04_start_model_server.sh"
  exit 0
fi
if ! health="$(curl --connect-timeout 2 --max-time 10 --silent --show-error --fail "$base_url/health" 2>/dev/null)" \
  || ! python3 -c 'import json,sys; assert json.loads(sys.argv[1]).get("status") == "ok"' "$health"; then
  result="$RESULTS_DIR/pi-smoke-$(run_id).json"
  write_status_json "$result" pi-agent "NOT RUN" "A verified llama.cpp server is not ready at $base_url" ""
  status_line "NOT RUN" "Verified llama.cpp health endpoint unavailable at $base_url"
  exit 0
fi

models_json="$(curl --connect-timeout 2 --max-time 10 --silent --show-error --fail "$base_url/v1/models")"
model_id="$(python3 -c 'import json,sys; data=json.loads(sys.argv[1]); print(data["data"][0]["id"])' "$models_json")"
[[ -n "$model_id" ]] || { status_line FAIL "Server returned no model ID"; exit 1; }
server_profile="$(python3 - "$STATE_DIR/llama-server.meta" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
if path.exists():
    for line in path.read_text().splitlines():
        if line.startswith("profile="):
            print(line.split("=", 1)[1])
            break
PY
)"
server_profile="${server_profile:-unknown}"

if [[ "$mode" == "hot-swap" ]]; then
  router_pid="${ROUTER_PID:-}"
  [[ "$router_pid" =~ ^[0-9]+$ ]] && kill -0 "$router_pid" 2>/dev/null || {
    result="$RESULTS_DIR/hot-swap-$(run_id).json"
    write_status_json "$result" hot-swap "NOT RUN" "Set ROUTER_PID to the verified llama router process" ""
    status_line "NOT RUN" "A live, explicitly supplied ROUTER_PID is required"
    exit 0
  }
  router_exe="$(readlink -f "/proc/$router_pid/exe" 2>/dev/null || true)"
  router_start="$(python3 - "$router_pid" <<'PY'
import pathlib, sys
value = pathlib.Path(f"/proc/{sys.argv[1]}/stat").read_text()
print(value[value.rfind(") ") + 2:].split()[19])
PY
)"
  router_cmdline="$(tr '\0' ' ' <"/proc/$router_pid/cmdline")"
  [[ "$(basename "$router_exe")" == "llama-server" && "$router_cmdline" == *"--models-preset"* && "$router_cmdline" == *"--port $SERVER_PORT"* ]] || {
    status_line FAIL "ROUTER_PID is not the expected llama-server router on port $SERVER_PORT"
    exit 1
  }
  verify_router() {
    [[ "$(readlink -f "/proc/$router_pid/exe" 2>/dev/null || true)" == "$router_exe" ]] || return 1
    local current_start
    current_start="$(python3 - "$router_pid" <<'PY'
import pathlib, sys
try:
    value = pathlib.Path(f"/proc/{sys.argv[1]}/stat").read_text()
    print(value[value.rfind(") ") + 2:].split()[19])
except (OSError, IndexError):
    pass
PY
)"
    [[ "$current_start" == "$router_start" ]]
  }
  mapfile -t model_ids < <(python3 -c 'import json,sys; data=json.loads(sys.argv[1]); [print(item["id"]) for item in data.get("data", [])]' "$models_json")
  if (( ${#model_ids[@]} < 2 )); then
    result="$RESULTS_DIR/hot-swap-$(run_id).json"
    write_status_json "$result" hot-swap "NOT RUN" "Router advertises fewer than two models" ""
    status_line "NOT RUN" "Router must advertise at least two model IDs"
    exit 0
  fi
  confirm_exact "RUN_HOT_SWAP" \
    "This loads model A, model B, then A again. It may heavily use RAM/VRAM for up to 15 minutes."

  id="$(run_id)"
  log="$LOGS_DIR/hot-swap-$id.log"
  result="$RESULTS_DIR/hot-swap-$id.json"
  pi_models_log="$LOGS_DIR/hot-swap-$id.pi-models.log"
  telemetry="$LOGS_DIR/hot-swap-$id.gpu.csv"
  : >"$telemetry"
  : >"$log"

  PI_SKIP_VERSION_CHECK=1 PI_TELEMETRY=0 PI_CODING_AGENT_DIR="$STATE_DIR/pi" \
    LLAMA_SERVER_URL="$base_url" timeout 30s "$pi_bin" --list-models >"$pi_models_log" 2>&1 || true
  if ! grep -Fq "${model_ids[0]}" "$pi_models_log" || ! grep -Fq "${model_ids[1]}" "$pi_models_log"; then
    write_status_json "$result" hot-swap FAIL "Pi did not discover both router model IDs" "$pi_models_log"
    status_line FAIL "Pi model discovery did not show both router IDs"
    exit 1
  fi

  hot_deadline=$((SECONDS + 840))
  load_and_infer() {
    local selected="$1" request response status_json remaining
    remaining=$((hot_deadline - SECONDS))
    (( remaining > 0 )) || return 1
    request="$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1]}))' "$selected")"
    curl --connect-timeout 2 --max-time "$((remaining < 10 ? remaining : 10))" --silent --show-error --fail -H 'Content-Type: application/json' \
      --data-binary "$request" "$base_url/models/load" >>"$log"
    printf '\n' >>"$log"
    while (( SECONDS < hot_deadline )); do
      verify_router || return 1
      status_json="$(curl --connect-timeout 2 --max-time 10 --silent --show-error --fail "$base_url/models")" || return 1
      if python3 -c 'import json,sys; data=json.loads(sys.argv[1]); wanted=sys.argv[2]; assert any(item.get("id") == wanted and item.get("status", {}).get("value") == "loaded" for item in data.get("data", []))' "$status_json" "$selected" 2>/dev/null; then
        loaded_count="$(python3 -c 'import json,sys; data=json.loads(sys.argv[1]); print(sum(item.get("status", {}).get("value") == "loaded" for item in data.get("data", [])))' "$status_json")"
        [[ "$loaded_count" == "1" ]] || return 1
        response="$(python3 -c 'import json,sys; print(json.dumps({"model": sys.argv[1], "messages": [{"role": "user", "content": "Reply OK"}], "max_tokens": 1, "temperature": 0, "stream": False}))' "$selected")"
        remaining=$((hot_deadline - SECONDS))
        (( remaining > 0 )) || return 1
        response="$(curl --connect-timeout 2 --max-time "$remaining" --silent --show-error --fail -H 'Content-Type: application/json' --data-binary "$response" "$base_url/v1/chat/completions")" || return 1
        python3 -c 'import json,sys; assert json.loads(sys.argv[1]).get("choices")' "$response" || return 1
        if command -v nvidia-smi >/dev/null 2>&1; then
          nvidia-smi --query-gpu=timestamp,memory.used,memory.free --format=csv,noheader,nounits >>"$telemetry"
        fi
        printf 'PASS model=%s loaded_count=%s\n' "$selected" "$loaded_count" >>"$log"
        return 0
      fi
      sleep 1
    done
    return 1
  }

  if load_and_infer "${model_ids[0]}" \
    && load_and_infer "${model_ids[1]}" \
    && load_and_infer "${model_ids[0]}" \
    && verify_router; then
    if [[ -s "$telemetry" ]]; then
      first_used="$(sed -n '1p' "$telemetry" | cut -d ',' -f 2 | tr -d ' ')"
      final_used="$(sed -n '3p' "$telemetry" | cut -d ',' -f 2 | tr -d ' ')"
      if [[ ! "$first_used" =~ ^[0-9]+$ || ! "$final_used" =~ ^[0-9]+$ ]] \
        || (( first_used - final_used > 256 || final_used - first_used > 256 )); then
        write_status_json "$result" hot-swap FAIL "Final model-A VRAM did not return within 256 MiB of its initial load" "$telemetry"
        status_line FAIL "Hot-swap VRAM reacquisition criterion failed"
        exit 1
      fi
    else
      write_status_json "$result" hot-swap FAIL "GPU transition telemetry was unavailable" "$log"
      status_line FAIL "Hot-swap telemetry is required"
      exit 1
    fi
    write_status_json "$result" hot-swap PASS "A-to-B-to-A passed with one router PID and Pi discovery" "$log"
    status_line PASS "Router hot swap and Pi discovery passed"
  else
    write_status_json "$result" hot-swap FAIL "Router hot swap, inference, one-model limit, or PID stability failed" "$log"
    status_line FAIL "Hot-swap test failed; inspect $log"
    exit 1
  fi
  exit 0
fi

confirm_exact "RUN_PI_SMOKE" \
  "Pi executes local extension code with your user permissions. This test exposes only its read tool and uses a disposable workspace."

id="$(run_id)"
workspace="$PROJECT_DIR/.tmp/pi-smoke-$id"
log="$LOGS_DIR/pi-smoke-$id.jsonl"
result="$RESULTS_DIR/pi-smoke-$id.json"
mkdir -p "$workspace"
marker="PI_LLAMA_SMOKE_7f94c2"
printf '%s\n' "$marker" >"$workspace/SMOKE.txt"
before="$(sha256sum "$workspace/SMOKE.txt")"
cleanup_workspace() {
  rm -rf -- "$workspace"
}
trap cleanup_workspace EXIT INT TERM

set +e
(
  cd "$workspace"
  PI_SKIP_VERSION_CHECK=1 \
  PI_TELEMETRY=0 \
  PI_CODING_AGENT_DIR="$STATE_DIR/pi" \
  LLAMA_SERVER_URL="$base_url" \
  timeout --signal=INT --kill-after=20s 300s \
    "$pi_bin" \
      --mode json \
      --no-session \
      --no-context-files \
      --tools read \
      --provider "llama-server=$base_url" \
      --model "$model_id" \
      'Use the read tool exactly once on SMOKE.txt. Reply with only its exact contents.'
) >"$log" 2>&1
exit_code=$?
set -e

after="$(sha256sum "$workspace/SMOKE.txt")"
status="FAIL"
message="Pi smoke test failed"
set +e
python3 - "$log" "$marker" <<'PY'
import json, pathlib, sys

path, marker = sys.argv[1:]
events = []
for line in pathlib.Path(path).read_text(errors="replace").splitlines():
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(value, dict):
        events.append(value)

def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)

objects = [item for event in events for item in walk(event)]
read_call = any(
    (obj.get("toolName") == "read" or obj.get("tool_name") == "read" or obj.get("name") == "read")
    and "SMOKE.txt" in json.dumps(obj)
    for obj in objects
)

assistant_texts = []
for obj in objects:
    if obj.get("role") != "assistant":
        continue
    content = obj.get("content")
    if isinstance(content, str):
        assistant_texts.append(content.strip())
    elif isinstance(content, list):
        text = "".join(
            part.get("text", "") for part in content
            if isinstance(part, dict) and part.get("type") == "text"
        ).strip()
        if text:
            assistant_texts.append(text)

if not read_call or marker not in assistant_texts:
    raise SystemExit(1)
PY
parsed=$?
set -e

if (( exit_code == 0 && parsed == 0 )) && [[ "$before" == "$after" ]]; then
  status="PASS"
  message="Pi used the read-only tool and returned the marker without modifying the fixture"
fi

write_status_json "$result" pi-agent "$status" "$message" "$log"
python3 - "$result" "$server_profile" "$model_id" <<'PY'
import json, pathlib, sys
path, profile, model_id = sys.argv[1:]
data = json.loads(pathlib.Path(path).read_text())
data["profile"] = profile
data["model_id"] = model_id
pathlib.Path(path).write_text(json.dumps(data, indent=2) + "\n")
PY
cleanup_workspace
trap - EXIT INT TERM
status_line "$status" "$message"
printf 'Evidence: %s\nResult: %s\n' "$log" "$result"
[[ "$status" != "FAIL" ]]
