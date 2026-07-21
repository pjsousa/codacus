#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  printf 'Usage: %s --list | PROFILE\n' "$0"
}

select_download() {
  case "$1" in
    qwen-reap-q4km)
      REPO="barozp/Qwen3.6-28B-REAP20-A3B-GGUF"
      REV="e3aeb8168f74dd3054eb2716f966c17638b97fef"
      FILE="Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf"
      BYTES="17264580480"
      SHA256="dcd137ca7984ebdaa041ef80281322773bc1a9911ef639b7e698a20979953a00"
      LICENSE="Apache-2.0; public"
      EVIDENCE="Candidate only: exact video repository is unresolved."
      ;;
    glm-reap-q4km)
      REPO="unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF"
      REV="983a65c63bc7bd37353e5246abc8005b3f72d5ec"
      FILE="GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf"
      BYTES="14113838816"
      SHA256="038e930ee1e050dca7732a7a2c768a4b0f83f5655add1acb6c7380852b9eef68"
      LICENSE="MIT; public"
      EVIDENCE="Strong model identification; exact video quant is unresolved."
      ;;
    *)
      printf 'Unknown download profile: %s\n' "$1" >&2
      return 1
      ;;
  esac
}

if [[ "${1:-}" == "--list" ]]; then
  printf '%-22s %s\n' qwen-reap-q4km '17.26 GB, candidate Qwen REAP Q4_K_M'
  printf '%-22s %s\n' glm-reap-q4km '14.11 GB, strong GLM candidate Q4_K_M'
  exit 0
fi

profile="${1:-}"
[[ -n "$profile" ]] || { usage >&2; exit 2; }
select_download "$profile"
require_command curl
require_command sha256sum
require_command flock

mkdir -p "$MODEL_DIR"
target="$MODEL_DIR/$FILE"
part="$target.part"
url="https://huggingface.co/$REPO/resolve/$REV/$FILE"
free_bytes="$(df --output=avail -B1 "$MODEL_DIR" | sed -n '2p' | tr -d ' ')"
reserve=$((5 * 1024 * 1024 * 1024))

printf 'Profile: %s\nRepository: %s\nRevision: %s\nFile: %s\nSize: %s bytes\nSHA-256: %s\nLicense: %s\nEvidence: %s\nFree disk: %s bytes\n' \
  "$profile" "$REPO" "$REV" "$FILE" "$BYTES" "$SHA256" "$LICENSE" "$EVIDENCE" "$free_bytes"

if [[ -f "$target" ]]; then
  actual="$(sha256sum "$target" | cut -d ' ' -f 1)"
  if [[ "$actual" == "$SHA256" ]]; then
    result="$RESULTS_DIR/model-download-${profile}-$(run_id).json"
    write_status_json "$result" download-model PASS "$FILE already exists and its checksum matches" "$target"
    status_line PASS "Model already exists and its checksum matches: $target"
    exit 0
  fi
  status_line FAIL "Existing file checksum differs; refusing to overwrite: $target"
  exit 1
fi

if (( free_bytes < BYTES + reserve )); then
  status_line FAIL "Insufficient disk space; download plus 5 GiB reserve is required"
  exit 1
fi

confirm_exact "DOWNLOAD_$profile" "This action downloads more than 5 GB to $MODEL_DIR."

exec 9>"$MODEL_DIR/.download-$profile.lock"
flock -n 9 || { status_line FAIL "Another $profile download is active"; exit 1; }
if [[ -f "$part" && "$(stat -c %s "$part")" == "$BYTES" ]]; then
  partial_sha="$(sha256sum "$part" | cut -d ' ' -f 1)"
  if [[ "$partial_sha" != "$SHA256" ]]; then
    status_line FAIL "Complete .part file has the wrong checksum; move it aside manually before retrying: $part"
    exit 1
  fi
fi
curl --fail --location --retry 5 --continue-at - --output "$part" "$url"

actual_size="$(stat -c %s "$part")"
[[ "$actual_size" == "$BYTES" ]] || {
  status_line FAIL "Size mismatch: expected $BYTES, got $actual_size; partial file retained"
  exit 1
}
actual_sha="$(sha256sum "$part" | cut -d ' ' -f 1)"
[[ "$actual_sha" == "$SHA256" ]] || {
  status_line FAIL "Checksum mismatch; partial file retained for inspection"
  exit 1
}
mv -- "$part" "$target"
result="$RESULTS_DIR/model-download-${profile}-$(run_id).json"
write_status_json "$result" download-model PASS "$FILE downloaded and verified" "$target"
status_line PASS "Model ready: $target"
