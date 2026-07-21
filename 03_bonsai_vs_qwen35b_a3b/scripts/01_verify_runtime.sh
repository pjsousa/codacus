#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

require_command git
require_file "$LLAMA_CLI"
require_file "$LLAMA_SERVER"
require_file "$LLAMA_BENCH"
require_file "$LLAMA_COMPLETION"

actual_rev="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
printf 'Expected revision: %s\nActual revision:   %s\n' "$LLAMA_REV" "$actual_rev"
if [[ "$actual_rev" != "$LLAMA_REV" ]]; then
  printf 'FAIL: use the unchanged project-01 build; do not switch or rebuild it.\n' >&2
  exit 1
fi
if [[ -n "$(git -C "$SOURCE_DIR" status --porcelain)" ]]; then
  printf 'FAIL: required source checkout is not clean; do not rebuild or alter it.\n' >&2
  exit 1
fi

version_text="$("$LLAMA_CLI" --version 2>&1)"
printf '%s\n' "$version_text"
if [[ "$version_text" != *"${LLAMA_REV:0:9}"* ]]; then
  printf 'FAIL: llama-cli does not report the expected build revision.\n' >&2
  exit 1
fi
server_version_text="$("$LLAMA_SERVER" --version 2>&1)"
printf '%s\n' "$server_version_text"
if [[ "$server_version_text" != *"${LLAMA_REV:0:9}"* ]]; then
  printf 'FAIL: llama-server does not report the expected build revision.\n' >&2
  exit 1
fi
completion_version_text="$("$LLAMA_COMPLETION" --version 2>&1)"
printf '%s\n' "$completion_version_text"
if [[ "$completion_version_text" != *"${LLAMA_REV:0:9}"* ]]; then
  printf 'FAIL: llama-completion does not report the expected build revision.\n' >&2
  exit 1
fi
sha256sum "$LLAMA_CLI" "$LLAMA_SERVER" "$LLAMA_BENCH" "$LLAMA_COMPLETION"
device_text="$("$LLAMA_CLI" --list-devices 2>&1)"
printf '%s\n' "$device_text"
if [[ "$device_text" != *"CUDA"* ]]; then
  printf 'FAIL: required CUDA device is not available to llama.cpp.\n' >&2
  exit 1
fi
"$LLAMA_BENCH" --list-devices

printf '\n== Required flags ==\n'
help_text="$("$LLAMA_CLI" --help 2>&1)"
for flag in --ctx-size --n-predict --gpu-layers --n-cpu-moe --cache-type-k --cache-type-v --seed --temp --top-p --top-k --repeat-penalty --presence-penalty --no-mmproj --fit --fit-target --flash-attn --reasoning --single-turn --simple-io --no-display-prompt --no-context-shift; do
  if [[ "$help_text" == *"$flag"* ]]; then
    printf 'PASS %s\n' "$flag"
  else
    printf 'FAIL %s\n' "$flag" >&2
    exit 1
  fi
done

server_help="$("$LLAMA_SERVER" --help 2>&1)"
for flag in --model --host --port --ctx-size --gpu-layers --cache-type-k --cache-type-v --reasoning; do
  if [[ "$server_help" == *"$flag"* ]]; then
    printf 'PASS llama-server %s\n' "$flag"
  else
    printf 'FAIL llama-server %s\n' "$flag" >&2
    exit 1
  fi
done

bench_help="$("$LLAMA_BENCH" --help 2>&1)"
for flag in --model --n-prompt --n-gen --repetitions --n-gpu-layers --n-cpu-moe --cache-type-k --cache-type-v --flash-attn --mmap --fit-target; do
  if [[ "$bench_help" == *"$flag"* ]]; then
    printf 'PASS llama-bench %s\n' "$flag"
  else
    printf 'FAIL llama-bench %s\n' "$flag" >&2
    exit 1
  fi
done

printf '\n== Weight-type capability ==\n'
if runtime_supports_model binary; then
  printf 'PASS binary: CUDA source contains GGML_TYPE_Q1_0 kernels. Model load remains empirical.\n'
else
  printf 'BLOCKED binary: Q1_0 CUDA support is absent.\n'
fi
if runtime_supports_model ternary; then
  printf 'PASS ternary: source contains GGML_TYPE_Q2_0. Model load remains empirical.\n'
else
  printf 'BLOCKED ternary: source has no GGML_TYPE_Q2_0; do not substitute TQ2_0.\n'
fi
