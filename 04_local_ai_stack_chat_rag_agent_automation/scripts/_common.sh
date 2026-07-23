#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_DIR/config.env}"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# Existing project-01 build locations (consumed read-only by default).
WORK_DIR="${WORK_DIR:-$HOME/llama-low-vram-repro}"
SOURCE_DIR="${SOURCE_DIR:-$WORK_DIR/llama-cpp-turboquant}"
BUILD_DIR="${BUILD_DIR:-$SOURCE_DIR/build}"
MODEL_DIR="${MODEL_DIR:-$WORK_DIR/models}"

LLAMA_REV="${LLAMA_REV:-c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea}"
#MODEL_FILE="${MODEL_FILE:-Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf}"
MODEL_FILE="${MODEL_FILE:-Bonsai-27B-Q1_0.gguf}"
MODEL_SHA256="${MODEL_SHA256:-a8138f183e3993f12cdc23afd2babb8cdb084e64088ce4a256d49101d47b949c}"
MODEL_PATH="${MODEL_PATH:-$MODEL_DIR/$MODEL_FILE}"

STACK_DIR="${STACK_DIR:-$PROJECT_DIR/stack}"
RESULTS_DIR="${RESULTS_DIR:-$PROJECT_DIR/results}"

# Engine / router configuration.
ROUTER_HOST="${ROUTER_HOST:-127.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-8088}"
MODEL_ALIAS="${MODEL_ALIAS:-local-chat}"
MODELS_MAX="${MODELS_MAX:-1}"
SLEEP_IDLE_SECONDS="${SLEEP_IDLE_SECONDS:--1}"
ENGINE_NGL="${ENGINE_NGL:-all}"
ENGINE_CPU_MOE="${ENGINE_CPU_MOE:-30}"
ENGINE_CTX="${ENGINE_CTX:-131072}"
ENGINE_CACHE_K="${ENGINE_CACHE_K:-turbo4}"
ENGINE_CACHE_V="${ENGINE_CACHE_V:-turbo2}"
ENGINE_NO_MMAP="${ENGINE_NO_MMAP:-1}"
ENGINE_MLOCK="${ENGINE_MLOCK:-0}"
THREADS="${THREADS:-3}"
THREADS_BATCH="${THREADS_BATCH:-8}"
LLAMA_API_KEY="${LLAMA_API_KEY:-}"

# Alternative router (optional).
LLAMA_SWAP_VERSION="${LLAMA_SWAP_VERSION:-241}"
LLAMA_SWAP_SHA256="${LLAMA_SWAP_SHA256:-4321cc7772d823c988a8e24a0045a9de1893be935048939e8422cb5924ab75d8}"
LLAMA_SWAP_PORT="${LLAMA_SWAP_PORT:-8089}"
LLAMA_SWAP_DIR="$STACK_DIR/llama-swap"

# Chat UI + RAG.
ANYTHINGLLM_IMAGE="${ANYTHINGLLM_IMAGE:-mintplexlabs/anythingllm:1.15.0}"
ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-3001}"
SWIN_PDF_URL="${SWIN_PDF_URL:-https://arxiv.org/pdf/2103.14030}"
SWIN_PDF_FILE="${SWIN_PDF_FILE:-Swin-Transformer-arXiv-2103.14030.pdf}"
SWIN_PDF_SHA256="${SWIN_PDF_SHA256:-dfdc7631fe2a35bb5892080b9c0eeadc4432d55cf1856f84bc88802efa877a7c}"
RAG_DOCS_DIR="$STACK_DIR/rag-docs"

# Coding agent.
PI_PACKAGE="${PI_PACKAGE:-@earendil-works/pi-coding-agent}"
PI_VERSION="${PI_VERSION:-0.81.1}"
PI_LLAMA_CPP_PACKAGE="${PI_LLAMA_CPP_PACKAGE:-pi-llama-cpp}"
PI_LLAMA_CPP_VERSION="${PI_LLAMA_CPP_VERSION:-0.9.1}"

# Automation.
N8N_IMAGE="${N8N_IMAGE:-docker.n8n.io/n8nio/n8n:2.29.8}"
N8N_PORT="${N8N_PORT:-5678}"
GENERIC_TIMEZONE="${GENERIC_TIMEZONE:-UTC}"

# Fixed smoke-test workload.
SMOKE_PROMPT="${SMOKE_PROMPT:-Reply with exactly: local engine online}"
SMOKE_MAX_TOKENS="${SMOKE_MAX_TOKENS:-32}"

# Executables from the existing project-01 build.
LLAMA_CLI="${LLAMA_CLI:-$BUILD_DIR/bin/llama-cli}"
LLAMA_SERVER="${LLAMA_SERVER:-$BUILD_DIR/bin/llama-server}"

ENGINE_PID_FILE="$STACK_DIR/engine.pid"
LLAMA_SWAP_PID_FILE="$STACK_DIR/llama-swap.pid"
PRESET_FILE="$STACK_DIR/presets/models.ini"
ENGINE_BASE_URL="http://$ROUTER_HOST:$ROUTER_PORT"

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
  mkdir -p "$RESULTS_DIR" "$STACK_DIR"
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

log_command() {
  local log_file="$1"
  shift
  printf 'Command:' | tee "$log_file"
  printf ' %q' "$@" | tee -a "$log_file"
  printf '\n' | tee -a "$log_file"
}

port_listener() {
  # Prints the listener line for a TCP port, or nothing when free.
  ss -tln 2>/dev/null | awk -v port="$1" '$4 ~ ":"port"$" {print}'
}

require_port_free() {
  if port_listener "$1" | grep -q .; then
    printf 'Port %s is already in use:\n%s\n' "$1" "$(port_listener "$1")" >&2
    printf 'Stop the conflicting service or override the port in config.env.\n' >&2
    exit 1
  fi
}

wait_http() {
  # wait_http <url> <timeout_seconds> [curl extra args...]
  local url="$1" timeout="$2"
  shift 2
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if curl --silent --fail --max-time 5 "$@" "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  printf 'Timed out after %ss waiting for %s\n' "$timeout" "$url" >&2
  return 1
}

curl_auth_args() {
  # shellcheck disable=SC2034  # Consumed by scripts that source this helper.
  if [[ -n "$LLAMA_API_KEY" ]]; then
    CURL_AUTH_ARGS=(-H "Authorization: Bearer $LLAMA_API_KEY")
  else
    CURL_AUTH_ARGS=()
  fi
}

# engine_model_args emits the shared model-placement arguments used by the
# preset generator, the llama-swap config, and direct llama-server commands.
engine_model_args() {
  local args=(
    --no-mmproj
    --fit off
    -ngl "$ENGINE_NGL"
    --n-cpu-moe "$ENGINE_CPU_MOE"
    --cache-type-k "$ENGINE_CACHE_K"
    --cache-type-v "$ENGINE_CACHE_V"
    -c "$ENGINE_CTX"
    -t "$THREADS"
    -tb "$THREADS_BATCH"
    --flash-attn auto
  )
  if [[ "$ENGINE_NO_MMAP" == "1" ]]; then
    args+=(--no-mmap)
  fi
  if [[ "$ENGINE_MLOCK" == "1" ]]; then
    args+=(--mlock)
  fi
  printf '%s\n' "${args[@]}"
}

require_engine() {
  require_file "$LLAMA_SERVER"
  require_file "$MODEL_PATH"
  prepare_results
}
