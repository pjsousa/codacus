#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

mode="${1:-}"
[[ "$mode" == "cache-reuse" || "$mode" == "context" ]] || {
  printf 'Usage: %s {cache-reuse|context}\n' "$0" >&2
  exit 2
}
require_command curl
require_command timeout

base_url="http://$SERVER_HOST:$SERVER_PORT"
id="$(run_id)"
result="$RESULTS_DIR/${mode}-$id.json"
if ! managed_server_identity; then
  write_status_json "$result" "$mode" "NOT RUN" "A verified managed llama.cpp server is required" ""
  status_line "NOT RUN" "Start the server with scripts/04_start_model_server.sh"
  exit 0
fi
if ! health="$(curl --connect-timeout 2 --max-time 10 --silent --show-error --fail "$base_url/health" 2>/dev/null)" \
  || ! python3 -c 'import json,sys; assert json.loads(sys.argv[1]).get("status") == "ok"' "$health"; then
  write_status_json "$result" "$mode" "NOT RUN" "Verified llama.cpp server is not ready at $base_url" ""
  status_line "NOT RUN" "Verified llama.cpp server is not ready at $base_url"
  exit 0
fi

run_dir="$LOGS_DIR/${mode}_$id"
mkdir -p "$run_dir"
resources_before="$run_dir/resources-before.txt"
resources_after="$run_dir/resources-after.txt"
capture_resources "$resources_before"
server_profile="unknown"
server_cache_k="unknown"
server_cache_v="unknown"
server_n_cpu_moe="-1"
server_ubatch="-1"
server_model_path=""
server_model_sha256=""
pid_file="$STATE_DIR/llama-server.pid"
meta_file="$STATE_DIR/llama-server.meta"
if [[ -f "$pid_file" ]]; then
  read -r managed_pid <"$pid_file" || true
  if [[ "${managed_pid:-}" =~ ^[0-9]+$ && -r "/proc/$managed_pid/cmdline" ]]; then
    server_profile="$(python3 - "$meta_file" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
if path.exists():
    for line in path.read_text().splitlines():
        if line.startswith("profile="):
            print(line.split("=", 1)[1])
            break
PY
)"
    read -r server_cache_k server_cache_v server_n_cpu_moe server_ubatch server_model_path < <(python3 - "$managed_pid" <<'PY'
import pathlib, sys
args = pathlib.Path(f"/proc/{sys.argv[1]}/cmdline").read_bytes().split(b"\0")
args = [value.decode(errors="replace") for value in args if value]
def value(flag, default):
    try:
        return args[args.index(flag) + 1]
    except (ValueError, IndexError):
        return default
print(value("--cache-type-k", "unknown"), value("--cache-type-v", "unknown"), value("--n-cpu-moe", "-1"), value("--ubatch-size", "-1"), value("--model", ""))
PY
)
    if [[ -f "$server_model_path" ]]; then
      server_model_sha256="$(sha256sum "$server_model_path" | cut -d ' ' -f 1)"
    fi
  fi
fi
server_profile="${server_profile:-unknown}"
[[ "$server_profile" == "$MANAGED_SERVER_PROFILE" ]] || {
  write_status_json "$result" "$mode" FAIL "Managed server profile metadata changed during validation" "$run_dir"
  status_line FAIL "Managed server profile identity changed"
  exit 1
}

if [[ "$mode" == "cache-reuse" ]]; then
  [[ -f "$pid_file" ]] || {
    write_status_json "$result" cache-reuse "NOT RUN" "Managed server PID evidence is required" ""
    status_line "NOT RUN" "Start the server with scripts/04_start_model_server.sh"
    exit 0
  }
  read -r pid <"$pid_file"
  [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || {
    status_line FAIL "Managed server PID is invalid"
    exit 1
  }
  cmdline="$(tr '\0' ' ' <"/proc/$pid/cmdline")"
  [[ "$cmdline" == *"--cache-reuse 256"* ]] || {
    write_status_json "$result" cache-reuse "NOT RUN" "Server was not started with --cache-reuse 256" "$run_dir"
    status_line "NOT RUN" "Restart a managed profile with cache-reuse 256"
    exit 0
  }
  confirm_exact "VALIDATE_CACHE_REUSE" \
    "This sends three controlled prompts and may heavily use the loaded model for up to 14 minutes."
  deadline=$((SECONDS + 840))

  python3 - "$run_dir" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
prefix = " ".join(f"prefix{i % 37}" for i in range(700))
middle_a = " ".join("ORIGINAL" for _ in range(300))
middle_c = " ".join("CHANGED" for _ in range(300))
suffix = " ".join(f"suffix{i % 41}" for i in range(700))
prompts = {
    "a": f"{prefix} {middle_a} {suffix}",
    "b": f"{prefix} {middle_a} {suffix} short delta",
    "c": f"{prefix} {middle_c} {suffix}",
}
for name, prompt in prompts.items():
    request = {"prompt": prompt, "n_predict": 1, "temperature": 0, "stream": False, "cache_prompt": True, "cache_key": "codacus-cache-reuse"}
    (root / f"{name}.request.json").write_text(json.dumps(request))
(root / "prefix.tokenize.json").write_text(json.dumps({"content": prefix, "add_special": True}))
(root / "c.tokenize.json").write_text(json.dumps({"content": prompts["c"], "add_special": True}))
PY

  curl --connect-timeout 2 --max-time 60 --silent --show-error --fail -H 'Content-Type: application/json' --data-binary "@$run_dir/prefix.tokenize.json" "$base_url/tokenize" >"$run_dir/prefix.tokens.json"
  curl --connect-timeout 2 --max-time 60 --silent --show-error --fail -H 'Content-Type: application/json' --data-binary "@$run_dir/c.tokenize.json" "$base_url/tokenize" >"$run_dir/c.tokens.json"
  for request in a b c; do
    remaining=$((deadline - SECONDS))
    (( remaining > 0 )) || { status_line FAIL "Cache-reuse test exceeded the shared 14-minute limit"; exit 1; }
    timeout --signal=INT --kill-after=20s "${remaining}s" curl --connect-timeout 2 --max-time "$remaining" --silent --show-error --fail \
      -H 'Content-Type: application/json' --data-binary "@$run_dir/$request.request.json" \
      "$base_url/completion" >"$run_dir/$request.response.json"
  done

  python3 - "$result" "$run_dir" "$server_profile" "$server_cache_k" "$server_cache_v" "$server_n_cpu_moe" "$server_ubatch" "$server_model_path" "$server_model_sha256" <<'PY'
import json, pathlib, sys
from datetime import datetime, timezone
output, run_dir, profile, cache_k, cache_v, n_cpu_moe, ubatch, model_path, model_sha256 = sys.argv[1:]
root = pathlib.Path(run_dir)
responses = {name: json.loads((root / f"{name}.response.json").read_text()) for name in "abc"}
prefix_tokens = len(json.loads((root / "prefix.tokens.json").read_text())["tokens"])
total_tokens = len(json.loads((root / "c.tokens.json").read_text())["tokens"])
c = responses["c"]
cached = int(c.get("tokens_cached", 0))
evaluated = int(c.get("tokens_evaluated", total_tokens))
passed = not c.get("truncated", False) and cached > prefix_tokens and evaluated < total_tokens - prefix_tokens
status = "PASS" if passed else "FAIL"
message = f"middle edit cached {cached}/{total_tokens} tokens and evaluated {evaluated}" if passed else "middle-edit chunk reuse was not proven"
data = {
    "timestamp": datetime.now(timezone.utc).isoformat(), "stage": "cache-reuse", "status": status,
    "message": message, "prefix_tokens": prefix_tokens, "total_tokens": total_tokens,
    "tokens_cached": cached, "tokens_evaluated": evaluated, "evidence": run_dir,
    "profile": profile, "configuration": {"cache_type_k": cache_k, "cache_type_v": cache_v, "n_cpu_moe": int(n_cpu_moe), "ubatch_size": int(ubatch), "model_path": model_path, "model_sha256": model_sha256},
}
pathlib.Path(output).write_text(json.dumps(data, indent=2) + "\n")
PY
else
  confirm_exact "VALIDATE_CONTEXT" \
    "This fills up to 50% of the configured context (capped at 16K tokens) and may run for up to 14 minutes."
  deadline=$((SECONDS + 840))
  props="$(curl --connect-timeout 2 --max-time 10 --silent --show-error --fail "$base_url/props")"
  n_ctx="$(python3 -c 'import json,sys; data=json.loads(sys.argv[1]); print(data.get("default_generation_settings", {}).get("n_ctx") or data.get("n_ctx") or 0)' "$props")"
  [[ "$n_ctx" =~ ^[0-9]+$ && "$n_ctx" -ge 4096 ]] || { status_line FAIL "Could not determine server context"; exit 1; }
  target=$((n_ctx / 2))
  (( target > 16384 )) && target=16384
  words="$target"

  for attempt in 1 2 3; do
    python3 - "$run_dir" "$words" <<'PY'
import json, pathlib, sys
root, count = pathlib.Path(sys.argv[1]), int(sys.argv[2])
quarter = max(1, count // 4)
segments = [" ".join(f"filler{i % 97}" for i in range(quarter)) for _ in range(4)]
prompt = (
    f"{segments[0]} Record alpha has value ALPHA_VALUE_2718. "
    f"{segments[1]} Record beta has value BETA_VALUE_3141. "
    f"{segments[2]} Record gamma has value GAMMA_VALUE_1618. {segments[3]}\n"
    "Return only the three values for records alpha, beta, and gamma in that order, separated by single spaces."
)
(root / "context.request.json").write_text(json.dumps({"prompt": prompt, "n_predict": 32, "temperature": 0, "stream": False, "cache_prompt": False}))
(root / "context.tokenize.json").write_text(json.dumps({"content": prompt, "add_special": True}))
PY
    remaining=$((deadline - SECONDS))
    (( remaining > 0 )) || { status_line FAIL "Context test exceeded the shared 14-minute limit"; exit 1; }
    curl --connect-timeout 2 --max-time "$((remaining < 60 ? remaining : 60))" --silent --show-error --fail -H 'Content-Type: application/json' --data-binary "@$run_dir/context.tokenize.json" "$base_url/tokenize" >"$run_dir/context.tokens.json"
    token_count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["tokens"]))' "$run_dir/context.tokens.json")"
    if (( token_count >= target * 9 / 10 && token_count <= target )); then
      break
    fi
    words=$((words * target / token_count))
  done

  remaining=$((deadline - SECONDS))
  (( remaining > 0 )) || { status_line FAIL "Context test exceeded the shared 14-minute limit"; exit 1; }
  timeout --signal=INT --kill-after=20s "${remaining}s" curl --connect-timeout 2 --max-time "$remaining" --silent --show-error --fail \
    -H 'Content-Type: application/json' --data-binary "@$run_dir/context.request.json" \
    "$base_url/completion" >"$run_dir/context.response.json"

  python3 - "$result" "$run_dir" "$n_ctx" "$token_count" "$server_profile" "$server_cache_k" "$server_cache_v" "$server_n_cpu_moe" "$server_ubatch" "$server_model_path" "$server_model_sha256" <<'PY'
import json, pathlib, sys
from datetime import datetime, timezone
output, run_dir, n_ctx, token_count, profile, cache_k, cache_v, n_cpu_moe, ubatch, model_path, model_sha256 = sys.argv[1:]
response = json.loads((pathlib.Path(run_dir) / "context.response.json").read_text())
content = response.get("content", "").strip()
expected = "ALPHA_VALUE_2718 BETA_VALUE_3141 GAMMA_VALUE_1618"
target = min(int(n_ctx) // 2, 16384)
prompt_tokens = int(token_count)
passed = target * 0.9 <= prompt_tokens <= target and not response.get("truncated", False) and content == expected
status = "PASS" if passed else "FAIL"
message = "all deterministic context keys were retrieved without truncation" if passed else "context retrieval or truncation criterion failed"
data = {
    "timestamp": datetime.now(timezone.utc).isoformat(), "stage": "context", "status": status,
    "message": message, "configured_context": int(n_ctx), "target_prompt_tokens": target, "prompt_tokens": prompt_tokens,
    "truncated": response.get("truncated"), "content": content, "evidence": run_dir,
    "profile": profile, "configuration": {"cache_type_k": cache_k, "cache_type_v": cache_v, "n_cpu_moe": int(n_cpu_moe), "ubatch_size": int(ubatch), "model_path": model_path, "model_sha256": model_sha256},
}
pathlib.Path(output).write_text(json.dumps(data, indent=2) + "\n")
PY
fi

capture_resources "$resources_after"
vram_free="$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | sed -n '1p' | tr -d ' ' || true)"
mem_available_kib="$(grep '^MemAvailable:' /proc/meminfo | tr -s ' ' | cut -d ' ' -f 2)"
swap_before_bytes="$(grep '^Swap:' "$resources_before" | tr -s ' ' | cut -d ' ' -f 3)"
swap_after_bytes="$(grep '^Swap:' "$resources_after" | tr -s ' ' | cut -d ' ' -f 3)"
if [[ ! "$vram_free" =~ ^[0-9]+$ ]] \
  || (( vram_free < 256 || mem_available_kib < 8 * 1024 * 1024 || swap_after_bytes > swap_before_bytes + 64 * 1024 * 1024 )); then
  python3 - "$result" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["status"] = "FAIL"
data["message"] = "Feature behavior completed but RAM/VRAM/swap safety evidence failed"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
fi

status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$result")"
message="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["message"])' "$result")"
status_line "$status" "$message"
printf 'Evidence: %s\nResult: %s\n' "$run_dir" "$result"
[[ "$status" != "FAIL" ]]
