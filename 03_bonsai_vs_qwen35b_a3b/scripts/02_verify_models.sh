#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

DOWNLOAD_MODELS="${DOWNLOAD_MODELS:-0}"
DOWNLOAD_SET="${DOWNLOAD_SET:-binary}"
REQUIRE_ALL="${REQUIRE_ALL:-0}"
missing_count=0
failed_count=0

verify_artifact() {
  local key="$1"
  local path expected expected_size actual actual_size stamp
  path="$(model_path "$key")"
  expected="$(model_sha256 "$key")"
  expected_size="$(model_size_bytes "$key")"
  printf '\n== %s ==\npath=%s\n' "$(model_label "$key")" "$path"
  if [[ -z "$path" || ! -f "$path" ]]; then
    printf 'MISSING\n'
    missing_count=$((missing_count + 1))
    return 0
  fi
  actual_size="$(stat -c %s "$path")"
  printf 'size_bytes=%s\n' "$actual_size"
  if [[ -n "$expected_size" && "$actual_size" != "$expected_size" ]]; then
    printf 'FAIL: expected size %s bytes\n' "$expected_size" >&2
    failed_count=$((failed_count + 1))
    return 0
  fi
  if [[ -z "$expected" ]]; then
    printf 'FAIL: no checksum is configured.\n' >&2
    failed_count=$((failed_count + 1))
    return 0
  fi
  actual="$(sha256sum "$path" | cut -d ' ' -f 1)"
  printf 'sha256=%s\n' "$actual"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: expected %s\n' "$expected" >&2
    failed_count=$((failed_count + 1))
  else
    printf 'PASS checksum\n'
    mkdir -p "$VERIFICATION_DIR"
    stamp="$(verification_stamp "$key")"
    artifact_signature "$key" >"$stamp"
    printf 'verification_stamp=%s\n' "$stamp"
  fi
}

download_artifact() {
  local key="$1"
  local destination
  require_command hf
  mkdir -p "$ARTIFACT_DIR"
  export HF_HOME="$ARTIFACT_DIR/.hf"
  export HF_HUB_CACHE="$HF_HOME/hub"
  export HF_XET_CACHE="$HF_HOME/xet"
  export TMPDIR="$ARTIFACT_DIR/.tmp"
  export HF_HUB_DISABLE_TELEMETRY=1
  export HF_HUB_DISABLE_UPDATE_CHECK=1
  export HF_HUB_DISABLE_IMPLICIT_TOKEN=1
  export DO_NOT_TRACK=1
  mkdir -p "$HF_HUB_CACHE" "$HF_XET_CACHE" "$TMPDIR"
  destination="$(model_path "$key")"
  if [[ -e "$destination" ]]; then
    printf 'Refusing to download over existing artifact: %s\n' "$destination" >&2
    return 1
  fi
  case "$key" in
    binary)
      hf download "$BINARY_REPO" "$BINARY_FILE" --revision "$BINARY_REV" --local-dir "$ARTIFACT_DIR"
      ;;
    ternary)
      hf download "$TERNARY_REPO" "$TERNARY_FILE" --revision "$TERNARY_REV" --local-dir "$ARTIFACT_DIR"
      ;;
    *)
      printf 'No download definition for model key: %s\n' "$key" >&2
      return 1
      ;;
  esac
}

if [[ "$DOWNLOAD_MODELS" == "1" ]]; then
  printf 'Explicit download enabled. Hugging Face cache/temp paths are scoped under %s.\n' "$ARTIFACT_DIR"
  mkdir -p "$ARTIFACT_DIR"
  read -r -a download_keys <<<"$DOWNLOAD_SET"
  required_bytes=0
  for key in "${download_keys[@]}"; do
    case "$key" in
      binary) required_bytes=$((required_bytes + BINARY_SIZE_BYTES)) ;;
      ternary) required_bytes=$((required_bytes + TERNARY_SIZE_BYTES)) ;;
      *) printf 'No download definition for model key: %s\n' "$key" >&2; exit 1 ;;
    esac
  done
  available_bytes="$(df --output=avail -B1 "$ARTIFACT_DIR" | tail -n 1 | tr -d ' ')"
  required_bytes=$((required_bytes + 2147483648))
  if (( available_bytes < required_bytes )); then
    printf 'FAIL: need %s bytes including safety margin; only %s available.\n' "$required_bytes" "$available_bytes" >&2
    exit 1
  fi
  for key in "${download_keys[@]}"; do
    download_artifact "$key"
  done
else
  printf 'Verification only. No downloads will occur.\n'
  printf 'Opt in with: DOWNLOAD_MODELS=1 DOWNLOAD_SET="binary" %q\n' "$0"
fi

verify_artifact qwen
verify_artifact binary
verify_artifact ternary
if [[ -n "$GEMMA_MODEL_PATH" ]]; then
  verify_artifact gemma
fi

printf '\nPinned sizes: binary=%s bytes; ternary=%s bytes.\n' "$BINARY_SIZE_BYTES" "$TERNARY_SIZE_BYTES"
if (( failed_count > 0 )); then
  exit 1
fi
if [[ "$REQUIRE_ALL" == "1" ]] && (( missing_count > 0 )); then
  printf 'FAIL: %s required artifact(s) are missing.\n' "$missing_count" >&2
  exit 1
fi
