#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

if [[ "${1:-}" == "--latest" ]]; then
  if [[ -z "${2:-}" ]]; then
    printf 'Usage: %s --latest PHASE_PREFIX | [RESULT_DIRECTORY]\n' "$0" >&2
    exit 1
  fi
  latest_dir=""
  latest_mtime=0
  for candidate in "$RESULTS_DIR/${2}_"*; do
    if [[ -d "$candidate" ]]; then
      candidate_mtime="$(stat -c %Y "$candidate")"
      if (( candidate_mtime > latest_mtime )); then
        latest_mtime="$candidate_mtime"
        latest_dir="$candidate"
      fi
    fi
  done
  if [[ -z "$latest_dir" ]]; then
    printf 'No result group found for prefix: %s\n' "$2" >&2
    exit 1
  fi
  VALIDATE_DIR="$latest_dir"
else
  VALIDATE_DIR="${1:-$RESULTS_DIR}"
fi
if [[ ! -d "$VALIDATE_DIR" ]]; then
  printf 'No results directory exists: %s\n' "$VALIDATE_DIR" >&2
  exit 1
fi

result_files=0
failures=0
status_files=0
require_command python3
printf 'Results root: %s\n' "$VALIDATE_DIR"

while IFS= read -r -d '' html_file; do
  result_files=$((result_files + 1))
  if python3 - "$html_file" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text(errors="replace").strip()
starts = re.match(r"(?is)<!doctype\s+html\b", text) is not None
ends = re.search(r"(?is)</html>\s*$", text) is not None
external = re.search(
    r"(?is)(?:src|href|srcset|action)\s*=\s*['\"]\s*(?:https?:)?//|"
    r"@import\s+(?:url\s*\()?\s*['\"]?\s*(?:https?:)?//|"
    r"url\s*\(\s*['\"]?\s*(?:https?:)?//",
    text,
) is not None
sys.exit(0 if starts and ends and not external else 1)
PY
  then
    status=PASS
  else
    status=FAIL
  fi
  printf '%s html %s bytes=%s\n' "$status" "$html_file" "$(stat -c %s "$html_file")"
  if [[ "$status" == FAIL ]]; then
    failures=$((failures + 1))
  fi
done < <(find "$VALIDATE_DIR" -type f -name '*.html' -print0)

while IFS= read -r -d '' log_file; do
  result_files=$((result_files + 1))
  if log_has_runtime_error "$log_file"; then
    printf 'FAIL runtime-error-text %s\n' "$log_file"
    failures=$((failures + 1))
  fi
  if ! grep -Eq '^Recorded exit status: 0$' "$log_file"; then
    printf 'FAIL missing/nonzero-recorded-exit %s\n' "$log_file"
    failures=$((failures + 1))
  fi
done < <(find "$VALIDATE_DIR" -type f -name '*.log' -print0)

while IFS= read -r -d '' status_file; do
  status_files=$((status_files + 1))
  if [[ "$(<"$status_file")" != COMPLETE ]]; then
    printf 'FAIL incomplete-group %s\n' "$status_file"
    failures=$((failures + 1))
  fi
done < <(find "$VALIDATE_DIR" -type f -name 'group.status' -print0)

printf 'Inspected files=%s failures=%s\n' "$result_files" "$failures"
if (( result_files == 0 )); then
  printf 'No result files were found.\n' >&2
  exit 1
fi
if (( status_files == 0 )); then
  printf 'No group.status manifest was found.\n' >&2
  exit 1
fi
if (( failures > 0 )); then
  exit 1
fi
