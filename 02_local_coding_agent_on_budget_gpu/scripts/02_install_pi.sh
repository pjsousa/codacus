#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_command curl
require_command npm
require_command node
require_command sha256sum

node_major="$(node -p 'process.versions.node.split(".")[0]')"
node_minor="$(node -p 'process.versions.node.split(".")[1]')"
if (( node_major < 22 || (node_major == 22 && node_minor < 19) )); then
  status_line FAIL "Pi $PI_VERSION requires Node >=22.19.0; found $(node --version)"
  printf 'Install or select Node 22.19.0 in an isolated version manager, then rerun.\n' >&2
  exit 1
fi

install_dir="$TOOLS_DIR/pi-$PI_VERSION"
state_dir="$STATE_DIR/pi"
pi_bin="$install_dir/node_modules/.bin/pi"
complete_marker="$install_dir/.pi-llama-cpp-$PI_LLAMA_CPP_VERSION.complete"
if [[ -x "$pi_bin" && -f "$complete_marker" && -f "$state_dir/settings.json" ]] \
  && PI_CODING_AGENT_DIR="$state_dir" "$pi_bin" --version 2>/dev/null | grep -q "$PI_VERSION"; then
  status_line PASS "Pi $PI_VERSION is already installed at $pi_bin"
  exit 0
fi

confirm_exact "INSTALL_PI_$PI_VERSION" \
  "This downloads and installs pinned npm packages under $install_dir only. It does not use global npm."

mkdir -p "$install_dir" "$state_dir"
package_url="https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/pi-coding-agent-install-package.json"
lock_url="https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/pi-coding-agent-install-package-lock.json"
curl --fail --location --output "$install_dir/package.json" "$package_url"
curl --fail --location --output "$install_dir/package-lock.json" "$lock_url"

if [[ "$PI_VERSION" == "0.80.10" ]]; then
  printf '%s  %s\n' \
    '38a7446abd4d3f2f17d793f4ad45ef37b13f310691ea8bf197584456d1addb92' "$install_dir/package.json" \
    'f0815f7807ae0aca1a53519fcdd37b20cc48d1ad6fa4161674e9a329e6ba004c' "$install_dir/package-lock.json" \
    | sha256sum --check --status
else
  printf 'No embedded release checksums for Pi %s. Update this script before installing.\n' "$PI_VERSION" >&2
  exit 1
fi

npm ci --ignore-scripts --prefix "$install_dir"
PI_CODING_AGENT_DIR="$state_dir" "$pi_bin" install "npm:pi-llama-cpp@$PI_LLAMA_CPP_VERSION"

mkdir -p "$state_dir"
if [[ ! -f "$state_dir/settings.json" ]]; then
  python3 - "$state_dir/settings.json" "$SERVER_HOST" "$SERVER_PORT" <<'PY'
import json, sys
output, host, port = sys.argv[1:]
data = {
    "llamaServerUrl": f"http://{host}:{port}",
    "compaction": {"enabled": True, "reserveTokens": 4096, "keepRecentTokens": 4096},
}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
fi
printf 'Pi %s with pi-llama-cpp %s completed at %s\n' \
  "$PI_VERSION" "$PI_LLAMA_CPP_VERSION" "$(date -u +%FT%TZ)" >"$complete_marker"

result="$RESULTS_DIR/pi-install-$(run_id).json"
write_status_json "$result" install-pi PASS \
  "Installed Pi $PI_VERSION and pi-llama-cpp $PI_LLAMA_CPP_VERSION in project-local paths" "$install_dir"
status_line PASS "Pi installed at $pi_bin"
printf 'State: %s\nResult: %s\n' "$state_dir" "$result"
