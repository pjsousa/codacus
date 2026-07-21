#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

id="$(run_id)"
run_dir="$LOGS_DIR/llamacpp_capabilities_${id}"
result="$RESULTS_DIR/llamacpp_capabilities_${id}.json"
mkdir -p "$run_dir"

server="$(find_llama_binary llama-server)" || {
  write_status_json "$result" verify-llamacpp FAIL "llama-server not found" "$run_dir"
  exit 1
}
cli="$(find_llama_binary llama-cli)" || {
  write_status_json "$result" verify-llamacpp FAIL "llama-cli not found" "$run_dir"
  exit 1
}

probe() {
  local output="$1" status_file="$2"
  shift 2
  set +e
  "$@" >"$output" 2>&1
  printf '%s\n' "$?" >"$status_file"
  set -e
}

probe "$run_dir/server-version.txt" "$run_dir/server-version.status" "$server" --version
probe "$run_dir/cli-version.txt" "$run_dir/cli-version.status" "$cli" --version
probe "$run_dir/server-help.txt" "$run_dir/server-help.status" "$server" --help
probe "$run_dir/cli-help.txt" "$run_dir/cli-help.status" "$cli" --help
probe "$run_dir/devices.txt" "$run_dir/devices.status" "$server" --list-devices

python3 - "$result" "$server" "$cli" "$run_dir" "$LLAMA_BUILD_DIR" <<'PY'
import hashlib
import json
import pathlib
import sys
from datetime import datetime, timezone

output, server, cli, run_dir, build_dir = sys.argv[1:]
root = pathlib.Path(run_dir)
server_help = (root / "server-help.txt").read_text(errors="replace")
cli_help = (root / "cli-help.txt").read_text(errors="replace")
devices = (root / "devices.txt").read_text(errors="replace")
version = (root / "server-version.txt").read_text(errors="replace").strip()
probe_status = {
    name: int((root / f"{name}.status").read_text().strip())
    for name in ("server-version", "cli-version", "server-help", "cli-help", "devices")
}

flags = {
    "model": ["--model"],
    "gpu_layers": ["--n-gpu-layers", "--gpu-layers"],
    "cpu_moe": ["--n-cpu-moe", "--cpu-moe"],
    "context": ["--ctx-size"],
    "parallel": ["--parallel"],
    "kv_cache": ["--cache-type-k", "--cache-type-v"],
    "flash_attention": ["--flash-attn"],
    "threads": ["--threads", "--threads-batch"],
    "batch": ["--batch-size", "--ubatch-size"],
    "mmap_mlock": ["--no-mmap", "--mlock"],
    "server_api": ["--host", "--port"],
    "server_safety": ["--cache-ram", "--offline", "--no-ui", "--jinja", "--metrics"],
    "cache_reuse": ["--cache-reuse"],
    "router": ["--models-preset", "--models-max"],
    "fit": ["--fit"],
}

capabilities = {
    name: {flag: flag in server_help for flag in spellings}
    for name, spellings in flags.items()
}
required = [value for group in capabilities.values() for value in group.values()]
cuda_visible = "CUDA" in devices and "GTX 1070" in devices
turbo_values = {value: value in server_help for value in ("turbo2", "turbo3", "turbo4")}
status = "PASS" if all(required) and cuda_visible and all(turbo_values.values()) and not any(probe_status.values()) else "FAIL"

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

data = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "stage": "verify-llamacpp",
    "status": status,
    "build_dir": build_dir,
    "version": version,
    "binaries": {
        "server": {"path": server, "sha256": sha256(server)},
        "cli": {"path": cli, "sha256": sha256(cli)},
    },
    "cuda_visible": cuda_visible,
    "probe_exit_codes": probe_status,
    "devices_output": str(root / "devices.txt"),
    "capabilities": capabilities,
    "kv_types": turbo_values,
    "raw_help": {
        "server": str(root / "server-help.txt"),
        "cli": str(root / "cli-help.txt"),
    },
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY

status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$result")"
status_line "$status" "llama.cpp capability report written to $result"
printf 'Raw evidence: %s\n' "$run_dir"
[[ "$status" != "FAIL" ]]
