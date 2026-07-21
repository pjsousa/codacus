#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

require_docker

ACTION="${1:-up}"
STACK_DIR="${DOCKER_COMPOSE_DIR:-$WORK_DIR/docker-stack}"
ANYTHING_LLM_PORT="${ANYTHING_LLM_PORT:-3001}"
N8N_PORT="${N8N_PORT:-5678}"
ANYTHING_LLM_DATA="${ANYTHING_LLM_DATA_DIR:-$WORK_DIR/anythingllm-data}"
N8N_DATA="${N8N_DATA_DIR:-$WORK_DIR/n8n-data}"

case "$ACTION" in
  up|start)
    mkdir -p "$STACK_DIR" "$ANYTHING_LLM_DATA" "$N8N_DATA"

    compose_file="$STACK_DIR/docker-compose.yml"

    if [[ ! -f "$compose_file" ]]; then
      printf 'Creating Docker Compose file: %s\n' "$compose_file"
      cat >"$compose_file" <<COMPOSEEOF
services:
  anything-llm:
    image: mintplexlabs/anythingllm:latest
    container_name: anything-llm
    ports:
      - "${ANYTHING_LLM_PORT}:3001"
    volumes:
      - "${ANYTHING_LLM_DATA}:/app/server/storage"
    restart: unless-stopped
    network_mode: host
    environment:
      - STORAGE_DIR=/app/server/storage

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    ports:
      - "${N8N_PORT}:5678"
    volumes:
      - "${N8N_DATA}:/home/node/.n8n"
    restart: unless-stopped
    network_mode: host
COMPOSEEOF
    fi

    printf 'Starting Docker stack...\n'
    printf '  AnythingLLM: http://localhost:%s\n' "$ANYTHING_LLM_PORT"
    printf '  n8n:         http://localhost:%s\n' "$N8N_PORT"

    docker compose -f "$compose_file" up -d
    printf '\nWaiting for containers to become ready...\n'

    printf '  AnythingLLM...\n'
    if wait_for_health "http://127.0.0.1:$ANYTHING_LLM_PORT" 60; then
      printf '    OK\n'
    else
      printf '    WARN: AnythingLLM did not report healthy. Check with: docker logs anything-llm\n'
    fi

    printf '  n8n...\n'
    if wait_for_health "http://127.0.0.1:$N8N_PORT/healthz" 60; then
      printf '    OK\n'
    else
      printf '    WARN: n8n did not report healthy. Check with: docker logs n8n\n'
    fi

    printf '\n=== Stack is running ===\n'
    docker compose -f "$compose_file" ps
    ;;

  stop|down)
    compose_file="$STACK_DIR/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
      printf 'Stopping Docker stack...\n'
      docker compose -f "$compose_file" down
    else
      printf 'No compose file found at %s.\n' "$compose_file" >&2
    fi
    ;;

  status)
    compose_file="$STACK_DIR/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
      docker compose -f "$compose_file" ps
    else
      printf 'No compose file found at %s.\n' "$compose_file" >&2
    fi
    ;;

  logs)
    compose_file="$STACK_DIR/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
      shift 2>/dev/null || true
      docker compose -f "$compose_file" logs "${@:-}"
    else
      printf 'No compose file found at %s.\n' "$compose_file" >&2
    fi
    ;;

  *)
    printf 'Usage: %s {up|start|stop|down|status|logs}\n' "$0" >&2
    exit 1
    ;;
esac
