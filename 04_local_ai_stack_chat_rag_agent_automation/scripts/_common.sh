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

LLAMA_REV="${LLAMA_REV:-c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea}"
LLAMA_CLI="${LLAMA_CLI:-$BUILD_DIR/bin/llama-cli}"
LLAMA_SERVER="${LLAMA_SERVER:-$BUILD_DIR/bin/llama-server}"
LLAMA_BENCH="${LLAMA_BENCH:-$BUILD_DIR/bin/llama-bench}"
LLAMA_COMPLETION="${LLAMA_COMPLETION:-$BUILD_DIR/bin/llama-completion}"

MODEL_FILE="${MODEL_FILE:-}"
MODEL_PATH="${MODEL_PATH:-${MODEL_DIR:+/dev/null}}"

LLAMA_HOST="${LLAMA_HOST:-127.0.0.1}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
LLAMA_BASE_URL="${LLAMA_BASE_URL:-http://$LLAMA_HOST:$LLAMA_PORT}"

THREADS="${THREADS:-4}"
THREADS_BATCH="${THREADS_BATCH:-8}"
BASE_CONTEXT="${BASE_CONTEXT:-4096}"

N8N_PORT="${N8N_PORT:-5678}"
ANYTHING_LLM_PORT="${ANYTHING_LLM_PORT:-3001}"
ANYTHING_LLM_DATA_DIR="${ANYTHING_LLM_DATA_DIR:-$WORK_DIR/anythingllm-data}"
N8N_DATA_DIR="${N8N_DATA_DIR:-$WORK_DIR/n8n-data}"
DOCKER_COMPOSE_DIR="${DOCKER_COMPOSE_DIR:-$WORK_DIR/docker-stack}"

PI_INSTALL_DIR="${PI_INSTALL_DIR:-$WORK_DIR/pi}"

HF_BIN="${HF_BIN:-$WORK_DIR/tools-venv/bin/hf}"

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

wait_for_health() {
  local url="$1"
  local max_attempts="${2:-60}"
  local attempt=0
  while (( attempt < max_attempts )); do
    if curl --silent --fail --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  return 1
}

require_model() {
  if [[ -z "$MODEL_FILE" ]]; then
    printf 'MODEL_FILE is not set. Set it in config.env or pass MODEL_FILE=/path/to/model.gguf\n' >&2
    exit 1
  fi
  if [[ ! -f "$MODEL_PATH" ]]; then
    printf 'Model not found at %s\n' "$MODEL_PATH" >&2
    exit 1
  fi
}

require_docker() {
  require_command docker
  if ! docker info >/dev/null 2>&1; then
    printf 'Docker daemon is not running or current user lacks permission.\n' >&2
    exit 1
  fi
}
