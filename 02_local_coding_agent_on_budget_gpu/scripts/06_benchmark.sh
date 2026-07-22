#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

stage="${1:-smoke}"
profile="${2:-$MODEL_PROFILE}"
case "$stage" in
  smoke|threads|ubatch|kv) ;;
  *) printf 'Usage: %s {smoke|threads|ubatch|kv} [PROFILE]\n' "$0" >&2; exit 2 ;;
esac

load_profiles
load_model_profile "$profile"
N_CPU_MOE="${N_CPU_MOE_OVERRIDE:-$N_CPU_MOE}"
CACHE_TYPE_K="${CACHE_TYPE_K_OVERRIDE:-$CACHE_TYPE_K}"
CACHE_TYPE_V="${CACHE_TYPE_V_OVERRIDE:-$CACHE_TYPE_V}"
UBATCH_SIZE="${UBATCH_SIZE_OVERRIDE:-$UBATCH_SIZE}"
write_not_run() {
  local message="$1" output
  output="$RESULTS_DIR/benchmark-${stage}-${profile}-$(run_id).json"
  write_status_json "$output" "benchmark-$stage" "NOT RUN" "$message" ""
  python3 - "$output" "$profile" <<'PY'
import json, pathlib, sys
path, profile = sys.argv[1:]
data = json.loads(pathlib.Path(path).read_text())
data["profile"] = profile
pathlib.Path(path).write_text(json.dumps(data, indent=2) + "\n")
PY
  status_line "NOT RUN" "$message"
}
bench="$(find_llama_binary llama-bench)" || {
  write_not_run "llama-bench is unavailable"
  exit 0
}
if [[ ! -f "$MODEL_PATH" ]]; then
  write_not_run "Model is absent: $MODEL_PATH"
  exit 0
fi

managed_pid_file="$STATE_DIR/llama-server.pid"
if [[ -f "$managed_pid_file" ]]; then
  read -r managed_pid <"$managed_pid_file" || true
  if [[ "${managed_pid:-}" =~ ^[0-9]+$ ]] && kill -0 "$managed_pid" 2>/dev/null; then
    status_line FAIL "Stop the managed llama-server before running llama-bench to avoid double-loading the model"
    exit 1
  fi
fi

require_command flock
exec 8>"$STATE_DIR/benchmark.lock"
flock -n 8 || { status_line FAIL "Another project benchmark is active"; exit 1; }

confirm_exact "BENCHMARK_${stage}_$profile" \
  "This bounded benchmark may heavily use CPU, RAM, and GPU for up to 14 minutes."

id="$(run_id)"
run_dir="$LOGS_DIR/benchmark_${stage}_${profile}_${id}"
raw="$run_dir/raw.jsonl"
stderr_log="$run_dir/stderr.log"
telemetry="$run_dir/gpu.csv"
resources_before="$run_dir/resources-before.txt"
resources_after="$run_dir/resources-after.txt"
result="$RESULTS_DIR/benchmark-${stage}-${profile}-${id}.json"
command_log="$run_dir/command.txt"
mkdir -p "$run_dir"
capture_resources "$resources_before"
model_sha256="$(sha256sum "$MODEL_PATH" | cut -d ' ' -f 1)"
model_bytes="$(stat -c %s "$MODEL_PATH")"
bench_sha256="$(sha256sum "$bench" | cut -d ' ' -f 1)"

bench_ngl="$N_GPU_LAYERS"
if [[ "$bench_ngl" == "all" ]]; then
  bench_ngl="99"
fi

base=(
  "$bench"
  -m "$MODEL_PATH"
  -ngl "$bench_ngl"
  -ncmoe "$N_CPU_MOE"
  -mmp 1
  -fa "$FLASH_ATTN"
  -ctk "$CACHE_TYPE_K"
  -ctv "$CACHE_TYPE_V"
  -b "$BATCH_SIZE"
  -o jsonl
)

case "$stage" in
  smoke)
    args=(-t "$THREADS" -ub "$UBATCH_SIZE" -p 512 -n 64 -r 2)
    ;;
  threads)
    args=(-t 1,2,3,4 -ub "$UBATCH_SIZE" -p 512 -n 64 -r 3)
    ;;
  ubatch)
    args=(-t "$THREADS" -ub 128,256,512,1024,2048 -p 2048 -n 64 -r 3)
    ;;
  kv)
    args=(-t "$THREADS" -ub "$UBATCH_SIZE" -p 1024 -n 64 -r 3)
    ;;
esac
log_command "$command_log" "${base[@]}" "${args[@]}"

telemetry_pid=""
telemetry_exe=""
telemetry_start=""
cleanup() {
  if [[ -n "$telemetry_pid" ]]; then
    python3 - "$telemetry_pid" "$telemetry_exe" "$telemetry_start" <<'PY' 2>/dev/null || true
import os, pathlib, signal, sys
pid, expected_exe, expected_start = int(sys.argv[1]), sys.argv[2], sys.argv[3]
pidfd = os.pidfd_open(pid)
try:
    actual_exe = str(pathlib.Path(f"/proc/{pid}/exe").resolve())
    value = pathlib.Path(f"/proc/{pid}/stat").read_text()
    actual_start = value[value.rfind(") ") + 2:].split()[19]
    if actual_exe == expected_exe and actual_start == expected_start:
        signal.pidfd_send_signal(pidfd, signal.SIGTERM)
finally:
    os.close(pidfd)
PY
    wait "$telemetry_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=timestamp,memory.used,memory.free,utilization.gpu,temperature.gpu,pstate \
    --format=csv,noheader,nounits -lms 500 >"$telemetry" &
  telemetry_pid=$!
  for _ in $(seq 1 20); do
    telemetry_exe="$(readlink -f "/proc/$telemetry_pid/exe" 2>/dev/null || true)"
    telemetry_start="$(python3 - "$telemetry_pid" <<'PY'
import pathlib, sys
try:
    value = pathlib.Path(f"/proc/{sys.argv[1]}/stat").read_text()
    print(value[value.rfind(") ") + 2:].split()[19])
except (OSError, IndexError):
    pass
PY
)"
    [[ -n "$telemetry_exe" && -n "$telemetry_start" ]] && break
    sleep 0.01
  done
  if [[ -z "$telemetry_exe" || -z "$telemetry_start" ]]; then
    kill "$telemetry_pid" 2>/dev/null || true
    wait "$telemetry_pid" 2>/dev/null || true
    telemetry_pid=""
  fi
fi

set +e
timeout --signal=INT --kill-after=20s 840s "${base[@]}" "${args[@]}" > >(tee "$raw") 2> >(tee "$stderr_log" >&2)
exit_code=$?
set -e
cleanup
telemetry_pid=""
capture_resources "$resources_after"

python3 - "$result" "$stage" "$profile" "$exit_code" "$raw" "$stderr_log" "$telemetry" "$resources_before" "$resources_after" "$command_log" "$N_CPU_MOE" "$CACHE_TYPE_K" "$CACHE_TYPE_V" "$UBATCH_SIZE" "$MODEL_PATH" "$model_sha256" "$model_bytes" "$bench" "$bench_sha256" "$bench_ngl" "$THREADS" "$BATCH_SIZE" "$FLASH_ATTN" <<'PY'
import json
import math
import pathlib
import statistics
import sys
from datetime import datetime, timezone

output, stage, profile, exit_code, raw_path, stderr_path, telemetry_path, resources_before, resources_after, command_log, n_cpu_moe, cache_type_k, cache_type_v, ubatch_size, model_path, model_sha256, model_bytes, bench_path, bench_sha256, n_gpu_layers, threads, batch_size, flash_attn = sys.argv[1:]
rows = []
for line in pathlib.Path(raw_path).read_text(errors="replace").splitlines():
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(value, dict):
        rows.append(value)

pp_metrics = []
tg_metrics = []
pp_rows = []
tg_rows = []
for row in rows:
    value = row.get("avg_ts")
    if isinstance(value, (int, float)) and math.isfinite(value) and value > 0:
        if row.get("n_prompt", 0) > 0 and row.get("n_gen", 0) == 0:
            pp_metrics.append(float(value))
            pp_rows.append((float(value), row))
        elif row.get("n_gen", 0) > 0 and row.get("n_prompt", 0) == 0:
            tg_metrics.append(float(value))
            tg_rows.append((float(value), row))

expected_values = {
    "smoke": {"field": None, "values": {None}},
    "threads": {"field": "n_threads", "values": {1, 2, 3, 4}},
    "ubatch": {"field": "n_ubatch", "values": {128, 256, 512, 1024, 2048}},
    "kv": {"field": None, "values": {None}},
}[stage]
observed_pp = set()
observed_tg = set()
for _, row in pp_rows:
    key = row.get(expected_values["field"]) if expected_values["field"] else None
    observed_pp.add(key)
for _, row in tg_rows:
    key = row.get(expected_values["field"]) if expected_values["field"] else None
    observed_tg.add(key)
matrix_complete = expected_values["values"].issubset(observed_pp) and expected_values["values"].issubset(observed_tg)

minimum_vram_free = None
telemetry_file = pathlib.Path(telemetry_path)
if telemetry_file.exists():
    for line in telemetry_file.read_text(errors="replace").splitlines():
        columns = [value.strip() for value in line.split(",")]
        if len(columns) >= 3:
            try:
                free = float(columns[2])
            except ValueError:
                continue
            minimum_vram_free = free if minimum_vram_free is None else min(minimum_vram_free, free)

def swap_used(path):
    for line in pathlib.Path(path).read_text(errors="replace").splitlines():
        if line.startswith("Swap:"):
            fields = line.split()
            return int(fields[2])
    return None

swap_before = swap_used(resources_before)
swap_after = swap_used(resources_after)
swap_grew = swap_before is not None and swap_after is not None and swap_after > swap_before + 64 * 1024 * 1024
thread_gain = None
ubatch_pp_gain = None
ubatch_tg_ratio = None
if stage == "threads" and tg_rows:
    rates = [item[0] for item in tg_rows]
    thread_gain = max(rates) / min(rates) - 1 if min(rates) else None
if stage == "ubatch":
    pp_by_ubatch = {int(row.get("n_ubatch")): rate for rate, row in pp_rows if row.get("n_ubatch") is not None}
    tg_by_ubatch = {int(row.get("n_ubatch")): rate for rate, row in tg_rows if row.get("n_ubatch") is not None}
    if 128 in pp_by_ubatch and pp_by_ubatch:
        best_ubatch = max(pp_by_ubatch, key=pp_by_ubatch.get)
        ubatch_pp_gain = pp_by_ubatch[best_ubatch] / pp_by_ubatch[128] - 1
        if 128 in tg_by_ubatch and best_ubatch in tg_by_ubatch and tg_by_ubatch[128]:
            ubatch_tg_ratio = tg_by_ubatch[best_ubatch] / tg_by_ubatch[128]

stderr = pathlib.Path(stderr_path).read_text(errors="replace")
fatal_terms = ("out of memory", "cuda error", "segmentation fault", "fatal")
fatal = any(term in stderr.lower() for term in fatal_terms)
if int(exit_code) == 124:
    status, message = "FAIL", "Benchmark exceeded the 14-minute safety limit"
elif int(exit_code) != 0 or fatal:
    status, message = "FAIL", "Benchmark command failed or reported a fatal runtime error"
elif not rows or not pp_metrics or not tg_metrics or not matrix_complete:
    status, message = "FAIL", "Required prompt/decode rows for the complete parameter matrix were missing"
elif minimum_vram_free is not None and minimum_vram_free < 256:
    status, message = "FAIL", "Benchmark completed with less than 256 MiB recorded VRAM headroom"
elif swap_grew:
    status, message = "FAIL", "Benchmark increased swap by more than 64 MiB"
elif stage == "threads" and (thread_gain is None or thread_gain <= 0.05):
    status, message = "WARN", "Thread sweep completed but did not prove a decode difference above 5%"
elif stage == "ubatch" and (ubatch_pp_gain is None or ubatch_pp_gain <= 0.05):
    status, message = "WARN", "Ubatch sweep completed but did not prove a prefill gain above 5%"
elif stage == "ubatch" and (ubatch_tg_ratio is None or ubatch_tg_ratio < 0.95):
    status, message = "WARN", "Best-prefill ubatch regressed decode by more than 5%"
elif minimum_vram_free is None:
    status, message = "WARN", "Required metrics passed, but VRAM telemetry was unavailable"
elif minimum_vram_free is not None and minimum_vram_free < 768:
    status, message = "WARN", "Required metrics passed with less than 768 MiB recorded VRAM headroom"
elif stage == "kv":
    status, message = "WARN", "One KV profile was measured safely; comparison plus retrieval quality is still required"
else:
    status = "PASS"
    message = f"Complete prompt/decode matrix parsed from {len(rows)} rows"

data = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "stage": f"benchmark-{stage}",
    "profile": profile,
    "configuration": {
        "n_cpu_moe": int(n_cpu_moe),
        "cache_type_k": cache_type_k,
        "cache_type_v": cache_type_v,
        "ubatch_size": int(ubatch_size),
        "model_path": model_path,
        "model_sha256": model_sha256,
        "model_bytes": int(model_bytes),
        "llama_bench_path": bench_path,
        "llama_bench_sha256": bench_sha256,
        "n_gpu_layers": int(n_gpu_layers),
        "threads": int(threads),
        "batch_size": int(batch_size),
        "flash_attention": flash_attn,
        "mmap": True,
    },
    "status": status,
    "message": message,
    "exit_code": int(exit_code),
    "row_count": len(rows),
    "matrix_complete": matrix_complete,
    "prompt_processing": {
        "count": len(pp_metrics),
        "median_tokens_per_second": statistics.median(pp_metrics) if pp_metrics else None,
    },
    "token_generation": {
        "count": len(tg_metrics),
        "median_tokens_per_second": statistics.median(tg_metrics) if tg_metrics else None,
    },
    "best_prompt_processing": max(pp_rows, key=lambda item: item[0])[1] if pp_rows else None,
    "best_token_generation": max(tg_rows, key=lambda item: item[0])[1] if tg_rows else None,
    "minimum_vram_free_mib": minimum_vram_free,
    "swap_before_bytes": swap_before,
    "swap_after_bytes": swap_after,
    "thread_decode_gain": thread_gain,
    "ubatch_prefill_gain": ubatch_pp_gain,
    "ubatch_decode_ratio": ubatch_tg_ratio,
    "raw": raw_path,
    "stderr": stderr_path,
    "telemetry": telemetry_path,
    "resources_before": resources_before,
    "resources_after": resources_after,
    "command": command_log,
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY

status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$result")"
status_line "$status" "$stage benchmark for $profile"
printf 'Raw evidence: %s\nResult: %s\n' "$run_dir" "$result"
[[ "$status" != "FAIL" ]]
