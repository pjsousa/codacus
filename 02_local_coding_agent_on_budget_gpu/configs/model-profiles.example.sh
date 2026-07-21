#!/usr/bin/env bash
# This file is executable configuration. Review changes before sourcing it.

list_model_profiles() {
  printf '%s\n' \
    existing-control \
    qwen-reap-safe \
    qwen-reap-video-intent \
    glm-reap-safe \
    glm-reap-video-intent
}

load_model_profile() {
  local profile="$1"

  PROFILE_NAME="$profile"
  N_GPU_LAYERS="all"
  CONTEXT_SIZE="8192"
  PARALLEL="1"
  BATCH_SIZE="1024"
  UBATCH_SIZE="256"
  CACHE_TYPE_K="q8_0"
  CACHE_TYPE_V="turbo4"
  FLASH_ATTN="on"
  CACHE_REUSE="256"
  MMAP_MODE="on"
  MODEL_CANDIDATE_NOTE=""

  case "$profile" in
    existing-control)
      MODEL_ID="qwen3.6-35b-control"
      MODEL_FILE="Qwen3.6-35B-A3B-UD-Q4_K_S.gguf"
      N_CPU_MOE="40"
      MODEL_CANDIDATE_NOTE="Prior-project control model; not a current-video REAP artifact."
      ;;
    qwen-reap-safe)
      MODEL_ID="qwen3.6-28b-reap20-q4km"
      MODEL_FILE="Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf"
      N_CPU_MOE="40"
      MODEL_CANDIDATE_NOTE="Candidate repository, not proven to be the video's exact artifact."
      ;;
    qwen-reap-video-intent)
      MODEL_ID="qwen3.6-28b-reap20-q4km"
      MODEL_FILE="Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf"
      N_CPU_MOE="34"
      CONTEXT_SIZE="32768"
      BATCH_SIZE="2048"
      UBATCH_SIZE="1024"
      CACHE_TYPE_K="turbo4"
      CACHE_TYPE_V="turbo2"
      MODEL_CANDIDATE_NOTE="Unmeasured GTX 1070 hypothesis matching the video's Turbo4/Turbo2 intent."
      ;;
    glm-reap-safe)
      MODEL_ID="glm-4.7-flash-reap-23b-a3b-q4km"
      MODEL_FILE="GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf"
      N_CPU_MOE="47"
      MODEL_CANDIDATE_NOTE="Strong video-model identification; exact video quant remains unresolved."
      ;;
    glm-reap-video-intent)
      MODEL_ID="glm-4.7-flash-reap-23b-a3b-q4km"
      MODEL_FILE="GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf"
      N_CPU_MOE="41"
      CONTEXT_SIZE="32768"
      BATCH_SIZE="2048"
      UBATCH_SIZE="1024"
      CACHE_TYPE_K="turbo4"
      CACHE_TYPE_V="turbo2"
      MODEL_CANDIDATE_NOTE="Unmeasured GTX 1070 hypothesis matching the video's Turbo4/Turbo2 intent."
      ;;
    *)
      printf 'Unknown model profile: %s\nAvailable profiles:\n' "$profile" >&2
      list_model_profiles >&2
      return 1
      ;;
  esac

  MODEL_PATH="${MODEL_PATH:-$MODEL_DIR/$MODEL_FILE}"
}
