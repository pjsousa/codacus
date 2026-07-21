#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

HF_BIN="${HF_BIN:-$WORK_DIR/tools-venv/bin/hf}"
if [[ ! -x "$HF_BIN" ]]; then
  HF_BIN="$(command -v hf || true)"
fi
if [[ -z "$HF_BIN" ]]; then
  printf 'hf CLI not found. Run %s/01_install_deps.sh first.\n' "$SCRIPT_DIR" >&2
  exit 1
fi

mkdir -p "$MODEL_DIR"
"$HF_BIN" download "$MODEL_REPO" "$MODEL_FILE" \
  --revision "$MODEL_REV" --local-dir "$MODEL_DIR"

require_file "$MODEL_PATH"
actual_sha256="$(sha256sum "$MODEL_PATH" | cut -d ' ' -f 1)"
if [[ -n "$MODEL_SHA256" ]] && [[ "$actual_sha256" != "$MODEL_SHA256" ]]; then
  printf 'SHA-256 mismatch for %s\nexpected: %s\nactual:   %s\n' \
    "$MODEL_PATH" "$MODEL_SHA256" "$actual_sha256" >&2
  exit 1
fi

printf 'Model ready: %s\n' "$MODEL_PATH"
du -h "$MODEL_PATH"

if [[ "${DOWNLOAD_DRAFT:-0}" == "1" ]]; then
  "$HF_BIN" download "$DRAFT_REPO" "$DRAFT_FILE" \
    --revision "$DRAFT_REV" --local-dir "$MODEL_DIR"
  require_file "$DRAFT_PATH"
  draft_sha256="$(sha256sum "$DRAFT_PATH" | cut -d ' ' -f 1)"
  if [[ "$draft_sha256" != "$DRAFT_SHA256" ]]; then
    printf 'SHA-256 mismatch for draft %s\nexpected: %s\nactual:   %s\n' \
      "$DRAFT_PATH" "$DRAFT_SHA256" "$draft_sha256" >&2
    exit 1
  fi
  printf 'Draft model ready: %s\n' "$DRAFT_PATH"
  du -h "$DRAFT_PATH"
fi
