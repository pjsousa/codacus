#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_DIR/config.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

ARTIFACT_DIR="${ARTIFACT_DIR:-$PROJECT_DIR/models}"
RESULTS_DIR="${RESULTS_DIR:-$PROJECT_DIR/results}"
SOURCE_DIR="${SOURCE_DIR:-$HOME/llama-low-vram-repro/llama-cpp-turboquant}"
BUILD_DIR="${BUILD_DIR:-$SOURCE_DIR/build}"

LLAMA_REPO="${LLAMA_REPO:-https://github.com/TheTom/llama-cpp-turboquant.git}"
LLAMA_REV="${LLAMA_REV:-c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea}"
QWEN_REPO="${QWEN_REPO:-unsloth/Qwen3.6-35B-A3B-GGUF}"
QWEN_REV="${QWEN_REV:-a483e9e6cbd595906af30beda3187c2663a1118c}"
QWEN_FILE="${QWEN_FILE:-Qwen3.6-35B-A3B-UD-Q4_K_S.gguf}"
QWEN_SHA256="${QWEN_SHA256:-a8138f183e3993f12cdc23afd2babb8cdb084e64088ce4a256d49101d47b949c}"
QWEN_SIZE_BYTES="${QWEN_SIZE_BYTES:-20893015008}"
QWEN_MODEL_PATH="${QWEN_MODEL_PATH:-$HOME/llama-low-vram-repro/models/$QWEN_FILE}"

BINARY_REPO="${BINARY_REPO:-prism-ml/Bonsai-27B-gguf}"
BINARY_REV="${BINARY_REV:-f10afb355f104535e3e3e98cf7ab7795c72bd292}"
BINARY_FILE="${BINARY_FILE:-Bonsai-27B-Q1_0.gguf}"
BINARY_SHA256="${BINARY_SHA256:-17ef842e47450caeb8eaa3ebfbbab5d2f2278b62b79be107985fb69a2f819aa0}"
BINARY_SIZE_BYTES="${BINARY_SIZE_BYTES:-3803452480}"
BINARY_MODEL_PATH="${BINARY_MODEL_PATH:-$ARTIFACT_DIR/$BINARY_FILE}"

TERNARY_REPO="${TERNARY_REPO:-prism-ml/Ternary-Bonsai-27B-gguf}"
TERNARY_REV="${TERNARY_REV:-abbae723028d71be674e71e1a71201a6f43fab22}"
TERNARY_FILE="${TERNARY_FILE:-Ternary-Bonsai-27B-Q2_0.gguf}"
TERNARY_SHA256="${TERNARY_SHA256:-868c11714cf8fe47f5ec9eeb2be0ab1a337112886f92ee0ede6b855c4fa31757}"
TERNARY_SIZE_BYTES="${TERNARY_SIZE_BYTES:-7165121600}"
TERNARY_MODEL_PATH="${TERNARY_MODEL_PATH:-$ARTIFACT_DIR/$TERNARY_FILE}"

GEMMA_MODEL_PATH="${GEMMA_MODEL_PATH:-}"
GEMMA_SHA256="${GEMMA_SHA256:-}"
MODEL_SET="${MODEL_SET:-qwen binary ternary}"
THREADS="${THREADS:-4}"
THREADS_BATCH="${THREADS_BATCH:-8}"
CONTEXT_SIZE="${CONTEXT_SIZE:-8192}"
N_PREDICT="${N_PREDICT:-512}"
SEED="${SEED:-42}"
TEMPERATURE="${TEMPERATURE:-0.7}"
TOP_P="${TOP_P:-0.95}"
TOP_K="${TOP_K:-20}"
REASONING="${REASONING:-off}"
KV_CACHE_K="${KV_CACHE_K:-q8_0}"
KV_CACHE_V="${KV_CACHE_V:-q8_0}"
QWEN_N_CPU_MOE="${QWEN_N_CPU_MOE:-35}"
GPU_MARGIN_MIB="${GPU_MARGIN_MIB:-768}"

LLAMA_CLI="${LLAMA_CLI:-$BUILD_DIR/bin/llama-cli}"
LLAMA_SERVER="${LLAMA_SERVER:-$BUILD_DIR/bin/llama-server}"
LLAMA_BENCH="${LLAMA_BENCH:-$BUILD_DIR/bin/llama-bench}"
LLAMA_COMPLETION="${LLAMA_COMPLETION:-$BUILD_DIR/bin/llama-completion}"
VERIFICATION_DIR="${VERIFICATION_DIR:-$ARTIFACT_DIR/.verified}"
TELEMETRY_PID=""

timestamp() {
  date -u +%Y%m%dT%H%M%S.%NZ
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    printf 'Required file not found: %s\n' "$1" >&2
    exit 1
  fi
}

require_executable() {
  if [[ ! -x "$1" ]]; then
    printf 'Required executable not found: %s\n' "$1" >&2
    exit 1
  fi
}

prepare_results() {
  mkdir -p "$RESULTS_DIR"
}

new_result_dir() {
  local prefix="$1"
  prepare_results
  NEW_RESULT_DIR="$RESULTS_DIR/${prefix}_$(timestamp)_$$"
  if ! mkdir "$NEW_RESULT_DIR"; then
    printf 'Refusing to reuse result directory: %s\n' "$NEW_RESULT_DIR" >&2
    exit 1
  fi
}

capture_snapshot() {
  local output="$1"
  {
    printf 'timestamp=%s\n' "$(date -u +%FT%TZ)"
    printf 'memlock_soft_kib=%s\n' "$(ulimit -Sl)"
    printf 'memlock_hard_kib=%s\n' "$(ulimit -Hl)"
    free -b
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu,pstate --format=csv,noheader
    fi
  } >"$output"
}

start_telemetry() {
  local output="$1"
  TELEMETRY_PID=""
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu,temperature.gpu,pstate \
      --format=csv,noheader -lms 500 >"$output" &
    TELEMETRY_PID=$!
  else
    printf 'nvidia-smi unavailable\n' >"$output"
  fi
}

stop_telemetry() {
  if [[ -n "$TELEMETRY_PID" ]]; then
    kill "$TELEMETRY_PID" 2>/dev/null || true
    wait "$TELEMETRY_PID" 2>/dev/null || true
    TELEMETRY_PID=""
  fi
}

log_command() {
  local log_file="$1"
  shift
  printf 'Command:' | tee "$log_file"
  printf ' %q' "$@" | tee -a "$log_file"
  printf '\n' | tee -a "$log_file"
}

run_with_log() {
  local log_file="$1"
  local status
  shift
  log_command "$log_file" "$@"
  if [[ -x /usr/bin/time ]]; then
    /usr/bin/time -v "$@" 2>&1 | tee -a "$log_file"
    status=${PIPESTATUS[0]}
  else
    "$@" 2>&1 | tee -a "$log_file"
    status=${PIPESTATUS[0]}
  fi
  printf 'Recorded exit status: %s\n' "$status" | tee -a "$log_file"
  return "$status"
}

run_capture_stdout() {
  local log_file="$1"
  local output_file="$2"
  local status
  shift 2
  log_command "$log_file" "$@"
  if [[ -x /usr/bin/time ]]; then
    /usr/bin/time -v "$@" 2> >(tee -a "$log_file" >&2) | tee "$output_file"
    status=${PIPESTATUS[0]}
  else
    "$@" 2> >(tee -a "$log_file" >&2) | tee "$output_file"
    status=${PIPESTATUS[0]}
  fi
  printf 'Recorded exit status: %s\n' "$status" | tee -a "$log_file"
  return "$status"
}

model_path() {
  case "$1" in
    qwen) printf '%s\n' "$QWEN_MODEL_PATH" ;;
    binary) printf '%s\n' "$BINARY_MODEL_PATH" ;;
    ternary) printf '%s\n' "$TERNARY_MODEL_PATH" ;;
    gemma) printf '%s\n' "$GEMMA_MODEL_PATH" ;;
    *) printf 'Unknown model key: %s\n' "$1" >&2; return 1 ;;
  esac
}

model_label() {
  case "$1" in
    qwen) printf 'Qwen3.6-35B-A3B Q4_K_S\n' ;;
    binary) printf 'Bonsai 27B Q1_0\n' ;;
    ternary) printf 'Ternary Bonsai 27B Q2_0\n' ;;
    gemma) printf 'User-supplied Gemma control\n' ;;
    *) return 1 ;;
  esac
}

model_sha256() {
  case "$1" in
    qwen) printf '%s\n' "$QWEN_SHA256" ;;
    binary) printf '%s\n' "$BINARY_SHA256" ;;
    ternary) printf '%s\n' "$TERNARY_SHA256" ;;
    gemma) printf '%s\n' "$GEMMA_SHA256" ;;
    *) return 1 ;;
  esac
}

model_size_bytes() {
  case "$1" in
    qwen) printf '%s\n' "$QWEN_SIZE_BYTES" ;;
    binary) printf '%s\n' "$BINARY_SIZE_BYTES" ;;
    ternary) printf '%s\n' "$TERNARY_SIZE_BYTES" ;;
    gemma) printf '\n' ;;
    *) return 1 ;;
  esac
}

verification_stamp() {
  printf '%s/%s.stamp\n' "$VERIFICATION_DIR" "$1"
}

artifact_signature() {
  local key="$1"
  local path
  path="$(model_path "$key")"
  printf '%s|%s|%s|%s\n' "$(model_sha256 "$key")" "$(stat -c %s "$path")" "$(stat -c %Y "$path")" "$path"
}

runtime_supports_model() {
  case "$1" in
    ternary)
      grep -Rqs 'GGML_TYPE_Q2_0' "$SOURCE_DIR/include" "$SOURCE_DIR/ggml" "$SOURCE_DIR/src" 2>/dev/null
      ;;
    binary)
      grep -Rqs 'GGML_TYPE_Q1_0' "$SOURCE_DIR/ggml/src/ggml-cuda" 2>/dev/null
      ;;
    qwen|gemma) return 0 ;;
    *) return 1 ;;
  esac
}

model_is_runnable() {
  local key="$1"
  local path
  path="$(model_path "$key")"
  if [[ -z "$path" ]]; then
    printf 'SKIP %s: no model path configured.\n' "$key" >&2
    return 1
  fi
  if [[ ! -f "$path" ]]; then
    printf 'SKIP %s: model is absent: %s\n' "$key" "$path" >&2
    return 1
  fi
  if [[ -z "$(model_sha256 "$key")" ]]; then
    printf 'SKIP %s: no checksum is configured.\n' "$key" >&2
    return 1
  fi
  local stamp
  stamp="$(verification_stamp "$key")"
  if [[ ! -f "$stamp" ]] || [[ "$(<"$stamp")" != "$(artifact_signature "$key")" ]]; then
    printf 'SKIP %s: artifact is not verified for its current size/mtime; run scripts/02_verify_models.sh.\n' "$key" >&2
    return 1
  fi
  if ! runtime_supports_model "$key"; then
    printf 'BLOCKED %s: pinned runtime lacks the required weight type/kernels.\n' "$key" >&2
    return 1
  fi
}

build_model_args() {
  local key="$1"
  local path
  path="$(model_path "$key")"
  MODEL_ARGS=(-m "$path" --no-mmproj)
  case "$key" in
    qwen)
      MODEL_ARGS+=(--fit off -ngl all --n-cpu-moe "$QWEN_N_CPU_MOE")
      ;;
    binary)
      MODEL_ARGS+=(--fit off -ngl all)
      ;;
    ternary|gemma)
      MODEL_ARGS+=(--fit on -ngl auto --fit-target "$GPU_MARGIN_MIB")
      ;;
  esac
}

build_generation_args() {
  GENERATION_ARGS=(
    -t "$THREADS"
    -tb "$THREADS_BATCH"
    --flash-attn auto
    --cache-type-k "$KV_CACHE_K"
    --cache-type-v "$KV_CACHE_V"
    --seed "$SEED"
    --temp "$TEMPERATURE"
    --top-p "$TOP_P"
    --top-k "$TOP_K"
    --reasoning "$REASONING"
    --single-turn
    --simple-io
    --no-display-prompt
    --no-context-shift
  )
}

require_cli() {
  require_executable "$LLAMA_CLI"
  prepare_results
  build_generation_args
}

require_bench() {
  require_executable "$LLAMA_BENCH"
  prepare_results
}

read_model_keys() {
  read -r -a MODEL_KEYS <<<"$MODEL_SET"
}

log_has_runtime_error() {
  grep -Eqi 'out of memory|CUDA error|GGML_ASSERT|segmentation fault|terminated by signal' "$1"
}

peak_gpu_mib() {
  awk -F',' '{ value=$2; gsub(/[^0-9.]/, "", value); if (value + 0 > peak) peak=value + 0 } END { print peak + 0 }' "$1"
}
