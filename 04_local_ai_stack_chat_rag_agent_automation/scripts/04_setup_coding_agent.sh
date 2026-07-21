#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

ACTION="${1:-install}"
LLAMA_BASE_URL="${LLAMA_BASE_URL:-http://${LLAMA_HOST:-127.0.0.1}:${LLAMA_PORT:-8080}}"

case "$ACTION" in
  install)
    printf '=== Pi Coding Agent Setup ===\n'
    printf 'This will install Pi globally via npm.\n'
    printf 'Source: https://pi.dev\n\n'

    if command -v pi >/dev/null 2>&1; then
      printf 'Pi is already installed: %s\n' "$(command -v pi)"
      pi --version 2>/dev/null || true
    else
      printf 'Installing Pi coding agent via npm...\n'
      npm install -g --ignore-scripts @earendil-works/pi-coding-agent

      if ! command -v pi >/dev/null 2>&1; then
        printf 'FAIL: Pi installation failed or pi not in PATH.\n' >&2
        exit 1
      fi
      printf 'Pi installed: %s\n' "$(command -v pi)"
    fi

    printf '\n=== Installing llama.cpp plugin ===\n'
    if [[ -d "$PI_INSTALL_DIR" ]]; then
      printf 'Plugin directory %s already exists.\n' "$PI_INSTALL_DIR"
    else
      mkdir -p "$PI_INSTALL_DIR"
    fi

    printf '\n=== Configuring Pi for local llama.cpp endpoint ===\n'
    pi_config_dir="${HOME}/.pi"
    mkdir -p "$pi_config_dir"
    config_file="$pi_config_dir/config.json"

    if [[ -f "$config_file" ]]; then
      printf 'Existing Pi config found at %s\n' "$config_file"
      printf 'Ensure it contains:\n'
    else
      printf 'Creating Pi config at %s\n' "$config_file"
    fi

    cat >"$config_file" <<CFGEOF
{
  "provider": "llamacpp",
  "llamacpp": {
    "url": "${LLAMA_BASE_URL}/v1"
  },
  "model": null,
  "theme": "dark",
  "modes": {
    "interactive": true,
    "print": false
  }
}
CFGEOF
    printf 'Config written to %s\n' "$config_file"
    printf 'Provider set to llamacpp with URL: %s/v1\n' "$LLAMA_BASE_URL"
    ;;

  verify)
    printf '=== Verifying Pi setup ===\n'
    if command -v pi >/dev/null 2>&1; then
      printf 'Pi binary: %s\n' "$(command -v pi)"
    else
      printf 'Pi is not installed.\n'
      exit 1
    fi

    config_file="${HOME}/.pi/config.json"
    if [[ -f "$config_file" ]]; then
      printf 'Config file: %s\n' "$config_file"
      cat "$config_file"
    else
      printf 'Config file not found at %s\n' "$config_file" >&2
      exit 1
    fi

    if command -v curl >/dev/null 2>&1; then
      printf '\nTesting LLM endpoint connectivity...\n'
      if curl --silent --fail --max-time 5 "$LLAMA_BASE_URL/v1/models" >/dev/null 2>&1; then
        printf 'OK: llama.cpp endpoint is reachable at %s/v1\n' "$LLAMA_BASE_URL"
      else
        printf 'WARN: llama.cpp endpoint is not reachable at %s/v1\n' "$LLAMA_BASE_URL"
        printf 'Start the server first with script 02_serve_model.sh\n'
      fi
    fi
    ;;

  *)
    printf 'Usage: %s {install|verify}\n' "$0" >&2
    exit 1
    ;;
esac
