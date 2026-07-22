#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

failures=0

check() {
  # check <description> <command...>
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  fi
}

printf '== Binary presence ==\n'
check "llama-cli exists" test -x "$LLAMA_CLI"
check "llama-server exists" test -x "$LLAMA_SERVER"

printf '\n== Build identity ==\n'
if [[ -x "$LLAMA_SERVER" ]]; then
  "$LLAMA_SERVER" --version
fi
if [[ -d "$SOURCE_DIR/.git" ]]; then
  actual_rev="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
  if [[ "$actual_rev" == "$LLAMA_REV" ]]; then
    printf 'PASS: source checkout matches pinned revision %s\n' "$LLAMA_REV"
  else
    printf 'FAIL: source checkout is %s, expected %s\n' "$actual_rev" "$LLAMA_REV"
    failures=$((failures + 1))
  fi
  if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain)" ]]; then
    printf 'WARN: source checkout has local modifications (left untouched).\n'
  fi
else
  printf 'WARN: %s is not a git checkout; cannot verify revision.\n' "$SOURCE_DIR"
fi

printf '\n== Router and tuning capabilities of this exact binary ==\n'
help_text="$("$LLAMA_SERVER" --help 2>&1 || true)"
for flag in --models-dir --models-preset --models-max --models-autoload \
  --sleep-idle-seconds --n-cpu-moe --cache-type-k --no-mmap --mlock --api-key; do
  if grep -q -- "$flag" <<<"$help_text"; then
    printf 'PASS: %s supported\n' "$flag"
  else
    printf 'FAIL: %s missing from llama-server --help\n' "$flag"
    failures=$((failures + 1))
  fi
done
for cache_type in turbo3 turbo4; do
  if grep -q -- "$cache_type" <<<"$help_text"; then
    printf 'PASS: KV cache type %s supported\n' "$cache_type"
  else
    printf 'FAIL: KV cache type %s missing\n' "$cache_type"
    failures=$((failures + 1))
  fi
done

printf '\n== Devices ==\n'
"$LLAMA_CLI" --list-devices

printf '\n== Model artifact ==\n'
require_file "$MODEL_PATH"
expected_size=20893015008
actual_size="$(stat -c %s "$MODEL_PATH")"
if [[ "$actual_size" == "$expected_size" ]]; then
  printf 'PASS: %s size is %s bytes\n' "$MODEL_FILE" "$actual_size"
else
  printf 'FAIL: %s size is %s bytes, expected %s\n' "$MODEL_FILE" "$actual_size" "$expected_size"
  failures=$((failures + 1))
fi
if [[ "${VERIFY_SHA256:-0}" == "1" ]]; then
  printf 'Hashing about 21 GB; this can take a minute...\n'
  actual_sha256="$(sha256sum "$MODEL_PATH" | cut -d ' ' -f 1)"
  if [[ "$actual_sha256" == "$MODEL_SHA256" ]]; then
    printf 'PASS: SHA-256 matches %s\n' "$MODEL_SHA256"
  else
    printf 'FAIL: SHA-256 mismatch\nexpected: %s\nactual:   %s\n' "$MODEL_SHA256" "$actual_sha256"
    failures=$((failures + 1))
  fi
else
  printf 'SKIP: SHA-256 check (set VERIFY_SHA256=1 to enable).\n'
fi

printf '\n== Result ==\n'
if (( failures > 0 )); then
  printf '%s check(s) failed. Do not continue until the engine verification passes.\n' "$failures" >&2
  exit 1
fi
printf 'Engine verification passed. Router preset mode is available on this build.\n'
