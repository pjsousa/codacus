#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

require_command git
require_command cmake

if [[ -x "$CUDA_ROOT/bin/nvcc" ]]; then
  NVCC="$CUDA_ROOT/bin/nvcc"
elif command -v nvcc >/dev/null 2>&1; then
  NVCC="$(command -v nvcc)"
else
  printf 'nvcc not found. Install CUDA 12.2 with INSTALL_CUDA=1 %s/01_install_deps.sh\n' "$SCRIPT_DIR" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$SOURCE_DIR")"
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git clone "$LLAMA_REPO" "$SOURCE_DIR"
fi

current_rev="$(git -C "$SOURCE_DIR" rev-parse HEAD)"
if [[ "$current_rev" != "$LLAMA_REV" ]] && [[ -n "$(git -C "$SOURCE_DIR" status --porcelain)" ]]; then
  printf 'Refusing to change revision: %s has uncommitted changes.\n' "$SOURCE_DIR" >&2
  exit 1
fi

git -C "$SOURCE_DIR" fetch origin "$LLAMA_REV"
git -C "$SOURCE_DIR" switch --detach "$LLAMA_REV"

cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_COMPILER="$NVCC" \
  -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCH" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF
cmake --build "$BUILD_DIR" --config Release -j "$BUILD_JOBS" \
  --target llama-cli llama-completion llama-bench llama-server

"$LLAMA_CLI" --version
"$LLAMA_CLI" --list-devices
printf 'Built pinned TurboQuant fork for CUDA architecture %s.\n' "$CUDA_ARCH"
