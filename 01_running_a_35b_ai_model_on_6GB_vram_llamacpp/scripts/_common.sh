#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_DIR/config.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

WORK_DIR="${WORK_DIR:-$HOME/llama-low-vram-repro}"
SOURCE_DIR="${SOURCE_DIR:-$WORK_DIR/llama-cpp-turboquant}"
BUILD_DIR="${BUILD_DIR:-$SOURCE_DIR/build}"
MODEL_DIR="${MODEL_DIR:-$WORK_DIR/models}"
RESULTS_DIR="${RESULTS_DIR:-$WORK_DIR/results}"

LLAMA_REPO="${LLAMA_REPO:-https://github.com/TheTom/llama-cpp-turboquant.git}"
LLAMA_REV="${LLAMA_REV:-c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea}"
MODEL_REPO="${MODEL_REPO:-unsloth/Qwen3.6-35B-A3B-GGUF}"
MODEL_REV="${MODEL_REV:-a483e9e6cbd595906af30beda3187c2663a1118c}"
MODEL_FILE="${MODEL_FILE:-Qwen3.6-35B-A3B-UD-Q4_K_S.gguf}"
MODEL_SHA256="${MODEL_SHA256:-a8138f183e3993f12cdc23afd2babb8cdb084e64088ce4a256d49101d47b949c}"
MODEL_PATH="${MODEL_PATH:-$MODEL_DIR/$MODEL_FILE}"
DRAFT_REPO="${DRAFT_REPO:-unsloth/Qwen3.5-0.8B-GGUF}"
DRAFT_REV="${DRAFT_REV:-6ab461498e2023f6e3c1baea90a8f0fe38ab64d0}"
DRAFT_FILE="${DRAFT_FILE:-Qwen3.5-0.8B-Q4_K_M.gguf}"
DRAFT_SHA256="${DRAFT_SHA256:-bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517}"
DRAFT_PATH="${DRAFT_PATH:-$MODEL_DIR/$DRAFT_FILE}"

CUDA_ARCH="${CUDA_ARCH:-61-real}"
CUDA_ROOT="${CUDA_ROOT:-/usr/local/cuda-12.2}"
BUILD_JOBS="${BUILD_JOBS:-4}"
THREADS="${THREADS:-4}"
THREADS_BATCH="${THREADS_BATCH:-8}"
BASE_CONTEXT="${BASE_CONTEXT:-4096}"
N_PREDICT="${N_PREDICT:-128}"
BASELINE_NGL="${BASELINE_NGL:-20}"
CPU_MOE_ALL="${CPU_MOE_ALL:-41}"
CPU_MOE_TUNED="${CPU_MOE_TUNED:-35}"
CPU_MOE_LONG_CONTEXT="${CPU_MOE_LONG_CONTEXT:-36}"
PROMPT="${PROMPT:-Explain in five concise points why mixture-of-experts inference can use less compute than a dense model.}"

LLAMA_CLI="${LLAMA_CLI:-$BUILD_DIR/bin/llama-cli}"
LLAMA_BENCH="${LLAMA_BENCH:-$BUILD_DIR/bin/llama-bench}"
LLAMA_SERVER="${LLAMA_SERVER:-$BUILD_DIR/bin/llama-server}"
LLAMA_COMPLETION="${LLAMA_COMPLETION:-$BUILD_DIR/bin/llama-completion}"

timestamp() {
  date -u +%Y%m%dT%H%M%SZ
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

prepare_results() {
  mkdir -p "$RESULTS_DIR"
}

capture_snapshot() {
  local output="$1"
  {
    printf 'timestamp=%s\n' "$(date -u +%FT%TZ)"
    free -b
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=name,driver_version,memory.total,memory.used,memory.free,utilization.gpu,pstate --format=csv,noheader
    fi
  } >"$output"
}

run_with_log() {
  local log_file="$1"
  shift
  printf 'Command:' | tee "$log_file"
  printf ' %q' "$@" | tee -a "$log_file"
  printf '\n' | tee -a "$log_file"
  if [[ -x /usr/bin/time ]]; then
    /usr/bin/time -v "$@" 2>&1 | tee -a "$log_file"
  else
    "$@" 2>&1 | tee -a "$log_file"
  fi
}

common_cli_args() {
  # shellcheck disable=SC2034  # Consumed by scripts that source this helper.
  COMMON_ARGS=(
    -m "$MODEL_PATH"
    --no-mmproj
    -t "$THREADS"
    -tb "$THREADS_BATCH"
    --flash-attn auto
    --seed 42
  )
}

require_runtime() {
  require_file "$LLAMA_CLI"
  require_file "$MODEL_PATH"
  prepare_results
  common_cli_args
}
