#!/usr/bin/env bash
# Coding-agent layer (video chapter 7:08): Pi plus the pi-llama-cpp extension.
# Default mode is read-only: it prints the exact pinned install commands and
# the required settings snippet. INSTALL_PI=1 runs npm installs (user-level,
# reversible). WRITE_PI_CONFIG=1 writes ~/.pi/agent/settings.json (outside the
# project, therefore opt-in) after backing up any existing file.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"
require_command node
require_command npm
require_command jq

printf '== Versions ==\nnode %s\nnpm %s\n' "$(node --version)" "$(npm --version)"

install_cmd="npm install -g --ignore-scripts $PI_PACKAGE@$PI_VERSION"
extension_spec="npm:$PI_LLAMA_CPP_PACKAGE@$PI_LLAMA_CPP_VERSION"
settings_json="$(jq -nc --arg url "$ENGINE_BASE_URL" '{llamaServerUrl:$url}')"
pi_settings_file="$HOME/.pi/agent/settings.json"

if [[ "${INSTALL_PI:-0}" == "1" ]]; then
  printf 'Installing pinned Pi...\n'
  # shellcheck disable=SC2086
  $install_cmd
  if command -v pi >/dev/null 2>&1; then
    if ! pi install "$extension_spec"; then
      printf 'Versioned extension spec failed; retrying unversioned %s\n' "$PI_LLAMA_CPP_PACKAGE" >&2
      pi install "npm:$PI_LLAMA_CPP_PACKAGE"
    fi
  else
    printf 'pi not on PATH after install; open a new shell or fix your npm global prefix.\n' >&2
    exit 1
  fi
else
  printf '\nDry run (default). To install, run:\n  %s\n  pi install %s\n' "$install_cmd" "$extension_spec"
  printf 'Or rerun this script with INSTALL_PI=1.\n'
fi

if [[ "${WRITE_PI_CONFIG:-0}" == "1" ]]; then
  mkdir -p "$HOME/.pi/agent"
  if [[ -f "$pi_settings_file" ]]; then
    backup="$pi_settings_file.bak.$(timestamp)"
    cp "$pi_settings_file" "$backup"
    printf 'Backed up existing settings to %s\n' "$backup"
    jq --arg url "$ENGINE_BASE_URL" '.llamaServerUrl = $url' "$pi_settings_file" \
      >"$pi_settings_file.tmp"
    mv "$pi_settings_file.tmp" "$pi_settings_file"
  else
    printf '%s\n' "$settings_json" >"$pi_settings_file"
  fi
  printf 'Wrote %s: llamaServerUrl=%s\n' "$pi_settings_file" "$ENGINE_BASE_URL"
else
  printf '\nGlobal Pi settings snippet (video: "global settings file"):\n  %s -> %s\n' \
    "$pi_settings_file" "$settings_json"
  printf 'Write it manually or rerun with WRITE_PI_CONFIG=1.\n'
fi

printf '\n== Validation ==\n'
if command -v pi >/dev/null 2>&1; then
  pi --version
  if curl --silent --fail --max-time 5 "$ENGINE_BASE_URL/v1/models" >/dev/null 2>&1; then
    printf 'Engine reachable; listing models visible to Pi (best effort, 60s timeout):\n'
    timeout 60 pi --list-models 2>&1 || \
      printf 'Non-interactive listing failed; run "pi" and use /models instead (checkpoint).\n'
  else
    printf 'Engine not reachable at %s; start it with scripts/02_start_engine.sh.\n' "$ENGINE_BASE_URL"
  fi
else
  printf 'pi is not installed yet (dry run). After installing, validate with:\n'
  printf '  pi --version\n  pi   # then type: /models\n'
fi
